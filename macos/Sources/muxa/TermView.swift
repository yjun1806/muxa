import AppKit
import Bonsplit
import Carbon
import GhosttyKit

/// 터미널 서피스 NSView — libghostty가 이 뷰에 Metal 레이어를 붙여 직접 렌더한다.
///
/// 키 입력·IME는 Ghostty 업스트림 SurfaceView_AppKit.swift(MIT)의 검증된 구현을 이식했다.
/// 핵심 계약: keyDown → interpretKeyEvents → (insertText | setMarkedText) 순서로 AppKit이
/// IME를 구동하고, 우리는 marked text를 ghostty_surface_preedit로, 확정 텍스트를
/// ghostty_surface_key(text:)로 내려보낸다. 조합 미리보기는 libghostty가 커서 위치에 그린다.
final class TermView: NSView, NSTextInputClient {
    private(set) var surface: ghostty_surface_t?

    /// 논리 포커스 — 포커스된 패인의 서피스만 커서를 활성화해 시각적으로 구분된다.
    var isFocused: Bool = false {
        didSet {
            guard let surface, isFocused != oldValue else { return }
            ghostty_surface_set_focus(surface, isFocused)
        }
    }

    /// 이 패인이 클릭으로 포커스됐을 때 상위(WorkspaceView)에 알린다 — 논리 focusedId 갱신용.
    var onFocus: (() -> Void)?

    /// 스크롤백 검색 상태(⌘F). 검색 오버레이가 관측하고, ghostty 검색 액션이 갱신한다.
    let search = SearchState()

    /// 이 뷰가 담긴 Bonsplit 탭 — 배지 라우팅용(A). TerminalStore.term(for:)에서 주입.
    var tabId: TabID?
    /// 셸의 현재 작업 디렉터리(OSC 7). 세션 저장 시 store가 읽어 이 경로에서 새 셸을 복원한다(DESIGN 4.2).
    var pwd: String?
    /// 백그라운드 주의 신호(완료·벨·알림)를 store로 넘긴다 — 억제 판정·배지·알림은 store가 결정.
    var onSignal: ((TerminalSignal) -> Void)?
    /// 이 탭을 사용자가 보게 됐을 때 배지 클리어 — store가 세팅.
    var onClearBadge: ((TabID) -> Void)?
    /// 셸이 종료(exit)돼 libghostty가 서피스 닫기를 요청할 때 — 이 탭만 닫는다. store가 세팅.
    var onRequestClose: ((TabID) -> Void)?
    /// 엔진(SET_TITLE)이 보낸 터미널 제목 — store가 받아 탭 이름에 반영한다.
    /// 수동 지정 탭은 store가 덮지 않게 판정하므로 TermView는 값만 넘긴다.
    var onTitle: ((String) -> Void)?

    /// IME 조합 중(preedit) 텍스트. NSTextInputClient가 채운다.
    private var markedText = NSMutableAttributedString()

    /// keyDown 동안 insertText가 확정한 텍스트를 모은다 (한국어 등 복합 입력).
    /// non-nil이면 "지금 keyDown 처리 중"이라는 신호다.
    private var keyTextAccumulator: [String]? = nil

    override var acceptsFirstResponder: Bool { true }

    init(app: ghostty_app_t, cwd: String?, tabId: TabID? = nil, sockPath: String? = nil,
         restoreScrollbackFile: String? = nil) {
        self.tabId = tabId
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false // 수동 프레임 — 제약 엔진 제외

        var config = ghostty_surface_config_new()
        config.platform_tag = GHOSTTY_PLATFORM_MACOS
        config.platform = ghostty_platform_u(macos: ghostty_platform_macos_s(
            nsview: Unmanaged.passUnretained(self).toOpaque()
        ))
        config.userdata = Unmanaged.passUnretained(self).toOpaque()
        config.scale_factor = Double(NSScreen.main?.backingScaleFactor ?? 2.0)
        config.context = GHOSTTY_SURFACE_CONTEXT_WINDOW

        // 훅용 env 주입 — 셸에 MUXA_TAB_ID·MUXA_SOCK를 심어 `muxa notify`가 이 탭·소켓을 찾게 한다.
        // strdup으로 복제한 C 문자열은 surface_new가 읽는 동안 유효해야 하므로 호출 직후에 해제한다.
        var envStorage: [UnsafeMutablePointer<CChar>] = []
        func dup(_ s: String) -> UnsafePointer<CChar> {
            let p = strdup(s)!
            envStorage.append(p)
            return UnsafePointer(p)
        }
        var envVars: [ghostty_env_var_s] = []
        if let tabId {
            envVars.append(ghostty_env_var_s(key: dup("MUXA_TAB_ID"), value: dup(tabId.uuid.uuidString)))
            // 이중 주소(칸 단위 라우팅) 여지 — 현재 muxa는 탭 1개 = TermView(서피스) 1개라 tabId가 곧 서피스 주소다.
            // 그래서 MUXA_SURFACE_ID를 tabId와 같은 값으로 함께 심어, 훗날 한 탭이 여러 서피스를 담게 되면
            // 훅이 서피스 단위로 더 정밀하게 지목할 수 있는 프로토콜 슬롯을 미리 노출한다(라우팅은 여전히 tabId 우선).
            envVars.append(ghostty_env_var_s(key: dup("MUXA_SURFACE_ID"), value: dup(tabId.uuid.uuidString)))
        }
        if let sockPath {
            envVars.append(ghostty_env_var_s(key: dup("MUXA_SOCK"), value: dup(sockPath)))
        }
        // 세션 복원: 새 셸이 시작하면 저장된 이전 화면을 재출력해 프롬프트 위에 복원한다(rc 훅 불필요).
        // initial_input은 셸 stdin으로 들어가 "정상 출력 경로"를 타므로 엔진 렌더와 충돌하지 않는다(process_output
        // 직접 주입은 이 ghostty 포크에서 흰 화면을 냈다). DESIGN 123 "새 셸에서 재출력"의 구현.
        // 앞에 `clear`를 둬 echo된 명령 줄·login 배너를 화면에서 지우고 순수 내용만 남긴다 — 다음 저장 캡처가
        // 깨끗해져 재출력 아티팩트(cat/배너)가 매 복원마다 쌓이는 중첩도 준다. (rm은 하지 않는다 — 저장
        // 레이아웃이 이 파일을 가리키므로 지우면 다음 복원에서 빈 파일이 돼 복원이 실패한다. 정리는 GC가 담당.)
        if let restoreScrollbackFile {
            let quoted = "'" + restoreScrollbackFile.replacingOccurrences(of: "'", with: "'\\''") + "'"
            config.initial_input = dup("clear; cat \(quoted)\n")
        }

        // working_directory·env_vars는 const 포인터 — surface_new가 읽는 동안만 유효하면 된다.
        envVars.withUnsafeMutableBufferPointer { buf in
            config.env_vars = buf.baseAddress
            config.env_var_count = buf.count
            if let cwd {
                self.surface = cwd.withCString { ptr in
                    config.working_directory = ptr
                    return ghostty_surface_new(app, &config)
                }
            } else {
                self.surface = ghostty_surface_new(app, &config)
            }
        }
        for p in envStorage { free(p) }

        // 검색어를 ghostty로 밀어넣는 브리지 — 전용 API가 없어 binding-action 문자열로만 가능(cmux 동일).
        search.applyNeedle = { [weak self] needle in
            self?.performBindingAction("search:\(needle)")
        }

        // 파일·이미지를 터미널에 떨구면 경로를 프롬프트에 삽입한다(아래 NSDraggingDestination).
        registerForDraggedTypes([.fileURL, .png, .tiff])

        // 셸 스폰 직후의 foreground pid(=셸)를 잡아 OS 레벨 종료 감시를 건다. pid가 아직 0이면 재시도한다.
        armProcessWatcher()
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    /// 창이 다른 모니터로 이동하는 것을 감지하는 관찰 토큰(배율·해상도 재동기화용).
    private var screenObserver: NSObjectProtocol?

    deinit {
        if let token = screenObserver { NotificationCenter.default.removeObserver(token) }
        processWatcher?.cancel() // 프로세스 종료 감시 소스 정리 (생명주기 종료)
        if let surface { ghostty_surface_free(surface) }
    }

    // MARK: 프로세스 종료 감지 (결정론적 done) — 서피스 자식(셸) pid를 OS 레벨로 감시
    //
    // OSC 133/셸 통합이나 close_surface_cb에 의존하지 않고, libghostty가 노출하는 foreground pid를
    // (스폰 직후 = 셸) 캡처해 DispatchSourceProcess(.exit)로 감시한다. 종료되면 done 신호를 store로 넘겨
    // 에이전트 크래시·강제종료·비정상 종료를 결정론으로 잡는다. store가 상태 확정·배지(안 보이는 탭)를 판정한다.
    // 서피스는 libghostty가 우리 프로세스 내에서 스폰한 자식이라 kqueue(NOTE_EXIT) 감시가 성립한다.

    /// 프로세스 종료 감시 소스(무장되면 non-nil). deinit·종료 시 취소한다.
    private var processWatcher: DispatchSourceProcess?
    /// pid 무장 재시도 횟수 — 셸 스폰이 늦어 foreground_pid가 아직 0일 때 몇 번 다시 시도한다.
    private var processArmAttempts = 0
    /// 재시도 상한(약 5초) — 이 안에 pid를 못 잡으면 감시를 포기한다(close_surface_cb가 최소 종료를 커버).
    private static let maxProcessArmAttempts = 20
    /// pid 무장 재시도 간격.
    private static let processArmRetryDelay: TimeInterval = 0.25

    /// 서피스의 foreground pid를 잡아 종료 감시를 무장한다. 이미 무장됐거나 서피스가 없으면 무동작,
    /// pid가 아직 유효하지 않으면(스폰 전) 잠시 뒤 재시도한다. 스폰 직후 첫 유효 pid = 셸이다.
    private func armProcessWatcher() {
        guard processWatcher == nil, let surface else { return }
        let raw = ghostty_surface_foreground_pid(surface)
        guard raw > 0, raw <= UInt64(pid_t.max) else {
            guard processArmAttempts < Self.maxProcessArmAttempts else { return }
            processArmAttempts += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.processArmRetryDelay) { [weak self] in
                self?.armProcessWatcher()
            }
            return
        }
        let source = DispatchSource.makeProcessSource(identifier: pid_t(raw), eventMask: .exit, queue: .main)
        source.setEventHandler { [weak self] in self?.handleProcessExit() }
        processWatcher = source
        source.resume()
    }

    /// 감시하던 프로세스가 종료됐다 — 감시 소스를 정리하고 결정론적 종료 신호를 store로 넘긴다(한 번만).
    private func handleProcessExit() {
        processWatcher?.cancel()
        processWatcher = nil
        onSignal?(.processExited)
    }

    // MARK: 크기·스케일 — 백킹 픽셀 단위로 전달 (업스트림 계약)

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        // 배율 변화(모니터 이동)면 Metal 레이어 배율부터 화면에 맞춘다 — 이게 빠지면 글자가 작아진다(cmux).
        syncScaleAndSize(force: true)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncScaleAndSize()
    }

    /// 마지막으로 libghostty에 전달한 백킹 크기·스케일 — 같은 값이면 재전달을 건너뛴다.
    /// SwiftUI 레이아웃 협상이 잠깐 작은 크기를 제안했다가 되돌리는 오실레이션에서
    /// 매번 ghostty를 리사이즈하면 레이아웃 재무효화 루프(창 크래시)로 번진다.
    private var lastBacking: NSSize = .zero
    private var lastScale: CGFloat = 0

    /// 현재 화면 배율 — convertToBacking(뷰 백킹, 모니터 이동 시 stale 가능)이 아니라 창의
    /// backingScaleFactor를 진실원천으로 쓴다(cmux). 최소 1.0.
    private var currentScale: CGFloat {
        max(1.0, window?.backingScaleFactor ?? layer?.contentsScale ?? NSScreen.main?.backingScaleFactor ?? 2.0)
    }

    /// force=true면 값이 같아 보여도 재전달 + 리드로우한다 — 모니터 이동처럼 뷰 좌표는 그대로여도
    /// 화면 배율·물리 해상도가 바뀌었을 때 강제로 다시 맞춘다.
    private func syncScaleAndSize(force: Bool = false) {
        // window에 붙기 전엔 아무것도 하지 않는다. Metal 레이어가 drawable에 연결되지 않은 상태의
        // set_size/refresh는 화면에 반영되지 않는데, lastBacking만 소진돼 정작 부착 후 첫 유효 크기의
        // firstValidSize refresh를 막아 빈 화면으로 남긴다(세션 복귀 간헐 빈 화면의 근인). window 가드로
        // "부착 이후"에만 크기·refresh를 흘려보내, 부착 후 첫 유효 크기에 반드시 리드로우되게 한다.
        guard let surface, window != nil, frame.width > 0, frame.height > 0 else { return }
        // 처음으로 유효한 크기를 얻는 순간(복원 직후 등)엔 반드시 리드로우 — 안 그러면 서피스가
        // 크기만 받고 그려지지 않아 빈 화면으로 남는다(재시작 시 터미널 빈 화면의 원인).
        let firstValidSize = (lastBacking == .zero)
        let scale = currentScale

        if force || scale != lastScale {
            // Metal 레이어 배율을 화면에 맞춘다(cmux) — set_content_scale만으론 부족하고,
            // 이 레이어 배율이 어긋나면 새 모니터에서 셀이 작게 래스터화돼 글자가 작아진다.
            if let layer {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                layer.contentsScale = scale
                CATransaction.commit()
            }
            ghostty_surface_set_content_scale(surface, scale, scale)
            lastScale = scale
        }

        let pixelWidth = UInt32((frame.size.width * scale).rounded())
        let pixelHeight = UInt32((frame.size.height * scale).rounded())
        let pixel = NSSize(width: CGFloat(pixelWidth), height: CGFloat(pixelHeight))
        if force || pixel != lastBacking {
            ghostty_surface_set_size(surface, pixelWidth, pixelHeight)
            lastBacking = pixel
        }
        // 첫 유효 크기·모니터 이동 시 리드로우. 일반 레이아웃 경로에서 매번 부르면 오실레이션 위험이라
        // 크기가 실제로 바뀐 경우로 제한한다(firstValidSize는 서피스당 1회).
        if force || firstValidSize { ghostty_surface_refresh(surface) }
    }

    /// 창이 속한 화면의 디스플레이 ID를 libghostty에 알린다(모니터별 색·리프레시 특성).
    private func syncDisplayID() {
        guard let surface,
              let num = window?.screen?.deviceDescription[.init("NSScreenNumber")] as? NSNumber
        else { return }
        ghostty_surface_set_display_id(surface, num.uint32Value)
    }

    // MARK: 포커스

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncDisplayID()
        // window에 실제로 붙는 순간엔 force refresh. firstValidSize 1회 refresh가 부착 전에
        // 소진되면(복원 시 뷰 attach 순서가 비결정적) lastBacking/lastScale 가드가 재-refresh를
        // 전부 막아 빈 화면으로 남는다. 부착·재부착(탭 전환 시 removeFromSuperview→addSubview 포함)이라는
        // 결정적 순간에 무조건 다시 그려 그 구멍을 닫는다.
        syncScaleAndSize(force: window != nil)
        // 부착 시점에 frame이 아직 0이면 위 force refresh가 무효다. 복원은 keepAllAlive가 모든 탭 서피스를
        // 한 패스에 일괄 생성해 "부착↔유효 frame" 순서가 어긋나기 쉽고, 그러면 재-setFrameSize가 없어
        // firstValidSize refresh가 영영 안 불려 빈 화면이 된다(cmux는 forceRefreshSurface로 이를 보장).
        // 유효 frame이 배정되는 즉시 확정 리드로우를 재시도로 보장해 그 레이스를 닫는다.
        if window != nil { scheduleAttachRefresh() }

        // 창이 다른 모니터로 이동하면(배율/해상도 변화) 재동기화한다.
        // 배율이 같은 화면으로 옮기면 viewDidChangeBackingProperties가 안 떠서 이 알림으로 잡는다.
        if let token = screenObserver {
            NotificationCenter.default.removeObserver(token)
            screenObserver = nil
        }
        if let window {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeScreenNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.syncDisplayID()
                    self?.syncScaleAndSize(force: true)
                }
            }
        }
    }

    /// 부착 후 재시도 횟수(유효 frame 대기). 유효해지거나 window에서 떨어지면 리셋한다.
    private var attachRefreshAttempts = 0
    /// 부착 재시도 상한(약 1초). SwiftUI 레이아웃이 유효 frame을 배정할 때까지의 여유.
    private static let maxAttachRefreshAttempts = 40

    /// window에 붙은 뒤, 유효 frame이 배정되는 즉시 딱 한 번 확정 리드로우를 보장한다(cmux forceRefreshSurface 대응).
    /// 복원 배치 생성에서 "부착↔유효 frame" 순서가 어긋나 firstValidSize refresh가 유실되는 창을 닫는다.
    /// frame이 아직 0이면 짧게 재시도하고, 유효해지면 force refresh 후 종료. window에서 떨어지면 중단.
    private func scheduleAttachRefresh() {
        guard window != nil else { attachRefreshAttempts = 0; return }
        if frame.width > 0, frame.height > 0 {
            attachRefreshAttempts = 0
            syncScaleAndSize(force: true)
            return
        }
        guard attachRefreshAttempts < Self.maxAttachRefreshAttempts else { attachRefreshAttempts = 0; return }
        attachRefreshAttempts += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) { [weak self] in
            self?.scheduleAttachRefresh()
        }
    }

    override func becomeFirstResponder() -> Bool {
        isFocused = true // didSet이 ghostty_surface_set_focus(true) — 논리 포커스도 실제와 동기화
        if let tabId { onClearBadge?(tabId) } // 이 탭을 보게 됐으니 배지 해제
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        isFocused = false
        return super.resignFirstResponder()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        onFocus?()
    }

    // MARK: 마우스 위치 — ghostty_surface_mouse_pos 동기화 (cmux 이식)
    //
    // libghostty는 마우스 리포팅을 켠 앱(claude code 등, DECSET 1000/1002)에는 스크롤을
    // "현재 커서 위치의 버튼 4/5 이벤트"로 변환해 보낸다. 위치를 한 번도 안 알려주면 embedded
    // cursor_pos가 초기값 (-1,-1)에 머물러 뷰포트 밖 판정으로 리포트가 통째로 버려지고
    // 뷰포트 스크롤도 건너뛴다 — claude code 안에서 스크롤이 죽던 근인. 그래서 커서가 뷰 위에
    // 있는 동안 위치를 계속 동기화한다. NSTrackingArea의 .mouseMoved가 window 설정 없이
    // mouseMoved 이벤트 수신을 보장한다.

    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .inVisibleRect, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    /// 이벤트 좌표를 ghostty 좌표계(좌상단 원점)로 변환해 서피스에 알린다.
    private func syncMousePos(with event: NSEvent) {
        guard let surface else { return }
        let point = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(surface, point.x, bounds.height - point.y, ghosttyMods(event.modifierFlags))
    }

    override func mouseMoved(with event: NSEvent) { syncMousePos(with: event) }
    override func mouseEntered(with event: NSEvent) { syncMousePos(with: event) }
    override func mouseDragged(with event: NSEvent) { syncMousePos(with: event) }

    override func mouseExited(with event: NSEvent) {
        guard let surface else { return }
        // 드래그 중 이탈은 위치를 유지한다 — 선택 오토스크롤이 "뷰포트 밖 포인터"를 관측해야 한다(cmux).
        if NSEvent.pressedMouseButtons != 0 { return }
        ghostty_surface_mouse_pos(surface, -1, -1, ghosttyMods(event.modifierFlags))
    }

    // MARK: 스크롤 — NSEvent 스크롤을 ghostty로 전달 (Ghostty 업스트림 scrollWheel 이식)
    //
    // TermView는 ghostty가 직접 그리는 뷰라 스크롤도 우리가 서피스에 넘겨야 한다. 안 넘기면 스크롤백을
    // 못 올린다. 정밀 델타(트랙패드)는 precision 비트(0x1)로, 모멘텀 페이즈는 상위 비트로 인코딩한다.

    override func scrollWheel(with event: NSEvent) {
        guard let surface else { return }
        // 트래킹 이벤트를 아직 못 받았어도(부착 직후 커서가 이미 뷰 안 등) 스크롤 이벤트 자신의
        // 좌표로 위치를 확정한다 — 마우스 리포팅 앱으로의 스크롤 변환이 위치에 의존하기 때문.
        syncMousePos(with: event)
        var x = event.scrollingDeltaX
        var y = event.scrollingDeltaY

        var mods: ghostty_input_scroll_mods_t = 0
        if event.hasPreciseScrollingDeltas {
            mods = 1 // precision(픽셀 단위 트랙패드)
            // 체감 속도 보정 — 업스트림과 동일한 2배.
            x *= 2
            y *= 2
        }

        // 모멘텀 페이즈를 상위 비트로 싣는다(관성 스크롤 정확도).
        var momentum = GHOSTTY_MOUSE_MOMENTUM_NONE
        switch event.momentumPhase {
        case .began: momentum = GHOSTTY_MOUSE_MOMENTUM_BEGAN
        case .stationary: momentum = GHOSTTY_MOUSE_MOMENTUM_STATIONARY
        case .changed: momentum = GHOSTTY_MOUSE_MOMENTUM_CHANGED
        case .ended: momentum = GHOSTTY_MOUSE_MOMENTUM_ENDED
        case .cancelled: momentum = GHOSTTY_MOUSE_MOMENTUM_CANCELLED
        case .mayBegin: momentum = GHOSTTY_MOUSE_MOMENTUM_MAY_BEGIN
        default: break
        }
        mods |= ghostty_input_scroll_mods_t(momentum.rawValue) << 1

        ghostty_surface_mouse_scroll(surface, x, y, mods)
    }

    // MARK: 스크롤백 검색 — ghostty binding-action 문자열로 구동 (cmux 이식)

    /// 키바인드 액션을 이름 문자열로 서피스에 전달한다(검색 전용 C API가 없다).
    @discardableResult
    func performBindingAction(_ action: String) -> Bool {
        guard let surface else { return false }
        return action.withCString { ghostty_surface_binding_action(surface, $0, UInt(strlen($0))) }
    }

    /// ⌘F — ghostty 검색 시작. 엔진이 START_SEARCH 액션으로 되돌려주면 오버레이가 뜬다.
    func startSearch() { performBindingAction("start_search") }

    /// 검색 종료 — 오버레이를 닫고 포커스를 터미널로 되돌린다.
    func closeSearch() {
        performBindingAction("end_search")
        search.active = false
        search.reset()
        window?.makeFirstResponder(self)
    }

    func searchNext() { performBindingAction("navigate_search:next") }
    func searchPrevious() { performBindingAction("navigate_search:previous") }

    // ghostty→앱 검색 액션 훅 (GhosttyRuntime.action_cb가 메인 스레드에서 호출)

    func onStartSearch(_ needle: String?) {
        if let needle, !needle.isEmpty { search.needle = needle }
        search.active = true
    }

    func onEndSearch() {
        search.active = false
        search.reset()
    }

    func onSearchTotal(_ total: Int?) { search.total = total }
    func onSearchSelected(_ selected: Int?) { search.selected = selected }

    // MARK: 알림·완료 감지 (A) — action_cb가 메인에서 호출. 신호 종류만 store로 넘긴다.
    //
    // "지금 이 탭이 보이나?" 판정과 배지/알림 억제(짧은 명령·벨 연타·보이는 칸)는 store가 한다.
    // TermView는 firstResponder 하나로 판정할 수 없다(3~4분할 시 비포커스여도 보이는 칸이 있음).

    /// OSC 9/777 데스크톱 알림.
    func onDesktopNotification(title: String, body: String) {
        onSignal?(.desktopNotification(title: title, body: body))
    }

    /// OSC 133 명령 완료(exitCode nil=미보고, duration ns).
    func onCommandFinished(exitCode: Int?, duration: UInt64) {
        onSignal?(.commandFinished(exitCode: exitCode, duration: duration))
    }

    /// 벨(주의 환기) — 에이전트가 완료를 벨로 알리는 경우가 많다.
    func onBell() {
        onSignal?(.bell)
    }

    // MARK: 출력 heartbeat — RENDER 액션 다운샘플 (에이전트 상태 추정, DESIGN 4.5)
    //
    // GHOSTTY_ACTION_RENDER는 프레임마다(고빈도) 온다 → 반드시 스로틀. 게이트(shouldEmitRenderHeartbeat)만
    // 콜백 스레드에서 저비용으로 통과시키고, 실제 신호는 메인에서 emitOutputHeartbeat가 넘긴다.

    /// 마지막으로 heartbeat를 흘려보낸 시각(단조 ns). RENDER 콜백 스레드에서만 접근(정렬된 8바이트 로드/스토어).
    @ObservationIgnored private var lastRenderNs: UInt64 = 0
    /// heartbeat 다운샘플 간격 — 초당 1회면 idle 추정(초 단위)에 충분하고 부하가 없다.
    private static let renderThrottleNs: UInt64 = 1_000_000_000

    /// RENDER 액션 스로틀 게이트 — 간격이 지났으면 true(+타임스탬프 갱신). 콜백 스레드에서 호출.
    /// 경합이 나도 최악은 heartbeat 한 번 더 흘리는 것뿐이라 락 없이 처리한다.
    func shouldEmitRenderHeartbeat() -> Bool {
        let now = DispatchTime.now().uptimeNanoseconds
        if now &- lastRenderNs < Self.renderThrottleNs { return false }
        lastRenderNs = now
        return true
    }

    /// 스로틀을 통과한 RENDER를 출력 heartbeat 신호로 store에 넘긴다(메인에서 호출).
    func emitOutputHeartbeat() {
        onSignal?(.outputHeartbeat)
    }

    /// OSC 7 작업 디렉터리 변경. 저장은 스냅샷 시점에 store가 pwd를 읽는 방식이라 여기선 값만 갱신한다.
    func onPwdChange(_ pwd: String) {
        self.pwd = pwd
    }

    /// OSC 0/2 터미널 제목(SET_TITLE). 수동 rename 여부·탭 반영은 store가 결정한다.
    func onSetTitle(_ title: String) {
        onTitle?(title)
    }

    // MARK: 명령 주입 — 셸에 텍스트 입력 + 실행 (에이전트 세션 재개용, D2)
    //
    // 신뢰 경계: 여기 들어오는 문자열은 훅이 넘긴 임의 셸 명령일 수 있다. 무단 실행을 막는 승인 게이트
    // (설정 agent_resume)는 호출부(TerminalStore.executeResume)가 판정한다 — TermView는 전송만 한다.

    /// 문자열을 셸에 보낸다(붙여넣기 경로). 끝의 개행 하나는 리터럴이 아니라 "실행(Enter)"으로 해석한다:
    /// ghostty_surface_text는 텍스트를 bracketed-paste(DECSET 2004)로 감싸므로 개행을 그 안에 넣으면
    /// 셸의 라인 에디터가 리터럴 줄바꿈으로 받아 **실행되지 않는다**. 그래서 명령 본문만 붙여넣고
    /// 실행은 별도 Return 키 이벤트로 커밋한다(insertText와 같은 C 문자열 수명 규칙).
    func sendText(_ s: String) {
        guard let surface, !s.isEmpty else { return }
        let submit = s.hasSuffix("\n")
        let body = submit ? String(s.dropLast()) : s
        if !body.isEmpty {
            let len = body.utf8CString.count
            if len > 1 {
                body.withCString { ptr in
                    ghostty_surface_text(surface, ptr, UInt(len - 1))
                }
            }
        }
        if submit { sendReturn(surface) }
    }

    /// Return 키를 한 번 눌러 앞서 붙여넣은 명령을 실행한다. 텍스트 없이 keycode만 넘겨 ghostty가
    /// 현재 모드에 맞게 인코딩하게 둔다(cmux 이식). PRESS 한 번이면 셸이 라인을 커밋한다.
    private func sendReturn(_ surface: ghostty_surface_t) {
        var keyEvent = ghostty_input_key_s()
        keyEvent.action = GHOSTTY_ACTION_PRESS
        keyEvent.keycode = UInt32(kVK_Return)
        keyEvent.mods = GHOSTTY_MODS_NONE
        keyEvent.consumed_mods = GHOSTTY_MODS_NONE
        keyEvent.unshifted_codepoint = 0
        keyEvent.composing = false
        keyEvent.text = nil
        _ = ghostty_surface_key(surface, keyEvent)
    }

    // MARK: 스크롤백 리드백 — 세션 저장 시 화면+스크롤백 텍스트 캡처 (④)
    //
    // libghostty read_text: SCREEN 태그의 top-left~bottom-right 선택으로 화면 전체(스크롤백 포함)를
    // 클립보드 형식 평문(SGR 없음)으로 읽는다. 반환 버퍼는 반드시 free_text로 해제한다.
    // 정제·상한은 순수 로직(ScrollbackText.sanitize)이 호출부에서 담당한다.

    /// 화면+스크롤백 전체를 평문으로 읽는다. 서피스가 없거나 비었으면 nil.
    func readScreenText() -> String? {
        guard let surface else { return nil }
        let topLeft = ghostty_point_s(tag: GHOSTTY_POINT_SCREEN, coord: GHOSTTY_POINT_COORD_TOP_LEFT, x: 0, y: 0)
        let bottomRight = ghostty_point_s(tag: GHOSTTY_POINT_SCREEN, coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT, x: 0, y: 0)
        let selection = ghostty_selection_s(top_left: topLeft, bottom_right: bottomRight, rectangle: false)
        var out = ghostty_text_s()
        guard ghostty_surface_read_text(surface, selection, &out), let ptr = out.text else { return nil }
        let text = ptr.withMemoryRebound(to: UInt8.self, capacity: Int(out.text_len)) { base in
            String(decoding: UnsafeBufferPointer(start: base, count: Int(out.text_len)), as: UTF8.self)
        }
        ghostty_surface_free_text(surface, &out)
        return text.isEmpty ? nil : text
    }

    // MARK: 드래그&드롭 — 파일·이미지를 떨구면 셸-이스케이프한 경로를 프롬프트에 삽입
    //
    // libghostty는 드롭을 처리하지 않아 뷰가 직접 받는다. Finder 파일은 경로를, 브라우저/스크린샷의
    // 이미지 데이터는 임시 PNG로 저장해 그 경로를 넣는다. claude code는 삽입된 이미지 경로를 인식해
    // 첨부한다(cmux 동일). 실행(Enter)은 사용자 몫이라 개행 없이 삽입만 한다.

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropPaths(from: sender) != nil ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let paths = dropPaths(from: sender), !paths.isEmpty else { return false }
        window?.makeFirstResponder(self)
        onFocus?()
        sendText(paths.map(Self.shellQuote).joined(separator: " "))
        return true
    }

    /// 드래그 페이스트보드에서 삽입할 경로들을 뽑는다 — 파일 URL 우선, 없으면 이미지 데이터를 임시 파일로.
    private func dropPaths(from sender: NSDraggingInfo) -> [String]? {
        let pb = sender.draggingPasteboard
        if let urls = pb.readObjects(forClasses: [NSURL.self],
                                     options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            return urls.map(\.path)
        }
        if let image = NSImage(pasteboard: pb), let path = Self.writeTempImage(image) {
            return [path]
        }
        return nil
    }

    /// 이미지를 임시 PNG로 저장하고 경로를 돌려준다(파일이 아닌 이미지 드래그용). 실패 시 nil.
    private static func writeTempImage(_ image: NSImage) -> String? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("muxa-drop-\(UUID().uuidString).png")
        do {
            try png.write(to: URL(fileURLWithPath: path))
            return path
        } catch {
            return nil
        }
    }

    /// 셸에 안전하게 넘길 단일 인용 이스케이프 — 공백·특수문자가 있는 경로를 한 토큰으로.
    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: 키 입력 — Ghostty SurfaceView_AppKit.keyDown 이식

    override func keyDown(with event: NSEvent) {
        guard let surface else {
            interpretKeyEvents([event])
            return
        }

        // 제어 조합(Ctrl + 키)은 텍스트가 아니라 곧장 ghostty가 인코딩해야 한다. interpretKeyEvents로
        // 넘기면 아래 translation이 control을 떼어내(control은 번역 모디파이어가 아님) 맨 글자만 남고,
        // 한글 입력 소스에선 그 글자가 조합을 시작해(두벌식 c→ㅊ) Ctrl+C가 preedit로 먹혀 터미널에 닿지 않는다.
        // 조합 중이 아닐 때만 우회 — 조합 중이면 아래 정상 경로가 확정/취소를 처리한다.
        // (⌘ 조합은 제외 — 앱 단축키는 로컬 모니터가, ⌘C/⌘V 복사·붙여넣기는 ghostty 내장 키바인드가 처리한다.)
        // text는 nil — 제어 조합은 ghostty가 keycode+mods+unshifted_codepoint에서 직접 제어 바이트를 만든다.
        // 단, 한글 등 IME가 활성이면 event 기반 unshifted_codepoint가 자모(c키→ㅊ, 0x314A)라 ghostty가
        // Ctrl+C를 0x03으로 인코딩하지 못한다 → 물리 키의 ASCII 문자로 교정해야 한다(cmux physicalControlKey 대응).
        if markedText.length == 0, event.modifierFlags.contains(.control) {
            let action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
            var keyEvent = ghosttyKeyEvent(event, action: action)
            if let ascii = TermView.asciiKeyChar(forKeyCode: event.keyCode) {
                keyEvent.unshifted_codepoint = ascii.value
            }
            keyEvent.composing = false
            _ = ghostty_surface_key(surface, keyEvent)
            return
        }

        // option-as-alt 등 번역 모디파이어 계산 (업스트림 계약: 같으면 원본 이벤트 재사용 —
        // AppKit 내부의 객체 동일성 때문에 한국어 입력이 여기 걸려 있다)
        let translationModsGhostty = eventModifierFlags(
            mods: ghostty_surface_key_translation_mods(surface, ghosttyMods(event.modifierFlags))
        )
        var translationMods = event.modifierFlags
        for flag in [NSEvent.ModifierFlags.shift, .control, .option, .command] {
            if translationModsGhostty.contains(flag) {
                translationMods.insert(flag)
            } else {
                translationMods.remove(flag)
            }
        }
        let translationEvent: NSEvent
        if translationMods == event.modifierFlags {
            translationEvent = event
        } else {
            translationEvent = NSEvent.keyEvent(
                with: event.type,
                location: event.locationInWindow,
                modifierFlags: translationMods,
                timestamp: event.timestamp,
                windowNumber: event.windowNumber,
                context: nil,
                characters: event.characters(byApplyingModifiers: translationMods) ?? "",
                charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
                isARepeat: event.isARepeat,
                keyCode: event.keyCode
            ) ?? event
        }

        let action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS

        // interpretKeyEvents가 insertText/setMarkedText를 부른다 — 그 결과를 모은다
        keyTextAccumulator = []
        defer { keyTextAccumulator = nil }

        let markedTextBefore = markedText.length > 0

        // 한영 전환(Shift+Space 등) 키가 자판을 바꿨다면 그 키는 터미널로 보내지 않는다
        let keyboardIdBefore: String? = markedTextBefore ? nil : KeyboardLayout.id

        interpretKeyEvents([translationEvent])

        if !markedTextBefore && keyboardIdBefore != KeyboardLayout.id {
            return
        }

        // 조합 상태를 libghostty에 동기화 — 미리보기는 엔진이 커서 위치에 그린다
        syncPreedit(clearIfNeeded: markedTextBefore)

        if let list = keyTextAccumulator, !list.isEmpty {
            // 조합이 확정한 텍스트 — composing=false로 전송
            for text in list {
                _ = keyAction(action, event: event, translationEvent: translationEvent, text: text)
            }
        } else {
            _ = keyAction(
                action,
                event: event,
                translationEvent: translationEvent,
                text: translationEvent.ghosttyCharacters,
                // 조합 중이거나(조합 취소 직후 포함) 그 키는 인코딩하면 안 된다
                composing: markedText.length > 0 || markedTextBefore
            )
        }
    }

    override func keyUp(with event: NSEvent) {
        _ = keyAction(GHOSTTY_ACTION_RELEASE, event: event)
    }

    /// 물리 키의 ASCII 문자(입력 소스 무관). 한글/중국어 IME가 활성이어도 Ctrl+C의 'c'를 얻는다 —
    /// NSEvent의 characters류는 현재 IME 레이아웃을 타 자모('ㅊ')를 돌려줘 제어 인코딩이 깨지기 때문이다.
    /// ASCII 호환 키보드 레이아웃으로 keyCode를 modifier 없이 직접 번역한다(cmux physicalControlKey 대응).
    static func asciiKeyChar(forKeyCode keyCode: UInt16) -> UnicodeScalar? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var scalar: UnicodeScalar?
        layoutData.withUnsafeBytes { raw in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }
            var deadKeys: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var count = 0
            let status = UCKeyTranslate(
                layout, keyCode, UInt16(kUCKeyActionDown), 0,
                UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeys, chars.count, &count, &chars
            )
            if status == noErr, count > 0, let s = UnicodeScalar(chars[0]) { scalar = s }
        }
        return scalar
    }

    /// 비프음 방지 + AppKit 셀렉터 디스패치 흡수 (인코딩은 keyAction이 담당)
    override func doCommand(by selector: Selector) {}

    private func keyAction(
        _ action: ghostty_input_action_e,
        event: NSEvent,
        translationEvent: NSEvent? = nil,
        text: String? = nil,
        composing: Bool = false
    ) -> Bool {
        guard let surface else { return false }

        var keyEvent = ghosttyKeyEvent(event, action: action, translationMods: translationEvent?.modifierFlags)
        keyEvent.composing = composing

        // 제어문자(0x20 미만)는 Ghostty가 자체 인코딩한다 — text로 보내지 않는다
        if let text, !text.isEmpty, let first = text.utf8.first, first >= 0x20 {
            return text.withCString { ptr in
                keyEvent.text = ptr
                return ghostty_surface_key(surface, keyEvent)
            }
        }
        return ghostty_surface_key(surface, keyEvent)
    }

    // MARK: NSTextInputClient — Ghostty 업스트림 이식

    func hasMarkedText() -> Bool { markedText.length > 0 }

    func markedRange() -> NSRange {
        guard markedText.length > 0 else { return NSRange() }
        return NSRange(0...(markedText.length - 1))
    }

    func selectedRange() -> NSRange { NSRange() }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        switch string {
        case let v as NSAttributedString: markedText = NSMutableAttributedString(attributedString: v)
        case let v as String: markedText = NSMutableAttributedString(string: v)
        default: break
        }
        // keyDown 밖에서 온 조합 변경(자판 전환 중 조합 등)은 즉시 동기화
        if keyTextAccumulator == nil { syncPreedit() }
    }

    func unmarkText() {
        if markedText.length > 0 {
            markedText.mutableString.setString("")
            syncPreedit()
        }
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }

    func characterIndex(for point: NSPoint) -> Int { 0 }

    /// IME 후보창 위치 — libghostty가 커서 픽셀 좌표를 알려준다
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let surface, let window else { return .zero }
        var x: Double = 0, y: Double = 0, w: Double = 0, h: Double = 0
        ghostty_surface_ime_point(surface, &x, &y, &w, &h)
        // Ghostty 좌표계는 좌상단 원점 — AppKit 좌하단으로 변환
        let viewRect = NSRect(x: x, y: frame.size.height - y, width: w, height: h)
        let winRect = convert(viewRect, to: nil)
        return window.convertToScreen(winRect)
    }

    func insertText(_ string: Any, replacementRange: NSRange) {
        guard NSApp.currentEvent != nil, let surface else { return }

        var chars = ""
        switch string {
        case let v as NSAttributedString: chars = v.string
        case let v as String: chars = v
        default: return
        }

        // insertText가 불렸다는 건 조합이 끝났다는 뜻
        unmarkText()

        // keyDown 처리 중이면 모아서 keyDown이 전송하게 한다
        if var acc = keyTextAccumulator {
            acc.append(chars)
            keyTextAccumulator = acc
            return
        }

        // keyDown 밖(딕테이션 등)에서 온 텍스트는 직접 전송
        let len = chars.utf8CString.count
        if len > 1 {
            chars.withCString { ptr in
                ghostty_surface_text(surface, ptr, UInt(len - 1))
            }
        }
    }

    /// markedText 상태를 libghostty preedit로 동기화
    private func syncPreedit(clearIfNeeded: Bool = true) {
        guard let surface else { return }
        if markedText.length > 0 {
            let str = markedText.string
            let len = str.utf8CString.count
            if len > 0 {
                str.withCString { ptr in
                    ghostty_surface_preedit(surface, ptr, UInt(len - 1))
                }
            }
        } else if clearIfNeeded {
            ghostty_surface_preedit(surface, nil, 0)
        }
    }
}

// MARK: - 헬퍼 (Ghostty.Input.swift · NSEvent+Extension.swift 이식)

/// NSEvent 모디파이어 → ghostty mods
func ghosttyMods(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
    var mods: UInt32 = GHOSTTY_MODS_NONE.rawValue
    if flags.contains(.shift) { mods |= GHOSTTY_MODS_SHIFT.rawValue }
    if flags.contains(.control) { mods |= GHOSTTY_MODS_CTRL.rawValue }
    if flags.contains(.option) { mods |= GHOSTTY_MODS_ALT.rawValue }
    if flags.contains(.command) { mods |= GHOSTTY_MODS_SUPER.rawValue }
    if flags.contains(.capsLock) { mods |= GHOSTTY_MODS_CAPS.rawValue }
    let raw = flags.rawValue
    if raw & UInt(NX_DEVICERSHIFTKEYMASK) != 0 { mods |= GHOSTTY_MODS_SHIFT_RIGHT.rawValue }
    if raw & UInt(NX_DEVICERCTLKEYMASK) != 0 { mods |= GHOSTTY_MODS_CTRL_RIGHT.rawValue }
    if raw & UInt(NX_DEVICERALTKEYMASK) != 0 { mods |= GHOSTTY_MODS_ALT_RIGHT.rawValue }
    if raw & UInt(NX_DEVICERCMDKEYMASK) != 0 { mods |= GHOSTTY_MODS_SUPER_RIGHT.rawValue }
    return ghostty_input_mods_e(mods)
}

/// ghostty mods → NSEvent 모디파이어 (역변환)
func eventModifierFlags(mods: ghostty_input_mods_e) -> NSEvent.ModifierFlags {
    var flags = NSEvent.ModifierFlags(rawValue: 0)
    if mods.rawValue & GHOSTTY_MODS_SHIFT.rawValue != 0 { flags.insert(.shift) }
    if mods.rawValue & GHOSTTY_MODS_CTRL.rawValue != 0 { flags.insert(.control) }
    if mods.rawValue & GHOSTTY_MODS_ALT.rawValue != 0 { flags.insert(.option) }
    if mods.rawValue & GHOSTTY_MODS_SUPER.rawValue != 0 { flags.insert(.command) }
    if mods.rawValue & GHOSTTY_MODS_CAPS.rawValue != 0 { flags.insert(.capsLock) }
    return flags
}

/// NSEvent → ghostty_input_key_s (text·composing 제외 — 수명 문제로 호출부가 채운다)
func ghosttyKeyEvent(
    _ event: NSEvent,
    action: ghostty_input_action_e,
    translationMods: NSEvent.ModifierFlags? = nil
) -> ghostty_input_key_s {
    var keyEvent = ghostty_input_key_s()
    keyEvent.action = action
    keyEvent.keycode = UInt32(event.keyCode)
    keyEvent.text = nil
    keyEvent.composing = false
    keyEvent.mods = ghosttyMods(event.modifierFlags)
    // ctrl·cmd는 텍스트 번역에 기여하지 않는다는 업스트림 휴리스틱
    keyEvent.consumed_mods = ghosttyMods(
        (translationMods ?? event.modifierFlags).subtracting([.control, .command])
    )
    keyEvent.unshifted_codepoint = 0
    if event.type == .keyDown || event.type == .keyUp {
        if let chars = event.characters(byApplyingModifiers: []),
           let codepoint = chars.unicodeScalars.first {
            keyEvent.unshifted_codepoint = codepoint.value
        }
    }
    return keyEvent
}

extension NSEvent {
    /// 제어문자·PUA(펑션키)를 걸러낸 전송용 문자 (업스트림 이식)
    var ghosttyCharacters: String? {
        guard let characters else { return nil }
        if characters.count == 1, let scalar = characters.unicodeScalars.first {
            if scalar.value < 0x20 {
                return self.characters(byApplyingModifiers: modifierFlags.subtracting(.control))
            }
            if scalar.value >= 0xF700 && scalar.value <= 0xF8FF {
                return nil
            }
        }
        return characters
    }
}

/// 현재 키보드 입력 소스 ID — 한영 전환 키 감지에 사용 (업스트림 이식)
enum KeyboardLayout {
    static var id: String {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
        else { return "" }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }
}

import SwiftUI

/// 서비스 등록 시트 — **스크립트를 고르거나, 직접 명령을 친다.**
///
/// 실제로 등록할 것의 대부분은 `package.json`의 스크립트(`pnpm dev`)다. 매번 타이핑하게 두면 오타와
/// **잘못된 패키지 매니저**가 새어든다. 그래서 프로젝트를 훑어 스크립트를 보여주고 클릭 한 번으로
/// 이름·명령이 채워지게 한다. 그 밖의 것(`./scripts/dev.sh`, `go run .`)은 직접 입력으로 받는다.
///
/// 명령은 인터랙티브 로그인 셸로 실행된다(`TmuxService.start`) — `.app` 번들은 PATH를 상속하지 않아
/// 감싸지 않으면 `pnpm`을 못 찾는다. 그래서 여기 적는 명령은 터미널에 치는 것과 똑같이 동작한다.
struct ServiceAddSheet: View {
    /// 기본 실행 경로(프로젝트 경로) — 실행 경로를 비워두면 여기서 돌고, 스크립트 스캔의 기본 대상이다.
    let cwd: String?
    /// 제목·하단 안내문은 파라미터다 — **스크립트 추가(ScriptStrip)가 같은 시트를 재사용**한다
    /// (스캔·매니저 감지·검증이 똑같고 문구만 다르다). 기본값은 서비스 문구 — 스크립트에
    /// "muxa를 꺼도 계속 돕니다"는 거짓말이라 호출부가 갈아 끼운다.
    var title = "서비스 추가"
    var footnote = "실행 경로에서 로그인 셸로 실행되고, muxa를 꺼도 계속 돕니다.\n죽으면 푸터 칩이 빨갛게 바뀌고 알림이 옵니다.\n명령은 평문으로 저장됩니다 — 토큰·API 키는 명령에 적지 말고 .env에 두세요."
    /// 시트를 열 때 명령을 미리 채운다(빈 문자열 = 안 채움) — 일회용 → 스크립트 승격이 명령을 넘겨
    /// 사용자가 이름만 짓게 한다.
    var initialCommand = ""
    /// (이름, 명령, 실행 폴더 지정) — 지정이 nil이면 프로젝트 경로 상속.
    let onAdd: (String, String, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var command = ""
    /// 실행 경로 입력 — **비워두면 기본(프로젝트 경로)**. 기본값과 같은 입력도 저장하지 않는다(`runCwdOverride`).
    @State private var cwdText = ""
    @State private var scripts: [ProjectScript] = []
    @State private var manager: PackageManager?
    /// lock 파일이 없어 매니저를 모를 때 사용자가 고른 값(추측하지 않는다).
    @State private var pickedManager: PackageManager = .npm

    private var effectiveManager: PackageManager { manager ?? pickedManager }

    /// 입력이 기본값과 실질적으로 다를 때만 나오는 지정값(nil = 상속) — 저장·검증·스캔이 같은 해석을 쓴다.
    private var cwdOverride: String? {
        runCwdOverride(entered: cwdText, defaultCwd: cwd, home: SystemPaths.home)
    }

    /// 실제로 실행될 폴더 — 지정이 있으면 그것, 없으면 프로젝트 경로.
    private var effectiveCwd: String? { cwdOverride ?? cwd }

    /// 실행될 폴더의 문제(없으면 nil). 없거나(nil·빈 문자열) 루트(`/`)면 pnpm 등이 그 폴더의
    /// package.json을 못 찾아 즉사하고(`ERR_PNPM_NO_IMPORTER_MANIFEST_FOUND`), 존재하지 않는 폴더면
    /// tmux 세션 생성 자체가 실패한다 — 전부 추가 전에 막는다.
    private enum CwdIssue { case unset, root, notFound }
    private var cwdIssue: CwdIssue? {
        guard let path = effectiveCwd, !path.isEmpty else { return .unset }
        guard path != "/" else { return .root }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return .notFound }
        return nil
    }

    private var cwdIsValid: Bool { cwdIssue == nil }

    private var isValid: Bool {
        cwdIsValid
            && !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !command.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Text(title)
                .font(.muxa(.title, weight: .semibold))
                .foregroundStyle(Color.pFg)

            runPath

            if !scripts.isEmpty {
                scriptPicker
                HDivider()
                Text("또는 직접 입력")
                    .font(.muxa(.caption))
                    .foregroundStyle(Color.pMuted)
            } else {
                // 스크립트가 하나도 없는 프로젝트(네이티브 앱 등) — 침묵하지 않고 왜 없는지 말한다.
                Text("package.json·Makefile·scripts/ 에서 찾은 스크립트가 없습니다.\n실행할 명령을 직접 적어주세요.")
                    .font(.muxa(.caption))
                    .foregroundStyle(Color.pMuted)
            }

            VStack(alignment: .leading, spacing: Space.xs) {
                Text("이름").font(.muxa(.caption)).foregroundStyle(Color.pMuted)
                TextField("web", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.muxa(.body))
            }

            VStack(alignment: .leading, spacing: Space.xs) {
                Text("명령").font(.muxa(.caption)).foregroundStyle(Color.pMuted)
                TextField("pnpm dev · ./scripts/dev.sh · go run .", text: $command)
                    .textFieldStyle(.roundedBorder)
                    .font(.muxaMono(.body))
            }

            // **추가 직전에 실제로 실행될 문자열을 그대로 보여준다.** 목록 미리보기는 한 줄로 잘리지만
            // 여기서는 접지 않는다 — 스크립트를 클릭해 채운 명령이 무엇인지 마지막으로 확인하는 자리다.
            if !command.trimmingCharacters(in: .whitespaces).isEmpty {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("실행될 명령").font(.muxa(.caption)).foregroundStyle(Color.pMuted)
                    Text(command.trimmingCharacters(in: .whitespaces))
                        .font(.muxaMono(.caption))
                        .foregroundStyle(Color.pFg)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true) // 잘리지 않고 줄바꿈된다
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Space.sm)
                        .background(Color.pBg, in: RoundedRectangle(cornerRadius: Radius.sm))
                }
            }

            Text(footnote)
                .font(.muxa(.caption))
                .foregroundStyle(Color.pMuted.opacity(0.8))

            HStack {
                Spacer()
                Button("취소") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("추가") {
                    onAdd(name.trimmingCharacters(in: .whitespaces),
                          command.trimmingCharacters(in: .whitespaces),
                          cwdOverride)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(Space.xl)
        .frame(width: 420)
        .background(Color.pPanel)
        // 실행 경로가 바뀌면 스크립트 후보도 그 폴더에서 다시 찾는다 — 모노레포 하위 패키지를 지정하면
        // 그 패키지의 package.json 스크립트가 나와야 클릭 채움이 의미 있다.
        .task(id: effectiveCwd) {
            let found = ProjectScripts.discover(in: effectiveCwd)
            scripts = found.scripts
            manager = found.manager
        }
        .onAppear { if command.isEmpty { command = initialCommand } } // 승격 프리필(한 번만)
    }

    // MARK: 실행 경로 — 이 서비스가 어느 폴더에서 도는지 명시하고, 필요하면 바꾼다

    /// 기본은 프로젝트 경로(placeholder로 보인다), 입력하면 그 폴더에서 돈다 — 모노레포의 하위
    /// 패키지(`apps/admin`)처럼 프로젝트 루트가 아닌 곳에서 돌 서비스를 위해 편집을 받는다.
    /// `~`는 홈으로 펴진다(runCwdOverride). 루트(`/`)·빈 경로·없는 폴더면 문제를 말하고 "추가"가 막힌다.
    ///
    /// 상태를 **모양으로** 나른다(DESIGN §2·ServiceRow와 같은 규칙): 컨테이너는 언제나 같고
    /// 글리프만 바뀐다 — 정상 = 조용한 `folder`(muted, `pBg` 박스), 이상 = `exclamationmark.triangle.fill`
    /// (호박, 호박 subtle 틴트 박스). 정상은 크롬처럼 조용하고, 이상은 색맹에도 모양으로 드러난다.
    @ViewBuilder private var runPath: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("실행 경로").font(.muxa(.caption)).foregroundStyle(Color.pMuted)
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                Image(systemName: cwdIsValid ? "folder" : "exclamationmark.triangle.fill")
                    .font(.muxa(.micro))
                    .foregroundStyle(cwdIsValid ? Color.pMuted : Color.pBorderActivity)
                    .frame(width: IconSize.statusSlot)
                    .accessibilityHidden(true) // 필드·경고문이 이미 의미를 말한다 — 글리프는 중복 낭독일 뿐
                // placeholder = 기본(프로젝트 경로). 비워두면 거기서 돌고, 적으면 그 폴더에서 돈다.
                TextField(cwd.map { displayPath($0, home: SystemPaths.home) } ?? "실행할 폴더 경로",
                          text: $cwdText)
                    .textFieldStyle(.plain)
                    .font(.muxaMono(.caption))
                    .foregroundStyle(Color.pFg)
            }
            .padding(Space.sm)
            .background(cwdIsValid ? Color.pBg : Color.pBorderActivity.opacity(Tint.subtle),
                        in: RoundedRectangle(cornerRadius: Radius.sm))
            if let issue = cwdIssue {
                Text(issueMessage(issue))
                    .font(.muxa(.caption))
                    .foregroundStyle(Color.pBorderActivity)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func issueMessage(_ issue: CwdIssue) -> String {
        switch issue {
        case .unset: return "실행할 폴더가 없습니다 — 경로를 적거나 워크스페이스 경로를 먼저 지정하세요."
        case .root: return "루트(/)에서는 실행할 수 없습니다 — 프로젝트 폴더를 적어주세요."
        case .notFound: return "폴더를 찾을 수 없습니다: \(displayPath(effectiveCwd, home: SystemPaths.home))"
        }
    }

    // MARK: package.json 스크립트 — 클릭 한 번으로 이름·명령을 채운다

    /// package.json 스크립트가 하나라도 있을 때만 패키지 매니저가 의미 있다(Makefile·sh는 무관).
    private var hasPackageScripts: Bool { scripts.contains { $0.source == .packageJSON } }

    private var scriptPicker: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                Text("프로젝트 스크립트")
                    .font(.muxa(.caption))
                    .foregroundStyle(Color.pMuted)
                Spacer(minLength: Space.sm)
                if hasPackageScripts {
                    if manager == nil {
                        // lock 파일이 없다 — **추측하지 않고 물어본다.** pnpm 프로젝트에 `npm run`을 넣으면
                        // lock이 깨지거나 엉뚱한 의존성이 깔린다. 기본값을 조용히 쓰지 않는다.
                        Picker("", selection: $pickedManager) {
                            ForEach(PackageManager.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .help("lock 파일이 없어 패키지 매니저를 알 수 없습니다 — 직접 고르세요")
                    } else {
                        Pill(color: Color.pBrand) {
                            Text(effectiveManager.rawValue).font(.muxa(.caption, weight: .semibold))
                        }
                        .help("lock 파일로 감지한 패키지 매니저")
                    }
                }
            }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(scripts) { script in
                        scriptRow(script)
                    }
                }
            }
            .frame(maxHeight: 150)
            .background(Color.pBg, in: RoundedRectangle(cornerRadius: Radius.sm))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(Color.pBorder, lineWidth: 1))
        }
    }

    /// 스크립트 한 줄 — [출처] 이름 | 설명(있으면) · 실제 명령.
    /// 클릭하면 아래 입력칸이 채워진다(바로 등록하지 않는다 — 이름을 바꾸거나 명령을 손볼 수 있게).
    /// 명령 조립 정책은 뷰가 아니라 `ProjectScripts.command(for:manager:)`에 있다.
    private func scriptRow(_ script: ProjectScript) -> some View {
        let filled = ProjectScripts.command(for: script, manager: effectiveManager)
        let isSelected = command == filled
        return Button {
            name = script.name
            command = filled
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                // 출처를 밝힌다 — 여러 소스가 섞이면 "이게 어디서 왔지"가 곧바로 궁금해진다.
                Text(sourceLabel(script.source))
                    .font(.muxa(.nano, weight: .semibold))
                    .foregroundStyle(Color.pMuted)
                    .frame(width: 34, alignment: .leading)
                Text(script.name)
                    .font(.muxaMono(.label, weight: .semibold))
                    .foregroundStyle(Color.pFg)
                    .frame(minWidth: 52, alignment: .leading)
                VStack(alignment: .leading, spacing: Space.tight) {
                    // 설명은 **리포가 준 문자열**이다 — 명령보다 진하게 그리면 명령인 척 위장할 수 있어
                    // 위계를 뒤집었다: 실제 실행될 명령이 주인공이고, 설명은 그 아래 보조로 내린다.
                    Text(filled)
                        .font(.muxaMono(.label))
                        .foregroundStyle(Color.pFg)
                        .lineLimit(1)
                        // **`.tail`이다(`.middle` 아님)** — 가운데를 접으면 긴 명령의 꼬리(`&& curl … | sh`)가
                        // 사라져 악의적인 명령이 평범해 보인다. 잘릴 땐 앞부터 정직하게 보인다.
                        .truncationMode(.tail)
                    if let note = script.note {
                        Text(note)
                            .font(.muxa(.caption))
                            .foregroundStyle(Color.pMuted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.muxa(.micro))
                        .foregroundStyle(Color.pBrand)
                }
            }
            .padding(.horizontal, Space.sm)
            .padding(.vertical, Space.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            // 목록 선택은 **중립 채움**이다(브랜드 wash 금지 — Palette 주석·DESIGN.md §2).
            .background(isSelected ? Color.pBtnActive : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickCursor()
    }

    private func sourceLabel(_ source: ScriptSource) -> String {
        switch source {
        case .packageJSON: return "pkg"
        case .makefile: return "make"
        case .shell: return "sh"
        }
    }
}

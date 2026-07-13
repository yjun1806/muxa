import SwiftUI

/// 서비스 상세 팝오버 — 푸터 칩을 **클릭하면** 열린다(사용량·백그라운드 팝오버와 같은 문법).
///
/// 푸터 칩은 "문제가 있나 없나"만 말한다. **무엇이 왜 그런지는 여기서 말한다** —
/// 서비스별 상태·포트·exit code. 행을 클릭하면 그 서비스의 로그(도크)로 바로 가고,
/// 재시작·제거는 도크까지 안 가도 여기서 끝낸다(도크 헤더와 같은 액션 세트).
struct ServicePopover: View {
    let state: AppState
    let project: Project
    /// 서비스가 도는 디렉터리 — 재시작에 필요하다. 모르면 재시작 버튼을 띄우지 않는다(엉뚱한 곳에서 띄우지 않게).
    let cwd: String?
    /// 행 클릭 → 도크를 그 서비스로 연다.
    let onOpen: (String?) -> Void
    /// "서비스 추가" → 도크를 열면서 추가 시트까지 바로 띄운다.
    let onAdd: () -> Void

    private var services: [Service] { state.services(of: project.id) }

    var body: some View {
        FooterPopover(title: "서비스", subtitle: subtitle) {
            FooterMark(icon: "square.stack.3d.up")
        } accessory: {
            if TmuxService.isAvailable, !services.isEmpty {
                FooterAction(icon: "plus", help: "서비스 추가", action: onAdd)
                FooterAction(icon: "rectangle.bottomthird.inset.filled",
                             help: "로그 도크 열기 (⌘J)") { onOpen(nil) }
            }
        } content: {
            if !TmuxService.isAvailable {
                // tmux가 없으면 목록이 있을 리 없다 — 왜 못 쓰는지 말하고 안내(도크)로 보낸다.
                FooterHint(title: "tmux가 필요합니다",
                           detail: "dev 서버를 muxa 바깥에서 살려두는 일을 tmux가 맡습니다.") {
                    Button("설치 안내 보기") { onOpen(nil) }
                        .font(.muxa(.label))
                }
            } else if services.isEmpty {
                // 아무것도 없으면 **추가만** 보여준다 — 빈 목록·빈 상태 문구를 늘어놓지 않는다.
                FooterHint(title: "등록된 서비스가 없습니다",
                           detail: "dev 서버처럼 오래 도는 명령을 등록하면\nmuxa를 꺼도 계속 돕니다.") {
                    Button("서비스 추가", action: onAdd)
                        .font(.muxa(.label))
                }
            } else {
                ForEach(services) { service in
                    row(service)
                }
            }
        }
    }

    /// 헤더 보조 — 목록을 다 읽지 않아도 심각도가 먼저 보인다.
    private var subtitle: String? {
        guard TmuxService.isAvailable, !services.isEmpty else { return nil }
        let dead = services.filter { isDead($0) }.count
        return dead > 0 ? "\(services.count)개 중 \(dead)개 종료됨" : "\(services.count)개 실행 중"
    }

    /// 서비스 한 줄 — [● 이름 :3000 / 명령] + [재시작] [제거].
    ///
    /// 위계: **이름이 제목**(굵게), 명령은 그게 뭔지 알려주는 보조(고정폭·흐리게).
    /// 꼬리표(:3000 / exit 1)는 이름 옆에 붙여 상태와 정체성을 한 눈에 묶는다.
    /// 긴 명령은 가운데를 접어 잘라내고(앞뒤가 다 보이게), 전문은 툴팁으로 돌려준다.
    private func row(_ service: Service) -> some View {
        let status = state.serviceMonitor.states[service.id] ?? .missing
        let tail = ServiceStatusStyle.tail(status, port: state.serviceMonitor.ports[service.id])
        return HStack(spacing: Space.xs) {
            Button { onOpen(service.id) } label: {
                HStack(spacing: Space.sm) {
                    Image(systemName: ServiceStatusStyle.glyph(status))
                        .font(.muxa(.micro))
                        .foregroundStyle(ServiceStatusStyle.color(status))
                        .frame(width: 12)
                    VStack(alignment: .leading, spacing: Space.tight) {
                        HStack(spacing: Space.xs) {
                            Text(service.name)
                                .font(.muxa(.label, weight: .semibold))
                                .foregroundStyle(Color.pFg)
                                .lineLimit(1)
                            if let tail {
                                Text(tail)
                                    .font(.muxaMono(.caption))
                                    .foregroundStyle(ServiceStatusStyle.color(status))
                                    .fixedSize()
                            }
                        }
                        Text(service.command)
                            .font(.muxaMono(.caption))
                            .foregroundStyle(Color.pMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: Space.xs)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("클릭하면 로그를 엽니다 — \(service.command)")

            if let cwd {
                FooterAction(icon: "arrow.clockwise", help: "재시작") {
                    state.restartService(service.id, in: project.id, cwd: cwd)
                }
            }
            FooterAction(icon: "trash", help: "서비스 제거 — 등록을 지우고 프로세스도 종료합니다",
                         destructive: true) {
                state.removeService(service.id, from: project.id)
            }
        }
        .padding(.vertical, Space.xs)
        .panelRow(height: nil) // hover 배경이 좌우 끝까지 — "이 줄 전체가 버튼"이 보인다
    }

    private func isDead(_ service: Service) -> Bool {
        if case .exited(let code) = state.serviceMonitor.states[service.id] ?? .missing { return code != 0 }
        return false
    }
}

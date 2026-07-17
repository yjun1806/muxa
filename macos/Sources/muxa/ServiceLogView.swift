import SwiftUI

/// 죽은 서비스·끝난 스크립트의 로그 — 읽기 전용 텍스트.
///
/// **죽은 프로세스에 터미널을 붙이지 않는다.** 두 가지 이유가 있다:
///  1) 상호작용할 게 없다. 프로세스가 끝났으니 Ctrl+C도 스크롤 외 입력도 의미가 없다.
///  2) 살아있다가 죽는 순간 터미널을 갈아끼우면(뷰 교체) 새 ghostty 서피스가 빈 화면으로 뜨는
///     레이스를 밟는다 — 정작 "왜 죽었는지"를 봐야 할 때 아무것도 안 보인다.
///
/// tmux가 `remain-on-exit`로 마지막 화면을 보존하고 있으므로, capture-pane으로 읽어 그대로 보여준다.
struct ServiceLogView: View {
    /// 읽을 tmux 세션명(서비스·스크립트 규약 무관 — 이름 조립은 호출부의 몫).
    /// nil = id가 규약을 벗어나 세션이 없다("남은 로그가 없습니다"로 정직하게 표시).
    let session: String?
    /// 재시작 등으로 세션이 갈아엎어지면 다시 읽어야 한다.
    let reloadToken: String
    /// **종료 시점 스냅샷 폴백** — 라이브 캡처가 비면(세션이 kill되거나 tmux가 죽어 pane이 없음) 이걸 쓴다.
    /// 재실행·중단·tmux 사망에도 마지막 로그가 살아남게 한다(AppState.finalLogs).
    var fallback: String?

    @State private var log = ""
    @State private var loading = true

    /// capture-pane 출력을 읽기 좋게 정리한다(순수).
    ///
    /// tmux는 **pane 화면 그대로**를 준다 — 짧은 로그 두 줄 뒤에 빈 줄 스무 개, 맨 아래 `Pane is dead`.
    /// 그대로 뿌리면 로그와 사인(死因)이 화면 밖으로 벌어져 정작 봐야 할 것이 안 보인다.
    /// 각 줄의 꼬리 공백을 없애고, 연속 빈 줄을 하나로 접고, 앞뒤 공백을 잘라낸다.
    static func tidy(_ raw: String) -> String {
        var lines: [String] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = String(line).replacingOccurrences(of: "[ \t]+$", with: "",
                                                            options: .regularExpression)
            if trimmed.isEmpty, lines.last?.isEmpty == true { continue } // 연속 빈 줄은 하나로
            lines.append(trimmed)
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            Text(loading ? "로그를 읽는 중…" : (log.isEmpty ? "남은 로그가 없습니다." : log))
                .font(.muxaMono(.caption))
                .foregroundStyle(loading || log.isEmpty ? Color.pMuted : Color.pFg)
                .textSelection(.enabled) // 에러 메시지를 복사해 검색·에이전트에 붙일 수 있게
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.panelInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.pBg)
        .task(id: reloadToken) {
            loading = true
            var raw = ""
            if let session { raw = await TmuxService.capture(session: session, lines: 400) }
            let live = ServiceLogView.tidy(raw)
            // 라이브 pane이 비면 종료 스냅샷으로 — 세션이 사라졌어도 마지막 로그를 보여준다.
            log = live.isEmpty ? ServiceLogView.tidy(fallback ?? "") : live
            loading = false
        }
    }
}

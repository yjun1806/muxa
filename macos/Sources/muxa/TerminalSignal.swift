/// 터미널이 백그라운드에서 보낸 주의 신호 — TermView가 종류만 만들어 넘기고,
/// "지금 이 탭이 보이나?"·"배지를 울릴 가치가 있나?" 판정은 TerminalStore가 한다.
/// (상태·판정은 위(store), 표현·신호는 아래(TermView) — controlled 원칙.)
enum TerminalSignal {
    /// OSC 133 명령 완료. exitCode nil=미보고, duration은 나노초.
    case commandFinished(exitCode: Int?, duration: UInt64)
    /// 벨(주의 환기) — 에이전트가 완료 신호로 자주 쓴다.
    case bell
    /// OSC 9/777 데스크톱 알림.
    case desktopNotification(title: String, body: String)
}

import SwiftUI

/// 서비스 상태의 표시 규칙 — 색·글리프·꼬리표의 단일 출처.
/// 푸터 칩·도크 목록·팝오버 세 곳이 같은 규칙을 써야 "빨간 건 죽은 것"이 흔들리지 않는다.
enum ServiceStatusStyle {
    /// **색만으로 구분하지 않는다**(색맹 안전) — 죽으면 글리프 자체가 바뀐다.
    static func glyph(_ status: ServiceState) -> String {
        switch status {
        case .running: return "circle.fill"
        case .exited(let code): return code == 0 ? "stop.circle" : "exclamationmark.triangle.fill"
        case .missing: return "circle.dotted"
        }
    }

    static func color(_ status: ServiceState) -> Color {
        switch status {
        case .running: return .pServiceRunning
        case .exited(let code): return code == 0 ? .pMuted : .pServiceExited
        case .missing: return .pMuted
        }
    }

    /// 꼬리표 — 포트(알면)나 exit code. 포트를 못 뽑았으면 아무것도 안 붙인다(지어내지 않는다).
    static func tail(_ status: ServiceState, port: Int?) -> String? {
        switch status {
        case .running: return port.map { ":\($0)" }
        case .exited(let code): return code == 0 ? "종료" : "exit \(code)"
        case .missing: return nil
        }
    }

    /// 서비스 여럿의 상태를 하나로 요약한다 — 푸터 칩은 "문제가 있나 없나"만 말한다.
    /// **문제가 최우선이다**: 하나라도 비정상 종료면 그게 요약이다(초록 다수에 묻히면 안 된다).
    static func summarize(_ statuses: [ServiceState]) -> ServiceState {
        if let dead = statuses.first(where: { if case .exited(let c) = $0 { return c != 0 } else { return false } }) {
            return dead
        }
        if statuses.contains(where: { $0 == .running }) { return .running }
        return statuses.first ?? .missing
    }
}

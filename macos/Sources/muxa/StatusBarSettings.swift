import SwiftUI

/// 사용량(Claude) 표시의 사용자 설정 — 팝오버 톱니에서 바꾸고 UserDefaults에 즉시 영속한다.
///
/// **왜 MuxaConfig가 아니라 UserDefaults인가** — `MuxaConfig`는 `~/.config/muxa/config` 파일을
/// **읽기 전용**으로 로드하는 값 타입이다. 여기는 앱 안에서 토글로 바꾸고 바로 저장되는 설정이라,
/// 파일을 되쓰기보다 UserDefaults가 맞다(라이브 @Observable + 즉시 영속).
///
/// 순수 표시 설정만 담는다 — 어떤 리셋 시각을 보일지, fable을 낄지, 어디에 놓을지, 얼마나 자주 갱신할지.
@Observable
final class StatusBarSettings {
    @MainActor static let shared = StatusBarSettings()

    /// 사용량 칩이 앉는 자리 — 푸터/헤더 × 좌/우.
    enum Position: String, CaseIterable, Identifiable {
        case footerLeft, footerRight, headerLeft, headerRight
        var id: String { rawValue }

        var label: String {
            switch self {
            case .footerLeft: return "푸터 왼쪽"
            case .footerRight: return "푸터 오른쪽"
            case .headerLeft: return "헤더 왼쪽"
            case .headerRight: return "헤더 오른쪽"
            }
        }

        var inFooter: Bool { self == .footerLeft || self == .footerRight }
        var isLeading: Bool { self == .footerLeft || self == .headerLeft }
    }

    /// 사용량 막대의 % 대비 색 규칙 — 사용자가 고른다.
    enum MeterColorMode: String, CaseIterable, Identifiable {
        /// 그린·옐로·레드 정석 게이지 — 낮으면 초록(여유), 70%+ 노랑, 90%+ 빨강.
        case gauge
        /// 브랜드색 기반 — 평시 브랜드색(버밀리언), 70%+ 노랑, 90%+ 빨강.
        case brand
        var id: String { rawValue }
        var label: String {
            switch self {
            case .gauge: return "그린·옐로·레드"
            case .brand: return "브랜드색"
            }
        }
    }

    /// 갱신 주기 선택지(초) — 상태바가 이 간격으로 캐시 만료를 다시 본다.
    static let refreshChoices: [Double] = [30, 60, 120, 300]

    /// 5시간 세션 한도 옆에 리셋까지 남은 시간 표시.
    var showSessionReset: Bool { didSet { save(\.showSessionReset, "showSessionReset") } }
    /// 주간 한도 옆에 리셋까지 남은 시간 표시.
    var showWeeklyReset: Bool { didSet { save(\.showWeeklyReset, "showWeeklyReset") } }
    /// fable(모델 전용) 한도를 상태바에도 표시(주간 다음 순서). 시간은 표시하지 않는다.
    var showFable: Bool { didSet { save(\.showFable, "showFable") } }
    /// 칩 위치.
    var position: Position { didSet { defaults.set(position.rawValue, forKey: Self.key("position")) } }
    /// 갱신 주기(초).
    var refreshIntervalSec: Double { didSet { defaults.set(refreshIntervalSec, forKey: Self.key("refreshInterval")) } }
    /// 사용량 막대의 색 모드(정석 게이지 vs 브랜드색).
    var meterColorMode: MeterColorMode { didSet { defaults.set(meterColorMode.rawValue, forKey: Self.key("meterColorMode")) } }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // 기본값: 세션 리셋만 표시(기존 동작), 주간·fable 숨김, 푸터 왼쪽, 60초.
        showSessionReset = defaults.object(forKey: Self.key("showSessionReset")) as? Bool ?? true
        showWeeklyReset = defaults.object(forKey: Self.key("showWeeklyReset")) as? Bool ?? false
        showFable = defaults.object(forKey: Self.key("showFable")) as? Bool ?? false
        position = (defaults.string(forKey: Self.key("position")).flatMap(Position.init(rawValue:))) ?? .footerLeft
        let stored = defaults.double(forKey: Self.key("refreshInterval"))
        refreshIntervalSec = Self.refreshChoices.contains(stored) ? stored : 60
        // 기본값: 정석 게이지(브랜드가 버밀리언이라 낮은 %가 빨강으로 읽히는 걸 피한다).
        meterColorMode = (defaults.string(forKey: Self.key("meterColorMode")).flatMap(MeterColorMode.init(rawValue:))) ?? .gauge
    }

    private static func key(_ name: String) -> String { "muxa.statusbar.\(name)" }

    private func save(_ keyPath: KeyPath<StatusBarSettings, Bool>, _ name: String) {
        defaults.set(self[keyPath: keyPath], forKey: Self.key(name))
    }
}

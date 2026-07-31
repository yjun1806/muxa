import Foundation
import Testing
@testable import muxa

/// claude 사용량 응답 파싱 검증 — 비공식 엔드포인트라 스키마가 흔들릴 수 있어,
/// "깨지더라도 앱은 멀쩡하고 빈 값만 나온다"를 특히 못박는다.
struct ClaudeUsageTests {
    /// 실제 응답에서 딴 픽스처(값만 축약).
    private let real = Data("""
    {
      "five_hour": {"utilization": 9.0, "resets_at": "2026-07-13T06:39:59.921992+00:00"},
      "seven_day": {"utilization": 54.0, "resets_at": "2026-07-14T06:59:59.922014+00:00"},
      "limits": [
        {"kind": "session", "group": "session", "percent": 9, "severity": "normal",
         "resets_at": "2026-07-13T06:39:59.921992+00:00", "scope": null, "is_active": false},
        {"kind": "weekly_all", "group": "weekly", "percent": 54, "severity": "normal",
         "resets_at": "2026-07-14T06:59:59.922014+00:00", "scope": null, "is_active": true},
        {"kind": "weekly_scoped", "group": "weekly", "percent": 17, "severity": "normal",
         "resets_at": "2026-07-14T06:59:59.922014+00:00",
         "scope": {"model": {"id": null, "display_name": "Fable"}, "surface": null}, "is_active": false}
      ]
    }
    """.utf8)

    @Test func parsesThreeLimitsWithLabels() {
        let limits = ClaudeUsage.parse(real)
        #expect(limits.map(\.label) == ["5h", "wk", "Fable"])
        #expect(limits.map(\.percent) == [9, 54, 17])
    }

    /// 상태바는 계정 전체 한도(세션·주간)만 — 모델 전용(Fable)은 팝오버 몫이다.
    @Test func statusBarHidesModelScopedLimits() {
        let shown = ClaudeUsage.statusBar(ClaudeUsage.parse(real))
        #expect(shown.map(\.label) == ["5h", "wk"])
        #expect(!(shown.contains { $0.isModelScoped }))
    }

    /// 모델 스코프 판단은 kind 이름이 아니라 scope.model 유무로 — 서버가 새 스코프를 추가해도 상태바가 조용하다.
    @Test func modelScopeDetectedByScopeNotKindName() {
        let data = Data(#"""
        {"limits":[{"kind":"daily_scoped","percent":5,
                    "scope":{"model":{"display_name":"Opus"}}}]}
        """#.utf8)
        let limit = ClaudeUsage.parse(data).first
        #expect(limit?.isModelScoped == true)
        #expect(ClaudeUsage.statusBar(ClaudeUsage.parse(data)).isEmpty)
    }

    /// 세션 한도만 상태바에 리셋 카운트다운을 띄운다 — 그 판단이 라벨이 아닌 kind에 붙어 있어야 한다.
    @Test func sessionFlagComesFromKind() {
        let limits = ClaudeUsage.parse(real)
        #expect(limits.filter(\.isSession).map(\.label) == ["5h"])
    }

    @Test func modelScopedLimitUsesDisplayName() {
        #expect(ClaudeUsage.label(kind: "weekly_scoped",
                                         scope: ["model": ["display_name": "Fable"]]) == "Fable")
        // 스코프가 비면 모델명을 못 만드니 일반 라벨로 떨어진다(항목이 사라지진 않는다).
        #expect(ClaudeUsage.label(kind: "weekly_scoped", scope: nil) == "모델")
    }

    /// 서버가 항목을 늘려도 조용히 사라지지 않아야 한다 — 모르는 kind는 그대로 보여준다.
    @Test func unknownKindIsKeptNotDropped() {
        let data = Data(#"{"limits":[{"kind":"monthly_new","percent":3,"severity":"normal"}]}"#.utf8)
        let limits = ClaudeUsage.parse(data)
        #expect(limits.count == 1)
        #expect(limits.first?.label == "monthly_new")
    }

    /// percent가 정수(9)로 오든 실수(9.4)로 오든 받아야 한다.
    @Test func percentAcceptsIntAndDouble() {
        let data = Data(#"{"limits":[{"kind":"session","percent":9.6}]}"#.utf8)
        #expect(ClaudeUsage.parse(data).first?.percent == 10) // 반올림
    }

    /// 스키마가 바뀌거나 응답이 깨져도 크래시 없이 빈 배열 — 상태바만 비고 앱은 멀쩡하다.
    @Test func brokenPayloadsYieldEmptyNotCrash() {
        #expect(ClaudeUsage.parse(Data("not json".utf8)).isEmpty)
        #expect(ClaudeUsage.parse(Data("{}".utf8)).isEmpty)
        #expect(ClaudeUsage.parse(Data(#"{"limits":"nope"}"#.utf8)).isEmpty)
        #expect(ClaudeUsage.parse(Data(#"{"limits":[{"kind":"session"}]}"#.utf8)).isEmpty) // percent 없음
    }

    @Test func severityDrivesWarning() {
        let data = Data(#"{"limits":[{"kind":"session","percent":95,"severity":"warning"}]}"#.utf8)
        #expect(ClaudeUsage.parse(data).first?.isWarning == true)
    }

    @Test func resetTextCountsDownAndHidesPast() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(ClaudeUsage.resetText(now.addingTimeInterval(3 * 3600 + 720), now: now) == "3시간 12분 후")
        #expect(ClaudeUsage.resetText(now.addingTimeInterval(300), now: now) == "5분 후")
        #expect(ClaudeUsage.resetText(now.addingTimeInterval(-60), now: now) == nil) // 이미 지남
        #expect(ClaudeUsage.resetText(nil, now: now) == nil)
    }

    /// 주간 한도는 남은 시간이 날 단위 — "27시간 후"가 아니라 "1일 3시간 후"로 읽혀야 한다.
    @Test func resetTextUsesDaysForWeeklyWindow() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let inADayAndThreeHours = now.addingTimeInterval(86400 + 3 * 3600 + 60)
        #expect(ClaudeUsage.resetText(inADayAndThreeHours, now: now) == "1일 3시간 후")
        #expect(ClaudeUsage.resetShort(inADayAndThreeHours, now: now) == "1d 3h")
    }

    @Test func resetShortIsCompact() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(ClaudeUsage.resetShort(now.addingTimeInterval(3 * 3600 + 2280), now: now) == "3h 38m")
        #expect(ClaudeUsage.resetShort(now.addingTimeInterval(720), now: now) == "12m")
        #expect(ClaudeUsage.resetShort(now.addingTimeInterval(-1), now: now) == nil)
    }

    /// 리셋 실제 시각 — 같은 날이면 시각만, 다른 날이면 날짜까지. (로케일 의존이라 존재·차이만 확인)
    @Test func resetClockOmitsDateOnlyWhenSameDay() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let sameDay = ClaudeUsage.resetClock(now.addingTimeInterval(3600), now: now)
        let nextDay = ClaudeUsage.resetClock(now.addingTimeInterval(86400 + 3600), now: now)
        #expect(sameDay != nil)
        #expect(nextDay != nil)
        #expect(nextDay!.count > sameDay!.count) // 날짜가 붙어 더 길다
        #expect(ClaudeUsage.resetClock(now.addingTimeInterval(-1), now: now) == nil)
    }

    @Test func parsesIso8601WithAndWithoutFractionalSeconds() {
        #expect(ClaudeUsage.date(from: "2026-07-13T06:39:59.921992+00:00") != nil)
        #expect(ClaudeUsage.date(from: "2026-07-13T06:39:59Z") != nil)
        #expect(ClaudeUsage.date(from: 1_000_000 as NSNumber) == Date(timeIntervalSince1970: 1_000_000))
        #expect(ClaudeUsage.date(from: "어제") == nil)
    }
}

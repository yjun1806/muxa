import Foundation

/// 연속 신호 병합기(순수 값) — 같은 키의 신호가 cooldown 안에 다시 오면 억제(병합)한다.
/// auto-approve로 에이전트가 도구를 연타하면 같은 탭 배지·시스템 알림이 폭주하는데,
/// 그 반복만 접고 **진짜 새 신호(다른 키·cooldown 밖)는 그대로 통과**시킨다.
///
/// muxa "순수 값 타입 분리" 원칙: 판정·상태(키별 마지막 통과 시각)를 값으로 들고 immutable하게 갱신한다
/// (부작용 없음, 테스트 가능). 경계 타입(TerminalStore)이 인스턴스를 소유하고 신호마다 `admitting`로 태운다.
/// 기존 `bellDebounce`(now - last < 임계)의 systemUptime 패턴을 키 단위로 일반화한 것.
struct SignalCoalescer<Key: Hashable> {
    /// cooldown(초) — 같은 키의 마지막 통과 이후 이 시간 안쪽 신호는 억제된다.
    let cooldown: TimeInterval

    /// 키별 마지막 통과 시각(systemUptime, 단조 증가). 통과한 신호만 갱신한다.
    private var lastAdmittedAt: [Key: TimeInterval]

    init(cooldown: TimeInterval) {
        self.cooldown = cooldown
        self.lastAdmittedAt = [:]
    }

    /// 이 신호를 통과시킬지 판정하고, 통과면 마지막 시각을 갱신한 새 병합기를 함께 돌려준다(immutable).
    /// cooldown 내 중복이면 억제(admit=false)하고 상태는 불변으로 둔다.
    /// - Returns: (admit: 통과 여부, next: 갱신된 병합기 — 억제 시 self와 동일)
    func admitting(_ key: Key, now: TimeInterval) -> (admit: Bool, next: SignalCoalescer) {
        if let last = lastAdmittedAt[key], now - last < cooldown {
            return (false, self)
        }
        var next = self
        next.lastAdmittedAt[key] = now
        return (true, next)
    }

    /// 특정 키의 병합 이력을 지운 새 병합기(주의 해소·탭 종료 시 — 다음 신호가 잘못 억제되지 않게 리셋).
    func resetting(_ predicate: (Key) -> Bool) -> SignalCoalescer {
        var next = self
        next.lastAdmittedAt = lastAdmittedAt.filter { !predicate($0.key) }
        return next
    }
}

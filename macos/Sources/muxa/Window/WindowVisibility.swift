/// 탭이 "지금 사용자 눈에 보이나"의 순수 판정 — 알림 억제 게이트의 입력이다.
enum WindowVisibility {
    /// `appActive`가 빠지면 앱이 백그라운드일 때도 "보인다"가 되어 **에이전트 완료 알림이 전면 억제된다**(제품 가치 소멸).
    /// 그래서 창 판별(key 여부)이 아니라 앱 활성 + 창 가시성으로 판정한다.
    static func isVisible(appActive: Bool,
                          windowVisible: Bool,
                          miniaturized: Bool,
                          occluded: Bool) -> Bool {
        appActive && windowVisible && !miniaturized && !occluded
    }
}

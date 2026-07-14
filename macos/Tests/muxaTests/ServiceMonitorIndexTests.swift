import Foundation
import Testing
@testable import muxa

/// 저장 파일(state.v4.json)은 신뢰 경계 밖이다 — 복붙·동기화 충돌로 같은 serviceId가 둘 생길 수 있다.
/// 색인이 `Dictionary(uniqueKeysWithValues:)`였을 때는 그 순간 fatalError로 앱이 죽었고,
/// 다시 켜도 같은 파일을 읽어 또 죽었다(영구 부팅 불가). 죽지 않고 첫 항목을 남긴다.
struct ServiceMonitorIndexTests {
    @Test @MainActor func 중복_서비스id에도_죽지_않고_색인한다() {
        let services = [Service(id: "S", name: "web", command: "pnpm dev"),
                        Service(id: "S", name: "web(복사본)", command: "pnpm dev")]
        let byId = ServiceMonitor.index(services)
        #expect(byId.count == 1)
        #expect(byId["S"]?.name == "web") // 먼저 온 것이 이긴다
    }

    @Test @MainActor func 정상_목록은_그대로_색인된다() {
        let services = [Service(id: "A", name: "web", command: "pnpm dev"),
                        Service(id: "B", name: "api", command: "cargo run")]
        let byId = ServiceMonitor.index(services)
        #expect(byId.count == 2)
        #expect(byId["B"]?.command == "cargo run")
    }
}

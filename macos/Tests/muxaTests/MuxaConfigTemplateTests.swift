import Testing
@testable import muxa

/// '설정 파일 열기'가 만들어 주는 기본 설정본 — 값이 아니라 "무엇을 쓸 수 있는지"만 알려야 한다.
struct MuxaConfigTemplateTests {
    @Test("기본 템플릿은 전부 주석이라 파싱하면 기본값과 같다")
    func 템플릿은기본값() {
        #expect(MuxaConfig.parse(MuxaConfig.template) == MuxaConfig.defaults)
    }

    @Test("템플릿이 실제 설정 키를 안내한다")
    func 키안내포함() {
        for key in ["sidebar_mode", "confirm_quit", "default_workspace_path", "agent_resume", "keybind."] {
            #expect(MuxaConfig.template.contains(key), "안내 누락: \(key)")
        }
    }
}

import Foundation

/// CC 프롬프트에 넣을 `@`멘션 경로를 고른다(순수). 대상 CC의 작업 디렉터리(`base`) **아래** 파일이면
/// 상대경로가 짧고 자연스럽다 — CC가 자기 cwd 기준으로 곧장 연다. `base`를 모르거나 그 밖의 파일이면
/// 절대경로 그대로 둔다(CC는 절대경로도 연다). `@`는 붙이지 않는다 — 호출부가 붙인다.
///
/// 파괴적이지 않은 순수 판정이라 UI 없이 테스트로 못 박는다(경계 슬래시·정확한 접두 경계만 다룬다).
enum AtMention {
    static func path(for filePath: String, relativeTo base: String?) -> String {
        guard let base, !base.isEmpty, base != "/" else { return filePath }
        let root = base.hasSuffix("/") ? base : base + "/"
        guard filePath.hasPrefix(root) else { return filePath }
        let rel = String(filePath.dropFirst(root.count))
        return rel.isEmpty ? filePath : rel
    }
}

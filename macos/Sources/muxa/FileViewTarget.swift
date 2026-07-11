import Foundation

/// 뷰어 탭이 여는 파일 — 확장자로 렌더 종류를 해석한다. (GitDiffTarget 대응)
/// 확장자→종류 매핑을 여기 한 곳에 캡슐화해, openFile·렌더 분기가 각각 하나로 재사용된다.
struct FileViewTarget: Identifiable, Equatable {
    let path: String

    /// 탭 dedup·복원 키. 제목이 아니라 전체 경로로 식별(동명 파일 충돌 방지).
    var id: String { "file:\(path)" }

    enum Kind { case markdown, code, html, image, video }

    var kind: Kind {
        switch (path as NSString).pathExtension.lowercased() {
        case "md", "markdown", "mdown", "mkd", "mkdn": return .markdown
        case "html", "htm", "xhtml": return .html
        case "png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "tif", "heic", "heif", "ico", "icns":
            return .image
        // AVFoundation이 재생 가능한 컨테이너만(webm·mkv 등은 코덱 미지원이라 제외).
        case "mp4", "mov", "m4v", "mpg", "mpeg", "3gp":
            return .video
        default: return .code
        }
    }

    /// 탭 라벨(짧게) — basename.
    var tabTitle: String { basename(path) }

    var tabIcon: String {
        switch kind {
        case .markdown: return "doc.richtext"
        case .html: return "chevron.left.forwardslash.chevron.right"
        case .code: return "doc.text"
        case .image: return "photo"
        case .video: return "play.rectangle"
        }
    }

    /// highlight.js 언어명(확장자 매핑). nil이면 하이라이터가 자동 감지.
    var language: String? {
        switch (path as NSString).pathExtension.lowercased() {
        case "swift": return "swift"
        case "ts", "tsx", "mts", "cts": return "typescript"
        case "js", "jsx", "mjs", "cjs": return "javascript"
        case "rs": return "rust"
        case "py", "pyi": return "python"
        case "go": return "go"
        case "json", "json5", "jsonc": return "json"
        case "yml", "yaml": return "yaml"
        case "toml": return "toml"
        case "sh", "bash", "zsh", "fish": return "bash"
        case "html", "htm", "xml", "svg": return "xml"
        case "css": return "css"
        case "scss", "sass": return "scss"
        case "c", "h": return "c"
        case "cpp", "cc", "cxx", "hpp", "hh": return "cpp"
        case "m", "mm": return "objectivec"
        case "java": return "java"
        case "kt", "kts": return "kotlin"
        case "rb": return "ruby"
        case "php": return "php"
        case "sql": return "sql"
        case "lua": return "lua"
        case "dart": return "dart"
        default: return nil
        }
    }
}

import AppKit

/// Material Icon Theme(PKief, MIT) 슬림 번들 기반 파일 아이콘 해석기.
/// VSCode의 컬러 파일/폴더 아이콘을 오프라인으로 제공한다. 번들 재생성은
/// `scripts/build-fileicons/build.py` (Resources/fileicons/*.svg + icons.json).
///
/// 매칭 규칙은 material-icon-theme를 따른다:
///   파일 = fileNames(원본→소문자) → 확장자(복합 최장 우선, 소문자) → 기본 file
///   폴더 = folderNames(소문자) → 기본 folder
/// 결과 NSImage는 아이콘 이름으로 캐시(같은 확장자 재로드 방지).
@MainActor
enum IconTheme {
    private struct Mapping: Decodable {
        let file: String
        let folder: String
        let fileExtensions: [String: String]
        let fileNames: [String: String]
        let folderNames: [String: String]
    }

    private static let mapping: Mapping? = {
        guard let url = Bundle.module.url(forResource: "icons", withExtension: "json", subdirectory: "fileicons"),
              let data = try? Data(contentsOf: url),
              let m = try? JSONDecoder().decode(Mapping.self, from: data) else { return nil }
        return m
    }()

    private static var cache: [String: NSImage] = [:]

    /// 노드에 대응하는 컬러 아이콘. 매핑/SVG 실패 시 nil(호출부가 시스템 아이콘으로 폴백).
    static func image(for node: FileNode) -> NSImage? {
        guard let name = iconName(for: node) else { return nil }
        return image(named: name)
    }

    /// 파일/폴더 → 아이콘 이름.
    private static func iconName(for node: FileNode) -> String? {
        guard let m = mapping else { return nil }
        if node.isDirectory {
            return m.folderNames[node.name.lowercased()] ?? m.folder
        }
        // 1) 정확한 파일명(원본 → 소문자)
        if let n = m.fileNames[node.name] ?? m.fileNames[node.name.lowercased()] { return n }
        // 2) 확장자 — 복합(test.ts 등) 최장 우선. "a.b.c" → "b.c" → "c".
        let lower = node.name.lowercased()
        let parts = lower.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count >= 2 {
            for start in 1..<parts.count {
                let ext = parts[start...].joined(separator: ".")
                if let n = m.fileExtensions[ext] { return n }
            }
        }
        return m.file
    }

    /// 아이콘 이름 → 번들 SVG를 NSImage로(캐시). 없으면 nil.
    private static func image(named name: String) -> NSImage? {
        if let cached = cache[name] { return cached }
        guard let url = Bundle.module.url(forResource: name, withExtension: "svg", subdirectory: "fileicons"),
              let img = NSImage(contentsOf: url) else { return nil }
        img.isTemplate = false // 컬러 원본 유지(틴트 금지)
        cache[name] = img
        return img
    }
}

import AppKit
import UniformTypeIdentifiers

/// 파일 타입 아이콘. 1순위 = Material Icon Theme(컬러, VSCode 동일 세트),
/// 폴백 = 시스템(NSWorkspace) 아이콘 + 폴더 SF Symbol.
enum FileIcon {
    @MainActor
    static func image(for node: FileNode) -> NSImage {
        if let material = IconTheme.image(for: node) { return material }
        // 폴백 — Material 매핑에 없거나 SVG 로드 실패.
        if node.isDirectory {
            return NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil) ?? NSImage()
        }
        let ext = (node.name as NSString).pathExtension
        if !ext.isEmpty, let type = UTType(filenameExtension: ext) {
            return NSWorkspace.shared.icon(for: type)
        }
        return NSWorkspace.shared.icon(for: .data)
    }
}

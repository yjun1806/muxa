import AppKit
import UniformTypeIdentifiers

/// 파일 타입 아이콘. 1차 = 시스템(NSWorkspace) 아이콘 + 폴더 SF Symbol.
/// Material Icon Theme 세트는 후속(Task 14)에서 이 한 함수만 교체해 VSCode급으로 올린다.
enum FileIcon {
    static func image(for node: FileNode) -> NSImage {
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

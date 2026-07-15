import AppKit

/// 클립보드에 **이미지**가 있으면(스크린샷 등 텍스트 표현이 없는 경우) 임시 PNG로 저장하고
/// 그 파일 경로를 돌려주는 경계 타입.
///
/// Cmd+V 붙여넣기 경로에서만 쓴다. libghostty의 `read_clipboard_cb`는 텍스트(`.string`)만 읽으므로
/// 스크린샷처럼 텍스트가 없는 클립보드는 아무것도 안 붙었다. 이미지를 임시 파일로 떨어뜨리고 그 **경로를
/// 프롬프트에 넣으면** claude code가 첨부로 인식한다 — muxa의 파일 드롭 첨부와 완전히 같은 메커니즘이며,
/// cmux·orca 두 참조 구현도 동일하게 "임시 PNG 저장 → 경로 붙여넣기"로 처리한다.
///
/// 파일 쓰기·정리 같은 부작용은 여기에만 격리한다(경로 포맷은 순수 로직 `TerminalDrop`이 담당).
enum ClipboardImage {
    /// muxa가 클립보드 이미지를 임시로 쌓는 전용 디렉토리.
    private static let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("muxa-clipboard", isDirectory: true)

    /// 하루 지난 임시 이미지는 붙여넣기가 끝난 것으로 보고 지운다. 로컬 붙여넣기는 즉시 삭제할 수 없다
    /// — 셸/claude가 나중에 그 경로를 읽어야 하므로. 대신 새로 쓸 때마다 오래된 것만 훑어 정리한다.
    private static let maxAge: TimeInterval = 24 * 60 * 60

    /// pasteboard에 이미지가 있으면 임시 PNG로 저장하고 경로를 반환한다. 없거나 실패하면 nil.
    static func materialize(from pasteboard: NSPasteboard) -> String? {
        guard let png = pngData(from: pasteboard) else { return nil }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            pruneOld(in: directory, using: fm)
            let url = directory.appendingPathComponent("clipboard-\(UUID().uuidString.prefix(8)).png")
            try png.write(to: url)
            return url.path
        } catch {
            NSLog("[muxa] 클립보드 이미지 저장 실패: \(error.localizedDescription)")
            return nil
        }
    }

    /// pasteboard에서 PNG 바이트를 뽑는다. macOS 스크린샷은 TIFF로 오므로 PNG로 변환한다.
    private static func pngData(from pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png), !png.isEmpty { return png }
        guard let tiff = pasteboard.data(forType: .tiff),
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]),
              !png.isEmpty else { return nil }
        return png
    }

    /// maxAge를 넘긴 파일만 지운다 — 판정은 좁게, 정리 실패는 무시한다(정리 때문에 붙여넣기를 막지 않는다).
    private static func pruneOld(in directory: URL, using fm: FileManager) {
        guard let urls = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-maxAge)
        for url in urls {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            if let modified, modified < cutoff {
                try? fm.removeItem(at: url)
            }
        }
    }
}

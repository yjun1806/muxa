import AppKit

/// 서브탭(문서·변경 그룹 안의 개별 칩) 우클릭 메뉴 — 닫기와 "이 파일이 어디 있나"가 전부다.
/// 서브탭은 뷰어(읽기 전용)라 편집 계열 동작은 없다.
@MainActor
enum SubTabMenu {
    /// `dir`은 리포 루트 — diff 항목의 상대 경로를 절대 경로로 풀 때 쓴다.
    static func items(_ item: GroupItemContent, dir: String, siblings: Int,
                      onClose: @escaping () -> Void, onCloseOthers: @escaping () -> Void) -> [MuxaMenuItem] {
        var items: [MuxaMenuItem] = [
            MuxaMenuItem(icon: "xmark", title: "닫기", shortcut: "⌘W", action: onClose),
            MuxaMenuItem(icon: "xmark.square.fill", title: "다른 서브탭 모두 닫기",
                         enabled: siblings > 1, action: onCloseOthers),
        ]
        if let path = absolutePath(item, dir: dir) {
            items.append(.separator)
            items.append(MuxaMenuItem(icon: "doc.on.doc", title: "경로 복사") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(path, forType: .string)
            })
            items.append(MuxaMenuItem(icon: "arrow.up.forward.app", title: "Finder에서 보기") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            })
        }
        if case .diff(.commit(let hash, _)) = item {
            items.append(.separator)
            items.append(MuxaMenuItem(icon: "number", title: "커밋 해시 복사") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(hash, forType: .string)
            })
        }
        if case .web(let tab) = item {
            let url = tab.currentURL.absoluteString
            items.append(.separator)
            items.append(MuxaMenuItem(icon: "link", title: "URL 복사") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url, forType: .string)
            })
            items.append(MuxaMenuItem(icon: "arrow.up.right.square", title: "시스템 브라우저로 열기") {
                NSWorkspace.shared.open(tab.currentURL)
            })
        }
        return items
    }

    /// 이 서브탭이 가리키는 실제 파일 경로 — 파일 뷰어는 절대 경로, 파일 diff는 리포 루트 기준 상대 경로다.
    /// 커밋·전체 diff는 특정 파일이 없다(nil).
    private static func absolutePath(_ item: GroupItemContent, dir: String) -> String? {
        switch item {
        case .file(let target):
            return target.path
        case .diff(.file(let change)):
            return dir.isEmpty ? nil : (dir as NSString).appendingPathComponent(change.path)
        case .diff:
            return nil
        case .web:
            return nil // 브라우저 서브탭은 파일이 아니다(URL 복사는 items에서 따로 붙인다)
        }
    }
}

import AppKit

/// 서브탭(문서·변경 그룹 안의 개별 칩) 우클릭 메뉴 — 닫기와 "이 파일이 어디 있나"가 전부다.
/// 서브탭은 뷰어(읽기 전용)라 편집 계열 동작은 없다.
@MainActor
enum SubTabMenu {
    /// `dir`은 리포 루트 — diff 항목의 상대 경로를 절대 경로로 풀 때 쓴다.
    static func items(_ item: GroupItemContent, dir: String, siblings: Int,
                      onClose: @escaping () -> Void, onCloseOthers: @escaping () -> Void,
                      onDetachRight: @escaping () -> Void = {}, onDetachDown: @escaping () -> Void = {},
                      mergeOptions: [MuxaMenuItem] = [],
                      onSendToClaude: @escaping (String) -> Void = { _ in }, canSend: Bool = false,
                      onClearContext: @escaping () -> Void = {}) -> [MuxaMenuItem] {
        var items: [MuxaMenuItem] = [
            MuxaMenuItem(icon: "xmark", title: "닫기", shortcut: "⌘W", action: onClose),
            MuxaMenuItem(icon: "xmark.square.fill", title: "다른 서브탭 모두 닫기",
                         enabled: siblings > 1, action: onCloseOthers),
        ]
        // 분리 — 항목이 둘 이상일 때만(하나뿐이면 그룹 탭 통째 이동이라 의미 없음).
        if siblings > 1 {
            items.append(.separator)
            items.append(MuxaMenuItem(icon: "rectangle.split.2x1", title: "옆으로 분리", action: onDetachRight))
            items.append(MuxaMenuItem(icon: "rectangle.split.1x2", title: "아래로 분리", action: onDetachDown))
        }
        // 병합 — 다른 패인의 같은 종류 그룹으로 이 그룹째 합친다("단 같은 그룹만"). 대상이 있을 때만.
        if !mergeOptions.isEmpty {
            items.append(.separator)
            items.append(contentsOf: mergeOptions)
        }
        if let path = item.filePath(dir: dir) {
            items.append(.separator)
            // 이 문서를 마지막 활성 CC 프롬프트에 `@경로`로 붙인다(제출은 사용자). 보낼 터미널이 없으면 비활성.
            items.append(MuxaMenuItem(icon: "sparkle", title: "Claude에 보내기",
                                      enabled: canSend, action: { onSendToClaude(path) }))
            // 공유 중인 IDE 컨텍스트(선택·활성 파일)를 지운다 — 자동 공유는 두되 원할 때 끈다.
            items.append(MuxaMenuItem(icon: "xmark.circle", title: "Claude 컨텍스트 지우기", action: onClearContext))
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
}

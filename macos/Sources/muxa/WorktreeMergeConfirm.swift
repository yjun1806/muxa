import AppKit

/// 워크트리 마무리(merge 후 정리) 동선의 파괴적 확인·오류 다이얼로그. (DESIGN 4.4 #5)
/// 메인 스레드(runModal)에서 호출 — SwiftUI 버튼 액션·MainActor Task 컨텍스트가 이에 해당.
enum WorktreeMergeConfirm {
    /// 병합+정리 확인. 확인 시 true. 파괴적(브랜치·워크트리 삭제)이라 되돌릴 수 없음을 명시한다.
    static func confirm(branch: String, target: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "‘\(branch)’를 \(target)에 병합하고 정리할까요?"
        alert.informativeText = "fast-forward로 병합한 뒤 이 워크트리를 제거하고 브랜치 ‘\(branch)’를 삭제합니다. 되돌릴 수 없어요."
        alert.addButton(withTitle: "병합 후 정리") // 첫 버튼 = 기본(Enter)
        alert.addButton(withTitle: "취소")
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// 실패 사유 표면화(충돌·발산·제거 실패 등).
    static func showError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "워크트리 정리를 완료하지 못했어요"
        alert.informativeText = message
        alert.addButton(withTitle: "확인")
        alert.runModal()
    }
}

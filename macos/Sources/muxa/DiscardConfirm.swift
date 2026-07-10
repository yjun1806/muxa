import AppKit

/// 변경 버리기(discard)의 파괴적 확인 다이얼로그. git 패널·diff 도구줄이 공유한다.
/// 메인 스레드(runModal)에서 호출 — SwiftUI 버튼 액션 컨텍스트가 이에 해당.
enum DiscardConfirm {
    /// 확인 시 true. untracked면 휴지통(복구 가능), 아니면 커밋 상태로 되돌림(복구 불가) 문구를 보여준다.
    static func confirm(fileName: String, untracked: Bool) -> Bool {
        let alert = NSAlert()
        alert.messageText = "변경을 버릴까요?"
        alert.informativeText = untracked
            ? "‘\(fileName)’을(를) 휴지통으로 이동합니다. 나중에 복구할 수 있어요."
            : "‘\(fileName)’의 변경 내용이 사라지고 마지막 커밋 상태로 되돌아갑니다. 되돌릴 수 없어요."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "변경 버리기")
        alert.addButton(withTitle: "취소")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

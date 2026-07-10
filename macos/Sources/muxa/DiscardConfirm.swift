import AppKit

/// 변경 버리기(discard)의 파괴적 확인 다이얼로그. git 패널·diff 도구줄이 공유한다.
/// 메인 스레드(runModal)에서 호출 — SwiftUI 버튼 액션 컨텍스트가 이에 해당.
enum DiscardConfirm {
    /// 확인 시 true. untracked면 휴지통(복구 가능), 아니면 커밋 상태로 되돌림(복구 불가) 문구를 보여준다.
    static func confirm(fileName: String, untracked: Bool) -> Bool {
        ask(message: "변경을 버릴까요?", detail: untracked
            ? "‘\(fileName)’을(를) 휴지통으로 이동합니다. 나중에 복구할 수 있어요."
            : "‘\(fileName)’의 변경 내용이 사라지고 마지막 커밋 상태로 되돌아갑니다. 되돌릴 수 없어요.")
    }

    /// hunk 하나만 버릴 때의 확인. 워크트리에서 그 변경만 사라지고 되돌릴 수 없다.
    static func confirmHunk(fileName: String) -> Bool {
        ask(message: "이 변경을 버릴까요?",
            detail: "‘\(fileName)’에서 선택한 변경(hunk)이 사라집니다. 되돌릴 수 없어요.")
    }

    /// 파괴적 확인 경고(버튼: 변경 버리기 / 취소). 확인 시 true.
    private static func ask(message: String, detail: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.addButton(withTitle: "변경 버리기")
        alert.addButton(withTitle: "취소")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

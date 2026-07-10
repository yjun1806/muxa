import Foundation

/// 변경 버리기(discard)를 실행할 단계 목록 — 부작용 없는 순수 계획. 실행은 GitService+Write가 순서대로 한다.
/// 파일 종류(추적안됨·새로추가·리네임·일반)마다 데이터 손실 없이 안전한 단계가 다르므로 여기서 결정한다.
enum DiscardPlan {
    /// 한 단계 — git 명령이거나 워크트리 파일을 휴지통으로.
    enum Step: Equatable {
        case git([String])   // `git <args>` 실행(exit 0 기대)
        case trash(String)   // dir 기준 상대경로를 휴지통으로 이동(복구 가능)
    }

    /// change 하나를 안전하게 버리는 단계들(순서대로 실행).
    /// - 추적 안 됨(?): 휴지통으로(복구 가능).
    /// - 새로 스테이지(A): HEAD에 없어 restore 불가 → 언스테이지 후 휴지통.
    /// - 스테이지된 리네임(R): 원본·대상 모두 안전 처리 — 인덱스를 HEAD로 되돌려 리네임을 취소하고,
    ///   원본을 워크트리에 복원한 뒤, 이제 untracked가 된 대상 파일을 휴지통으로(복구 가능).
    ///   (opPath만 restore하면 원본이 삭제된 채 남아 데이터가 사라질 수 있어 분리한다.)
    /// - 그 외 추적 파일(수정·삭제 등): 인덱스·워크트리를 마지막 커밋(HEAD)으로.
    static func steps(for change: GitFileChange) -> [Step] {
        if change.isUntracked {
            return [.trash(change.opPath)]
        }
        if change.isRename {
            let old = change.oldPath
            let new = change.newPath
            return [
                .git(["restore", "--staged", "--", old, new]),        // 인덱스를 HEAD로(리네임 취소)
                .git(["restore", "--worktree", "--source=HEAD", "--", old]), // 원본 워크트리 복원
                .trash(new),                                          // 대상은 이제 untracked → 휴지통
            ]
        }
        if change.index == "A" {
            return [.git(["restore", "--staged", "--", change.opPath]), .trash(change.opPath)]
        }
        return [.git(["restore", "--staged", "--worktree", "--source=HEAD", "--", change.opPath])]
    }
}

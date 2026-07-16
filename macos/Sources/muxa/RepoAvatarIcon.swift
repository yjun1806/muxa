import SwiftUI

/// 워크스페이스 리포 아바타 — git remote의 GitHub owner 아바타(orca의 기본 리포 아이콘과 같은 출처).
///
/// **정체성 마크라 원본 색을 유지한다**(ClaudeMark와 같은 규칙 — 크롬 무채 원칙의 예외는 정체성뿐).
/// URL이 없거나(비 GitHub·remote 없음) 아직 로딩 전이면 **호출부의 폴백**(레이어 글리프·이니셜)이 보인다 —
/// 이 뷰는 "아바타가 확정된 경우"만 그린다. 로딩 중 자리는 옅은 원(placeholder)로 지킨다.
struct RepoAvatarIcon: View {
    let url: URL
    var size: CGFloat = IconSize.inlineMark

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Circle().fill(Color.pBtnHover) // 로딩 중 — 자리만 조용히
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

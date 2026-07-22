import Foundation

/// md/HTML 뷰어에서 클릭된 링크(href)를 어디로 보낼지 판정하는 순수 로직.
/// 부작용(브라우저 열기·탭 열기·파일 존재 확인)은 경계(MarkdownWebView.Coordinator)에 둔다 —
/// 여기서는 href·baseDir만 보고 목적지 종류와 경로만 계산한다(테스트 가능).
/// 외부로 넘길 링크 스킴 화이트리스트. 여기 없는 스킴은 무시한다.
enum MarkdownLinkSchemes {
    static let external: Set<String> = ["http", "https", "mailto"]
}

enum MarkdownLinkTarget: Equatable {
    /// 외부(웹·mailto 등) — 시스템 기본 앱으로.
    case external(URL)
    /// 로컬 파일(절대경로) — 앱 내 새 탭 뷰어로. 존재 확인은 호출측 몫.
    case localFile(String)
    /// 처리하지 않음 — 빈 링크·페이지 내 앵커(#…)·해석 불가.
    case ignore
}

/// 링크 href를 판정한다.
/// - 스킴이 있으면: `file`은 로컬 파일, 그 외(http·https·mailto·tel…)는 외부.
/// - 스킴이 없으면: baseDir 기준 상대경로 → 로컬 파일. 단 순수 프래그먼트(#…)는 무시.
/// 프래그먼트(#…)와 퍼센트 인코딩(%20)은 경로에서 제거·복원한다.
func resolveMarkdownLink(href rawHref: String, baseDir: String) -> MarkdownLinkTarget {
    let href = rawHref.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !href.isEmpty, !href.hasPrefix("#") else { return .ignore }

    guard let comps = URLComponents(string: href) else { return .ignore }

    if let scheme = comps.scheme?.lowercased() {
        if scheme == "file" {
            let path = comps.path.removingPercentEncoding ?? comps.path
            guard !path.isEmpty else { return .ignore }
            return .localFile((path as NSString).standardizingPath)
        }
        // 외부는 안전한 스킴만 연다 — md 본문은 신뢰 경계 밖일 수 있어(clone한 리포 등)
        // javascript:·data:·커스텀 스킴을 NSWorkspace로 넘기지 않는다.
        guard MarkdownLinkSchemes.external.contains(scheme),
              let url = URL(string: href) else { return .ignore }
        return .external(url)
    }

    // 스킴 없음 → 상대경로 파일. 프래그먼트만 있는 경우는 위에서 걸러졌다.
    let rawPath = comps.path
    guard !rawPath.isEmpty else { return .ignore }
    let path = rawPath.removingPercentEncoding ?? rawPath

    let joined = (path as NSString).isAbsolutePath
        ? path
        : (baseDir as NSString).appendingPathComponent(path)
    return .localFile((joined as NSString).standardizingPath)
}

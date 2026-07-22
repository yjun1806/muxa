import Foundation

/// 주소창에 입력한 문자열을 로드할 URL로 정규화하는 순수 로직.
/// 스킴이 없으면 https를 가정하고, 공백이 든 검색어성 입력은 거른다(검색은 미지원).
/// 부작용 없이 문자열→URL만 계산한다(테스트 가능).
func normalizeBrowserAddress(_ raw: String) -> URL? {
    let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty else { return nil }

    // 이미 http(s) 스킴이면 그대로.
    if let u = URL(string: t), let scheme = u.scheme?.lowercased(),
       scheme == "http" || scheme == "https" {
        return u
    }
    // 스킴 없음 → https 가정. 공백이 있으면 URL이 아니라 검색어로 보고 거른다.
    guard !t.contains(" ") else { return nil }
    return URL(string: "https://" + t)
}

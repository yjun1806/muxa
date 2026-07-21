import Foundation

/// 명령 이름 자동완성 — muxa가 **이미 아는 명령**(즐겨찾기·발견 스크립트·히스토리)에서 매칭한다(순수).
///
/// Kiro CLI 완성의 *느낌*을 임의 CLI 엔진(JS 스펙·figterm) 없이 낸다: 런처에 필요한 건 임의 플래그가
/// 아니라 "아는 명령을 빨리 다시 부르기"다. 매칭은 순수, 표시·적용은 호출부(`ServiceDock`).
enum CommandComplete {
    /// 드롭다운이 화면을 덮지 않게 후보 상한.
    static let limit = 8

    /// 세 소스를 우선순위 순(즐겨찾기 → 발견 → 히스토리)으로 정규화한다(순수).
    /// `panelSections`가 이미 서로소로 갈라주므로 교차 dedup은 불필요 — 이어붙이기만 한다.
    static func candidates(favorites: [CommandEntry], scripts: [DiscoveredScript],
                           history: [CommandEntry]) -> [CommandSuggestion] {
        favorites.map { CommandSuggestion(command: $0.command, label: $0.name ?? $0.command,
                                          source: "즐겨찾기", glyph: "star.fill") }
        + scripts.map { CommandSuggestion(command: $0.command, label: $0.name,
                                          source: $0.source, glyph: "play.square") }
        + history.map { CommandSuggestion(command: $0.command, label: $0.command,
                                          source: "최근", glyph: "clock") }
    }

    /// `input`으로 후보를 거른다(순수). 대소문자 무시, `command`·`label` 어느 쪽이든 매칭.
    /// 접두 매칭을 앞에 두고, 각 그룹은 후보 순서(우선순위)를 지킨다.
    /// 입력과 정확히 같은 명령(이미 다 친 것)은 덮지 않게 뺀다. 빈 입력 → 후보 없음(런처: 아무것도 안 띄움).
    static func match(_ input: String, in candidates: [CommandSuggestion]) -> [CommandSuggestion] {
        let q = input.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        var prefix: [CommandSuggestion] = []
        var contains: [CommandSuggestion] = []
        for c in candidates {
            let cmd = c.command.lowercased(), label = c.label.lowercased()
            if cmd == q { continue }
            if cmd.hasPrefix(q) || label.hasPrefix(q) { prefix.append(c) }
            else if cmd.contains(q) || label.contains(q) { contains.append(c) }
        }
        return Array((prefix + contains).prefix(limit))
    }
}

/// 완성 후보 한 줄 — 표시(제목·부제·아이콘) + 적용값(`command`). `command`가 신원.
struct CommandSuggestion: Equatable, Identifiable {
    /// 적용값 — 고르면 입력창에 채운다. "pnpm run dev"
    let command: String
    /// 표시 제목 — 친근한 이름 또는 명령 그대로. "dev"
    let label: String
    /// 부제 — 어디서 왔나. "즐겨찾기" · "package.json" · "최근"
    let source: String
    /// SF Symbol 이름.
    let glyph: String
    var id: String { command }
}

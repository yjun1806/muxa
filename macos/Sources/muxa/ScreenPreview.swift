import Foundation

/// 백그라운드 세션의 "마지막 화면" 미리보기를 **읽을 수 있는 몇 줄**로 간추리는 순수 로직.
///
/// tmux `capture-pane`이 주는 건 화면 **그대로**다. 그래서 그냥 마지막 몇 줄을 자르면
/// claude 같은 TUI에선 입력 상자의 **테두리**(`│ … │`)가, 유휴 셸에선 **프롬프트 찌꺼기**(`└%`, `^R`)가
/// 미리보기로 올라온다 — 어느 세션이었는지 알려주는 정보가 하나도 없다(실측).
///
/// 그래서 세 가지를 걷어낸다:
/// 1. **테두리·블록 글리프** — 지우고 나서 남는 알맹이가 진짜 내용이다.
/// 2. **알맹이가 없는 줄** — 기호뿐이거나 너무 짧은 줄(프롬프트 심볼).
/// 3. **이미 위에 쓴 정보** — 프롬프트가 찍은 현재 경로. 행에 cwd를 이미 보여주고 있다.
enum ScreenPreview {
    /// 화면 덤프 → 미리보기 `limit`줄. 마지막(=가장 최근) 쪽을 남긴다.
    static func summarize(_ raw: String, cwd: String? = nil, home: String? = nil, limit: Int = 3) -> String {
        let paths = [cwd, displayPath(cwd, home: home)].compactMap { $0 }.filter { !$0.isEmpty }
        let kept = raw
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { squeeze(dropPathPrefix(strip($0), paths: paths)) }
            .filter(hasSubstance)
        return dedup(kept).suffix(limit).joined(separator: "\n")
    }

    /// 에이전트가 **마지막으로 한 말**을 미리보기 `limit`줄로 — 화면이 아니라 대화 기록에서 온 텍스트다.
    /// 화면 덤프와 달리 테두리·프롬프트가 없으니, 빈 줄만 걷어내고 **앞쪽**을 남긴다(말은 첫머리가 요지다).
    static func message(_ text: String, limit: Int = 3) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { squeeze(String($0)) }
            .filter { !$0.isEmpty }
            .prefix(limit)
            .joined(separator: "\n")
    }

    /// 줄 **맨 앞**의 현재 경로를 떼어낸다 — 프롬프트가 매 줄 앞에 찍는 그것.
    /// 경로는 행에서 이미 보여주고 있고, 그대로 두면 한 줄이 세 줄로 접혀 미리보기 예산을 다 먹는다
    /// (실측: 프롬프트 한 줄 = `경로 + 브랜치 + 명령 + 시각`이 통째로 한 줄이다).
    /// 맨 앞만 떼는 이유: 줄 가운데의 경로는 진짜 내용일 수 있다(`cd ~/x`, 에러 메시지의 파일 경로).
    private static func dropPathPrefix(_ line: String, paths: [String]) -> String {
        guard let hit = paths.first(where: line.hasPrefix) else { return line }
        return String(line.dropFirst(hit.count))
    }

    /// 터미널은 화면 칸을 공백으로 메운다 — 공백 덩어리를 한 칸으로 접지 않으면 한 줄이 화면 폭만큼 벌어진다.
    private static func squeeze(_ line: String) -> String {
        line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// 테두리(─│╭╮╰╯…)·블록(█▌…)·Nerd Font 아이콘을 지우고 좌우 공백을 턴다.
    /// ASCII `|`는 건드리지 않는다 — 파이프는 명령어의 일부다.
    private static func strip(_ line: Substring) -> String {
        String(String.UnicodeScalarView(line.unicodeScalars.filter { !isDecoration($0) }))
            .trimmingCharacters(in: .whitespaces)
    }

    /// Box Drawing(U+2500–257F) · Block Elements(U+2580–259F) · Private Use Area(U+E000–F8FF).
    ///
    /// PUA까지 지우는 이유: 프롬프트 테마(powerlevel10k 등)가 경로 앞에 **Nerd Font 아이콘**을 붙인다.
    /// 앱 폰트엔 그 글리프가 없어 어차피 두부(□)로 보이고, 남겨두면 "프롬프트가 찍은 경로" 판정도
    /// 빗나가 같은 경로가 미리보기에 한 번 더 실린다(실측).
    private static func isDecoration(_ scalar: Unicode.Scalar) -> Bool {
        (0x2500...0x259F).contains(scalar.value) || (0xE000...0xF8FF).contains(scalar.value)
    }

    /// 알맹이가 있는 줄인가 — 글자·숫자가 하나라도 있고, 기호 한둘로 끝나지 않는다.
    private static func hasSubstance(_ line: String) -> Bool {
        guard line.count >= 3 else { return false }
        return line.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
    }

    /// 연속으로 같은 줄이 반복되면 하나로 — TUI는 같은 줄을 여러 번 그린다.
    private static func dedup(_ lines: [String]) -> [String] {
        lines.reduce(into: []) { acc, line in
            if acc.last != line { acc.append(line) }
        }
    }
}

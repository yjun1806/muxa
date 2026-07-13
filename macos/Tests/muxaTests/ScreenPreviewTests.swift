import Testing
@testable import muxa

/// 백그라운드 세션 미리보기 간추리기(순수).
///
/// 실측으로 걸린 함정: 화면 마지막 몇 줄을 그대로 쓰면 claude TUI는 입력 상자 **테두리**만,
/// 유휴 셸은 **프롬프트 찌꺼기**만 미리보기로 올라온다 — "어느 세션이었지"에 답이 안 된다.
struct ScreenPreviewTests {
    @Test func TUI_테두리는_걷어내고_알맹이만_남긴다() {
        let raw = """
        ╭──────────────────────────────╮
        │ > 테스트를 다시 돌려줘        │
        ╰──────────────────────────────╯
        """
        #expect(ScreenPreview.summarize(raw) == "> 테스트를 다시 돌려줘")
    }

    @Test func 알맹이_없는_줄은_버린다() {
        // 프롬프트 심볼(`└%`)·짧은 힌트(`^R`)·빈 줄은 정보가 아니다.
        let raw = """
        빌드 성공 — 3.2초

        └%
        ^R
        """
        #expect(ScreenPreview.summarize(raw) == "빌드 성공 — 3.2초")
    }

    @Test func 프롬프트가_찍은_현재_경로는_버린다() {
        // 경로는 행에서 이미 보여준다 — 미리보기까지 같은 말을 하면 세 줄 중 한 줄을 낭비한다.
        let raw = """
        npm run dev 종료
        ~/Documents/muxa
        /Users/yj/Documents/muxa
        """
        let out = ScreenPreview.summarize(raw, cwd: "/Users/yj/Documents/muxa", home: "/Users/yj")
        #expect(out == "npm run dev 종료")
    }

    @Test func 프롬프트_한_줄에서_경로만_떼고_명령은_남긴다() {
        // 실측 화면: 프롬프트는 [경로 · 브랜치 · 명령 · 시각]이 **한 줄**이고, 칸은 공백으로 메워져 있다.
        // 경로를 떼고 공백을 접지 않으면 이 한 줄이 세 줄로 접혀 미리보기를 다 먹는다.
        let raw = "~/Documents/muxa   main *1 ?1   sleep 1000            ✔  19:32:12"
        let out = ScreenPreview.summarize(raw, cwd: "/Users/yj/Documents/muxa", home: "/Users/yj")
        #expect(out == "main *1 ?1 sleep 1000 ✔ 19:32:12")
    }

    @Test func 줄_가운데의_경로는_건드리지_않는다() {
        // 맨 앞(프롬프트)만 떼어낸다 — 가운데 경로는 진짜 내용이다.
        let raw = "cd /Users/yj/Documents/muxa && swift build"
        let out = ScreenPreview.summarize(raw, cwd: "/Users/yj/Documents/muxa", home: "/Users/yj")
        #expect(out == "cd /Users/yj/Documents/muxa && swift build")
    }

    @Test func 프롬프트_아이콘이_붙어도_경로로_알아본다() {
        // powerlevel10k류가 경로 앞에 Nerd Font 아이콘(PUA)을 붙인다 — 그것 때문에 경로 판정이 빗나가면
        // 같은 경로가 미리보기에 한 번 더 실린다.
        let raw = "빌드 실패\n\u{F07C} ~/Documents/muxa"
        let out = ScreenPreview.summarize(raw, cwd: "/Users/yj/Documents/muxa", home: "/Users/yj")
        #expect(out == "빌드 실패")
    }

    @Test func 마지막_세_줄만_남기고_연속_중복은_접는다() {
        let raw = """
        line one
        line two
        같은 줄
        같은 줄
        line three
        line four
        """
        #expect(ScreenPreview.summarize(raw) == "같은 줄\nline three\nline four")
    }

    @Test func ASCII_파이프는_지우지_않는다() {
        // `|`는 명령어의 일부다 — 유니코드 테두리(│)와 구분해야 한다.
        let raw = "grep foo | wc -l"
        #expect(ScreenPreview.summarize(raw) == "grep foo | wc -l")
    }

    @Test func 남는_게_없으면_빈_문자열() {
        #expect(ScreenPreview.summarize("╭────╮\n│    │\n╰────╯") == "")
    }
}

import Testing

@testable import muxa

/// 커스텀 메뉴의 키보드 이동 판정(순수) — 구분선·비활성 항목을 건너뛰고 끝에서 순환한다.
@Suite("메뉴 키보드 이동")
struct MuxaMenuNavTests {
    /// [0] 활성 · [1] 구분선 · [2] 비활성 · [3] 활성
    private let items: [MuxaMenuItem] = [
        MuxaMenuItem(title: "이름 변경", action: {}),
        MuxaMenuItem.separator,
        MuxaMenuItem(title: "복제", enabled: false, action: {}),
        MuxaMenuItem(title: "닫기", destructive: true, action: {}),
    ]

    @Test("선택이 없으면 아래키는 첫 항목, 위키는 마지막 항목으로 진입한다")
    func 진입점() {
        #expect(MuxaMenuNav.next(from: nil, in: items, forward: true) == 0)
        #expect(MuxaMenuNav.next(from: nil, in: items, forward: false) == 3)
    }

    @Test("아래키는 구분선과 비활성 항목을 건너뛴다")
    func 아래로_건너뛰기() {
        #expect(MuxaMenuNav.next(from: 0, in: items, forward: true) == 3)
    }

    @Test("위키도 구분선과 비활성 항목을 건너뛴다")
    func 위로_건너뛰기() {
        #expect(MuxaMenuNav.next(from: 3, in: items, forward: false) == 0)
    }

    @Test("목록 끝에서 순환한다")
    func 순환() {
        #expect(MuxaMenuNav.next(from: 3, in: items, forward: true) == 0)
        #expect(MuxaMenuNav.next(from: 0, in: items, forward: false) == 3)
    }

    @Test("고를 항목이 하나뿐이면 어느 방향이든 제자리다")
    func 단일_항목() {
        let one = [MuxaMenuItem.separator, MuxaMenuItem(title: "닫기", action: {})]
        #expect(MuxaMenuNav.next(from: 1, in: one, forward: true) == 1)
        #expect(MuxaMenuNav.next(from: 1, in: one, forward: false) == 1)
    }

    @Test("고를 항목이 없으면 nil — 눌러도 아무 일이 없어야 한다")
    func 고를_항목_없음() {
        let none = [MuxaMenuItem.separator, MuxaMenuItem(title: "복제", enabled: false, action: {})]
        #expect(MuxaMenuNav.next(from: nil, in: none, forward: true) == nil)
        #expect(MuxaMenuNav.selectable(none).isEmpty)
    }
}

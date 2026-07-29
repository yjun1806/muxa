import Foundation

/// 종료 전에 무엇을 묻는가(순수) — 이 창에서 유일하게 파괴적인 동작의 방어선(YJ-6).
///
/// 자동 GC는 "모르는 프로젝트는 안 건드린다"는 가드로 안전을 샀고, 그 대가로 고아를 영영 못 지운다.
/// 이 창은 그 판정을 사람에게 넘긴다 — **넘기는 대신 무엇을 죽이는지 먼저 말해야** 한다.
///
/// 묻는 기준은 고아 여부가 아니라 **무게**다. 실측에서 986MB짜리 스크립트 세션이 어느 state에도
/// 없어 "고아"였지만 실제로는 헤드리스 크롬과 esbuild가 돌고 있었다. 고아 표시를 근거로 삼았다면
/// 조용히 죽였을 것이다.
enum SessionKillPlan {
    struct Warning: Equatable {
        let title: String
        let detail: String
    }

    /// 확인이 필요하면 물어볼 말, 아니면 nil.
    ///
    /// **빈 셸은 묻지 않는다.** 되찾을 것이 없는 걸 죽일 때마다 확인창이 뜨면 사람이 읽지 않고 누르는
    /// 습관이 들고, 정작 위험할 때 그 습관이 막지 못한다.
    static func warning(for items: [SessionListItem], ownSocket: String) -> Warning? {
        guard !items.isEmpty else { return nil }

        var reasons: [String] = []

        // 1) 안에서 뭔가 돌고 있다 — 가장 중요한 사유. 이름을 대준다.
        let working = items.filter { !$0.weight.labels.isEmpty }
        if let names = working.flatMap(\.weight.labels).uniqued().prefix(4).nilIfEmpty {
            reasons.append("안에서 \(names.joined(separator: ", "))이(가) 돌고 있습니다.")
        }

        // 2) 다른 소켓 — 다른 muxa 인스턴스가 쓰는 중일 수 있다. D19가 지키려던 선이다.
        if items.contains(where: { $0.row.socket != ownSocket }) {
            reasons.append("다른 muxa 인스턴스의 세션이 섞여 있습니다.")
        }

        // 3) 연결됨 — 죽이면 보고 있던 화면이 사라진다.
        if items.contains(where: { $0.row.isAttached && !$0.row.isDead }) {
            reasons.append("연결된 세션이 있습니다 — 보고 있던 화면이 사라집니다.")
        }

        guard !reasons.isEmpty else { return nil }
        return Warning(title: "세션 \(items.count)개를 종료할까요?",
                       detail: reasons.joined(separator: "\n") + "\n\n되돌릴 수 없습니다.")
    }

    /// 확인 없이 쓸어도 되는 것 — **죽었고 안에 아무것도 없는** pane.
    ///
    /// 죽은 pane이라도 자식이 살아남는 경우가 있어(고아 프로세스) 프로세스 수까지 본다.
    /// 일괄 정리는 확인 없이 도는 동작이라 판정을 좁게 잡는다.
    static func sweepable(_ items: [SessionListItem]) -> [SessionListItem] {
        items.filter { $0.row.isDead && $0.weight.processCount == 0 }
    }
}

private extension Array where Element: Hashable {
    /// 순서를 지키며 중복을 접는다.
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

private extension ArraySlice where Element == String {
    var nilIfEmpty: [String]? { isEmpty ? nil : Array(self) }
}

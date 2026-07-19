import Foundation

/// 커밋 하나가 건드린 파일 하나 — 상태 문자 + 경로 + 변경 줄 수. 값 타입.
///
/// 히스토리·리뷰 탭의 커밋 행을 펼치면 이 배열이 파일 행으로 그려진다. 변경사항 탭의
/// `GitFileChange`와 **일부러 다른 타입**이다: 저쪽은 워크트리 상태(스테이지 X·워크트리 Y 두 축 +
/// 스테이지/버리기 같은 쓰기 동작)를 담고, 이쪽은 **이미 커밋된 불변 사실**이라 축이 하나다.
struct GitCommitFile: Identifiable, Equatable {
    /// porcelain 상태 문자 — A(추가) M(수정) D(삭제) R(이름변경) C(복사) T(타입변경).
    /// 머지 커밋의 결합 diff는 부모 수만큼 문자가 붙으므로(`MM`) **첫 글자만** 담는다.
    let status: Character
    /// 커밋 후 경로(리네임이면 새 이름) — 표시·diff 조회의 기준.
    let path: String
    /// 리네임 원본. 리네임·복사가 아니면 nil.
    let oldPath: String?
    /// 추가된 줄 수. **모르면 nil** — 바이너리이거나 머지 결합 diff에서 짝을 못 찾은 경우.
    /// (DESIGN §7 "모르면 침묵한다" — 0으로 지어내지 않는다. 0은 "안 바뀜"이라는 다른 사실이다.)
    let added: Int?
    /// 삭제된 줄 수. nil 규칙은 `added`와 같다.
    let deleted: Int?

    /// numstat이 `-  -`로 답한 파일 — 줄 수 개념이 없다(이미지·바이너리).
    let isBinary: Bool

    var id: String { path }

    init(status: Character, path: String, oldPath: String? = nil,
         added: Int? = nil, deleted: Int? = nil, isBinary: Bool = false) {
        self.status = status
        self.path = path
        self.oldPath = oldPath
        self.added = added
        self.deleted = deleted
        self.isBinary = isBinary
    }
}

/// `git show`의 파일 목록 출력 파싱(순수·테스트 대상).
///
/// **왜 두 출력을 경로로 잇나** — `--name-status`(상태)와 `--numstat`(줄 수)을 한 명령에 같이 주면
/// 뒤엣것이 앞엣것을 덮어써서 하나만 나온다. 그렇다고 두 출력을 **순서로** 짝지으면 머지 커밋에서
/// 깨진다: 결합 diff는 `--name-status`와 `--numstat`의 줄 수가 서로 다르다(실측 3 vs 15).
/// 그래서 상태를 기준 목록으로 삼고 줄 수는 **경로로 조회**한다 — 짝이 없으면 침묵한다.
enum GitCommitFileParse {
    /// `--name-status` 출력 → 파일 목록(줄 수는 아직 없음).
    ///
    /// 줄 형식: `M\tpath` · `R060\told\tnew` · `MM\tpath`(머지 결합 diff).
    static func parseNameStatus(_ output: String) -> [GitCommitFile] {
        output.split(separator: "\n").compactMap { raw in
            let fields = String(raw).components(separatedBy: "\t")
            guard fields.count >= 2, let code = fields[0].first else { return nil }
            // 리네임·복사는 유사도 점수가 붙고(R060) 경로가 둘이다.
            let isMove = (code == "R" || code == "C") && fields.count >= 3
            return GitCommitFile(status: code,
                                 path: isMove ? fields[2] : fields[1],
                                 oldPath: isMove ? fields[1] : nil)
        }
    }

    /// `--numstat` 출력 → 경로별 줄 수. 형식: `12\t3\tpath` · `-\t-\tpath`(바이너리).
    ///
    /// 리네임 경로는 `src/{old.tsx => new.tsx}` 또는 `old => new`로 **압축**돼 나오므로
    /// 새 경로로 펴서 키를 잡는다 — 그래야 `--name-status`의 새 경로와 만난다.
    static func parseNumstat(_ output: String) -> [String: (added: Int?, deleted: Int?, binary: Bool)] {
        var result: [String: (added: Int?, deleted: Int?, binary: Bool)] = [:]
        for raw in output.split(separator: "\n") {
            let fields = String(raw).components(separatedBy: "\t")
            guard fields.count >= 3 else { continue }
            let path = expandRenamePath(fields[2...].joined(separator: "\t"))
            let binary = fields[0] == "-" && fields[1] == "-"
            result[path] = binary ? (nil, nil, true)
                                  : (Int(fields[0]), Int(fields[1]), false)
        }
        return result
    }

    /// numstat의 압축 리네임 경로 → 커밋 후 경로.
    /// `src/{a.tsx => b.tsx}` → `src/b.tsx` · `{x => y}/f` → `y/f` · `a => b` → `b`.
    static func expandRenamePath(_ path: String) -> String {
        if let open = path.firstIndex(of: "{"),
           let close = path[open...].firstIndex(of: "}"),
           let arrow = path[open..<close].range(of: " => ") {
            let prefix = path[path.startIndex..<open]
            let newMiddle = path[arrow.upperBound..<close]
            let suffix = path[path.index(after: close)...]
            return String(prefix + newMiddle + suffix)
        }
        if let arrow = path.range(of: " => ") { return String(path[arrow.upperBound...]) }
        return path
    }

    /// 두 출력을 합쳐 최종 목록으로. 상태 목록이 기준이고 줄 수는 있으면 얹는다.
    static func merge(nameStatus: String, numstat: String) -> [GitCommitFile] {
        let stats = parseNumstat(numstat)
        return parseNameStatus(nameStatus).map { file in
            guard let s = stats[file.path] else { return file } // 짝이 없으면 침묵
            return GitCommitFile(status: file.status, path: file.path, oldPath: file.oldPath,
                                 added: s.added, deleted: s.deleted, isBinary: s.binary)
        }
    }
}

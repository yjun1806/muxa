import Foundation

/// 에이전트가 **읽기만** 한 것 — 참고 자료. 변경 목록과 섞지 않는다
/// (편집 1건에 읽기 수십 건이라, 섞으면 바꾼 것이 파묻힌다).
struct AgentReference: Equatable, Codable {
    enum Kind: String, Equatable, Codable { case file, web }
    let kind: Kind
    /// 파일이면 절대 경로, 웹이면 **URL 전문**. 호스트만 남기면 열 수 없다
    /// (진행 표시용 `ToolActivity`는 호스트만 쓰지만, 이건 여는 데 쓴다).
    let value: String
    var lastSeenAt: Date
    /// **무엇을 하다가 이걸 열었나** — 그 턴의 사용자 프롬프트.
    /// 목록만으로는 "왜 이걸 봤지"가 안 풀린다. 비용은 0이다(탭별 프롬프트가 이미 메모리에 있다).
    /// 같은 것을 여러 번 보면 **가장 최근 맥락**이 남는다.
    /// 옵셔널이라 예전 저장분도 그대로 디코드된다(없으면 nil).
    var context: String?

    /// 중복 제거 키 — 종류가 다르면 값이 같아도 다른 항목이다.
    var key: String { "\(kind.rawValue):\(value)" }
}

/// 한 파일에 대한 기록.
struct AgentChangeEntry: Equatable, Codable {
    let path: String
    var firstTouchedAt: Date
    var lastTouchedAt: Date
    var touchCount: Int
    /// claude `session_id` — **구획 라벨일 뿐 그룹 경계가 아니다**(경계는 muxa 탭).
    /// `/clear`·`--resume`에서 바뀌지만 같은 칸에서 이어가는 작업은 사용자에게 같은 작업이다.
    var lastSessionId: String?
    /// 사용자가 diff를 연 시각. nil = 안 봤음.
    /// "다시 봐야 하나"의 판정(`lastTouchedAt`·mtime과의 비교)은 표시 단계의 몫이다.
    var seenAt: Date?
    /// **어느 지시로 이걸 건드렸나** — 처음 만진 턴의 프롬프트.
    /// 참고 항목과 대칭이다. 20턴짜리 세션에서 "이 파일은 왜 바뀐 거지"는 목록만으론 안 풀린다.
    /// **처음 것을 남긴다**(참고는 최근 것) — 파일이 생겨난 이유가 그 파일의 정체성이고,
    /// 나중 손질까지 제목을 빼앗으면 "왜 이게 여기 있나"가 사라진다.
    var context: String?
}

/// 한 탭(에이전트 세션)이 만진 파일과 참고한 것의 축적 — 순수 값.
///
/// 신호는 **이미 오는** `PreToolUse` 훅 하나에서 온다(`ClaudeHookPayload.toolInput`).
/// 새 훅을 붙이지 않는다 — `PostToolUse`는 이 저장소가 이미 기각했다
/// (전역 설정 스폰·도구 호출당 2배·`tool_response` 전문이 소켓 버퍼 초과, `ClaudeHookPayload.swift`).
///
/// 그 신호는 도구가 **실행되기 전**의 것이라, 이 타입은 "무엇을 시도했나"를 모을 뿐
/// "무엇이 바뀌었나"를 단정하지 않는다. 거부·실패한 편집도 여기 들어오고,
/// 실제 변경 여부는 git·mtime과 교차하는 표시 단계가 판정한다.
struct AgentChangeSet: Equatable, Codable {
    /// **첫 수집 턴의 프롬프트를 얼린 값** — 그룹 제목.
    /// 마지막 프롬프트를 쓰면 20턴 전에 만진 파일이 지금 프롬프트로 적힌 그룹 아래 놓여
    /// 라벨이 거짓이 된다. "무엇으로 시작된 작업인가"는 시간이 지나도 참이다.
    var originPrompt: String?
    /// 첫 수집 순간의 HEAD — diff의 base. 도달 불가능해질 수 있어 여는 시점에 검증한다.
    var baselineHead: String?

    private(set) var entries: [String: AgentChangeEntry] = [:]
    private(set) var references: [String: AgentReference] = [:]
    /// 천장에 닿아 **기록하지 못한** 경로 수. 지운 게 아니라 못 받은 것이고, 침묵하지 않으려 센다.
    private(set) var truncatedCount: Int = 0

    /// 안전 천장. 존재 이유는 폭주 방어(루프 Write 난사)뿐이다 — 실사용(수백 건)엔 닿지 않는다.
    /// **닿으면 오래된 걸 지우지 않는다.** oldest-touched 축출은 이 기능이 막으려던
    /// "안 본 변경이 남는다"의 재생산이다.
    static let entryCeiling = 5_000

    init() {}

    // MARK: 관대한 디코딩 — 필드가 늘어도 예전 파일이 안 깨진다
    //
    // **자동 생성 `Codable`은 키가 없으면 기본값을 쓰지 않고 던진다.** non-optional 필드를 하나
    // 추가하는 순간 이전에 저장된 파일이 전부 디코드에 실패하고, 호출부의 `try?`가 그걸 nil로
    // 삼켜 **기록이 통째로 사라진 것처럼 보인다**(실제로 그렇게 터졌다 — `detailWasOpen` 추가 때).
    //
    // 그래서 전부 `decodeIfPresent`로 읽고 없으면 기본값을 쓴다. 앞으로 필드가 늘어도
    // 여기만 한 줄 늘리면 되고, 예전 파일은 계속 읽힌다.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        originPrompt = try c.decodeIfPresent(String.self, forKey: .originPrompt)
        baselineHead = try c.decodeIfPresent(String.self, forKey: .baselineHead)
        entries = try c.decodeIfPresent([String: AgentChangeEntry].self, forKey: .entries) ?? [:]
        references = try c.decodeIfPresent([String: AgentReference].self, forKey: .references) ?? [:]
        truncatedCount = try c.decodeIfPresent(Int.self, forKey: .truncatedCount) ?? 0
    }

    // MARK: 수집 판정 (순수)

    /// 편집 도구가 만진 절대 경로. 대상 도구가 아니거나 경로를 확정할 수 없으면 nil.
    static func touchedPath(toolName: String?, input: [String: String], cwd: String?) -> String? {
        switch toolName {
        case "Edit", "Write", "MultiEdit":
            return absolute(input["file_path"], cwd: cwd)
        // 노트북은 `file_path`가 아니라 `notebook_path`로 온다.
        case "NotebookEdit":
            return absolute(input["notebook_path"] ?? input["file_path"], cwd: cwd)
        default:
            return nil
        }
    }

    /// 참고 항목(읽기·웹 조회). **열 수 있는 것만** 받는다 —
    /// `Grep` 패턴·`WebSearch` 질의·`Bash` 명령은 클릭할 대상이 없어 목록에 넣지 않는다.
    static func reference(toolName: String?, input: [String: String], cwd: String?,
                          context: String? = nil, at now: Date) -> AgentReference? {
        switch toolName {
        case "Read":
            guard let path = absolute(input["file_path"], cwd: cwd) else { return nil }
            return AgentReference(kind: .file, value: path, lastSeenAt: now, context: context)
        case "WebFetch":
            // 스킴 화이트리스트 — `MarkdownLinkSchemes.external`과 같은 태도.
            guard let raw = input["url"], let scheme = URL(string: raw)?.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else { return nil }
            return AgentReference(kind: .web, value: raw, lastSeenAt: now, context: context)
        default:
            return nil
        }
    }

    /// 경로를 절대·정규화한다. **상대경로인데 cwd가 없으면 버린다** — 어디를 가리키는지 지어낼 수 없다.
    ///
    /// `standardizedFileURL`까지만 쓴다(`../` 정리). symlink는 **해석하지 않는다** —
    /// macOS는 `/tmp`를 `/private/tmp`로 바꿔버려서, 해석하면 리포 상대경로 계산이 어긋난다.
    private static func absolute(_ raw: String?, cwd: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let expanded = (raw as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded).standardizedFileURL.path
        }
        guard let cwd, !cwd.isEmpty else { return nil }
        return URL(fileURLWithPath: cwd).appendingPathComponent(expanded).standardizedFileURL.path
    }

    // MARK: upsert

    /// 제목을 **한 번만** 얼린다 — 첫 수집 턴의 프롬프트.
    /// 편집이든 읽기든 **처음 잡힌 신호**가 기준이다(읽기만 하는 세션도 제목이 있어야 한다).
    /// 첫 신호에 프롬프트가 없었으면(훅 이전 세션) 다음 기회에 받는다 — 빈 제목을 고수하지 않는다.
    mutating func freezeOrigin(_ prompt: String?) {
        guard originPrompt == nil, let prompt, !prompt.isEmpty else { return }
        originPrompt = prompt
    }

    /// 편집 기록. 같은 경로는 항목을 늘리지 않고 갱신한다.
    mutating func record(path: String, sessionId: String?, prompt: String?,
                         at now: Date, ceiling: Int = Self.entryCeiling) {
        freezeOrigin(prompt)

        if var existing = entries[path] {
            existing.lastTouchedAt = now
            existing.touchCount += 1
            if let sessionId { existing.lastSessionId = sessionId }
            // 맥락은 **덮지 않는다** — 처음 만진 이유가 그 파일이 여기 있는 이유다.
            // 다만 처음에 프롬프트를 못 읽었으면 다음 기회에 채운다.
            if existing.context == nil { existing.context = prompt }
            entries[path] = existing
            return
        }
        // 천장에 닿았어도 **기존 항목 갱신은 위에서 이미 통과**했다 — 최신 활동을 잃지 않는다.
        guard entries.count < ceiling else {
            truncatedCount += 1
            return
        }
        entries[path] = AgentChangeEntry(path: path, firstTouchedAt: now, lastTouchedAt: now,
                                         touchCount: 1, lastSessionId: sessionId, seenAt: nil,
                                         context: prompt)
    }

    /// 참고 기록. 같은 것을 여러 번 봐도 한 항목이고, 마지막으로 본 시각만 갱신된다.
    mutating func record(reference: AgentReference, at now: Date) {
        var ref = reference
        ref.lastSeenAt = now
        // 맥락은 **비어 있지 않을 때만** 덮는다 — 프롬프트를 못 읽은 턴이 이미 아는 맥락을 지우면 안 된다.
        if ref.context == nil { ref.context = references[ref.key]?.context }
        references[ref.key] = ref
    }

    /// 사용자가 그 파일의 diff를 열었다. **모르는 경로로는 항목을 만들지 않는다**
    /// (수집한 적 없는 파일이 "봤음"으로 목록에 생기면 안 된다).
    mutating func markSeen(path: String, at now: Date) {
        guard var entry = entries[path] else { return }
        entry.seenAt = now
        entries[path] = entry
    }
}

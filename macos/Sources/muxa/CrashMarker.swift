import Foundation

/// 세션 크래시(더티 종료) 감지용 마커 — 경계 타입(파일 IO 부작용 격리).
///
/// 원리: 앱 실행 중에는 마커 파일이 존재하고, 정상 종료(applicationWillTerminate)에서 지운다.
/// 다음 시작에 마커가 남아 있으면 직전 실행이 정상 종료 경로를 못 탔다는 뜻 = 크래시(또는 강제종료).
/// 정상 종료였다면 지워져 있으므로 마커가 없다. 첫 실행도 마커가 없어 자연히 '더티 아님'으로 판정된다.
///
/// muxa는 탭/뷰어 변경마다 즉시 저장이라 유실 방어는 이미 돼 있다. 이 마커는 "직전이 크래시였나"만
/// 알려 준다 — 그 판정을 어떻게 쓸지(복구 배너·자동 resume 조건 등)는 후속 단계가 결정한다.
enum CrashMarker {
    private static let fileURL = MuxaSupportDir.url.appendingPathComponent("session.lock")

    /// 직전 실행이 더티(크래시)였는지 판정하고, 이번 실행 마커를 남긴다(arm). 시작 시 1회 호출.
    /// 반환 true = 직전 실행이 정상 종료 경로를 안 탔음(크래시/강제종료).
    static func detectAndArm() -> Bool {
        let wasDirty = FileManager.default.fileExists(atPath: fileURL.path)
        try? Data([0x01]).write(to: fileURL, options: .atomic)
        return wasDirty
    }

    /// 정상 종료 시 마커를 지운다(disarm) — 다음 실행에 "크래시 아님"을 알린다.
    static func disarm() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

import Foundation
import Testing
@testable import muxa

/// 프로젝트 경로 판정 — "폴더 없음/접근 불가"를 "git 저장소 아님"으로 위장하지 않기 위한 순수 판정.
struct PathStateTests {
    @Test("읽을 수 있는 폴더는 ok")
    func 정상폴더() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("muxa-pathstate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(PathState.check(dir.path) == .ok)
        #expect(PathState.check(dir.path).message == nil)
    }

    @Test("사라진 폴더는 missing")
    func 없는폴더() {
        let path = "/tmp/muxa-없는폴더-\(UUID().uuidString)"
        #expect(PathState.check(path) == .missing)
        #expect(PathState.check(path).message == "폴더를 찾을 수 없습니다")
    }

    @Test("파일은 폴더가 아니므로 missing")
    func 폴더가아닌파일() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("muxa-pathstate-\(UUID().uuidString).txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(PathState.check(file.path) == .missing)
    }

    @Test("읽기 권한이 없는 폴더는 denied")
    func 권한없는폴더() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("muxa-pathstate-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer {
            try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
            try? fm.removeItem(at: dir)
        }
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: dir.path)
        #expect(PathState.check(dir.path) == .denied)
        #expect(PathState.check(dir.path).message != nil)
    }
}

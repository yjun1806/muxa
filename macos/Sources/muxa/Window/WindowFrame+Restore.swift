import AppKit

extension FrameSnapshot {
    /// 실물 창 프레임 → 저장 값. 복원(`WindowFrame.restore`)의 역방향이라 나란히 둔다.
    init(_ rect: NSRect) {
        self.init(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height)
    }
}

/// 저장된 분리 창 프레임(FrameSnapshot)의 복원 판정 — 기존 `WindowFrame.isReachable`을 재사용한다.
extension WindowFrame {
    /// 이보다 작은 창은 상단바조차 못 그린다 — 손상된 저장분(0폭 등)을 그대로 복원하면 창이 없는 것과 같다.
    static let minRestorableSize = NSSize(width: 480, height: 320)

    /// 복원해도 되는 프레임이면 그 `NSRect`, 아니면 nil(= 기본 크기 + cascade로 띄운다).
    static func restore(_ snapshot: FrameSnapshot?, screens: [NSRect]) -> NSRect? {
        guard let snapshot else { return nil }
        let frame = NSRect(x: snapshot.x, y: snapshot.y,
                           width: snapshot.width, height: snapshot.height)
        guard frame.width >= minRestorableSize.width,
              frame.height >= minRestorableSize.height else { return nil }
        guard isReachable(frame, screens: screens) else { return nil }
        return frame
    }
}

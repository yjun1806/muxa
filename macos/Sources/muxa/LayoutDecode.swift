import Foundation

/// 프로젝트별 **격리 디코드** — 스냅샷 하나가 손상돼도 나머지 프로젝트는 살린다.
///
/// 이전에는 `layouts`를 `try?` 한 번으로 통짜 디코드해서, 프로젝트 하나의 스냅샷이 깨지면
/// **모든 프로젝트의 레이아웃이 조용히 사라졌다**. 스키마가 진화하는 한(필드 추가·enum 확장)
/// 부분 손상은 언제든 생기므로, 손상 범위를 그 프로젝트 하나로 가둔다.
///
/// 같은 이유로 Orca도 세션 스키마를 필드 단위(`.catch(default)`)로 격리한다 — 미지의 값 하나가
/// 전체 세션 파싱을 실패시켜 모든 탭을 날리는 걸 막는 것이 목적이다.
struct LenientLayouts: Decodable {
    /// 성공적으로 디코드된 프로젝트 레이아웃.
    private(set) var layouts: [String: PaneSnapshot] = [:]
    /// 디코드에 실패해 버린 프로젝트 id — 사용자에게 표면화하기 위해 남긴다(조용한 유실 금지).
    private(set) var dropped: [String] = []

    /// 프로젝트 id가 키인 임의 키 컨테이너용.
    private struct ProjectKey: CodingKey {
        let stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ProjectKey.self)
        for key in container.allKeys {
            if let snapshot = try? container.decode(PaneSnapshot.self, forKey: key) {
                layouts[key.stringValue] = snapshot
            } else {
                dropped.append(key.stringValue)
            }
        }
    }
}

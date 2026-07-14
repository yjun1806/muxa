import AppKit
import SwiftUI

/// 사이드바 행들의 **공통 상호작용**과 공통 표시 조각.
/// hover 강조 + 우클릭 메뉴 보일러플레이트가 워크스페이스 행·프로젝트 행·접힘 모드 항목(2종)에
/// 네 번 반복됐다 — 세 번이면 추출한다.
extension View {
    /// - id: 이 행의 신원(워크스페이스·프로젝트가 같은 id 공간을 쓴다).
    /// - menu: **닫히는 순간이 아니라 열리는 순간에** 만든다(클로저) — 메뉴 항목을 미리 만들면
    ///   `store(for:in:)` 같은 부작용이 우클릭 전에 일어난다.
    @MainActor
    func sidebarRow(id: String,
                    hoveredId: Binding<String?>,
                    menuOpenId: Binding<String?>,
                    menu: @escaping () -> [MuxaMenuItem]) -> some View {
        onHover { hovering in
            if hovering {
                hoveredId.wrappedValue = id
            } else if hoveredId.wrappedValue == id {
                hoveredId.wrappedValue = nil
            }
        }
        // 메뉴가 열려 있는 동안 `menuOpenId`가 강조와 hover peek를 붙든다(메뉴는 별도 창이라
        // 마우스가 사이드바를 벗어난다 — 없으면 메뉴만 남고 사이드바가 접힌다).
        .onRightClick { point in
            menuOpenId.wrappedValue = id
            MuxaMenuWindow.show(menu(), at: point) { menuOpenId.wrappedValue = nil }
        }
        .animation(Motion.fast, value: hoveredId.wrappedValue == id || menuOpenId.wrappedValue == id)
    }
}

/// 접힌 모드(icon·slim)에서 호버한 항목의 이름(+경로)을 사이드바 **바깥**에 띄우는 칩.
/// 이름이 안 보이는 모드의 유일한 이름이라, 워크스페이스 항목과 프로젝트 항목이 같은 칩을 쓴다.
struct SidebarNameChip: View {
    let title: String
    let subtitle: String?
    /// 워크트리·자체 경로 프로젝트의 이름은 식별자다 → 모노스페이스(트리 행과 같은 규칙).
    var mono = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.tight) {
            Text(title)
                .font(mono ? .muxaMono(.body, weight: .medium) : .muxa(.body, weight: .medium))
                .foregroundStyle(Color.pFg)
            if let subtitle {
                Text(subtitle)
                    .font(.muxa(.caption))
                    .foregroundStyle(Color.pMuted)
            }
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.xs)
        .background(Color.pPanel)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Color.pBorder, lineWidth: RowHeight.hairline))
        .shadow(color: .black.opacity(Elevation.keyOpacity),
                radius: Elevation.keyRadius, y: Elevation.keyOffsetY)
    }
}

extension Workspace {
    /// 네이티브 툴팁(이름 + 경로) — 트리 행과 접힘 모드 항목이 같은 문자열을 쓴다.
    var tooltip: String {
        guard let path else { return name }
        return "\(name)\n\(displayPath(path, home: SystemPaths.home))"
    }
}

extension Project {
    /// 이름을 **모노스페이스**로 읽는 프로젝트 = 자체 경로를 가진 프로젝트(워크트리·임의 폴더).
    /// 워크스페이스 경로를 상속하는 프로젝트(`path == nil`)는 사람이 붙인 이름이라 일반 서체다.
    ///
    /// (워크트리인지 임의 폴더인지는 `Project`가 구분하지 않는다 — 둘 다 "경로가 곧 신원"이라
    ///  같은 서체로 읽는 게 지금 모델에서 말할 수 있는 전부다. 진짜 구분이 필요해지면 필드를 늘려야 한다.)
    var usesMonoName: Bool { path != nil }
}

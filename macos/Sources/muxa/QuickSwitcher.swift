import AppKit
import SwiftUI

/// ⌘K 빠른 전환기(명령 팔레트) — 계층 5단(워크스페이스›프로젝트›칸/탭›서브탭)을 퍼지로 탐색해 즉시 점프한다.
/// 상태는 AppState.showQuickSwitch가 소유하고, 이 뷰는 controlled로 열고 닫는다. 항목·랭킹은 순수 로직에 위임.
/// 입력창은 IME(한글 조합) 안전을 위해 NSTextField 기반(SearchOverlay와 같은 이유·같은 패턴).
struct QuickSwitcher: View {
    let state: AppState

    @State private var query = ""
    @State private var selection = 0

    var body: some View {
        // 루트는 항상 존재해야 열림 전환을 관측(onChange)해 입력을 리셋할 수 있다.
        ZStack {
            if state.showQuickSwitch {
                let items = QuickSwitchRanker.rank(state.quickSwitchItems(), query: query)
                overlay(items)
            }
        }
        .onChange(of: state.showQuickSwitch) { _, open in
            if open { query = ""; selection = 0 }
        }
    }

    @ViewBuilder
    private func overlay(_ items: [QuickSwitchItem]) -> some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { close() }
            panel(items)
                .frame(width: 520)
                .padding(.top, 72)
        }
    }

    private func panel(_ items: [QuickSwitchItem]) -> some View {
        VStack(spacing: 0) {
            QuickSwitchField(
                text: $query,
                onChange: { selection = 0 },
                onUp: { move(-1, count: items.count) },
                onDown: { move(1, count: items.count) },
                onEnter: { jump(items) },
                onClose: { close() }
            )
            .frame(height: 40)
            .padding(.horizontal, 12)

            Rectangle().fill(Color.pBorder).frame(height: 1)

            if items.isEmpty {
                emptyState
            } else {
                resultList(items)
            }
        }
        .background(Color.pPanel)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.pBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 20, y: 8)
    }

    private var emptyState: some View {
        Text("일치하는 항목 없음")
            .font(.system(size: 12))
            .foregroundStyle(Color.pMuted)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
    }

    private func resultList(_ items: [QuickSwitchItem]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        row(item, selected: idx == clamped(selection, items.count))
                            .id(idx)
                            .contentShape(Rectangle())
                            .onTapGesture { state.quickJump(item) }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 360)
            .onChange(of: selection) { _, sel in
                proxy.scrollTo(clamped(sel, items.count), anchor: .center)
            }
        }
    }

    /// 항목 한 줄 — [종류 아이콘][제목 · 위치][대기 점][종류 라벨]. 선택 행은 강조 배경.
    private func row(_ item: QuickSwitchItem, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .font(.system(size: 13))
                .foregroundStyle(selected ? Color.pFg : Color.pMuted)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.pFg)
                    .lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.pMuted)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            Spacer(minLength: 6)
            if item.waiting {
                Circle().fill(Color.pBorderActivity).frame(width: 7, height: 7)
            }
            Text(item.kind.label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.pMuted.opacity(0.8))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Color.pBtnActive.opacity(0.6) : Color.clear)
    }

    // MARK: 액션

    private func move(_ delta: Int, count: Int) {
        guard count > 0 else { selection = 0; return }
        selection = clamped(selection + delta, count)
    }

    private func jump(_ items: [QuickSwitchItem]) {
        let i = clamped(selection, items.count)
        guard items.indices.contains(i) else { return }
        state.quickJump(items[i])
    }

    private func close() {
        state.showQuickSwitch = false
    }

    /// 선택 인덱스를 항목 수 안으로 가둔다(리스트가 줄어도 유효하게).
    private func clamped(_ i: Int, _ count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(i, 0), count - 1)
    }
}

/// IME 안전 전환기 입력창 — ↑↓ 이동, Return 점프, Esc 닫기를 field editor delegate에서 처리하되
/// 조합 중(hasMarkedText)이면 IME에 양보한다(SearchOverlay의 SearchField와 같은 규칙).
private struct QuickSwitchField: NSViewRepresentable {
    @Binding var text: String
    let onChange: () -> Void
    let onUp: () -> Void
    let onDown: () -> Void
    let onEnter: () -> Void
    let onClose: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = "워크스페이스 · 프로젝트 · 탭 검색"
        field.font = .systemFont(ofSize: 15)
        field.focusRingType = .none
        field.isBordered = false
        field.drawsBackground = false
        field.delegate = context.coordinator
        field.stringValue = text
        // 표시되면 즉시 포커스 — 터미널에서 first responder를 가져온다(타이핑이 터미널로 새지 않게).
        DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        // 조합 중이 아니고 값이 다를 때만 프로그램적 동기화 — 조합 중 덮어쓰면 입력이 깨진다.
        let editing = (field.currentEditor() as? NSTextView)?.hasMarkedText() == true
        if field.stringValue != text, !editing {
            field.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: QuickSwitchField
        init(_ parent: QuickSwitchField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
            parent.onChange()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            // 조합 중이면 방향/Return/Esc를 가로채지 않고 IME가 확정·취소·후보이동에 쓰게 넘긴다.
            if textView.hasMarkedText() { return false }
            switch selector {
            case #selector(NSResponder.moveUp(_:)):
                parent.onUp(); return true
            case #selector(NSResponder.moveDown(_:)):
                parent.onDown(); return true
            case #selector(NSResponder.insertNewline(_:)):
                parent.onEnter(); return true
            case #selector(NSResponder.cancelOperation(_:)): // Esc
                parent.onClose(); return true
            default:
                return false
            }
        }
    }
}

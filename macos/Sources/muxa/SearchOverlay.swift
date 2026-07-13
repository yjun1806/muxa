import AppKit
import Carbon.HIToolbox
import SwiftUI

/// 포커스된 터미널 위에 뜨는 스크롤백 검색바(⌘F). term.search(SearchState)를 관측한다.
/// active일 때만 우상단에 나타난다. 입력창은 IME(한글 조합) 안전을 위해 NSTextField 기반이다
/// — SwiftUI TextField는 터미널(NSTextInputClient)과 first-responder를 다투고 조합 중 값 동기화가 입력을 씹는다.
struct SearchOverlay: View {
    @ObservedObject private var search: SearchState
    private let term: TermView

    init(term: TermView) {
        self.term = term
        _search = ObservedObject(wrappedValue: term.search)
    }

    var body: some View {
        if search.active {
            HStack(spacing: 6) {
                SearchField(
                    text: $search.needle,
                    onChange: { search.commitNeedle() },
                    onNext: { term.searchNext() },
                    onPrevious: { term.searchPrevious() },
                    onClose: { term.closeSearch() }
                )
                .frame(width: 180, height: 22)

                Text(counter)
                    .font(.muxa(.label).monospacedDigit())
                    .foregroundStyle(Color.pMuted)
                    .frame(minWidth: 42, alignment: .trailing)

                iconButton("chevron.up") { term.searchPrevious() }
                iconButton("chevron.down") { term.searchNext() }
                iconButton("xmark") { term.closeSearch() }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.pPanel)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.pBorder, lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
            .padding(10)
        }
    }

    /// 카운터 표기: total 미확정이면 빈칸, selected 있으면 "선택/총", 없으면 "-/총"(1-based 표시).
    private var counter: String {
        guard let total = search.total else { return "" }
        if total == 0 { return "0/0" }
        if let sel = search.selected { return "\(sel + 1)/\(total)" }
        return "-/\(total)"
    }

    private func iconButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.muxa(.label, weight: .medium))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.pFg)
        .frame(width: 20, height: 20)
        .contentShape(Rectangle())
    }
}

/// IME 안전 검색 입력창. Return=다음, Shift+Return=이전, Esc=닫기를 field editor delegate에서
/// 처리하되 조합 중(hasMarkedText)이면 IME에 양보한다(Return=조합확정, Esc=조합취소).
private struct SearchField: NSViewRepresentable {
    @Binding var text: String
    let onChange: () -> Void
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onClose: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = "검색"
        field.font = .systemFont(ofSize: 12)
        field.focusRingType = .none
        field.bezelStyle = .roundedBezel
        field.isBordered = true
        field.delegate = context.coordinator
        field.stringValue = text
        // 표시되면 즉시 포커스 — 터미널에서 first responder를 가져온다(타이핑이 터미널로 새지 않게).
        DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        // 조합 중이 아니고 값이 다를 때만 프로그램적 동기화 — 조합 중 덮어쓰면 입력이 깨진다.
        let editing = (field.currentEditor() as? NSTextView)?.hasMarkedText() == true
        if field.stringValue != text, !editing {
            field.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        private let parent: SearchField
        init(_ parent: SearchField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
            parent.onChange()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            // 조합 중이면 Return/Esc를 가로채지 않고 IME가 확정·취소에 쓰게 넘긴다.
            if textView.hasMarkedText() { return false }
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                    parent.onPrevious()
                } else {
                    parent.onNext()
                }
                return true
            case #selector(NSResponder.cancelOperation(_:)): // Esc
                parent.onClose()
                return true
            default:
                return false
            }
        }
    }
}

import SwiftUI

/// CC 칸 **아래**(ghostty 서피스 밖)에 붙는 muxa 소유 푸터 밴드 — 이 세션에 지금 공유 중인 문서 컨텍스트를
/// 보이게 하고, `떼기 ✕`로 뗀다. 공유가 없으면 호출부가 이 뷰를 아예 안 그린다(0이면 숨김). 스코프는 이 칸의 CC.
///
/// 디자인 승인 반영: 유채색 상단선 대신 1px `pBorder`(유채색 하단바가 "칸 상태"로 오독되는 것 회피),
/// 맨몸 ✕ 대신 **동사 라벨 `떼기 ✕`**(무설명 발견성), `⧉` 미사용(muxa에서 diff 열기 의미), 전체=`◉` 마커로 구분.
struct TerminalFooterBand: View {
    let context: IdeSelection
    let onClear: () -> Void
    @State private var hovering = false

    private var filename: String { (context.filePath as NSString).lastPathComponent }

    /// 선택 줄 라벨(1-기반 표시) 또는 전체 파일.
    private var detail: String {
        guard !context.isEmpty else { return "전체 파일" }
        let s = context.startLine + 1, e = max(context.endLine + 1, context.startLine + 1)
        let n = e - s + 1
        return s == e ? "L\(s) · \(n)줄" : "L\(s)–\(e) · \(n)줄"
    }

    var body: some View {
        HStack(spacing: Space.xs) {
            // 전체 파일 마커(선택과 구분). ⧉는 muxa에서 "diff 서브탭 열기"라 재사용 안 함.
            if context.isEmpty {
                Text("◉").font(.muxa(.caption)).foregroundStyle(Color.pMuted)
            }
            Text(filename).font(.muxa(.label)).foregroundStyle(Color.pFg).lineLimit(1)
            Text("· \(detail)").font(.muxa(.label)).foregroundStyle(Color.pMuted).lineLimit(1)
            Spacer(minLength: Space.sm)
            // 밴드가 "무엇이 공유 중"인지 이미 보여주므로 ✕만으로 자명하다(채팅 첨부 지우기 패턴).
            Button(action: onClear) {
                Image(systemName: "xmark").font(.muxa(.label, weight: .medium))
                    .foregroundStyle(hovering ? Color.pBrand : Color.pMuted)
                    .frame(width: 20, height: 20)
                    .background(hovering ? Color.pBrandSubtle : Color.clear,
                                in: RoundedRectangle(cornerRadius: Radius.sm))
            }
            .buttonStyle(.plain)
            .clickCursor()
            .onHover { hovering = $0 }
            .help("공유 해제")
            .accessibilityLabel("\(filename) 공유 해제")
        }
        .padding(.horizontal, Space.md)
        .frame(height: RowHeight.bar)
        .frame(maxWidth: .infinity)
        .background(Color.pPanel)
        .overlay(alignment: .top) { Color.pBorder.frame(height: 1) } // 1px 경계 — 유채색 아님
    }
}

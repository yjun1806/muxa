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

    /// 선택 텍스트의 **실제 줄 수**(렌더가 아닌 원문 기준 — claude가 받은 것과 일치).
    private var lineCount: Int {
        context.text.isEmpty ? 0 : context.text.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    /// 파일 크기/선택 요약. 선택이면 줄 수, 없으면 전체 파일.
    private var detail: String { context.isEmpty ? "전체 파일" : "\(lineCount)줄" }

    /// 선택 텍스트 미리보기(개행→공백) — 폭이 허락하는 만큼 보이고 넘치면 SwiftUI가 …로 자른다(1줄).
    private var preview: String {
        context.text.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 호버 툴팁 — claude에 실제로 전달되는 것(전체 경로 포함)을 그대로 노출.
    private var shareInfo: String {
        context.isEmpty
            ? "claude에 공유: 전체 파일 · \(context.filePath)"
            : "claude에 공유: 선택 \(lineCount)줄 · \(context.filePath)"
    }

    var body: some View {
        HStack(spacing: Space.xs) {
            // 링킹 아이콘 — Claude의 컨텍스트 칩(⧉)과 맞춘 두-사각형 글리프. 선택/전체 구분은 텍스트로.
            Image(systemName: "square.on.square").font(.muxa(.label))
                .foregroundStyle(Color.pBrand)
            Text(filename).font(.muxa(.label)).foregroundStyle(Color.pFg).lineLimit(1).layoutPriority(1)
            Text("· \(detail)").font(.muxa(.label)).foregroundStyle(Color.pMuted).fixedSize()
            // 실제 공유된 선택 텍스트 미리보기(선택일 때만) — claude가 받은 원문과 일치. 남은 폭을 flex로 채우고 …로 자름.
            if !context.isEmpty, !preview.isEmpty {
                Text("“\(preview)”").font(.muxa(.label)).italic()
                    .foregroundStyle(Color.pMuted).lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: Space.sm)
            }
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
        .help(shareInfo) // 호버 시 claude에 전달되는 전체 경로·내용
        .background(Color.pPanel)
        .overlay(alignment: .top) { Color.pBorder.frame(height: 1) } // 1px 경계 — 유채색 아님
    }
}

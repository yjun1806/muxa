import SwiftUI

/// 서비스 등록 시트 — 이름 + 명령.
///
/// 명령은 **로그인 셸로 실행된다**(TmuxService.start) — `.app` 번들은 PATH를 상속하지 않아
/// 감싸지 않으면 `pnpm`을 못 찾는다. 그래서 여기 적는 명령은 터미널에 치는 것과 똑같이 동작한다.
struct ServiceAddSheet: View {
    let onAdd: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var command = ""

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !command.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Text("서비스 추가")
                .font(.muxa(.title, weight: .semibold))
                .foregroundStyle(Color.pFg)

            VStack(alignment: .leading, spacing: Space.xs) {
                Text("이름").font(.muxa(.caption)).foregroundStyle(Color.pMuted)
                TextField("web", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.muxa(.body))
            }

            VStack(alignment: .leading, spacing: Space.xs) {
                Text("명령").font(.muxa(.caption)).foregroundStyle(Color.pMuted)
                TextField("pnpm dev", text: $command)
                    .textFieldStyle(.roundedBorder)
                    .font(.muxaMono(.body))
            }

            Text("프로젝트 폴더에서 실행되고, muxa를 꺼도 계속 돕니다.\n죽으면 푸터 칩이 빨갛게 바뀌고 알림이 옵니다.")
                .font(.muxa(.caption))
                .foregroundStyle(Color.pMuted.opacity(0.8))

            HStack {
                Spacer()
                Button("취소") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("추가") {
                    onAdd(name.trimmingCharacters(in: .whitespaces),
                          command.trimmingCharacters(in: .whitespaces))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(Space.xl)
        .frame(width: 380)
        .background(Color.pPanel)
    }
}

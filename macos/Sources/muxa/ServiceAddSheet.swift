import SwiftUI

/// 서비스 등록 시트 — **스크립트를 고르거나, 직접 명령을 친다.**
///
/// 실제로 등록할 것의 대부분은 `package.json`의 스크립트(`pnpm dev`)다. 매번 타이핑하게 두면 오타와
/// **잘못된 패키지 매니저**가 새어든다. 그래서 프로젝트를 훑어 스크립트를 보여주고 클릭 한 번으로
/// 이름·명령이 채워지게 한다. 그 밖의 것(`./scripts/dev.sh`, `go run .`)은 직접 입력으로 받는다.
///
/// 명령은 로그인 셸로 실행된다(`TmuxService.start`) — `.app` 번들은 PATH를 상속하지 않아
/// 감싸지 않으면 `pnpm`을 못 찾는다. 그래서 여기 적는 명령은 터미널에 치는 것과 똑같이 동작한다.
struct ServiceAddSheet: View {
    /// 프로젝트 경로 — 스크립트를 찾을 곳.
    let cwd: String?
    let onAdd: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var command = ""
    @State private var scripts: [ProjectScript] = []
    @State private var manager: PackageManager?
    /// lock 파일이 없어 매니저를 모를 때 사용자가 고른 값(추측하지 않는다).
    @State private var pickedManager: PackageManager = .npm

    private var effectiveManager: PackageManager { manager ?? pickedManager }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !command.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Text("서비스 추가")
                .font(.muxa(.title, weight: .semibold))
                .foregroundStyle(Color.pFg)

            if !scripts.isEmpty {
                scriptPicker
                HDivider()
                Text("또는 직접 입력")
                    .font(.muxa(.caption))
                    .foregroundStyle(Color.pMuted)
            } else {
                // 스크립트가 하나도 없는 프로젝트(네이티브 앱 등) — 침묵하지 않고 왜 없는지 말한다.
                Text("package.json·Makefile·scripts/ 에서 찾은 스크립트가 없습니다.\n실행할 명령을 직접 적어주세요.")
                    .font(.muxa(.caption))
                    .foregroundStyle(Color.pMuted)
            }

            VStack(alignment: .leading, spacing: Space.xs) {
                Text("이름").font(.muxa(.caption)).foregroundStyle(Color.pMuted)
                TextField("web", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.muxa(.body))
            }

            VStack(alignment: .leading, spacing: Space.xs) {
                Text("명령").font(.muxa(.caption)).foregroundStyle(Color.pMuted)
                TextField("pnpm dev · ./scripts/dev.sh · go run .", text: $command)
                    .textFieldStyle(.roundedBorder)
                    .font(.muxaMono(.body))
            }

            Text("프로젝트 폴더에서 로그인 셸로 실행되고, muxa를 꺼도 계속 돕니다.\n죽으면 푸터 칩이 빨갛게 바뀌고 알림이 옵니다.")
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
        .frame(width: 420)
        .background(Color.pPanel)
        .task {
            let found = ProjectScripts.discover(in: cwd)
            scripts = found.scripts
            manager = found.manager
        }
    }

    // MARK: package.json 스크립트 — 클릭 한 번으로 이름·명령을 채운다

    /// package.json 스크립트가 하나라도 있을 때만 패키지 매니저가 의미 있다(Makefile·sh는 무관).
    private var hasPackageScripts: Bool { scripts.contains { $0.source == .packageJSON } }

    private var scriptPicker: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                Text("프로젝트 스크립트")
                    .font(.muxa(.caption))
                    .foregroundStyle(Color.pMuted)
                Spacer(minLength: Space.sm)
                if hasPackageScripts {
                    if manager == nil {
                        // lock 파일이 없다 — **추측하지 않고 물어본다.** pnpm 프로젝트에 `npm run`을 넣으면
                        // lock이 깨지거나 엉뚱한 의존성이 깔린다. 기본값을 조용히 쓰지 않는다.
                        Picker("", selection: $pickedManager) {
                            ForEach(PackageManager.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .help("lock 파일이 없어 패키지 매니저를 알 수 없습니다 — 직접 고르세요")
                    } else {
                        Pill(color: Color.pBrand) {
                            Text(effectiveManager.rawValue).font(.muxa(.caption, weight: .semibold))
                        }
                        .help("lock 파일로 감지한 패키지 매니저")
                    }
                }
            }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(scripts) { script in
                        scriptRow(script)
                    }
                }
            }
            .frame(maxHeight: 150)
            .background(Color.pBg, in: RoundedRectangle(cornerRadius: Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Color.pBorder, lineWidth: 1))
        }
    }

    /// 스크립트가 실제로 실행할 명령. package.json만 패키지 매니저로 조립하고
    /// (`pnpm run dev`), Makefile·셸 스크립트는 이미 완성된 명령이다(`make dev`·`./scripts/dev.sh`).
    private func runCommand(_ script: ProjectScript) -> String {
        script.source == .packageJSON ? effectiveManager.runCommand(script.name) : script.body
    }

    /// 스크립트 한 줄 — [출처] 이름 | 설명(있으면) · 실제 명령.
    /// 클릭하면 아래 입력칸이 채워진다(바로 등록하지 않는다 — 이름을 바꾸거나 명령을 손볼 수 있게).
    private func scriptRow(_ script: ProjectScript) -> some View {
        let filled = runCommand(script)
        let isSelected = command == filled
        return Button {
            name = script.name
            command = filled
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                // 출처를 밝힌다 — 여러 소스가 섞이면 "이게 어디서 왔지"가 곧바로 궁금해진다.
                Text(sourceLabel(script.source))
                    .font(.muxa(.nano, weight: .semibold))
                    .foregroundStyle(Color.pMuted)
                    .frame(width: 34, alignment: .leading)
                Text(script.name)
                    .font(.muxaMono(.label, weight: .semibold))
                    .foregroundStyle(Color.pFg)
                    .frame(minWidth: 52, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    // 설명이 있으면 그게 주인공이다 — 명령보다 사람 말이 먼저 읽혀야 한다.
                    if let note = script.note {
                        Text(note)
                            .font(.muxa(.label))
                            .foregroundStyle(Color.pFg)
                            .lineLimit(1)
                    }
                    Text(filled)
                        .font(.muxaMono(.caption))
                        .foregroundStyle(Color.pMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.muxa(.micro))
                        .foregroundStyle(Color.pBrand)
                }
            }
            .padding(.horizontal, Space.sm)
            .padding(.vertical, Space.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            // 목록 선택은 **중립 채움**이다(브랜드 wash 금지 — Palette 주석·DESIGN.md §2).
            .background(isSelected ? Color.pBtnActive : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sourceLabel(_ source: ScriptSource) -> String {
        switch source {
        case .packageJSON: return "pkg"
        case .makefile: return "make"
        case .justfile: return "just"
        case .shell: return "sh"
        }
    }
}

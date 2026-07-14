// swift-tools-version: 5.9
// muxa M0 PoC — GhosttyKit 임베딩 + 한글 IME 게이트 (ARCHITECTURE.md v2 M0)
import PackageDescription

let package = Package(
    name: "muxa",
    platforms: [.macOS(.v14)], // SwiftUI @Observable·최신 API
    dependencies: [
        // 분할·탭 SwiftUI 프레임워크(MIT). **우리 fork**(yjun1806/bonsplit, `muxa` 브랜치) —
        // manaflow-ai fork에서 갈라져 나왔다(그쪽이 SplitActionButton·ChromeColors 등
        // 탭바 커스터마이즈 API를 추가했고, 원본 almonk엔 그게 없다). 탭바 디자인·툴바를
        // 우리 입맛대로 고치려면 소스 수정이 필요해 fork했다.
        // upstream 추적: 로컬 클론(~/Documents/private/bonsplit)에 `upstream` 리모트로 manaflow가 걸려 있다.
        // 태그가 없어 revision 고정(재현성) — Package.resolved가 동일 커밋을 보장한다.
        .package(url: "https://github.com/yjun1806/bonsplit.git", revision: "10c154fda321f2cf21a998eeffc28f67a28bd08e"),
    ],
    targets: [
        .executableTarget(
            name: "muxa",
            dependencies: [
                "GhosttyKit",
                .product(name: "Bonsplit", package: "bonsplit"),
            ],
            resources: [
                // md/HTML 뷰어용 오프라인 JS 에셋(markdown-it·highlight.js·mermaid) + HTML 셸.
                .copy("Resources/mdviewer"),
                // 코드 뷰어용 Shiki 오프라인 번들(shiki.bundle.js) + HTML 셸.
                .copy("Resources/codeviewer"),
                // 파일 익스플로러 컬러 아이콘(Material Icon Theme 슬림 번들 + icons.json).
                .copy("Resources/fileicons"),
                // 앱 아이콘(1024) — bare 실행에서도 Dock 아이콘을 이걸로 설정한다(main.swift). 재생성 = scripts/build-appicon.
                .copy("Resources/AppIcon.png"),
                // Claude 심볼(공식 SVG) — 사용량 표시의 출처 마크. NSImage가 벡터로 렌더한다.
                .copy("Resources/claude-symbol.svg"),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("WebKit"), // md/HTML 뷰어(WKWebView)
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("CoreText"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("Carbon"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("GameController"), // imgui_impl_osx가 참조
                // GhosttyKit(ghostty-internal.a)은 self-contained — libintl·zlib·imgui·
                // freetype·oniguruma·libpng 등 C/C++ 의존성을 아카이브에 모두 포함한다.
                // (cmux fork의 prebuilt universal 빌드) C++ 런타임만 시스템에서 링크.
                .linkedLibrary("c++"),
            ]
        ),
        // 훅용 CLI — 셸 env(MUXA_SOCK/MUXA_TAB_ID)를 읽어 앱 소켓에 한 줄 쓰고 종료. 외부 의존성 없음.
        .executableTarget(name: "muxa-notify"),
        // 순수 로직 단위 테스트 — 값 타입·순수 함수(파싱·랭킹·게이트·앵커링 등)만 검증.
        // @testable import muxa로 앱 모듈 심볼에 접근. GhosttyKit 링크는 앱과 동일(bootstrap 필요).
        .testTarget(name: "muxaTests", dependencies: ["muxa"]),
        // cmux fork의 prebuilt xcframework(universal, ReleaseFast). scripts/bootstrap.sh가
        // vendor/ghostty/macos/에 설치하고, 이 심링크(GhosttyKit.xcframework)가 그걸 가리킨다.
        .binaryTarget(name: "GhosttyKit", path: "GhosttyKit.xcframework"),
    ]
)

// swift-tools-version: 5.9
// muxa M0 PoC — GhosttyKit 임베딩 + 한글 IME 게이트 (DESIGN.md v2 M0)
import PackageDescription

let package = Package(
    name: "muxa",
    platforms: [.macOS(.v14)], // SwiftUI @Observable·최신 API
    dependencies: [
        // 분할·탭 SwiftUI 프레임워크(MIT). cmux(manaflow) fork — 탭바 SplitActionButton
        // (새터미널·분할 버튼을 탭바에 내장)으로 탭 추가 버튼을 분할 버튼 옆에 둔다.
        // 태그가 없어 revision 고정(재현성) — bootstrap/Package.resolved가 동일 커밋 보장.
        .package(url: "https://github.com/manaflow-ai/bonsplit.git", revision: "10c154fda321f2cf21a998eeffc28f67a28bd08e"),
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
        // cmux fork의 prebuilt xcframework(universal, ReleaseFast). scripts/bootstrap.sh가
        // vendor/ghostty/macos/에 설치하고, 이 심링크(GhosttyKit.xcframework)가 그걸 가리킨다.
        .binaryTarget(name: "GhosttyKit", path: "GhosttyKit.xcframework"),
    ]
)

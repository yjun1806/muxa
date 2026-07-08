// swift-tools-version: 5.9
// muxa M0 PoC — GhosttyKit 임베딩 + 한글 IME 게이트 (DESIGN.md v2 M0)
import PackageDescription

let package = Package(
    name: "muxa",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "muxa",
            dependencies: ["GhosttyKit"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("CoreText"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("Carbon"),
                .linkedFramework("UniformTypeIdentifiers"),
            ]
        ),
        // vendor/ghostty에서 zig로 빌드한 산출물 (심링크)
        .binaryTarget(name: "GhosttyKit", path: "GhosttyKit.xcframework"),
    ]
)

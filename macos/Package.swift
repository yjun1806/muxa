// swift-tools-version: 5.9
// muxa M0 PoC — GhosttyKit 임베딩 + 한글 IME 게이트 (DESIGN.md v2 M0)
import PackageDescription

let package = Package(
    name: "muxa",
    platforms: [.macOS(.v14)], // SwiftUI @Observable·최신 API
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
                .linkedFramework("GameController"), // imgui_impl_osx가 참조
                // GhosttyKit(fat.a)이 참조하는 C/C++ 정적 의존성.
                // Ghostty는 셰이더·폰트·유니코드 라이브러리를 fat.a에 넣지 않고 별도 .a로 두므로
                // 여기서 개별 링크한다(ld가 심볼 기준으로 필요한 오브젝트만 뽑는다).
                // deps/는 vendor/ghostty/build-deps.sh가 zig-cache에서 채운다.
                .linkedLibrary("c++"),
                // GhosttyKit fat.a가 참조하는 C/C++ 정적 의존성. build-deps.sh가 zig의
                // (정렬 안 된) .a를 ld -r로 라이브러리별 재배치 .o로 변환한 것을 링크한다.
                // GhosttyKit은 -Di18n=false로 빌드해 gettext(libintl) 의존을 제거했다.
                .unsafeFlags([
                    "../vendor/ghostty/deps/libsimdutf.o",
                    "../vendor/ghostty/deps/libhighway.o",
                    "../vendor/ghostty/deps/libz.o",
                    "../vendor/ghostty/deps/libspirv_cross.o",
                    "../vendor/ghostty/deps/libmacos.o",
                    "../vendor/ghostty/deps/libfreetype.o",
                    "../vendor/ghostty/deps/libutfcpp.o",
                    "../vendor/ghostty/deps/liboniguruma.o",
                    "../vendor/ghostty/deps/libpng.o",
                    "../vendor/ghostty/deps/libdcimgui.o",
                    "../vendor/ghostty/deps/libglslang.o",
                    // fat.a 조립 시 누락된 libghostty.a 오브젝트(simd·compiler_rt·stb)
                    "../vendor/ghostty/deps/libghostty_missing.o",
                ]),
            ]
        ),
        // vendor/ghostty에서 zig로 빌드한 산출물 (심링크)
        .binaryTarget(name: "GhosttyKit", path: "GhosttyKit.xcframework"),
        // 순수 로직(Tree 등) 단위 테스트
        .testTarget(name: "muxaTests", dependencies: ["muxa"]),
    ]
)

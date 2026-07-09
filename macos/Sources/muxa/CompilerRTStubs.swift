// GhosttyKit(zig Debug 빌드)의 ubsan_rt가 128-bit float 확장 루틴 __extend{df,xf}tf2를
// 참조하지만, 이 심볼은 zig compiler_rt에서 local(hidden)로 컴파일돼 외부에서 안 보인다.
// arm64 macOS는 long double == double이라 이 루틴은 실제로 호출되지 않으므로 링크용 스텁만 둔다.
//
// TODO(M0 게이트 통과 후): GhosttyKit을 -Doptimize=ReleaseFast로 빌드하면 ubsan_rt가
// 사라져 이 스텁 전체가 불필요해진다. 그때 이 파일을 삭제한다.
@_cdecl("__extenddftf2") func muxa_stub_extenddftf2(_ a: Double) -> Double { a }
@_cdecl("__extendxftf2") func muxa_stub_extendxftf2(_ a: Double) -> Double { a }

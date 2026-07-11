import AppKit

// muxa 아이콘 revH2 — 색반전(청록 bg + 차콜 심볼) 베이스에 muxa 정체성 결합.
//  a: ❯ _  차콜 chevron + 차콜 언더바 커서 — "명령을 기다리는 프롬프트" (전부 차콜, 가장 절제)
//  b: ❯ ●  차콜 chevron + 주황 점(중앙 높이) — "세션이 나를 기다림" 상태점
//  c: ≫    이중 chevron (뒤쪽 반투명) — 다중 세션 감시, 깊이감
//  d: ❯ _  차콜 chevron + 주황 언더바 커서 — 프롬프트+대기 이중 의미
//  e: ❯ +  대형 chevron + 우상단 주황 배지 점 — 알림 뱃지 문법
// 좌표는 시각적 bounding box(캡 반경 포함) 기준 광학 센터링.

let S: CGFloat = 1024
func hex(_ h: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((h >> 16) & 0xFF) / 255, green: CGFloat((h >> 8) & 0xFF) / 255,
            blue: CGFloat(h & 0xFF) / 255, alpha: a)
}
func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x, y: y) }

let charcoal = hex(0x1B1B1D)
let amber = hex(0xFBBF24)

let variant = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "a"
let out = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "revH2_\(variant).png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// ── 배경 squircle (proH_b 그대로) ──────────────────────────────
let margin: CGFloat = 100
let shape = CGRect(x: margin, y: margin, width: S - 2 * margin, height: S - 2 * margin)
let corner = shape.width * 0.2237
let squircle = NSBezierPath(roundedRect: shape, xRadius: corner, yRadius: corner)
squircle.addClip()
NSGradient(colors: [hex(0x35DECA), hex(0x27C4B1)])!.draw(in: shape, angle: -90)
let inset = squircle.copy() as! NSBezierPath
inset.lineWidth = 3
hex(0xFFFFFF, 0.10).setStroke()
inset.stroke()

// ── 프리미티브 ────────────────────────────────────────────────
func chevron(x0: CGFloat, yMid: CGFloat, rise: CGFloat, K: CGFloat,
             w: CGFloat, color: NSColor) {
    let p = NSBezierPath()
    p.move(to: pt(x0, yMid + rise))
    p.line(to: pt(x0 + K, yMid))
    p.line(to: pt(x0, yMid - rise))
    p.lineWidth = w
    p.lineCapStyle = .round
    p.lineJoinStyle = .round
    color.setStroke()
    p.stroke()
}
func bar(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, r: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: CGRect(x: x, y: y, width: w, height: h),
                 xRadius: r, yRadius: r).fill()
}
func dot(cx: CGFloat, cy: CGFloat, d: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(ovalIn: CGRect(x: cx - d / 2, y: cy - d / 2, width: d, height: d)).fill()
}

// ── variant 레이아웃 ──────────────────────────────────────────
switch variant {
case "b":
    // ❯ ● — chevron + 주황 상태점(중앙 높이). 점은 커서 아님, "대기 중 세션".
    let w: CGFloat = 138, rise: CGFloat = 226, K: CGFloat = 244
    let gap: CGFloat = 96, d: CGFloat = 148
    let chevVisW = K + w
    let groupW = chevVisW + gap + d
    let left = 512 - groupW / 2
    chevron(x0: left + w / 2, yMid: 512, rise: rise, K: K, w: w, color: charcoal)
    dot(cx: left + chevVisW + gap + d / 2, cy: 512, d: d, color: amber)

case "c":
    // ≫ — 이중 chevron. 뒤쪽은 반투명 차콜(청록에 가라앉음) → 깊이/다중 세션.
    let w: CGFloat = 128, rise: CGFloat = 214, K: CGFloat = 230
    let dx: CGFloat = 196
    let visW = dx + K + w
    let left = 512 - visW / 2 + 4   // 광학 보정
    chevron(x0: left + w / 2, yMid: 512, rise: rise, K: K, w: w, color: hex(0x1B1B1D, 0.40))
    chevron(x0: left + w / 2 + dx, yMid: 512, rise: rise, K: K, w: w, color: charcoal)

case "d":
    // ❯ _ — chevron 차콜 + 언더바 주황. 프롬프트 커서 = 대기 신호.
    let w: CGFloat = 124, rise: CGFloat = 212, K: CGFloat = 228
    let gap: CGFloat = 84
    let barW: CGFloat = 236, barH: CGFloat = 118
    let chevVisW = K + w
    let groupW = chevVisW + gap + barW
    let left = 512 - groupW / 2
    chevron(x0: left + w / 2, yMid: 512, rise: rise, K: K, w: w, color: charcoal)
    let yBase = 512 - rise - w / 2
    bar(x: left + chevVisW + gap, y: yBase, w: barW, h: barH, r: barH / 2, color: amber)

case "e":
    // 대형 ❯ 센터 + 우상단 주황 배지 점 — macOS 알림 뱃지 문법.
    let w: CGFloat = 144, rise: CGFloat = 228, K: CGFloat = 246
    let visW = K + w
    let x0 = 512 - visW / 2 + w / 2 - 6    // 배지가 오른쪽 질량을 더하므로 살짝 왼쪽
    chevron(x0: x0, yMid: 512, rise: rise, K: K, w: w, color: charcoal)
    // 배지 점: chevron 상단 캡과 같은 높이로 정렬 — 우연이 아닌 의도된 배치로 읽히게
    dot(cx: shape.maxX - 186, cy: 512 + rise, d: 124, color: amber)

default: // "a"
    // ❯ _ — 전부 차콜. 색반전 순수형 + 프롬프트 문법.
    let w: CGFloat = 124, rise: CGFloat = 212, K: CGFloat = 228
    let gap: CGFloat = 84
    let barW: CGFloat = 236, barH: CGFloat = 118
    let chevVisW = K + w
    let groupW = chevVisW + gap + barW
    let left = 512 - groupW / 2
    chevron(x0: left + w / 2, yMid: 512, rise: rise, K: K, w: w, color: charcoal)
    let yBase = 512 - rise - w / 2
    bar(x: left + chevVisW + gap, y: yBase, w: barW, h: barH, r: barH / 2, color: charcoal)
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out) [\(variant)]")

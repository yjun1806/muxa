import AppKit

// muxa 아이콘.
//  x: ✕    다크 그래파이트 bg + 버밀리언 손그림 X — "muXa"의 X를 아이가 크레용으로 그린 낙서체 (현행)
//  ── 아래는 옛 청록 베이스(색반전 bg + 차콜 심볼) 안, a~e로 재생성 가능 ──
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
let vermilion = hex(0xE24A20) // 선셋 버밀리언(키컬러) — 낙서 X variant "x" 전용

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
// variant "x"(낙서 X)는 다크 그래파이트 배경, 나머지는 기존 청록.
let bgColors: [NSColor] = variant == "x"
    ? [hex(0x2C2825), hex(0x151312)]   // 다크 그래파이트(위 명·아래 암)
    : [hex(0x35DECA), hex(0x27C4B1)]   // 청록(기존 아이콘)
NSGradient(colors: bgColors)!.draw(in: shape, angle: -90)
let inset = squircle.copy() as! NSBezierPath
inset.lineWidth = 3
hex(0xFFFFFF, variant == "x" ? 0.06 : 0.10).setStroke()
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
/// 아이가 크레용으로 그린 듯한 삐뚤빼뚤 X (muXa의 X). 두 획이 흔들리며 교차한다.
/// 직선 대신 컨트롤 포인트를 대각선에서 밀어내 손그림 waver를, 굵은 라운드 캡으로 크레용 질감을 낸다.
/// AppKit 좌표는 y가 위로 갈수록 크다(하단 원점).
func doodleX(color: NSColor, w: CGFloat = 94) {
    NSGraphicsContext.saveGraphicsState()
    // 살짝 기울여 "반듯하지 않은" 손맛(-4°, 캔버스 중심 기준).
    let t = NSAffineTransform()
    t.translateX(by: 512, yBy: 512); t.rotate(byDegrees: -4); t.translateX(by: -512, yBy: -512)
    t.concat()
    color.setStroke()
    func stroke(_ p: NSBezierPath) {
        p.lineWidth = w; p.lineCapStyle = .round; p.lineJoinStyle = .round; p.stroke()
    }
    // 획 1: 좌상 → 우하
    let a = NSBezierPath()
    a.move(to: pt(322, 700))
    a.curve(to: pt(516, 512), controlPoint1: pt(438, 636), controlPoint2: pt(452, 556))
    a.curve(to: pt(706, 320), controlPoint1: pt(578, 470), controlPoint2: pt(602, 398))
    stroke(a)
    // 획 2: 우상 → 좌하 (좌우 비대칭으로 더 사람 손 느낌)
    let b = NSBezierPath()
    b.move(to: pt(704, 702))
    b.curve(to: pt(508, 510), controlPoint1: pt(598, 632), controlPoint2: pt(560, 556))
    b.curve(to: pt(320, 320), controlPoint1: pt(452, 460), controlPoint2: pt(410, 392))
    stroke(b)
    NSGraphicsContext.restoreGraphicsState()
}

// ── variant 레이아웃 ──────────────────────────────────────────
switch variant {
case "x":
    // 낙서 X — 다크 그래파이트 배경 위 버밀리언 손그림 X("muXa"의 X). 가장 가볍고 사람 냄새.
    doodleX(color: vermilion)

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

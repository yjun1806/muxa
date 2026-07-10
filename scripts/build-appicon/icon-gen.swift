import AppKit

// muxa 앱 아이콘 — GitBaro의 "GB 겹친 모노그램" 톤을 따르되 muxa 정체성 색을 쓴다.
// 차콜 squircle + 두꺼운 geometric "MA" 모노그램(M=밝은 흰, A=청록 borderFocus)이 획을 겹친다.

let S: CGFloat = 1024

func hex(_ h: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((h >> 16) & 0xFF) / 255, green: CGFloat((h >> 8) & 0xFF) / 255,
            blue: CGFloat(h & 0xFF) / 255, alpha: a)
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// ── squircle 배경 (GitBaro 톤: 차콜, 미세 그라디언트) ──
let margin: CGFloat = 100
let shape = CGRect(x: margin, y: margin, width: S - 2 * margin, height: S - 2 * margin)
let corner = shape.width * 0.2237
let bg = NSBezierPath(roundedRect: shape, xRadius: corner, yRadius: corner)
bg.addClip()
NSGradient(colors: [hex(0x2C2C31), hex(0x161618)])!.draw(in: shape, angle: -90)
NSGradient(colors: [hex(0xFFFFFF, 0.06), hex(0xFFFFFF, 0)])!
    .draw(in: CGRect(x: shape.minX, y: shape.midY, width: shape.width, height: shape.height / 2), angle: -90)

// ── MA 모노그램 (두꺼운 stroke, round join — geometric) ──
let lw: CGFloat = 76
func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x, y: y) }

func stroke(_ path: NSBezierPath, _ color: NSColor) {
    path.lineWidth = lw
    path.lineJoinStyle = .round
    path.lineCapStyle = .round
    color.setStroke()
    path.stroke()
}

let yBot: CGFloat = 350
let yTop: CGFloat = 690

// M — 왼쪽. 좌하→좌상(뾰족)→중턱(V 바닥)→우상(뾰족)→우하. 밝은 흰.
let m = NSBezierPath()
m.move(to: p(252, yBot))
m.line(to: p(252, yTop))
m.line(to: p(408, 508))
m.line(to: p(564, yTop))
m.line(to: p(564, yBot))
stroke(m, hex(0xF4F4F5))

// A — 오른쪽, M과 획을 겹친다(왼다리가 M 오른쪽 영역과 포갬). 청록(muxa 포커스색).
let a = NSBezierPath()
a.move(to: p(474, yBot))
a.line(to: p(630, yTop))
a.line(to: p(786, yBot))
stroke(a, hex(0x2DD4BF))
// A 가로바
let bar = NSBezierPath()
bar.move(to: p(536, 486))
bar.line(to: p(724, 486))
stroke(bar, hex(0x2DD4BF))

NSGraphicsContext.restoreGraphicsState()
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")

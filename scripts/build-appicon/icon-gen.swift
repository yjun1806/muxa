import AppKit

// muxa 앱 아이콘 — GitBaro의 겹친 모노그램 톤. 차콜 squircle + MA.
// M(흰)과 A(청록)를 각각 온전한 글자로 그리되, M의 오른다리와 A의 왼다리를 바닥에서
// 같은 지점으로 붙여 두 글자가 하나의 실루엣처럼 엮이게 한다.

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

let margin: CGFloat = 100
let shape = CGRect(x: margin, y: margin, width: S - 2 * margin, height: S - 2 * margin)
let corner = shape.width * 0.2237
NSBezierPath(roundedRect: shape, xRadius: corner, yRadius: corner).addClip()
NSGradient(colors: [hex(0x2C2C31), hex(0x161618)])!.draw(in: shape, angle: -90)
NSGradient(colors: [hex(0xFFFFFF, 0.06), hex(0xFFFFFF, 0)])!
    .draw(in: CGRect(x: shape.minX, y: shape.midY, width: shape.width, height: shape.height / 2), angle: -90)

func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x, y: y) }
func stroke(_ path: NSBezierPath, _ c: NSColor, width: CGFloat = 76) {
    path.lineWidth = width; path.lineJoinStyle = .round; path.lineCapStyle = .round
    c.setStroke(); path.stroke()
}

let yBot: CGFloat = 360
let yTop: CGFloat = 690

// M — 온전한 글자(좌하·좌상·골·우상·우하). 우하가 A의 왼다리 밑동과 같은 자리로 내려온다. [흰]
let m = NSBezierPath()
m.move(to: pt(236, yBot))
m.line(to: pt(236, yTop))
m.line(to: pt(384, 512))
m.line(to: pt(532, yTop))
m.line(to: pt(532, yBot))
stroke(m, hex(0xF4F4F5))

// A — 온전한 글자. 왼다리 밑동(526)이 M 우하(532) 바로 옆에서 시작해 둘이 바닥에서 하나로 붙는다. [청록]
let aL = NSBezierPath()
aL.move(to: pt(526, yBot))
aL.line(to: pt(662, yTop))
stroke(aL, hex(0x2DD4BF))
let aR = NSBezierPath()
aR.move(to: pt(662, yTop))
aR.line(to: pt(798, yBot))
stroke(aR, hex(0x2DD4BF))
let bar = NSBezierPath()          // A 가로바
bar.move(to: pt(598, 528))
bar.line(to: pt(726, 528))
stroke(bar, hex(0x2DD4BF), width: 62)

NSGraphicsContext.restoreGraphicsState()
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")

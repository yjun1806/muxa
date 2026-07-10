import AppKit

// muxa 앱 아이콘 생성기 — Core Graphics 드로잉(SVG 래스터라이저 의존 없음).
// 정체성: 에이전트 오케스트레이션 터미널 = 분할된 칸(멀티플렉싱) + "나를 기다린다" 알림 점.
// 색은 Palette.swift 다크 값 그대로.

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
let ctx = NSGraphicsContext.current!.cgContext

// ── 1. squircle 배경 (macOS 아이콘 그리드: 824 shape in 1024, 여백 100) ──
let margin: CGFloat = 100
let shape = CGRect(x: margin, y: margin, width: S - 2 * margin, height: S - 2 * margin)
let corner: CGFloat = shape.width * 0.2237 // Apple squircle 근사
let bgPath = NSBezierPath(roundedRect: shape, xRadius: corner, yRadius: corner)
bgPath.addClip()

// 차콜 세로 그라디언트 (위가 살짝 밝아 입체감)
let grad = NSGradient(colors: [hex(0x2C2C31), hex(0x161618)])!
grad.draw(in: shape, angle: -90)

// 상단 미세 하이라이트(유리질 느낌)
let gloss = NSGradient(colors: [hex(0xFFFFFF, 0.06), hex(0xFFFFFF, 0)])!
gloss.draw(in: CGRect(x: shape.minX, y: shape.midY, width: shape.width, height: shape.height / 2), angle: -90)

// ── 2. 3분할 터미널 칸 (좌 큰 칸 + 우 상/하) ──
let pad: CGFloat = 78
let content = shape.insetBy(dx: pad, dy: pad)
let gap: CGFloat = 30
let leftW = content.width * 0.55
let rightW = content.width - leftW - gap
let rightX = content.minX + leftW + gap
let halfH = (content.height - gap) / 2

let paneRadius: CGFloat = 30
struct Pane { let rect: CGRect; let active: Bool }
let leftPane  = Pane(rect: CGRect(x: content.minX, y: content.minY, width: leftW, height: content.height), active: true)
let topRight  = Pane(rect: CGRect(x: rightX, y: content.minY + halfH + gap, width: rightW, height: halfH), active: false)
let botRight  = Pane(rect: CGRect(x: rightX, y: content.minY, width: rightW, height: halfH), active: false)

func drawPane(_ p: Pane) {
    let path = NSBezierPath(roundedRect: p.rect, xRadius: paneRadius, yRadius: paneRadius)
    hex(0x1B1B1D).setFill()
    path.fill()
    // 활성 칸은 청록 테두리(포커스), 나머지는 은은한 회색.
    (p.active ? hex(0x2DD4BF) : hex(0x3A3A3F)).setStroke()
    path.lineWidth = p.active ? 7 : 4
    path.stroke()
}
[leftPane, topRight, botRight].forEach(drawPane)

// ── 3. 각 칸의 프롬프트 (chevron › + 텍스트 라인 막대) ──
func bar(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: NSColor) {
    c.setFill()
    NSBezierPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), xRadius: h / 2, yRadius: h / 2).fill()
}

// chevron "›" 을 두 획 path로 그린다(폰트 의존 없음).
func chevron(at pt: CGPoint, size: CGFloat, color: NSColor, width: CGFloat) {
    let p = NSBezierPath()
    p.move(to: CGPoint(x: pt.x, y: pt.y + size))
    p.line(to: CGPoint(x: pt.x + size * 0.62, y: pt.y + size / 2))
    p.line(to: CGPoint(x: pt.x, y: pt.y))
    p.lineWidth = width
    p.lineCapStyle = .round
    p.lineJoinStyle = .round
    color.setStroke()
    p.stroke()
}

// 좌측 활성 칸: 밝은 프롬프트 + 청록 커서 블록
do {
    let r = leftPane.rect.insetBy(dx: 46, dy: 46)
    let lh: CGFloat = 26           // 라인 높이(막대 두께)
    let ls: CGFloat = 58           // 라인 간격
    let chSize: CGFloat = 46
    var y = r.maxY - chSize
    // line 1: › + 명령
    chevron(at: CGPoint(x: r.minX, y: y), size: chSize, color: hex(0x2DD4BF), width: 13)
    bar(r.minX + chSize * 0.95, y + (chSize - lh) / 2, r.width * 0.52, lh, hex(0x9A9AA2))
    y -= ls
    // line 2~3: 출력 라인(어두운 muted)
    bar(r.minX, y + (chSize - lh) / 2, r.width * 0.82, lh, hex(0x55555C))
    y -= ls
    bar(r.minX, y + (chSize - lh) / 2, r.width * 0.66, lh, hex(0x55555C))
    y -= ls
    // 커서 라인: › + 청록 커서 블록
    chevron(at: CGPoint(x: r.minX, y: y), size: chSize, color: hex(0x2DD4BF), width: 13)
    hex(0x2DD4BF).setFill()
    NSBezierPath(rect: CGRect(x: r.minX + chSize * 0.95, y: y, width: 34, height: chSize)).fill()
}

// 우측 두 칸: 간단한 프롬프트 + 상태 점(상=대기 주황, 하=완료 초록)
func drawRightPane(_ p: Pane, dotColor: NSColor) {
    let r = p.rect.insetBy(dx: 34, dy: 34)
    let lh: CGFloat = 18
    let ls: CGFloat = 40
    let chSize: CGFloat = 32
    var y = r.maxY - chSize
    chevron(at: CGPoint(x: r.minX, y: y), size: chSize, color: hex(0x8A8A90), width: 9)
    bar(r.minX + chSize * 0.95, y + (chSize - lh) / 2, r.width * 0.45, lh, hex(0x6A6A72))
    y -= ls
    bar(r.minX, y + (chSize - lh) / 2, r.width * 0.7, lh, hex(0x4A4A50))
    // 상태 점 — 칸 우상단 모서리("이 세션이 나를 기다린다/끝났다")
    let d: CGFloat = 46
    let dot = CGRect(x: p.rect.maxX - d - 28, y: p.rect.maxY - d - 28, width: d, height: d)
    dotColor.setFill()
    NSBezierPath(ovalIn: dot).fill()
    // 점 둘레 살짝 어둡게(칸 배경 위 대비)
    hex(0x1B1B1D, 0.0).setStroke()
}
drawRightPane(topRight, dotColor: hex(0xFBBF24)) // 대기(주황)
drawRightPane(botRight, dotColor: hex(0x3FB950)) // 완료(초록)

NSGraphicsContext.restoreGraphicsState()

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")

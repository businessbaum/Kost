// Zeichnet das App-Symbol: der Kalorienring der App auf heller Kachel.
// Aufruf: swift Werkzeug/symbol.swift <Zieldatei.png>
import AppKit

let kante = 1024.0
let ziel = CommandLine.arguments.dropFirst().first ?? "symbol.png"

guard let flaeche = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(kante), pixelsHigh: Int(kante), bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
), let kontext = NSGraphicsContext(bitmapImageRep: flaeche) else { exit(1) }

NSGraphicsContext.current = kontext
let cg = kontext.cgContext

func farbe(_ hex: UInt32) -> CGColor {
    CGColor(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, alpha: 1)
}

// Kachel nach dem macOS-Raster: 824 Punkt breit, mittig, mit weichem Schatten
let kachel = CGRect(x: 100, y: 100, width: 824, height: 824)
let form = CGPath(roundedRect: kachel, cornerWidth: 186, cornerHeight: 186, transform: nil)
cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.28))
cg.addPath(form)
cg.setFillColor(farbe(0xFFFFFF))
cg.fillPath()
cg.restoreGState()

cg.saveGState()
cg.addPath(form)
cg.clip()
let verlauf = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [farbe(0xFFFFFF), farbe(0xEEF0F3)] as CFArray, locations: [0, 1])!
cg.drawLinearGradient(verlauf, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
cg.restoreGState()

// Ring: Spur plus drei Bögen in den Makrofarben, im Uhrzeigersinn ab 12 Uhr
let mitte = CGPoint(x: 512, y: 512)
let radius = 232.0
let staerke = 84.0
cg.setLineWidth(staerke)
cg.setLineCap(.butt)
cg.setStrokeColor(farbe(0xE4E6EA))
cg.addArc(center: mitte, radius: radius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
cg.strokePath()

let luecke = 0.035
var start = Double.pi / 2
for (hex, anteil) in [(UInt32(0x2A78D6), 0.24), (0xEB6834, 0.34), (0x1BAF7A, 0.20)] {
    let ende = start - anteil * 2 * .pi
    cg.setStrokeColor(farbe(hex))
    cg.addArc(center: mitte, radius: radius, startAngle: start, endAngle: ende + luecke, clockwise: true)
    cg.strokePath()
    start = ende
}

kontext.flushGraphics()
guard let png = flaeche.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: ziel))

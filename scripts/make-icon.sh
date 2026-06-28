#!/usr/bin/env bash
# Render the VocabLook app icon (ink-indigo squircle + serif "V") into Resources/AppIcon.icns.
# Reproducible: regenerates the .icns from a CoreGraphics drawing. Run from the repo root.
set -euo pipefail
cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
SWIFT="$WORK/icon.swift"
PNG="$WORK/icon_1024.png"

cat > "$SWIFT" <<'SWIFTEOF'
import AppKit

let px = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
let gctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = gctx
let ctx = gctx.cgContext
let S = CGFloat(px)

// Squircle background with an ink-indigo -> violet gradient (transparent corners).
let margin = S * 0.06
let rect = CGRect(x: margin, y: margin, width: S - 2 * margin, height: S - 2 * margin)
let radius = rect.width * 0.2237
let squircle = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
ctx.saveGState()
ctx.addPath(squircle); ctx.clip()
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
    NSColor(srgbRed: 0.36, green: 0.36, blue: 0.90, alpha: 1).cgColor,
    NSColor(srgbRed: 0.55, green: 0.35, blue: 0.93, alpha: 1).cgColor
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: rect.minX, y: rect.maxY),
                       end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
ctx.restoreGState()

// Serif "V" headword glyph.
let font = NSFont(name: "Georgia-Bold", size: S * 0.52) ?? NSFont.systemFont(ofSize: S * 0.5, weight: .bold)
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
shadow.shadowBlurRadius = S * 0.018
shadow.shadowOffset = NSSize(width: 0, height: -S * 0.012)
let str = NSAttributedString(string: "V", attributes: [
    .font: font, .foregroundColor: NSColor.white, .shadow: shadow])
let sz = str.size()
str.draw(at: NSPoint(x: (S - sz.width) / 2, y: (S - sz.height) / 2 + S * 0.04))

// Dictionary-entry underline accent.
ctx.setFillColor(NSColor.white.withAlphaComponent(0.92).cgColor)
let ulW = S * 0.30, ulH = S * 0.024
let ul = CGRect(x: (S - ulW) / 2, y: S * 0.205, width: ulW, height: ulH)
ctx.addPath(CGPath(roundedRect: ul, cornerWidth: ulH / 2, cornerHeight: ulH / 2, transform: nil))
ctx.fillPath()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
SWIFTEOF

swift "$SWIFT" "$PNG"

SET="$WORK/AppIcon.iconset"
mkdir -p "$SET"
sips -z 16 16    "$PNG" --out "$SET/icon_16x16.png"      >/dev/null
sips -z 32 32    "$PNG" --out "$SET/icon_16x16@2x.png"   >/dev/null
sips -z 32 32    "$PNG" --out "$SET/icon_32x32.png"      >/dev/null
sips -z 64 64    "$PNG" --out "$SET/icon_32x32@2x.png"   >/dev/null
sips -z 128 128  "$PNG" --out "$SET/icon_128x128.png"    >/dev/null
sips -z 256 256  "$PNG" --out "$SET/icon_128x128@2x.png" >/dev/null
sips -z 256 256  "$PNG" --out "$SET/icon_256x256.png"    >/dev/null
sips -z 512 512  "$PNG" --out "$SET/icon_256x256@2x.png" >/dev/null
sips -z 512 512  "$PNG" --out "$SET/icon_512x512.png"    >/dev/null
cp "$PNG"        "$SET/icon_512x512@2x.png"

mkdir -p Resources
iconutil -c icns "$SET" -o Resources/AppIcon.icns
echo "Wrote Resources/AppIcon.icns"

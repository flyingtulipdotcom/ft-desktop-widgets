import AppKit
import FTWidgetCore

/// The menu bar title as an image, so the health factor can be coloured. The drawing handler runs at draw time,
/// so the plain text follows the menu bar's light or dark appearance.
enum TitleImage {
    static func render(_ t: TitleParts, offline: Bool) -> NSImage {
        let font = NSFont.menuBarFont(ofSize: 0)
        let hfColor: NSColor = t.hfLevel == 2 ? NSColor(srgbRed: 0xef / 255, green: 0x44 / 255, blue: 0x44 / 255, alpha: 1)
            : (t.hfLevel == 1 ? NSColor(srgbRed: 0xf5 / 255, green: 0xa5 / 255, blue: 0x24 / 255, alpha: 1) : NSColor.labelColor)

        func attr(_ s: String, _ c: NSColor?) -> NSAttributedString {
            NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: c ?? NSColor.labelColor])
        }
        var pieces: [(String, Bool)] = []   // (text, is HF)
        if offline { pieces = [("FT offline", false)] }
        else {
            pieces.append((t.price, false))
            if let f = t.fees { pieces.append(("  " + f, false)) }
            if let h = t.hf { pieces.append(("  " + h, true)) }
            if let w = t.wallet { pieces.append(("  " + w, false)) }
            if t.stale { pieces.append((" ⚠", false)) }
        }
        let sizes = pieces.map { attr($0.0, nil).size().width }
        let textW = ceil(sizes.reduce(0, +))
        let logoSide: CGFloat = 16, gap: CGFloat = 5
        let width = logoSide + gap + textW + 2
        let height: CGFloat = 20
        let logo = Logo.image
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            if let logo = logo {
                logo.draw(in: NSRect(x: 0, y: (height - logoSide) / 2, width: logoSide, height: logoSide))
            }
            var x = logoSide + gap
            for (i, p) in pieces.enumerated() {
                let a = attr(p.0, p.1 ? hfColor : nil)
                let h = a.size().height
                a.draw(at: NSPoint(x: x, y: (height - h) / 2))
                x += sizes[i]
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}

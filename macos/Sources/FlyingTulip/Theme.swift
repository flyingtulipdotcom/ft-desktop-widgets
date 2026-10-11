import AppKit
import SwiftUI

// The Flying Tulip palette, the same hex values as the Omarchy panel.
enum Theme {
    static let bg = Color(hex: 0x0e0e11)
    static let border = Color(red: 76 / 255, green: 76 / 255, blue: 82 / 255).opacity(0.5)
    static let cardFill = Color(red: 24 / 255, green: 24 / 255, blue: 27 / 255).opacity(0.65)
    static let text = Color(hex: 0xe4e4e7)
    static let sub = Color(hex: 0xa1a1aa)
    static let faint = Color(hex: 0x71717a)
    static let tulip = Color(hex: 0x7559ff)
    static let tulip300 = Color(hex: 0xb7b1ff)
    static let tulip400 = Color(hex: 0x9385ff)
    static let green = Color(hex: 0x0fd727)
    static let red = Color(hex: 0xef4444)
    static let amber = Color(hex: 0xf5a524)
    static let blue = Color(hex: 0x5587f3)
    static let productColors: [Color] = [tulip, tulip400, tulip300, green, blue, red]

    static func delta(_ v: Double) -> Color {
        !v.isFinite || abs(v) < 0.005 ? sub : (v > 0 ? green : red)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }
}

enum Logo {
    /// The Flying Tulip logo from the app bundle (or, when run from the build folder, from the sources).
    static let image: NSImage? = {
        if let u = Bundle.main.url(forResource: "logo", withExtension: "png"), let i = NSImage(contentsOf: u) { return i }
        return nil
    }()
}

import AppKit
import SimpleVectorCore
import SwiftUI

/// The dark palette of the Simple family (SimpleAudio, SimplePJ, SimpleVectorizer, SimpleSKP).
enum Theme {
    static let background = NSColor(hex: 0x111317)
    static let panel = NSColor(hex: 0x16191E)
    static let lane = NSColor(hex: 0x181B21)
    static let laneAlt = NSColor(hex: 0x1B1F26)
    static let laneSelected = NSColor(hex: 0x1F2530)
    static let header = NSColor(hex: 0x14171C)
    static let separator = NSColor(hex: 0x0B0C0F)
    static let gridMinor = NSColor(white: 1, alpha: 0.035)
    static let gridMajor = NSColor(white: 1, alpha: 0.085)
    static let text = NSColor(hex: 0xE6E8EC)
    static let textDim = NSColor(hex: 0x8A919E)
    static let textFaint = NSColor(hex: 0x565D6A)
    static let accent = NSColor(hex: 0xFFB454)
    static let alive = NSColor(hex: 0x9ECE6A)
    static let standby = NSColor(hex: 0x7AA2F7)
    static let tcp = NSColor(hex: 0x5CE1E6)
    static let osc = NSColor(hex: 0xC792EA)
    static let warning = NSColor(hex: 0xF2D96B)
    static let danger = NSColor(hex: 0xFF5C57)
    static let selection = NSColor.white

    static func elementTint(_ el: VectorElement) -> NSColor {
        switch el.kind {
        case .text(let t):
            return t.isPDFExtracted ? (el.hasModifiedPDFText ? alive : tcp) : standby
        case .signature:
            return accent
        case .path:
            return osc
        case .shape:
            return alive
        case .stamp:
            return warning
        }
    }

    static func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: size, weight: weight)
    }

    static func mono(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        .monospacedDigitSystemFont(ofSize: size, weight: weight)
    }
}

extension NSColor {
    convenience init(hex: Int, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat(hex >> 16 & 0xff) / 255,
            green: CGFloat(hex >> 8 & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha
        )
    }

    var swiftUI: Color { Color(nsColor: self) }
}

enum Format {
    static func count(_ n: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(n) " + (n > 1 ? (plural ?? singular + "s") : singular)
    }

    static func percent(_ scale: CGFloat) -> String {
        "\(Int(round(scale * 100))) %"
    }
}

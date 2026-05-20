import Foundation
import AppKit

/// SF-Symbols-style copy helpers used by the sidebar context menu and the
/// icon detail header.
enum CopyAction {
    /// The actual Unicode character — pastable into a Figma text layer
    /// after the user has set its font to "SF Custom".
    static func symbol(_ icon: Icon) {
        guard let scalar = Unicode.Scalar(icon.codepoint) else { return }
        write(String(Character(scalar)))
    }

    /// The SF Symbol-style name (e.g. "satellite.fill").
    static func name(_ icon: Icon) {
        write(icon.name)
    }

    /// The Private Use Area codepoint as "U+XXXX".
    static func codepoint(_ icon: Icon) {
        write(String(format: "U+%04X", icon.codepoint))
    }

    /// The raw source SVG markup.
    static func svg(_ icon: Icon) {
        write(icon.sourceSVG)
    }

    private static func write(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}

extension Icon {
    /// The single-character form of the icon's codepoint (or empty string
    /// if the codepoint is invalid, which shouldn't happen for PUA values).
    var symbolCharacter: String {
        guard let scalar = Unicode.Scalar(codepoint) else { return "" }
        return String(Character(scalar))
    }

    /// "U+XXXX" string for display.
    var codepointString: String {
        String(format: "U+%04X", codepoint)
    }
}

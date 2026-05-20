import Foundation

/// One icon in the user's library.
///
/// We store the *source* SVG verbatim — every weight/scale variant is
/// regenerated from it on demand by `StrokeSnooper` (WKWebView). This keeps
/// the data model tiny and lets us recompute variants any time we tweak the
/// scaling curve.
struct Icon: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var sourceSVG: String
    var createdAt: Date
    var updatedAt: Date

    /// Optional Unicode codepoint for font compilation. Defaults to the
    /// Private Use Area starting at U+E000 and is assigned by the library.
    var codepoint: UInt32

    /// Identity of the source Figma node, if this icon was sent from the
    /// plugin. Used to auto-update the icon when the same node is
    /// re-sent — no duplicates, no manual "replace" step.
    var figmaNodeID: String?

    init(
        id: UUID = UUID(),
        name: String,
        sourceSVG: String,
        codepoint: UInt32,
        figmaNodeID: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.sourceSVG = sourceSVG
        self.codepoint = codepoint
        self.figmaNodeID = figmaNodeID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

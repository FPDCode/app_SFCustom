import XCTest
@testable import SFCustomEngine

/// Harder icons: many corners, overlaps at heavy weights, unsupported features.
final class ComplexIconTests: XCTestCase {

    static let head = ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#000" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">"##

    static var gear: String {
        var pts: [String] = []
        for i in 0..<8 {
            for (a, r) in [(-0.20, 6.2), (-0.10, 9.0), (0.10, 9.0), (0.20, 6.2)] {
                let t = (Double(i) + a) * 2 * Double.pi / 8
                pts.append(String(format: "%.3f %.3f", 12 + r * sin(t), 12 - r * cos(t)))
            }
        }
        return head + "<path d=\"M" + pts.joined(separator: " L") + " Z\"/><circle cx=\"12\" cy=\"12\" r=\"2.6\"/></svg>"
    }

    static var star: String {
        var pts: [String] = []
        for i in 0..<10 {
            let r = i % 2 == 0 ? 10.0 : 4.2
            let t = Double(i) * Double.pi / 5
            pts.append(String(format: "%.3f %.3f", 12 + r * sin(t), 12.5 - r * cos(t)))
        }
        return head.replacingOccurrences(of: "stroke-linejoin=\"round\"", with: "stroke-linejoin=\"miter\"")
            + "<path d=\"M" + pts.joined(separator: " L") + " Z\"/></svg>"
    }

    static let importOutline = head + """
    <path d="M8.5 6H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-2.5"/>
    <path d="M10 2v10"/><path d="M7 9.5l3 3 3-3"/>
    <path d="M8 18v1.5a2 2 0 0 0 2 2h8.5a2 2 0 0 0 2-2V11a2 2 0 0 0-2-2H16"/></svg>
    """

    /// Regression: at Black, the loops at concave corners flip a contour's
    /// signed area. That used to be read as "runs the other way" and the
    /// contour was reversed — scrambling every weight above Regular.
    func testHeavyWeightsAreNotMisreadAsReversed() throws {
        for (name, svg) in [("gear", Self.gear), ("star", Self.star), ("import", Self.importOutline)] {
            let t = try SymbolTemplateBuilder.build(sourceSVG: svg, options: .init(name: name))
            XCTAssertEqual(t.compatibility.status, .ok, name)
            XCTAssertFalse(t.warnings.contains { $0.contains("Auto-fixed") }, "\(name): \(t.warnings)")
            // The full (geometric) check must agree, also on the written file.
            let full = CompatibilityChecker.check(anchors: t.anchors.map { ($0.weight, $0.path) })
            XCTAssertEqual(full.status, .ok, "\(name): \(full.issues)")
            XCTAssertEqual(CompatibilityChecker.check(templateSVG: t.svg).status, .ok, name)
        }
    }

    /// In-between weights must move every point smoothly: a point at
    /// Bold lies between its Regular and Black positions, and the blended
    /// outline still covers the source centreline.
    func testInBetweenWeightsStaySane() throws {
        for (name, svg) in [("gear", Self.gear), ("star", Self.star)] {
            let t = try SymbolTemplateBuilder.build(sourceSVG: svg, options: .init(name: name))
            let reg = t.anchor(.regular).path, black = t.anchor(.black).path
            let bold = try XCTUnwrap(t.interpolated(at: 1.6)?.path)
            // Corresponding points shouldn't travel far: well under half the symbol.
            var maxTravel = 0.0
            for (a, b) in zip(reg.subpaths, black.subpaths) {
                for (x, y) in zip(a.segments, b.segments) { maxTravel = max(maxTravel, x.p0.distance(to: y.p0)) }
            }
            XCTAssertLessThan(maxTravel, SymbolTemplateBuilder.capHeight * 0.25, "\(name): points jump between weights")
            let rb = reg.tightBounds, kb = black.tightBounds, bb = bold.tightBounds
            XCTAssertGreaterThan(bb.height, rb.height - 0.01, name)
            XCTAssertLessThan(bb.height, kb.height + 0.01, name)
        }
    }

    func testUnsupportedFeaturesAreReported() throws {
        let dashed = Self.head + ##"<circle cx="12" cy="12" r="9" stroke-dasharray="3 3.3"/></svg>"##
        let t1 = try SymbolTemplateBuilder.build(sourceSVG: dashed, options: .init(name: "dashed"))
        XCTAssertTrue(t1.warnings.contains { $0.contains("dashed strokes") }, "\(t1.warnings)")

        let masked = ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><defs><mask id="m"><rect width="24" height="24" fill="#fff"/></mask></defs><rect x="4" y="6" width="12" height="12" rx="2" mask="url(#m)"/></svg>"##
        let t2 = try SymbolTemplateBuilder.build(sourceSVG: masked, options: .init(name: "masked"))
        XCTAssertTrue(t2.warnings.contains { $0.contains("mask") }, "\(t2.warnings)")

        let plain = try SymbolTemplateBuilder.build(sourceSVG: Self.importOutline, options: .init(name: "plain"))
        XCTAssertTrue(plain.warnings.isEmpty, "\(plain.warnings)")
    }
}

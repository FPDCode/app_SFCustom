import XCTest
@testable import SFCustomEngine

/// Stroked heart in a 24-unit grid, like most icon sets.
let heartSVG = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.05 3 5.5l7 7Z"/></svg>
"""

/// Mixed: open strokes + a filled circle.
let bellSVG = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#000" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"/><path d="M10.3 21a1.94 1.94 0 0 0 3.4 0"/><circle cx="18" cy="5" r="2.5" fill="#000" stroke="none"/></svg>
"""

/// Filled ring drawn with even-odd (hole wound the same way as the outside).
let ringSVG = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill-rule="evenodd" d="M12 2a10 10 0 1 1 0 20 10 10 0 0 1 0-20Zm0 5a5 5 0 1 1 0 10 5 5 0 0 1 0-10Z"/></svg>
"""

final class SymbolTemplateTests: XCTestCase {

    func testHeartBuildsCompatibleAnchorsWithTalkLadder() throws {
        let t = try SymbolTemplateBuilder.build(sourceSVG: heartSVG, options: .init(name: "heart"))
        XCTAssertEqual(t.compatibility.status, .ok, "\(t.compatibility.issues)")
        XCTAssertTrue(t.hasStrokes)
        let widths = t.anchors.compactMap(\.strokeWidth)
        XCTAssertEqual(widths.count, 3)
        XCTAssertEqual(widths[0], 2, accuracy: 0.01)
        XCTAssertEqual(widths[1], 7, accuracy: 0.01)
        XCTAssertEqual(widths[2], 13, accuracy: 0.01)
        // Regular sits exactly between baseline and cap line.
        let rb = t.anchor(.regular).contentBounds
        XCTAssertEqual(rb.height, SymbolTemplateBuilder.capHeight, accuracy: 0.01)
        XCTAssertEqual(rb.maxY, 0, accuracy: 0.01)
        // Black grows evenly around the same centre line.
        let bb = t.anchor(.black).contentBounds
        XCTAssertEqual((bb.minY + bb.maxY) / 2, (rb.minY + rb.maxY) / 2, accuracy: 0.05)
    }

    func testMixedFillsAndStrokesStayCompatible() throws {
        let t = try SymbolTemplateBuilder.build(sourceSVG: bellSVG, options: .init(name: "bell"))
        XCTAssertEqual(t.compatibility.status, .ok, "\(t.compatibility.issues)")
        let sigs = t.anchors.map { $0.path.signature() }
        XCTAssertEqual(sigs[0], sigs[1])
        XCTAssertEqual(sigs[2], sigs[1])
    }

    func testNoStrokesWarnsAndScaleOnlyIsIdentical() throws {
        let weights = try SymbolTemplateBuilder.build(sourceSVG: ringSVG, options: .init(name: "ring"))
        XCTAssertFalse(weights.hasStrokes)
        XCTAssertTrue(weights.warnings.contains { $0.contains("no strokes") })

        let scaleOnly = try SymbolTemplateBuilder.build(sourceSVG: heartSVG, options: .init(name: "heart", mode: .scaleOnly))
        XCTAssertEqual(scaleOnly.anchor(.ultralight).path.subpaths.count, scaleOnly.anchor(.black).path.subpaths.count)
        XCTAssertEqual(scaleOnly.anchor(.ultralight).strokeWidth ?? 0, 7, accuracy: 0.01)
        XCTAssertEqual(scaleOnly.anchor(.black).strokeWidth ?? 0, 7, accuracy: 0.01)
    }

    func testEvenOddHoleStaysEmptyUnderNonZero() throws {
        let t = try SymbolTemplateBuilder.build(sourceSVG: ringSVG, options: .init(name: "ring"))
        let p = t.anchor(.regular).path
        let b = p.tightBounds
        XCTAssertEqual(Coverage.winding(b.center, in: p), 0, "hole must be empty")
        let ring = Point(b.minX + b.width * 0.12, b.center.y)
        XCTAssertNotEqual(Coverage.winding(ring, in: p), 0, "ring must be filled")
    }

    func testMarginsArePlacedAndCustomisable() throws {
        var o = SymbolBuildOptions(name: "heart")
        o.margins[.black] = AnchorMargins(left: 4, right: 12)
        let t = try SymbolTemplateBuilder.build(sourceSVG: heartSVG, options: o)
        let reg = t.anchor(.regular), black = t.anchor(.black)
        XCTAssertEqual(reg.contentBounds.minX, AnchorMargins.standard.left, accuracy: 1e-6)
        XCTAssertEqual(black.contentBounds.minX, 4, accuracy: 1e-6)
        XCTAssertEqual(black.slotWidth, 4 + black.contentBounds.width + 12, accuracy: 1e-6)
    }

    func testCustomLadderWithoutNormalisation() throws {
        let o = SymbolBuildOptions(name: "heart", ladder: StrokeLadder(ultralight: 1, regular: 2, black: 4),
                                   normalizeRegularStroke: false)
        let t = try SymbolTemplateBuilder.build(sourceSVG: heartSVG, options: o)
        let w = t.anchors.compactMap(\.strokeWidth)
        XCTAssertEqual(w[0] / w[1], 0.5, accuracy: 1e-6)
        XCTAssertEqual(w[2] / w[1], 2, accuracy: 1e-6)
    }

    func testInterpolationHitsAnchorsAndGoesBetween() throws {
        let t = try SymbolTemplateBuilder.build(sourceSVG: heartSVG, options: .init(name: "heart"))
        XCTAssertEqual(t.interpolated(at: 1)?.path, t.anchor(.regular).path)
        XCTAssertEqual(t.interpolated(at: 0)?.path, t.anchor(.ultralight).path)
        let medium = try XCTUnwrap(t.interpolated(at: 1.2)?.path)
        let wReg = t.anchor(.regular).contentBounds.width, wBlack = t.anchor(.black).contentBounds.width
        XCTAssertGreaterThan(medium.tightBounds.width, wReg)
        XCTAssertLessThan(medium.tightBounds.width, wBlack)
        XCTAssertNotNil(SymbolPreviewRenderer.interpolatedPreview(at: 1.6, in: t))
        XCTAssertTrue(SymbolPreviewRenderer.onionSkin(t).svg.contains("<circle"))
    }

    func testWrittenTemplateRoundTripsThroughChecker() throws {
        let t = try SymbolTemplateBuilder.build(sourceSVG: bellSVG, options: .init(name: "bell"))
        let svg = t.svg
        for id in ["Ultralight-S", "Regular-S", "Black-S", "left-margin-Regular-S", "Template v.7.0"] {
            XCTAssertTrue(svg.contains(id), id)
        }
        XCTAssertEqual(CompatibilityChecker.check(templateSVG: svg).status, .ok)
    }

    func testSymbolsetAndFontSpec() throws {
        let t = try SymbolTemplateBuilder.build(sourceSVG: heartSVG, options: .init(name: "heart.fill"))
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sfc-\(UUID().uuidString)/Assets.xcassets", isDirectory: true)
        let folder = try SymbolsetExporter.write(templateSVG: t.svg, name: "heart.fill", to: dir)
        XCTAssertEqual(folder.lastPathComponent, "heart.fill.symbolset")
        let contents = try String(contentsOf: folder.appendingPathComponent("Contents.json"), encoding: .utf8)
        XCTAssertTrue(contents.contains("\"filename\" : \"heart.fill.svg\""))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Contents.json").path))
        XCTAssertEqual(SymbolsetExporter.assetName("my icon/2"), "my-icon-2")

        let spec = FontSpec.icon(name: "heart", codepoint: 0xE000, template: t)
        let masters = try XCTUnwrap(spec["masters"] as? [String: Any])
        XCTAssertEqual(Set(masters.keys), ["ultralight", "regular", "black"])
        XCTAssertEqual(spec["compatible"] as? Bool, true)
        XCTAssertTrue(HandoffSnippet.swiftUI(name: "heart.fill").contains("Image(\"heart.fill\")"))
    }
}

/// Each pitfall from the talk, injected into Apple's own templates.
final class CompatibilityCheckerTests: XCTestCase {

    func anchors(_ file: String) throws -> [AnchorWeight: PathModel] {
        let svg = try String(contentsOf: Fixtures.appleSamplesDir.appendingPathComponent(file), encoding: .utf8)
        var out: [AnchorWeight: PathModel] = [:]
        for w in AnchorWeight.allCases {
            out[w] = SVGShapeReader.path(svg, insideElementWithID: "\(w.templateID)-S")
        }
        return out
    }

    func list(_ d: [AnchorWeight: PathModel]) -> [(AnchorWeight, PathModel)] {
        AnchorWeight.allCases.map { ($0, d[$0]!) }
    }

    func assertFix(_ broken: [AnchorWeight: PathModel], kind: CompatibilityIssue.Kind,
                   file: StaticString = #filePath, line: UInt = #line) {
        let report = CompatibilityChecker.check(anchors: list(broken))
        XCTAssertEqual(report.status, .fixable, "\(report.issues)", file: file, line: line)
        XCTAssertTrue(report.issues.contains { $0.kind == kind }, "\(report.issues)", file: file, line: line)
        let fixed = CompatibilityFixer.fix(anchors: list(broken))
        let after = CompatibilityChecker.check(anchors: AnchorWeight.allCases.map { ($0, fixed[$0]!) })
        XCTAssertEqual(after.status, .ok, "\(after.issues)", file: file, line: line)
    }

    func testDifferentStartingPointIsDetectedAndFixed() throws {
        var a = try anchors("calendar.svg")
        var black = a[.black]!
        black.subpaths[0] = black.subpaths[0].rotated(by: 7)
        a[.black] = black
        assertFix(a, kind: .startPoint)
    }

    func testSwitchedPartOrderIsDetectedAndFixed() throws {
        var a = try anchors("chevron.down.2.svg")
        a[.ultralight]!.subpaths.swapAt(0, 1)
        assertFix(a, kind: .order)
    }

    func testReversedDirectionIsDetectedAndFixed() throws {
        var a = try anchors("chevron.down.2.svg")
        a[.black]!.subpaths[1] = a[.black]!.subpaths[1].reversed()
        assertFix(a, kind: .direction)
    }

    func testFewerPointsInBlackIsBroken() throws {
        var a = try anchors("calendar.svg")
        var sp = a[.black]!.subpaths[0]
        let merged = Segment.line(sp.segments[3].p0, sp.segments[4].p3)
        sp.segments.replaceSubrange(3...4, with: [merged])
        a[.black]!.subpaths[0] = sp
        let report = CompatibilityChecker.check(anchors: list(a))
        XCTAssertEqual(report.status, .broken)
        XCTAssertTrue(report.issues.contains { $0.kind == .pointCount && $0.message.contains("fewer points") })
    }

    func testMissingPartIsBroken() throws {
        var a = try anchors("chevron.down.2.svg")
        a[.ultralight]!.subpaths.removeLast()
        let report = CompatibilityChecker.check(anchors: list(a))
        XCTAssertEqual(report.status, .broken)
        XCTAssertTrue(report.issues.contains { $0.kind == .partCount })
    }

    func testLineVersusCurveInTemplateFileIsFixable() throws {
        // Same geometry, but Regular uses L where the others use C.
        func group(_ id: String, _ d: String) -> String { "<g id=\"\(id)\" transform=\"matrix(1 0 0 1 100 696)\"><path d=\"\(d)\"/></g>" }
        let curve = "M0 0C3.33 0 6.67 0 10 0C10 -3.33 10 -6.67 10 -10C6.67 -10 3.33 -10 0 -10Z"
        let line = "M0 0L10 0C10 -3.33 10 -6.67 10 -10C6.67 -10 3.33 -10 0 -10Z"
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\"><g id=\"Symbols\">"
            + group("Ultralight-S", curve) + group("Regular-S", line) + group("Black-S", curve) + "</g></svg>"
        let report = CompatibilityChecker.check(templateSVG: svg)
        XCTAssertEqual(report.status, .fixable, "\(report.issues)")
        XCTAssertTrue(report.issues.contains { $0.kind == .commandMismatch })
        let fixed = try XCTUnwrap(CompatibilityFixer.fix(templateSVG: svg))
        XCTAssertEqual(CompatibilityChecker.check(templateSVG: fixed).status, .ok)
    }

    func testFixingATemplateFileRewritesOnlyAnchorGroups() throws {
        let t = try SymbolTemplateBuilder.build(sourceSVG: heartSVG, options: .init(name: "heart"))
        var svg = t.svg
        // Break the Black anchor's start point inside the file.
        var black = t.anchor(.black).path
        black.subpaths[0] = black.subpaths[0].rotated(by: 5)
        let range = try XCTUnwrap(TemplateAnchors.groupRange(id: "Black-S", in: svg))
        svg.replaceSubrange(range, with: "<g id=\"Black-S\"><path d=\"\(SVGPathWriter.write(black))\"/></g>")
        XCTAssertEqual(CompatibilityChecker.check(templateSVG: svg).status, .fixable)
        let fixed = try XCTUnwrap(CompatibilityFixer.fix(templateSVG: svg))
        XCTAssertEqual(CompatibilityChecker.check(templateSVG: fixed).status, .ok)
        XCTAssertTrue(fixed.contains("id=\"Guides\""))
        XCTAssertNil(CompatibilityFixer.fix(templateSVG: fixed), "nothing left to fix")
    }
}

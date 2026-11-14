import XCTest
@testable import SFCustomEngine

final class SVGPathParserTests: XCTestCase {

    func testAllCommandsBecomeCubics() throws {
        let p = try SVGPathParser.parse("M0 0 L10 0 H20 V10 C20 20 10 20 10 10 S0 0 0 10 Q5 15 10 10 T20 10 A5 5 0 0 1 30 10 Z")
        XCTAssertEqual(p.subpaths.count, 1)
        XCTAssertTrue(p.subpaths[0].isClosed)
        // L H V C S Q T + arc (180° → 2 pieces) + closing line
        XCTAssertEqual(p.subpaths[0].segments.count, 10)
    }

    func testRelativeAndImplicitCommands() throws {
        // m with implicit l, compact numbers, exponent
        let p = try SVGPathParser.parse("m10,10 5,0 0,5-5,0z m1e1 0 l.5.5")
        XCTAssertEqual(p.subpaths.count, 2)
        XCTAssertEqual(p.subpaths[0].segments.count, 4)
        XCTAssertEqual(p.subpaths[0].segments[0].p3, Point(15, 10))
        // After z the pen returns to (10,10); m10 0 → (20,10)
        XCTAssertEqual(p.subpaths[1].start, Point(20, 10))
        XCTAssertEqual(p.subpaths[1].end, Point(20.5, 10.5))
    }

    func testArcFlagsWithoutSeparators() throws {
        let p = try SVGPathParser.parse("M0 0a10 10 0 1110 10")
        XCTAssertEqual(p.subpaths.first?.end, Point(10, 10))
        XCTAssertGreaterThanOrEqual(p.subpaths[0].segments.count, 3) // large arc, ~270°
    }

    func testArcEndpointsAreExact() throws {
        let p = try SVGPathParser.parse("M45 50 A5 5 0 1 1 55 50")
        let s = try XCTUnwrap(p.subpaths.first)
        XCTAssertEqual(s.start, Point(45, 50))
        XCTAssertEqual(s.end, Point(55, 50))
        XCTAssertEqual(s.segments.count, 2) // 180° → two 90° pieces
    }

    func testZeroLengthSegmentsAreDropped() throws {
        let p = try SVGPathParser.parse("M0 0 L0 0 L10 0 L10 0 Z")
        XCTAssertEqual(p.subpaths[0].segments.count, 2) // L10 0 + closing line
    }

    func testInvalidDataThrows() {
        XCTAssertThrowsError(try SVGPathParser.parse("10 10 L 5 5"))
        XCTAssertThrowsError(try SVGPathParser.parse("M0 0 L 5"))
    }

    func testWriterRoundTripKeepsSignature() throws {
        for src in Fixtures.strokedSources {
            let p = try SVGPathParser.parse(src.d)
            let again = try SVGPathParser.parse(SVGPathWriter.write(p, precision: 6))
            XCTAssertEqual(p.signature(), again.signature(), src.name)
        }
    }

    func testTransformParsing() {
        let t = AffineTransform2D.parse("translate(10 20) scale(2) rotate(90)")
        let p = t.apply(Point(1, 0))
        XCTAssertEqual(p.x, 10, accuracy: 1e-9)
        XCTAssertEqual(p.y, 22, accuracy: 1e-9)
    }

    func testShapeReaderFlattensTransformsAndStyles() {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
          <defs><path id="hidden" d="M0 0 L100 100"/></defs>
          <g transform="translate(10 0)" style="stroke:#000; stroke-width:2; fill:none">
            <line x1="0" y1="0" x2="10" y2="0" stroke-linecap="round"/>
            <circle cx="50" cy="50" r="10" transform="scale(2)"/>
          </g>
          <rect x="0" y="0" width="10" height="10" rx="2"/>
          <text>nope</text>
        </svg>
        """
        let r = SVGShapeReader.read(svg)
        XCTAssertEqual(r.shapes.count, 3)
        XCTAssertEqual(r.unsupportedElements, ["text"])
        let line = r.shapes[0]
        XCTAssertFalse(line.isFilled)
        XCTAssertEqual(line.stroke?.cap, .round)
        XCTAssertEqual(line.path.subpaths[0].start, Point(10, 0))
        XCTAssertEqual(r.shapes[1].stroke?.width ?? 0, 4, accuracy: 1e-9) // scaled by transform
        XCTAssertTrue(r.shapes[2].isFilled)
        XCTAssertNil(r.shapes[2].stroke)
        XCTAssertEqual(r.shapes[2].path.subpaths[0].segments.count, 8) // 4 sides + 4 corners
    }

    /// Apple's own templates must pass our structural fingerprint: the three
    /// anchors of every official sample have identical signatures.
    func testAppleSampleAnchorsHaveEqualSignatures() throws {
        let samples = try Fixtures.appleSamples()
        XCTAssertFalse(samples.isEmpty, "No Apple samples found at \(Fixtures.appleSamplesDir.path)")
        for (name, svg) in samples {
            let ul = SVGShapeReader.path(svg, insideElementWithID: "Ultralight-S")
            let rg = SVGShapeReader.path(svg, insideElementWithID: "Regular-S")
            let bl = SVGShapeReader.path(svg, insideElementWithID: "Black-S")
            XCTAssertFalse(rg.isEmpty, "\(name): Regular-S empty")
            XCTAssertEqual(ul.signature(), rg.signature(), "\(name): Ultralight vs Regular")
            XCTAssertEqual(bl.signature(), rg.signature(), "\(name): Black vs Regular")
        }
    }
}

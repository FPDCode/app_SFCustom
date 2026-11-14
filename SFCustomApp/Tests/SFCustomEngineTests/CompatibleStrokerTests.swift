import XCTest
@testable import SFCustomEngine

final class CompatibleStrokerTests: XCTestCase {

    /// The core promise: structure is independent of stroke width.
    func testSignatureIsIdenticalAcrossWidths() throws {
        for src in Fixtures.strokedSources {
            let path = try SVGPathParser.parse(src.d)
            var reference: [[Character]]?
            for w in Fixtures.widths {
                var style = src.style
                style.width = w
                let out = CompatibleStroker.outline(path, style: style)
                XCTAssertFalse(out.isEmpty, "\(src.name) @\(w)")
                XCTAssertTrue(out.subpaths.allSatisfy(\.isClosed), "\(src.name) @\(w) has open contours")
                if let ref = reference {
                    XCTAssertEqual(out.signature(), ref, "\(src.name): signature changed at width \(w)")
                } else {
                    reference = out.signature()
                }
            }
        }
    }

    func testContoursAreContiguous() throws {
        for src in Fixtures.strokedSources {
            let out = CompatibleStroker.outline(try SVGPathParser.parse(src.d), style: src.style)
            for sp in out.subpaths {
                for i in 1..<sp.segments.count {
                    XCTAssertLessThan(sp.segments[i - 1].p3.distance(to: sp.segments[i].p0), 1e-9, src.name)
                }
                XCTAssertLessThan(sp.segments.last!.p3.distance(to: sp.segments.first!.p0), 1e-9, src.name)
            }
        }
    }

    func testClosedSourceYieldsOuterAndInnerContours() throws {
        let p = try SVGPathParser.parse("M10 10 H90 V90 H10 Z")
        let out = CompatibleStroker.outline(p, style: StrokeStyle(width: 7))
        XCTAssertEqual(out.subpaths.count, 2)
        // Opposite winding keeps the hole empty under non-zero.
        XCTAssertLessThan(out.subpaths[0].signedArea * out.subpaths[1].signedArea, 0)
        XCTAssertEqual(Coverage.winding(Point(50, 50), in: out), 0, "hole must stay empty")
        XCTAssertNotEqual(Coverage.winding(Point(10, 50), in: out), 0, "stroke must be filled")
    }

    /// Geometric sanity: the outline covers the centerline and the stroke
    /// body, and nothing far outside it.
    func testOutlineCoversStrokeArea() throws {
        for src in Fixtures.strokedSources {
            let path = try SVGPathParser.parse(src.d)
            for w in [2.0, 7, 13] {
                var style = src.style
                style.width = w
                let out = CompatibleStroker.outline(path, style: style)
                let d = w / 2
                for sp in path.subpaths {
                    for seg in sp.segments {
                        for t in stride(from: 0.2, through: 0.8, by: 0.3) {
                            let c = seg.point(at: t)
                            guard let n = seg.tangent(at: t)?.perpendicular else { continue }
                            for q in [c, c + n * (0.8 * d), c - n * (0.8 * d)] {
                                XCTAssertNotEqual(Coverage.winding(q, in: out), 0,
                                                  "\(src.name) @\(w): point \(q) inside stroke not covered")
                            }
                            // Points truly outside the stroke body must stay empty.
                            // Skip shapes with miters / square caps: their extensions
                            // legitimately reach beyond `d` from the centerline.
                            if style.join == .miter || style.cap == .square { continue }
                            for q in [c + n * (1.5 * d), c - n * (1.5 * d)]
                            where Coverage.distanceToCenterline(q, path) > 1.4 * d {
                                XCTAssertEqual(Coverage.winding(q, in: out), 0,
                                               "\(src.name) @\(w): point \(q) outside stroke is filled")
                            }
                        }
                    }
                }
            }
        }
    }

    /// Black-weight inner corners must not lose points (talk pitfall #2).
    func testTightCurveKeepsPointsAtBlack() throws {
        let p = try SVGPathParser.parse("M45 50 A5 5 0 1 1 55 50 A5 5 0 1 1 45 50 Z")
        let thin = CompatibleStroker.outline(p, style: StrokeStyle(width: 2))
        let black = CompatibleStroker.outline(p, style: StrokeStyle(width: 13)) // > radius*2
        XCTAssertEqual(thin.signature(), black.signature())
    }

    func testSymbolOutlinerMergesFillsAndStrokes() {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg">
          <circle cx="50" cy="50" r="20" fill="none" stroke="black" stroke-width="7"/>
          <rect x="45" y="45" width="10" height="10"/>
          <path d="M10 10 L30 30" stroke="black" stroke-width="7" stroke-linecap="round" fill="none"/>
        </svg>
        """
        let shapes = SVGShapeReader.read(svg).shapes
        let ul = SymbolOutliner.outline(shapes, strokeScale: 2.0 / 7.0)
        let rg = SymbolOutliner.outline(shapes, strokeScale: 1)
        let bl = SymbolOutliner.outline(shapes, strokeScale: 13.0 / 7.0)
        XCTAssertEqual(ul.signature(), rg.signature())
        XCTAssertEqual(bl.signature(), rg.signature())
        // circle → 2 contours, rect → 1, open line → 1
        XCTAssertEqual(rg.subpaths.count, 4)
    }
}

import Foundation

public struct CompatibilityIssue: Hashable, Sendable, Identifiable {
    public enum Kind: String, Sendable, Hashable {
        case missingAnchor, partCount, pointCount, commandMismatch, startPoint, order, direction
    }

    public var kind: Kind
    public var weight: AnchorWeight
    /// 1-based part number in the Regular anchor, when it applies.
    public var part: Int?
    public var message: String
    public var isAutoFixable: Bool

    public var id: String { "\(kind.rawValue)-\(weight.rawValue)-\(part ?? 0)" }
}

public struct CompatibilityReport: Hashable, Sendable {
    public enum Status: String, Sendable, Hashable {
        /// Interpolates cleanly.
        case ok
        /// Has problems that `CompatibilityFixer` can repair.
        case fixable
        /// Has problems that need a designer (different point counts…).
        case broken
    }

    public var issues: [CompatibilityIssue]

    public var status: Status {
        if issues.isEmpty { return .ok }
        return issues.allSatisfy(\.isAutoFixable) ? .fixable : .broken
    }

    public var summary: String {
        switch status {
        case .ok:      return "Interpolates cleanly"
        case .fixable: return "Auto-fixable (\(issues.count))"
        case .broken:  return "Won’t interpolate (\(issues.filter { !$0.isAutoFixable }.count))"
        }
    }
}

/// Checks that Ultralight / Regular / Black can be interpolated, covering
/// every pitfall from the "Custom SF Symbols; fun, but not easy!" talk:
///
/// | Check | Pitfall | Auto-fix |
/// |---|---|---|
/// | same number of parts | different point counts | — |
/// | same points per part | Black loses inner corners | — |
/// | same command letters | handles count as points | rewrite as curves |
/// | same start point | different starting point | rotate start |
/// | same part order | wrong / switched path order | reorder |
/// | same direction | (related) | reverse |
public enum CompatibilityChecker {

    /// - Parameter structuralOnly: only compare part and point counts.
    ///   Used for anchors the engine built itself: their order, direction
    ///   and start points are right by construction, and the geometric
    ///   guesses below can misread heavy weights (overlapping loops look
    ///   like a reversed or shifted path).
    public static func check(anchors: [(AnchorWeight, PathModel)],
                             rawCommands: [AnchorWeight: [[Character]]]? = nil,
                             structuralOnly: Bool = false) -> CompatibilityReport {
        let dict = Dictionary(anchors, uniquingKeysWith: { a, _ in a })
        var issues: [CompatibilityIssue] = []
        for w in AnchorWeight.allCases where dict[w] == nil || dict[w]!.isEmpty {
            issues.append(.init(kind: .missingAnchor, weight: w, part: nil,
                                message: "\(w.displayName) is missing or empty.", isAutoFixable: false))
        }
        guard let reg = dict[.regular], !reg.isEmpty else { return CompatibilityReport(issues: issues) }

        for w in [AnchorWeight.ultralight, .black] {
            guard let other = dict[w], !other.isEmpty else { continue }
            let a = Analysis(reference: reg, other: other, heuristics: !structuralOnly)
            if a.partCountMismatch {
                issues.append(.init(kind: .partCount, weight: w, part: nil,
                                    message: "\(w.displayName) has \(other.subpaths.count) parts, Regular has \(reg.subpaths.count).",
                                    isAutoFixable: false))
                continue
            }
            if a.reordered {
                issues.append(.init(kind: .order, weight: w, part: nil,
                                    message: "Parts are in a different order in \(w.displayName).", isAutoFixable: true))
            }
            for pair in a.pairs {
                let part = pair.ref + 1
                if pair.refCount != pair.otherCount {
                    let word = pair.otherCount < pair.refCount ? "fewer" : "more"
                    issues.append(.init(kind: .pointCount, weight: w, part: part,
                                        message: "\(w.displayName) has \(word) points in part \(part) (\(pair.otherCount) vs \(pair.refCount)).",
                                        isAutoFixable: false))
                    continue
                }
                if pair.reversed {
                    issues.append(.init(kind: .direction, weight: w, part: part,
                                        message: "Part \(part) runs the other way in \(w.displayName).", isAutoFixable: true))
                }
                if pair.rotation != 0 {
                    issues.append(.init(kind: .startPoint, weight: w, part: part,
                                        message: "Part \(part) starts at a different point in \(w.displayName).", isAutoFixable: true))
                }
                if let raw = rawCommands, let rr = raw[.regular], let ro = raw[w],
                   pair.ref < rr.count, pair.other < ro.count,
                   normalizedLetters(rr[pair.ref]) != normalizedLetters(ro[pair.other]) {
                    issues.append(.init(kind: .commandMismatch, weight: w, part: part,
                                        message: "Part \(part) mixes straight lines and curves differently in \(w.displayName).",
                                        isAutoFixable: true))
                }
            }
        }
        return CompatibilityReport(issues: issues)
    }

    /// Check an SF Symbol template file (e.g. one drawn by hand).
    public static func check(templateSVG: String) -> CompatibilityReport {
        let anchors = TemplateAnchors.read(templateSVG)
        return check(anchors: AnchorWeight.allCases.map { ($0, anchors.paths[$0] ?? PathModel()) },
                     rawCommands: anchors.rawCommands)
    }

    /// Collapse command letters to the families that matter for
    /// interpolation (H/V are lines, S is a cubic, T a quadratic).
    static func normalizedLetters(_ s: [Character]) -> [Character] {
        s.map { c in
            switch c.uppercased().first! {
            case "H", "V", "L": return "L"
            case "S", "C": return "C"
            case "T", "Q": return "Q"
            case let u: return u
            }
        }
    }
}

// MARK: - Analysis shared by checker and fixer

/// Matches the parts of `other` to the parts of `reference` and works out,
/// per pair, direction and start-point offset.
struct Analysis {
    struct Pair {
        var ref: Int
        var other: Int
        var refCount: Int
        var otherCount: Int
        var reversed: Bool
        var rotation: Int
    }

    var partCountMismatch = false
    var reordered = false
    var pairs: [Pair] = []

    init(reference: PathModel, other: PathModel, heuristics: Bool = true) {
        guard reference.subpaths.count == other.subpaths.count else {
            partCountMismatch = true
            return
        }
        let rb = reference.tightBounds, ob = other.tightBounds
        let rDesc = reference.subpaths.map { Self.descriptor($0, in: rb) }
        let oDesc = other.subpaths.map { Self.descriptor($0, in: ob) }
        let n = rDesc.count

        func cost(_ i: Int, _ j: Int) -> Double {
            let a = rDesc[i], b = oDesc[j]
            var c = a.centroid.distance(to: b.centroid)
            c += 0.15 * abs(a.logArea - b.logArea)
            if a.segments != b.segments { c += 0.25 }
            return c
        }

        // Greedy assignment, cheapest pairs first.
        var candidates: [(Double, Int, Int)] = []
        for i in 0..<n { for j in 0..<n { candidates.append((cost(i, j), i, j)) } }
        candidates.sort { $0.0 < $1.0 }
        var mapping = Array(repeating: -1, count: n)
        var used = Set<Int>()
        for (_, i, j) in candidates where mapping[i] < 0 && !used.contains(j) {
            mapping[i] = j
            used.insert(j)
        }
        // Only call it "reordered" when identity is clearly worse.
        let identityCost = (0..<n).reduce(0) { $0 + cost($1, $1) }
        let matchedCost = (0..<n).reduce(0) { $0 + cost($1, mapping[$1]) }
        if heuristics, mapping != Array(0..<n), matchedCost < identityCost * 0.7, identityCost - matchedCost > 0.05 {
            reordered = true
        } else {
            mapping = Array(0..<n)
        }

        for i in 0..<n {
            let rs = reference.subpaths[i], os = other.subpaths[mapping[i]]
            var pair = Pair(ref: i, other: mapping[i], refCount: rs.segments.count,
                            otherCount: os.segments.count, reversed: false, rotation: 0)
            if heuristics, pair.refCount == pair.otherCount, rs.segments.count > 1 {
                // Direction and start point are judged by how well the
                // points line up (positions relative to the whole symbol),
                // not by signed area: heavy weights have overlapping loops
                // that can flip the area of a perfectly matching contour.
                let an = Self.normalizedStarts(rs, in: rb)
                let forward = Self.normalizedStarts(os, in: ob)
                let backward = Self.normalizedStarts(os.reversed(), in: ob)
                let closed = rs.isClosed && os.isClosed
                let (fRot, fCost) = Self.bestRotation(an, forward, allowRotation: closed)
                let (bRot, bCost) = Self.bestRotation(an, backward, allowRotation: closed)
                let fBest = fRot.cost
                if bCost.best < fBest * 0.6, fBest - bCost.best > 0.02 {
                    pair.reversed = true
                    pair.rotation = bRot.index
                } else if fRot.index != 0, fBest < fCost.identity * 0.6, fCost.identity - fBest > 0.02 {
                    pair.rotation = fRot.index
                }
            }
            pairs.append(pair)
        }
    }

    struct Descriptor {
        var centroid: Point
        var logArea: Double
        var segments: Int
    }

    static func descriptor(_ sp: Subpath, in bounds: Rect) -> Descriptor {
        let w = max(bounds.width, 1e-9), h = max(bounds.height, 1e-9)
        let c = sp.centroid
        let area = abs(sp.signedArea) / (w * h)
        return Descriptor(centroid: Point((c.x - bounds.minX) / w, (c.y - bounds.minY) / h),
                          logArea: log(max(area, 1e-9)), segments: sp.segments.count)
    }

    /// Start-index shift of `b` that best lines its points up with `a`.
    static func bestRotation(_ an: [Point], _ bn: [Point], allowRotation: Bool)
        -> (rotation: (index: Int, cost: Double), costs: (identity: Double, best: Double)) {
        let n = an.count
        func cost(_ r: Int) -> Double {
            var c = 0.0
            for k in 0..<n { c += an[k].distance(to: bn[(k + r) % n]) }
            return c / Double(n)
        }
        let c0 = cost(0)
        var best = 0, bestCost = c0
        if allowRotation {
            for r in 1..<n {
                let c = cost(r)
                if c < bestCost - 1e-12 { best = r; bestCost = c }
            }
        }
        return ((best, bestCost), (c0, bestCost))
    }

    /// Segment start points, relative to the bounds of the whole anchor.
    static func normalizedStarts(_ sp: Subpath, in b: Rect) -> [Point] {
        let w = max(b.width, 1e-9), h = max(b.height, 1e-9)
        return sp.segments.map { Point(($0.p0.x - b.minX) / w, ($0.p0.y - b.minY) / h) }
    }
}

// MARK: - Fixer

public enum CompatibilityFixer {

    /// Returns fixed Ultralight / Black (Regular is the reference and is
    /// returned unchanged). Unfixable problems are left as they are.
    public static func fix(anchors: [(AnchorWeight, PathModel)]) -> [AnchorWeight: PathModel] {
        let dict = Dictionary(anchors, uniquingKeysWith: { a, _ in a })
        guard let reg = dict[.regular] else { return dict }
        var out = dict
        for w in [AnchorWeight.ultralight, .black] {
            guard let other = dict[w] else { continue }
            let a = Analysis(reference: reg, other: other)
            guard !a.partCountMismatch else { continue }
            var subpaths: [Subpath] = []
            for pair in a.pairs {
                var sp = other.subpaths[pair.other]
                if pair.refCount == pair.otherCount {
                    if pair.reversed { sp = sp.reversed() }
                    if pair.rotation != 0 { sp = sp.rotated(by: pair.rotation) }
                }
                subpaths.append(sp)
            }
            out[w] = PathModel(subpaths: subpaths)
        }
        return out
    }

    /// Fix an SF Symbol template file in place: the anchor groups are
    /// rewritten as single paths of absolute curves (which also resolves
    /// line/curve command mismatches). Returns nil when nothing changed or
    /// the file has no anchor groups.
    public static func fix(templateSVG: String) -> String? {
        let anchors = TemplateAnchors.read(templateSVG)
        guard anchors.paths[.regular] != nil else { return nil }
        let report = CompatibilityChecker.check(templateSVG: templateSVG)
        guard report.status != .ok else { return nil }
        let fixed = fix(anchors: AnchorWeight.allCases.compactMap { w in anchors.paths[w].map { (w, $0) } })
        var svg = templateSVG
        for w in AnchorWeight.allCases {
            guard let p = fixed[w], let range = TemplateAnchors.groupRange(id: "\(w.templateID)-S", in: svg) else { continue }
            let replacement = "<g id=\"\(w.templateID)-S\">\n   <path d=\"\(SVGPathWriter.write(p, precision: 4))\"/>\n  </g>"
            svg.replaceSubrange(range, with: replacement)
        }
        return svg
    }
}

extension Subpath {
    /// Closed subpath starting at segment `k` instead of 0.
    public func rotated(by k: Int) -> Subpath {
        guard isClosed, !segments.isEmpty else { return self }
        let r = ((k % segments.count) + segments.count) % segments.count
        return Subpath(segments: Array(segments[r...] + segments[..<r]), isClosed: true)
    }
}

// MARK: - Reading anchors from a template file

enum TemplateAnchors {
    struct Result {
        var paths: [AnchorWeight: PathModel] = [:]
        var rawCommands: [AnchorWeight: [[Character]]] = [:]
    }

    static func read(_ svg: String) -> Result {
        var r = Result()
        for w in AnchorWeight.allCases {
            let id = "\(w.templateID)-S"
            let p = SVGShapeReader.path(svg, insideElementWithID: id, keepDegenerate: true)
            if !p.isEmpty { r.paths[w] = p }
            if let range = groupRange(id: id, in: svg) {
                r.rawCommands[w] = rawCommandLetters(String(svg[range]))
            }
        }
        return r
    }

    /// Range of `<g id="…"> … </g>` including nested groups.
    static func groupRange(id: String, in svg: String) -> Range<String.Index>? {
        guard let open = svg.range(of: "<g id=\"\(id)\"") ?? svg.range(of: "<g id='\(id)'") else { return nil }
        var depth = 0
        var i = open.lowerBound
        while i < svg.endIndex {
            if svg[i...].hasPrefix("<g") {
                let next = svg.index(i, offsetBy: 2, limitedBy: svg.endIndex) ?? svg.endIndex
                if next == svg.endIndex || " >\n\t/".contains(svg[next]) {
                    // Self-closing <g/>?
                    if let close = svg[i...].firstIndex(of: ">"), svg[svg.index(before: close)] == "/" {
                        i = svg.index(after: close); continue
                    }
                    depth += 1
                }
            } else if svg[i...].hasPrefix("</g>") {
                depth -= 1
                if depth == 0 { return open.lowerBound..<svg.index(i, offsetBy: 4) }
            }
            i = svg.index(after: i)
        }
        return nil
    }

    /// Per-subpath command letters of every `d` attribute in a fragment.
    static func rawCommandLetters(_ fragment: String) -> [[Character]] {
        var out: [[Character]] = []
        let pattern = #"\sd\s*=\s*["']([^"']*)["']"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = fragment as NSString
        for m in re.matches(in: fragment, range: NSRange(location: 0, length: ns.length)) {
            let d = ns.substring(with: m.range(at: 1))
            var current: [Character] = []
            for c in d where c.isLetter && c != "e" && c != "E" {
                if c == "M" || c == "m" {
                    if !current.isEmpty { out.append(current) }
                    current = [c]
                } else {
                    current.append(c)
                }
            }
            if !current.isEmpty { out.append(current) }
        }
        return out
    }
}

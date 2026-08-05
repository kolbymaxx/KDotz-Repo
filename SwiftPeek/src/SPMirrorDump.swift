import Foundation

/// Swift-side labelled tree for milestone 2 string proof.
@objc(SPMirrorDump)
public final class SPMirrorDump: NSObject {

    @objc(treeForObject:maxDepth:maxNodes:)
    public static func treeForObject(_ object: Any, maxDepth: Int, maxNodes: Int) -> [[String: Any]] {
        var out: [[String: Any]] = []
        var count = 0
        let depthLimit = max(0, min(maxDepth, 5))
        let nodeLimit = max(1, min(maxNodes, 256))

        func stringify(_ value: Any) -> String? {
            switch value {
            case let s as String:
                return s.isEmpty ? nil : s
            case let s as NSString:
                return s.length == 0 ? nil : (s as String)
            case let b as Bool:
                return b ? "true" : "false"
            case let i as Int:
                return String(i)
            case let d as Double:
                return String(d)
            default:
                let m = Mirror(reflecting: value)
                if m.children.isEmpty {
                    let s = String(describing: value)
                    if s.count > 0 && s.count < 200 && s != "nil" && !s.hasPrefix("0x") {
                        return s
                    }
                }
                return nil
            }
        }

        func walk(_ any: Any, depth: Int) {
            guard count < nodeLimit, depth <= depthLimit else { return }
            let mirror = Mirror(reflecting: any)
            for child in mirror.children {
                guard count < nodeLimit else { return }
                let name = child.label ?? "$child"
                if let s = stringify(child.value) {
                    count += 1
                    out.append([
                        "name": name,
                        "value": s,
                        "source": "mirror",
                    ])
                }
                if depth < depthLimit {
                    let nested = Mirror(reflecting: child.value)
                    if !nested.children.isEmpty {
                        walk(child.value, depth: depth + 1)
                    }
                }
            }
        }

        walk(object, depth: 0)
        return out
    }

    @objc(titleStringsInObject:maxNodes:)
    public static func titleStringsInObject(_ object: Any, maxNodes: Int) -> [String] {
        let rows = treeForObject(object, maxDepth: 4, maxNodes: maxNodes)
        var titles: [String] = []
        var seen = Set<String>()
        for row in rows {
            guard let s = row["value"] as? String else { continue }
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard t.count >= 2 && t.count <= 80 else { continue }
            if t.hasPrefix("<") && t.hasSuffix(">") { continue }
            if t.hasPrefix("0x") { continue }
            if t == "true" || t == "false" { continue }
            if seen.contains(t) { continue }
            seen.insert(t)
            titles.append(t)
            if titles.count >= 24 { break }
        }
        return titles
    }
}

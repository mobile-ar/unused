import Foundation

struct GraphRenderer {

    func render(_ result: ReferenceGraphResult, options: GraphDisplayOptions = GraphDisplayOptions()) -> String {
        let root = result.root ?? DeclarationReference(
            name: result.target.name,
            parentType: result.target.parentType,
            file: result.target.file,
            line: result.target.line,
            kind: result.target.type.rawValue
        )
        var inbound: [DeclarationReference: [DeclarationReference: [ReferenceEdge]]] = [:]
        var outbound: [DeclarationReference: [DeclarationReference: [ReferenceEdge]]] = [:]
        for edge in Set(result.edges) {
            inbound[edge.target, default: [:]][edge.source, default: []].append(edge)
            outbound[edge.source, default: [:]][edge.target, default: []].append(edge)
        }

        let width = max(1, options.width)
        let warning = options.ascii ? "[!]" : "⚠"
        let check = options.ascii ? "[OK]" : "✓"
        let arrow = options.ascii ? "->" : "→"
        let cyan = "137;220;235"
        let green = "166;227;161"
        let mauve = "203;166;247"
        let yellow = "249;226;175"
        var lines: [String] = []
        func append(_ text: String, color: String? = nil) {
            for line in wrapped(printable(text, ascii: options.ascii), width: width) {
                if options.color, let color {
                    lines.append("\u{1B}[38;2;\(color)m\(line)\u{1B}[0m")
                } else {
                    lines.append(line)
                }
            }
        }

        var header = [
            "SELECTED #\(result.target.id)",
            "\(root.kind) \(root.displayName)",
            "Location: \(location(root.file, line: root.line, column: root.column, directory: options.directory))",
            reportContext(result.target.exclusionReason),
            "Scope: \(counted(result.scannedFileCount, "scanned file")); tests \(result.includesTests ? "included" : "excluded")."
        ]
        if !result.targetFound {
            header.append("\(warning) Selected declaration not found; refresh report.")
        }
        if width >= 5 {
            let rows = header.flatMap { wrapped(printable($0, ascii: options.ascii), width: width - 4) }
            let innerWidth = rows.map(cellWidth).max() ?? 1
            let border = String(repeating: options.ascii ? "-" : "─", count: innerWidth + 2)
            append("\(options.ascii ? "+" : "╭")\(border)\(options.ascii ? "+" : "╮")", color: cyan)
            for row in rows {
                let padding = String(repeating: " ", count: max(0, innerWidth - cellWidth(row)))
                let side = options.ascii ? "|" : "│"
                append("\(side) \(row)\(padding) \(side)", color: cyan)
            }
            append("\(options.ascii ? "+" : "╰")\(border)\(options.ascii ? "+" : "╯")", color: cyan)
        } else {
            for row in header { append(row, color: cyan) }
        }
        append("")

        var hasVisibleAmbiguity = false
        if !options.outboundOnly {
            append("Inbound dependents \(arrow) SELECTED", color: green)
            let rendered = tree(root: root, adjacency: inbound, options: options)
            for line in rendered.lines { append(line) }
            hasVisibleAmbiguity = rendered.hasAmbiguity
            append("")
        }
        if !options.inboundOnly {
            append("SELECTED \(arrow) Outbound dependencies", color: mauve)
            let rendered = tree(root: root, adjacency: outbound, options: options)
            for line in rendered.lines { append(line) }
            hasVisibleAmbiguity = hasVisibleAmbiguity || rendered.hasAmbiguity
            append("")
        }

        append("Summary (all direct project references)", color: cyan)
        let incoming = inbound[root, default: [:]]
        let outgoing = outbound[root, default: [:]]
        for line in summary("Inbound", groups: incoming) { append(line) }
        for line in summary("Outbound", groups: outgoing) { append(line) }
        if !result.targetFound {
            append("\(warning) Selected declaration not found; refresh report before assessing references.", color: yellow)
        } else if incoming.isEmpty {
            if scanIsIncomplete(result.warnings) {
                append("Assessment: \(warning) No incoming references found in scanned sources; scan incomplete.", color: yellow)
            } else {
                append("Assessment: \(check) No incoming project references found; verify runtime/external uses.", color: green)
            }
        } else {
            append("Assessment: \(warning) Project references found; inspect before removing.", color: yellow)
            let edges = incoming.values.flatMap { $0 }
            if !edges.isEmpty && edges.allSatisfy(\.isAmbiguous) {
                append("\(warning) Only ambiguous incoming matches (?); these are possible, not confirmed references.", color: yellow)
            }
        }
        if hasVisibleAmbiguity || incoming.values.joined().contains(where: \.isAmbiguous)
            || outgoing.values.joined().contains(where: \.isAmbiguous) {
            append("? marks ambiguous declaration matches.")
        }
        let unresolved = referenceSites(result.unresolved)
        append("Unresolved/external candidates: \(counted(unresolved.count, "reference site"))", color: yellow)
        append("  Resolution unavailable; these are not necessarily external.")
        for usage in unresolved.prefix(3) {
            append("  \(usage.kinds) \(usage.names) @ \(location(usage.file, line: usage.line, column: usage.column, directory: options.directory))")
        }
        if unresolved.count > 3 {
            append("  \(counted(unresolved.count - 3, "unresolved reference site")) hidden (showing first 3).")
        }
        for message in result.warnings { append("\(warning) \(message)", color: yellow) }
        append("\(warning) Syntax-only analysis: dynamic dispatch, runtime uses, external modules and unresolved references may be missing.", color: yellow)
        return lines.joined(separator: "\n")
    }

    private func tree(
        root: DeclarationReference,
        adjacency: [DeclarationReference: [DeclarationReference: [ReferenceEdge]]],
        options: GraphDisplayOptions
    ) -> (lines: [String], hasAmbiguity: Bool) {
        var lines: [String] = []
        var hasAmbiguity = false
        var shownDepth: [DeclarationReference: Int] = [:]
        let nodeBudget = 200
        var displayedNodeCount = 0
        var budgetReached = false
        let limit = max(0, options.limit)
        let branch = options.ascii ? "|-- " : "├── "
        let end = options.ascii ? "`-- " : "└── "
        let vertical = options.ascii ? "|   " : "│   "

        func visit(_ node: DeclarationReference, prefix: String, depth: Int, path: Set<DeclarationReference>) {
            let groups = adjacency[node, default: [:]]
            let neighbors = groups.keys.sorted(by: declarationOrder)
            guard !neighbors.isEmpty else { return }
            guard depth > 0 else {
                lines.append("\(prefix)\(end)\(counted(neighbors.count, "next-level node")) hidden; increase --depth.")
                return
            }
            let displayed = Array(neighbors.prefix(limit))
            let hidden = neighbors.count - displayed.count
            for (index, neighbor) in displayed.enumerated() {
                guard displayedNodeCount < nodeBudget else {
                    budgetReached = true
                    return
                }
                displayedNodeCount += 1
                let last = index == displayed.count - 1 && hidden == 0
                let continuation = prefix + (last ? "    " : vertical)
                let edges = groups[neighbor, default: []]
                let usages = referenceSites(edges.map(\.usage))
                let kinds = Set(edges.map { $0.usage.kind.rawValue }).sorted().joined(separator: ", ")
                let badge = "\(kinds); \(counted(usages.count, "site"))"
                let isAmbiguous = edges.contains(where: \.isAmbiguous)
                hasAmbiguity = hasAmbiguity || isAmbiguous
                let ambiguous = isAmbiguous ? "; ? ambiguous" : ""
                let cycle = path.contains(neighbor)
                let previousDepth = shownDepth[neighbor]
                let shared = previousDepth != nil && !cycle
                let marker = cycle ? " [cycle]" : (shared ? " [shared; shown above]" : "")
                lines.append("\(prefix)\(last ? end : branch)\(neighbor.kind) \(neighbor.displayName) [\(badge)\(ambiguous)]\(marker)")
                lines.append("\(continuation)at \(location(neighbor.file, line: neighbor.line, column: neighbor.column, directory: options.directory))")
                for usage in usages.prefix(3) {
                    lines.append("\(continuation)\(usage.kinds) @ \(location(usage.file, line: usage.line, column: usage.column, directory: options.directory))")
                }
                if usages.count > 3 {
                    lines.append("\(continuation)\(counted(usages.count - 3, "more reference site")) hidden (showing first 3).")
                }
                if cycle { continue }
                if let previousDepth, previousDepth >= depth { continue }
                shownDepth[neighbor] = depth
                visit(neighbor, prefix: continuation, depth: depth - 1, path: path.union([neighbor]))
                if budgetReached { return }
            }
            if hidden > 0 {
                lines.append("\(prefix)\(end)\(counted(hidden, "node")) hidden; increase --limit.")
            }
        }

        if adjacency[root, default: [:]].isEmpty {
            return (["\(end)(none)"], false)
        }
        visit(root, prefix: "", depth: max(0, options.depth), path: [root])
        if budgetReached {
            lines.append("\(end)Additional nodes hidden: output budget of \(nodeBudget) node entries per tree reached.")
        }
        return (lines, hasAmbiguity)
    }

    private func counted(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }

    private func summary(
        _ label: String,
        groups: [DeclarationReference: [ReferenceEdge]]
    ) -> [String] {
        let nodes = Array(groups.keys)
        let edges = groups.values.flatMap { $0 }
        let usages = referenceSites(edges.map(\.usage))
        let syntaxMatched = referenceSites(edges.filter { !$0.isAmbiguous }.map(\.usage)).count
        let possibleOnly = usages.count - syntaxMatched
        let nodeFiles = Set(nodes.map { canonicalPath($0.file) }).count
        let siteFiles = Set(usages.map { canonicalPath($0.file) }).count
        let testNodes = nodes.filter { isTestFile($0.file) }.count
        let testSites = usages.filter { isTestFile($0.file) }.count
        return [
            "\(label): \(counted(nodes.count, "node")) in \(counted(nodeFiles, "file")); \(counted(usages.count, "reference site")) in \(counted(siteFiles, "file")).",
            "  Nodes: \(nodes.count - testNodes) production, \(testNodes) test.",
            "  Sites: \(usages.count - testSites) production, \(testSites) test.",
            "  Resolution: \(counted(syntaxMatched, "syntax-matched reference site")), \(counted(possibleOnly, "possible-only reference site"))."
        ]
    }

    private func scanIsIncomplete(_ warnings: [String]) -> Bool {
        warnings.contains { warning in
            let text = warning.lowercased()
            return ["could not read", "unable to read", "failed to read", "unreadable", "syntax error", "syntax-error"].contains {
                text.contains($0)
            }
        }
    }

    private func reportContext(_ reason: ExclusionReason) -> String {
        switch reason {
        case .none:
            "Report context: no exclusion recorded (report candidate)."
        case .writeOnly:
            "Report context: write-only; writes are not evidence of reads."
        case .override:
            "Exclusion: override; dispatch may supply incoming uses."
        case .protocolImplementation:
            "Exclusion: protocol implementation; requirement uses may be indirect."
        case .objcAttribute, .ibAction, .ibOutlet:
            "Exclusion: \(reason.description); runtime or Interface Builder uses may be indirect."
        case .caseIterable:
            "Exclusion: CaseIterable; synthesized references may be indirect."
        case .mainAttribute:
            "Exclusion: @main; the runtime supplies the entry point."
        case .unresolvedProtocol:
            "Exclusion: protocol requirements unavailable; this may be a required witness."
        }
    }

    private func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func location(_ file: String, line: Int, column: Int, directory: String?) -> String {
        let path: String
        if let directory {
            let canonicalFile = canonicalPath(file.hasPrefix("/") ? file : URL(fileURLWithPath: directory).appendingPathComponent(file).path)
            let base = canonicalPath(directory)
            let prefix = base == "/" ? "/" : base + "/"
            path = canonicalFile.hasPrefix(prefix) ? String(canonicalFile.dropFirst(prefix.count)) : canonicalFile
        } else {
            path = file
        }
        return "\(path):\(line):\(column)"
    }

    private func isTestFile(_ file: String) -> Bool {
        let components = file.split(separator: "/")
        return components.dropLast().contains { $0.lowercased() == "tests" }
            || (components.last?.contains("Test") ?? false)
    }

    private func declarationOrder(_ lhs: DeclarationReference, _ rhs: DeclarationReference) -> Bool {
        if lhs.displayName != rhs.displayName { return lhs.displayName < rhs.displayName }
        if lhs.file != rhs.file { return lhs.file < rhs.file }
        if lhs.line != rhs.line { return lhs.line < rhs.line }
        if lhs.column != rhs.column { return lhs.column < rhs.column }
        return lhs.kind < rhs.kind
    }

    private func referenceSites(_ usages: [ReferenceUsage]) -> [(file: String, line: Int, column: Int, kinds: String, names: String)] {
        let groups = Dictionary(grouping: usages) {
            location(canonicalPath($0.file), line: $0.line, column: $0.column, directory: nil)
        }
        return groups.values.compactMap { usages in
            guard let first = usages.sorted(by: usageOrder).first else { return nil }
            return (
                file: first.file, line: first.line, column: first.column,
                kinds: Set(usages.map { $0.kind.rawValue }).sorted().joined(separator: ", "),
                names: Set(usages.map(\.name)).sorted().joined(separator: ", ")
            )
        }.sorted {
            if $0.file != $1.file { return $0.file < $1.file }
            if $0.line != $1.line { return $0.line < $1.line }
            return $0.column < $1.column
        }
    }

    private func usageOrder(_ lhs: ReferenceUsage, _ rhs: ReferenceUsage) -> Bool {
        if lhs.file != rhs.file { return lhs.file < rhs.file }
        if lhs.line != rhs.line { return lhs.line < rhs.line }
        if lhs.column != rhs.column { return lhs.column < rhs.column }
        if lhs.kind != rhs.kind { return lhs.kind.rawValue < rhs.kind.rawValue }
        return lhs.name < rhs.name
    }

    private func printable(_ text: String, ascii: Bool) -> String {
        text.unicodeScalars.map { scalar in
            if scalar.value < 32 || (127...159).contains(scalar.value) { return " " }
            guard ascii, !scalar.isASCII else { return String(scalar) }
            switch scalar.value {
            case 0x2013, 0x2014: return "-"
            case 0x2018, 0x2019: return "'"
            case 0x201C, 0x201D: return "\""
            case 0x2026: return "..."
            case 0x2192: return "->"
            case 0x2713: return "[OK]"
            case 0x26A0: return "[!]"
            default: return "\\u{\(String(scalar.value, radix: 16))}"
            }
        }.joined()
    }

    private func wrapped(_ text: String, width: Int) -> [String] {
        guard !text.isEmpty else { return [""] }
        let characters = Array(text)
        var lines: [String] = []
        var start = 0
        while start < characters.count {
            var end = start
            var cells = 0
            while end < characters.count {
                let next = cellWidth(String(characters[end]))
                if cells + next > width { break }
                cells += next
                end += 1
            }
            if end == start {
                lines.append("?")
                start += 1
                continue
            }
            var nextStart = end
            if end < characters.count,
                let space = (start..<end).last(where: { characters[$0].isWhitespace }),
                space > start,
                characters[start..<space].contains(where: { !$0.isWhitespace }) {
                end = space
                nextStart = space + 1
                while nextStart < characters.count && characters[nextStart].isWhitespace { nextStart += 1 }
            }
            lines.append(String(characters[start..<end]))
            start = nextStart
        }
        return lines
    }

    private func cellWidth(_ text: String) -> Int {
        text.reduce(0) { total, character in
            total + (character.unicodeScalars.map { scalar -> Int in
                switch scalar.properties.generalCategory {
                case .nonspacingMark, .enclosingMark, .format: return 0
                default: break
                }
                let value = scalar.value
                if (0x1100...0x115F).contains(value) || (0x2329...0x232A).contains(value)
                    || ((0x2E80...0xA4CF).contains(value) && value != 0x303F)
                    || (0xAC00...0xD7A3).contains(value) || (0xF900...0xFAFF).contains(value)
                    || (0xFE10...0xFE19).contains(value) || (0xFE30...0xFE6F).contains(value)
                    || (0xFF00...0xFF60).contains(value) || (0xFFE0...0xFFE6).contains(value)
                    || (0x1F1E6...0x1F1FF).contains(value) || (0x1F300...0x1FAFF).contains(value)
                    || (0x20000...0x3FFFD).contains(value) { return 2 }
                return 1
            }.max() ?? 0)
        }
    }
}

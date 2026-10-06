import Foundation
import Testing
@testable import unused

struct GraphRendererTests {

    @Test func selectedBoxUsesRootMetadataAndReportContext() {
        let root = node("fetch", parent: "API", file: "/project/Sources/API.swift", line: 45, column: 7, signature: "fetch(id: Int) async -> User")
        let result = graph(root, scannedFiles: 12, includesTests: false)
        let output = GraphRenderer().render(result, options: GraphDisplayOptions(directory: "/project"))

        #expect(output.contains("SELECTED #42"))
        #expect(output.contains("function API.fetch(id: Int) async -> User"))
        #expect(output.contains("Location: Sources/API.swift:45:7"))
        #expect(output.contains("no exclusion recorded (report candidate)"))
        #expect(output.contains("Scope: 12 scanned files; tests excluded."))
        #expect(output.hasPrefix("╭"))
        #expect(output.contains("Inbound dependents → SELECTED"))
        #expect(output.contains("SELECTED → Outbound dependencies"))
    }

    @Test func missingRootUsesTargetMetadataForStaleHeader() {
        let target = report(name: "count", type: .variable, parent: "Counter")
        let result = ReferenceGraphResult(target: target, targetFound: false)
        let output = GraphRenderer().render(result, options: GraphDisplayOptions(directory: "/project"))

        #expect(output.contains("SELECTED #42"))
        #expect(output.contains("variable Counter.count"))
        #expect(output.contains("Location: Sources/Selected.swift:1:1"))
        #expect(output.contains("Inbound: 0 nodes in 0 files; 0 reference sites in 0 files."))
        #expect(output.contains("Outbound: 0 nodes in 0 files; 0 reference sites in 0 files."))
        #expect(output.contains("refresh report"))
        #expect(!output.contains("Assessment:"))
    }

    @Test func groupsUsageKindsAndCountsNodesSeparatelyFromSites() {
        let root = node("selected")
        let production = node("load", file: "/project/Sources/Load.swift")
        let test = node("verify", file: "/project/Tests/Verify.swift")
        let dependency = node("store", file: "/project/Sources/Store.swift", kind: "variable")
        let call = edge(production, root, kind: .call, line: 10, column: 4)
        let edges = [
            call, call,
            edge(production, root, kind: .read, line: 11, column: 8),
            edge(test, root, kind: .type, line: 20, column: 2, ambiguous: true),
            edge(root, dependency, kind: .write, line: 30, column: 9)
        ]
        let output = GraphRenderer().render(graph(root, edges: edges), options: GraphDisplayOptions(directory: "/project"))

        #expect(output.contains("load [call, read; 2 sites]"))
        #expect(output.contains("verify [type; 1 site; ? ambiguous]"))
        #expect(output.contains("store [write; 1 site]"))
        #expect(output.contains("call @ Sources/Load.swift:10:4"))
        #expect(output.contains("read @ Sources/Load.swift:11:8"))
        #expect(output.contains("type @ Tests/Verify.swift:20:2"))
        #expect(output.contains("write @ Sources/Selected.swift:30:9"))
        #expect(output.contains("Inbound: 2 nodes in 2 files; 3 reference sites in 2 files."))
        #expect(output.contains("Outbound: 1 node in 1 file; 1 reference site in 1 file."))
        #expect(output.contains("Nodes: 1 production, 1 test."))
        #expect(output.contains("Sites: 2 production, 1 test."))
        #expect(output.contains("? marks ambiguous declaration matches."))
        #expect(!output.contains("Only ambiguous incoming"))
    }

    @Test func siteIdentityIgnoresResolutionMetadataAndRetainsAllUsageKinds() {
        let root = node("selected")
        let dependent = node("dependent")
        let call = ReferenceUsage(name: "selected", kind: .call, file: "/project/Sources/Use.swift", line: 4, column: 7)
        let qualified = ReferenceUsage(name: "selected", kind: .call, file: "/project/Sources/./Use.swift", line: 4, column: 7, receiverType: "Owner", isMember: true)
        let read = ReferenceUsage(name: "selected", kind: .read, file: call.file, line: call.line, column: call.column)
        var result = graph(root, edges: [call, qualified, read].map {
            ReferenceEdge(source: dependent, target: root, usage: $0, isAmbiguous: false)
        })
        result.unresolved = [call, qualified]
        let output = GraphRenderer().render(result, options: GraphDisplayOptions(directory: "/project"))

        #expect(output.contains("dependent [call, read; 1 site]"))
        #expect(output.contains("call, read @ Sources/Use.swift:4:7"))
        #expect(output.contains("Inbound: 1 node in 1 file; 1 reference site in 1 file."))
        #expect(output.contains("Unresolved/external candidates: 1 reference site"))
    }

    @Test func edgesDriveSummaryWhenInboundSectionIsHidden() {
        let root = node("selected")
        let result = ReferenceGraphResult(
            target: report(), root: root,
            edges: [edge(node("dependent"), root), edge(root, node("dependency"))]
        )
        let output = GraphRenderer().render(result, options: GraphDisplayOptions(outboundOnly: true))

        #expect(output.contains("dependency [call; 1 site]"))
        #expect(output.contains("Inbound: 1 node in 1 file; 1 reference site in 1 file."))
        #expect(output.contains("Project references found; inspect before removing."))
        #expect(!output.contains("No incoming project references found"))
    }

    @Test func unrelatedEdgesAreNotCountedAsIncomingReferences() {
        let root = node("selected")
        let result = graph(root, edges: [edge(node("a"), node("b"))])
        let output = GraphRenderer().render(result)

        #expect(output.contains("Inbound: 0 nodes in 0 files; 0 reference sites in 0 files."))
        #expect(output.contains("Outbound: 0 nodes in 0 files; 0 reference sites in 0 files."))
        #expect(output.contains("No incoming project references found; verify runtime/external uses."))
        #expect(!output.contains("a [call"))
    }

    @Test func unrelatedAmbiguousEdgesDoNotAddLegend() {
        let root = node("selected")
        let result = graph(root, edges: [
            edge(node("dependent"), root),
            edge(node("unrelatedSource"), node("unrelatedTarget"), ambiguous: true)
        ])
        let output = GraphRenderer().render(result)

        #expect(output.contains("dependent [call; 1 site]"))
        #expect(!output.contains("? marks ambiguous declaration matches."))
        #expect(!output.contains("; ? ambiguous"))
    }

    @Test(arguments: [true, false]) func deeperAmbiguityLegendOnlyAppearsForVisibleTrees(inbound: Bool) {
        let root = node("selected")
        let neighbor = node("neighbor")
        let possible = node("possible")
        let edges = inbound
            ? [edge(neighbor, root), edge(possible, neighbor, ambiguous: true)]
            : [edge(root, neighbor), edge(neighbor, possible, ambiguous: true)]
        let result = graph(root, edges: edges)
        let renderer = GraphRenderer()
        let shallow = renderer.render(result, options: GraphDisplayOptions(inboundOnly: inbound, outboundOnly: !inbound))
        let deeper = renderer.render(result, options: GraphDisplayOptions(inboundOnly: inbound, outboundOnly: !inbound, depth: 2))
        let truncated = renderer.render(result, options: GraphDisplayOptions(inboundOnly: inbound, outboundOnly: !inbound, depth: 2, limit: 0))
        let filtered = renderer.render(result, options: GraphDisplayOptions(inboundOnly: !inbound, outboundOnly: inbound, depth: 2))

        #expect(!shallow.contains("? marks ambiguous declaration matches."))
        #expect(deeper.contains("possible [call; 1 site; ? ambiguous]"))
        #expect(deeper.contains("? marks ambiguous declaration matches."))
        #expect(!truncated.contains("? marks ambiguous declaration matches."))
        #expect(!filtered.contains("? marks ambiguous declaration matches."))
    }

    @Test func directAmbiguityLegendAndResolutionCountsSurviveDisplayFilters() {
        let root = node("selected")
        let matched = ReferenceUsage(name: "selected", kind: .call, file: "/project/Sources/Use.swift", line: 1, column: 2)
        let possible = ReferenceUsage(name: "selected", kind: .call, file: matched.file, line: 2, column: 2)
        let result = graph(root, edges: [
            ReferenceEdge(source: node("a"), target: root, usage: matched, isAmbiguous: false),
            ReferenceEdge(source: node("b"), target: root, usage: matched, isAmbiguous: true),
            ReferenceEdge(source: node("c"), target: root, usage: possible, isAmbiguous: true),
            ReferenceEdge(source: node("d"), target: root, usage: possible, isAmbiguous: true)
        ])
        let output = GraphRenderer().render(result, options: GraphDisplayOptions(outboundOnly: true, limit: 0))

        #expect(output.contains("Inbound: 4 nodes in 1 file; 2 reference sites in 1 file."))
        #expect(output.contains("Resolution: 1 syntax-matched reference site, 1 possible-only reference site."))
        #expect(output.contains("Resolution: 0 syntax-matched reference sites, 0 possible-only reference sites."))
        #expect(output.contains("? marks ambiguous declaration matches."))
    }

    @Test(arguments: [0, 1, 2]) func countsUseSingularOnlyForOne(count: Int) {
        let root = node("selected")
        let dependents = (0..<count).map { node("dependent\($0)", file: "/project/Sources/Use\($0).swift") }
        var result = graph(root, edges: dependents.map { edge($0, root) }, scannedFiles: count)
        result.unresolved = dependents.map {
            ReferenceUsage(name: "external", kind: .call, file: $0.file, line: 4, column: 2)
        }
        let output = GraphRenderer().render(result)
        let suffix = count == 1 ? "" : "s"

        #expect(output.contains("Scope: \(count) scanned file\(suffix); tests included."))
        #expect(output.contains("Inbound: \(count) node\(suffix) in \(count) file\(suffix); \(count) reference site\(suffix) in \(count) file\(suffix)."))
        #expect(output.contains("Resolution: \(count) syntax-matched reference site\(suffix), 0 possible-only reference sites."))
        #expect(output.contains("Unresolved/external candidates: \(count) reference site\(suffix)"))
        if count > 0 {
            let limited = GraphRenderer().render(result, options: GraphDisplayOptions(limit: 0))
            let shallow = GraphRenderer().render(result, options: GraphDisplayOptions(depth: 0))
            #expect(limited.contains("\(count) node\(suffix) hidden; increase --limit."))
            #expect(shallow.contains("\(count) next-level node\(suffix) hidden; increase --depth."))
        }
    }

    @Test(arguments: [4, 5]) func hiddenSiteCountsUseCorrectGrammar(siteCount: Int) {
        let root = node("selected")
        let dependent = node("dependent")
        let edges = (1...siteCount).map { edge(dependent, root, line: $0) }
        var result = graph(root, edges: edges)
        result.unresolved = edges.map(\.usage)
        let output = GraphRenderer().render(result)
        let hidden = siteCount - 3
        let suffix = hidden == 1 ? "" : "s"

        #expect(output.contains("\(hidden) more reference site\(suffix) hidden (showing first 3)."))
        #expect(output.contains("\(hidden) unresolved reference site\(suffix) hidden (showing first 3)."))
    }

    @Test func referenceLocationsAreBoundedAndSorted() {
        let root = node("selected")
        let dependent = node("dependent")
        let edges = (1...5).reversed().map { edge(dependent, root, kind: .reference, line: $0, column: $0 + 1) }
        let output = GraphRenderer().render(graph(root, edges: edges), options: GraphDisplayOptions(directory: "/project"))

        #expect(output.contains("dependent [reference; 5 sites]"))
        #expect(output.contains("reference @ Sources/Selected.swift:1:2"))
        #expect(output.contains("reference @ Sources/Selected.swift:2:3"))
        #expect(output.contains("reference @ Sources/Selected.swift:3:4"))
        #expect(!output.contains("reference @ Sources/Selected.swift:4:5"))
        #expect(output.contains("2 more reference sites hidden (showing first 3)."))
        #expect(output.contains("Inbound: 1 node in 1 file; 5 reference sites in 1 file."))
        #expect(output == GraphRenderer().render(graph(root, edges: Array(edges.reversed())), options: GraphDisplayOptions(directory: "/project")))
    }

    @Test func defaultDepthShowsOnlyDirectNodesInBothDirections() {
        let root = node("selected")
        let dependent = node("dependent")
        let upstream = node("upstream")
        let dependency = node("dependency")
        let downstream = node("downstream")
        let result = graph(root, edges: [edge(dependent, root), edge(upstream, dependent), edge(root, dependency), edge(dependency, downstream)])
        let output = GraphRenderer().render(result)

        #expect(output.contains("dependent [call; 1 site]"))
        #expect(output.contains("dependency [call; 1 site]"))
        #expect(!output.contains("upstream ["))
        #expect(!output.contains("downstream ["))
        #expect(output.split(separator: "\n").filter { $0.contains("1 next-level node hidden; increase --depth.") }.count == 2)
        #expect(output.contains("Inbound: 1 node in 1 file; 1 reference site in 1 file."))
        #expect(output.contains("Outbound: 1 node in 1 file; 1 reference site in 1 file."))

        let deeper = GraphRenderer().render(result, options: GraphDisplayOptions(depth: 2))
        #expect(deeper.contains("upstream [call; 1 site]"))
        #expect(deeper.contains("downstream [call; 1 site]"))
        #expect(!deeper.contains("increase --depth"))
    }

    @Test func cyclesArePerPathAndSharedNodesAreNotFalseCycles() {
        let root = node("selected")
        let a = node("a")
        let b = node("b")
        let shared = node("shared")
        let result = graph(root, edges: [
            edge(root, a), edge(root, b), edge(a, shared), edge(b, shared),
            edge(shared, a), edge(shared, root), edge(root, root)
        ])
        let options = GraphDisplayOptions(outboundOnly: true, depth: 20)
        let output = GraphRenderer().render(result, options: options)

        #expect(output.contains("a [call; 1 site] [cycle]"))
        #expect(output.contains("selected [call; 1 site] [cycle]"))
        #expect(output.contains("shared [call; 1 site] [shared; shown above]"))
        #expect(!output.contains("shared [call; 1 site] [cycle]"))
        #expect(output.split(separator: "\n").count < 70)
        #expect(output.contains("Inbound: 2 nodes in 1 file; 1 reference site in 1 file."))
    }

    @Test func sharedNodesCanExpandWithMoreRemainingDepth() {
        let root = node("selected")
        let a = node("a")
        let b = node("b")
        let middle = node("middle")
        let shared = node("shared")
        let leaf = node("leaf")
        let result = graph(root, edges: [
            edge(root, a), edge(a, middle), edge(middle, shared),
            edge(root, b), edge(b, shared), edge(shared, leaf)
        ])
        let output = GraphRenderer().render(result, options: GraphDisplayOptions(outboundOnly: true, depth: 3))

        #expect(output.contains("shared [call; 1 site] [shared; shown above]"))
        #expect(output.contains("leaf [call; 1 site]"))
    }

    @Test func limitAppliesAtEachBranchAndSummaryRemainsComplete() {
        let root = node("selected")
        let children = [node("a"), node("b"), node("c")]
        let leaves = [node("x"), node("y"), node("z")]
        let edges = children.map { edge(root, $0) } + leaves.map { edge(children[0], $0) }
        let output = GraphRenderer().render(graph(root, edges: edges), options: GraphDisplayOptions(outboundOnly: true, depth: 2, limit: 1))

        #expect(output.contains("a [call; 1 site]"))
        #expect(output.contains("x [call; 1 site]"))
        #expect(!output.contains("b ["))
        #expect(!output.contains("y ["))
        #expect(output.split(separator: "\n").filter { $0.contains("2 nodes hidden; increase --limit.") }.count == 2)
        #expect(output.contains("Outbound: 3 nodes in 1 file; 1 reference site in 1 file."))
        #expect(output.contains("No incoming project references found; verify runtime/external uses."))
    }

    @Test(arguments: [true, false]) func globalTreeBudgetBoundsBreadthAndNestedBranches(nested: Bool) {
        let root = node("selected")
        let parents = (0..<(nested ? 20 : 201)).map { node("parent\($0)") }
        var edges = parents.enumerated().map { edge(root, $0.element, line: $0.offset + 1) }
        if nested {
            for (index, parent) in parents.enumerated() {
                edges += (0..<20).map { edge(parent, node("leaf\(index)_\($0)"), line: $0 + 1) }
            }
        }
        let output = GraphRenderer().render(graph(root, edges: edges), options: GraphDisplayOptions(outboundOnly: true, depth: 10, limit: nested ? 20 : 500))

        #expect(output.split(separator: "\n").filter { $0.contains("[call; 1 site]") }.count == 200)
        #expect(output.contains("Additional nodes hidden: output budget of 200 node entries per tree reached."))
        #expect(!output.contains("increase --limit"))
        #expect(output.contains("Outbound: \(parents.count) nodes in 1 file; \(parents.count) reference sites in 1 file."))
        #expect(output.contains("No incoming project references found; verify runtime/external uses."))
        #expect(output.split(separator: "\n").count < 1200)
    }

    @Test func treeBudgetsAreIndependentForEachDirection() {
        let root = node("selected")
        let incoming = (0..<201).map { edge(node("dependent\($0)"), root, line: $0 + 1) }
        let outgoing = (0..<201).map { edge(root, node("dependency\($0)"), line: $0 + 1) }
        let output = GraphRenderer().render(graph(root, edges: incoming + outgoing), options: GraphDisplayOptions(depth: 10, limit: 500))

        #expect(output.split(separator: "\n").filter { $0.contains("[call; 1 site]") }.count == 400)
        #expect(output.split(separator: "\n").filter { $0.contains("output budget of 200 node entries per tree reached.") }.count == 2)
        #expect(output.contains("Inbound: 201 nodes in 1 file; 201 reference sites in 1 file."))
        #expect(output.contains("Outbound: 201 nodes in 1 file; 201 reference sites in 1 file."))
        #expect(output.contains("Project references found; inspect before removing."))
    }

    @Test func exactTreeBudgetDoesNotReportHiddenNodes() {
        let root = node("selected")
        let edges = (0..<200).map { edge(root, node("dependency\($0)")) }
        let output = GraphRenderer().render(graph(root, edges: edges), options: GraphDisplayOptions(outboundOnly: true, depth: 10, limit: 200))

        #expect(output.split(separator: "\n").filter { $0.contains("[call; 1 site]") }.count == 200)
        #expect(!output.contains("output budget"))
        #expect(!output.contains("nodes hidden"))
    }

    @Test func defaultLimitIsTwenty() {
        let root = node("selected")
        let edges = (0..<21).map { edge(node("dependent\($0)"), root, line: $0 + 1) }
        let output = GraphRenderer().render(graph(root, edges: edges), options: GraphDisplayOptions(inboundOnly: true))

        #expect(output.split(separator: "\n").filter { $0.contains("[call; 1 site]") }.count == 20)
        #expect(output.contains("1 node hidden; increase --limit."))
        #expect(output.contains("Inbound: 21 nodes in 1 file; 21 reference sites in 1 file."))
    }

    @Test(arguments: [0, -1]) func nonpositiveLimitsHideNodesWithoutChangingAssessment(limit: Int) {
        let root = node("selected")
        let result = graph(root, edges: [edge(node("dependent"), root)])
        let output = GraphRenderer().render(result, options: GraphDisplayOptions(limit: limit))

        #expect(output.contains("1 node hidden; increase --limit."))
        #expect(!output.contains("dependent ["))
        #expect(output.contains("Project references found; inspect before removing."))
        #expect(output.contains("Inbound: 1 node in 1 file; 1 reference site in 1 file."))
    }

    @Test(arguments: [0, -1]) func nonpositiveDepthHidesNodesWithoutChangingAssessment(depth: Int) {
        let root = node("selected")
        let output = GraphRenderer().render(graph(root, edges: [edge(node("dependent"), root)]), options: GraphDisplayOptions(depth: depth))

        #expect(output.contains("1 next-level node hidden; increase --depth."))
        #expect(!output.contains("dependent ["))
        #expect(output.contains("Project references found; inspect before removing."))
    }

    @Test(arguments: [true, false]) func directionFiltersDoNotChangeSummaryOrAssessment(inboundOnly: Bool) {
        let root = node("selected")
        let result = graph(root, edges: [edge(node("dependent"), root), edge(root, node("dependency"))])
        let options = GraphDisplayOptions(inboundOnly: inboundOnly, outboundOnly: !inboundOnly, limit: 0)
        let output = GraphRenderer().render(result, options: options)

        #expect(output.contains("Inbound dependents → SELECTED") == inboundOnly)
        #expect(output.contains("SELECTED → Outbound dependencies") == !inboundOnly)
        #expect(output.contains("Inbound: 1 node in 1 file; 1 reference site in 1 file."))
        #expect(output.contains("Outbound: 1 node in 1 file; 1 reference site in 1 file."))
        #expect(output.contains("Project references found; inspect before removing."))
        #expect(!output.contains("No incoming project references found"))
        #expect(result.inbound.count == 1)
        #expect(result.outbound.count == 1)
        #expect(result.edges.count == 2)
    }

    @Test func ambiguousOnlyMatchesRemainCautiousWhenInboundIsHidden() {
        let root = node("selected")
        let usage = ReferenceUsage(name: "selected", kind: .call, file: "/project/Sources/Use.swift", line: 8, column: 3)
        let edges = [
            ReferenceEdge(source: node("a"), target: root, usage: usage, isAmbiguous: true),
            ReferenceEdge(source: node("b"), target: root, usage: usage, isAmbiguous: true)
        ]
        let output = GraphRenderer().render(graph(root, edges: edges), options: GraphDisplayOptions(outboundOnly: true))

        #expect(output.contains("Inbound: 2 nodes in 1 file; 1 reference site in 1 file."))
        #expect(output.contains("Only ambiguous incoming matches (?)"))
        #expect(output.contains("Project references found; inspect before removing."))
        #expect(!output.contains("No incoming project references found"))
    }

    @Test func emptyGraphIncludesCautionAndSyntaxLimitations() {
        var result = graph(node("selected"))
        result.unresolved = [ReferenceUsage(name: "unknown", kind: .reference, file: "/project/Use.swift", line: 3, column: 4)]
        let output = GraphRenderer().render(result)

        #expect(output.contains("└── (none)"))
        #expect(output.contains("✓ No incoming project references found; verify runtime/external uses."))
        #expect(output.contains("Unresolved/external candidates: 1 reference site"))
        #expect(output.contains("Resolution unavailable; these are not necessarily external."))
        #expect(output.contains("reference unknown @ /project/Use.swift:3:4"))
        #expect(output.contains("⚠ Syntax-only analysis: dynamic dispatch, runtime uses, external modules"))
        #expect(output.contains("and unresolved references"))
        #expect(output.contains("may be missing."))
        #expect(!output.contains("safe to remove"))
        #expect(!output.contains("⚠️"))
    }

    @Test func unresolvedDetailsAreNamedRelativeSortedAndBounded() {
        let usages = [
            ReferenceUsage(name: "print", kind: .call, file: "/project/Sources/Use.swift", line: 1, column: 4),
            ReferenceUsage(name: "value", kind: .read, file: "/project/Sources/Use.swift", line: 2, column: 8),
            ReferenceUsage(name: "Model", kind: .type, file: "/project/Sources/Use.swift", line: 3, column: 12),
            ReferenceUsage(name: "hiddenWrite", kind: .write, file: "/project/Sources/Use.swift", line: 4, column: 2),
            ReferenceUsage(name: "hiddenReference", kind: .reference, file: "/project/Sources/Use.swift", line: 5, column: 7)
        ]
        let result = ReferenceGraphResult(target: report(), root: node("selected"), unresolved: Array(usages.reversed()) + [usages[0]])
        let output = GraphRenderer().render(result, options: GraphDisplayOptions(outboundOnly: true, limit: 0, directory: "/project"))

        #expect(output.contains("Unresolved/external candidates: 5 reference sites"))
        #expect(output.contains("Resolution unavailable; these are not necessarily external."))
        #expect(output.contains("call print @ Sources/Use.swift:1:4"))
        #expect(output.contains("read value @ Sources/Use.swift:2:8"))
        #expect(output.contains("type Model @ Sources/Use.swift:3:12"))
        #expect(!output.contains("hiddenWrite"))
        #expect(!output.contains("hiddenReference"))
        #expect(output.contains("2 unresolved reference sites hidden (showing first 3)."))
        #expect(!output.contains("increase --limit"))
    }

    @Test func emptyUnresolvedListHasNoInventedDetails() {
        let output = GraphRenderer().render(graph(node("selected")))

        #expect(output.contains("Unresolved/external candidates: 0 reference sites"))
        #expect(!output.contains("unresolved reference sites hidden"))
        #expect(!output.contains(" @ "))
    }

    @Test(arguments: [
        "Could not read /project/Sources/Use.swift; incoming references may be missing.",
        "Syntax errors in /project/Sources/Use.swift; references from this file may be incomplete.",
        "Unreadable source file.",
        "Syntax-error warning."
    ]) func incompleteScansNeverUseAPositiveCheck(warning: String) {
        var result = graph(node("selected"))
        result.warnings = [warning]
        for ascii in [false, true] {
            let output = GraphRenderer().render(result, options: GraphDisplayOptions(outboundOnly: true, ascii: ascii))
            let marker = ascii ? "[!]" : "⚠"

            #expect(output.contains("Assessment: \(marker) No incoming references found in scanned sources; scan incomplete."))
            #expect(!output.contains("✓"))
            #expect(!output.contains("[OK]"))
            #expect(!output.contains("No incoming project references found"))
            #expect(output.contains("Inbound: 0 nodes in 0 files; 0 reference sites in 0 files."))
            #expect(output.contains("Syntax-only analysis"))
        }
    }

    @Test func ordinaryWarningsDoNotImplyAnIncompleteScan() {
        var result = graph(node("selected"))
        result.warnings = ["Source changed since the report was generated.", "2 test files excluded; use --include-tests."]
        let output = GraphRenderer().render(result)

        #expect(output.contains("✓ No incoming project references found; verify runtime/external uses."))
        #expect(!output.contains("scan incomplete"))
    }

    @Test func incompleteScanWithIncomingEdgesRetainsCautiousAssessment() {
        let root = node("selected")
        var result = graph(root, edges: [edge(node("dependent"), root)])
        result.warnings = ["Could not read /project/Sources/Other.swift; incoming references may be missing."]
        let output = GraphRenderer().render(result)

        #expect(output.contains("Project references found; inspect before removing."))
        #expect(!output.contains("No incoming references found"))
        #expect(!output.contains("✓"))
    }

    @Test func staleTargetSuppressesAssessmentAndRequestsReportRefresh() {
        let result = ReferenceGraphResult(
            target: report(),
            warnings: ["Source location changed."], scannedFileCount: 4, targetFound: false
        )
        let output = GraphRenderer().render(result)

        #expect(output.contains("SELECTED #42"))
        #expect(output.contains("Selected declaration not found; refresh report"))
        #expect(output.contains("⚠ Source location changed."))
        #expect(!output.contains("Assessment:"))
        #expect(!output.contains("No incoming project references found"))
        #expect(!output.contains("Project references found; inspect before removing."))
        #expect(output.contains("Syntax-only analysis"))
    }

    @Test(arguments: [ExclusionReason.override, .protocolImplementation, .objcAttribute, .ibAction, .ibOutlet, .caseIterable, .mainAttribute])
    func excludedTargetsShowContext(reason: ExclusionReason) {
        let output = GraphRenderer().render(graph(node("selected"), target: report(reason: reason)))

        #expect(output.contains("Exclusion:"))
        #expect(output.contains(reason.description))
        #expect(output.contains("verify runtime/external uses."))
        #expect(!output.contains("safe to remove"))
    }

    @Test func writeOnlyContextDoesNotTreatWritesAsReads() {
        let root = node("selected", kind: "variable")
        let result = graph(root, edges: [edge(node("setter"), root, kind: .write)], target: report(type: .variable, reason: .writeOnly))
        let output = GraphRenderer().render(result)

        #expect(output.contains("Report context: write-only; writes are not evidence of reads."))
        #expect(output.contains("setter [write; 1 site]"))
        #expect(output.contains("Project references found; inspect before removing."))
        #expect(!output.contains("callers"))
    }

    @Test func productionAndTestSplitsUseComponentsAndUsageFiles() {
        let root = node("selected")
        let nodes = [
            node("a", file: "/project/Tests/Suite.swift"),
            node("b", file: "/project/Sources/FeatureTest.swift"),
            node("c", file: "/project/MyTests/Production.swift"),
            node("d", file: "/project/Sources/Contest.swift"),
            node("e", file: "/project/TestsLike/Production.swift")
        ]
        let edges = nodes.enumerated().map { index, dependent in
            edge(dependent, root, file: index == 0 ? "/project/Sources/Use.swift" : "/project/Tests/Use.swift", line: index + 1)
        }
        let output = GraphRenderer().render(graph(root, edges: edges))

        #expect(output.contains("Inbound: 5 nodes in 5 files; 5 reference sites in 2 files."))
        #expect(output.contains("Nodes: 3 production, 2 test."))
        #expect(output.contains("Sites: 1 production, 4 test."))
    }

    @Test func pathsAreRelativeOnlyToTheActualProjectDirectory() {
        let root = node("selected", file: "/project/Sources/Module/Selected.swift")
        let outside = node("outside", file: "/project-other/Sources/Module/Outside.swift")
        let result = graph(root, edges: [edge(outside, root)])
        let relative = GraphRenderer().render(result, options: GraphDisplayOptions(directory: "/project/./Sources/.."))
        let absolute = GraphRenderer().render(result)

        #expect(relative.contains("Location: Sources/Module/Selected.swift:1:1"))
        #expect(relative.contains("/project-other/Sources/Module/Outside.swift:1:1"))
        #expect(absolute.contains("Location: /project/Sources/Module/Selected.swift:1:1"))
        #expect(absolute.contains("/project-other/Sources/Module/Outside.swift:1:1"))

        let relativeModel = graph(node("selected", file: "Sources/Selected.swift"))
        #expect(GraphRenderer().render(relativeModel, options: GraphDisplayOptions(directory: "/project")).contains("Location: Sources/Selected.swift:1:1"))
    }

    @Test func symlinkProjectPathsAreCanonicalized() throws {
        let manager = FileManager.default
        let temporary = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? manager.removeItem(at: temporary) }
        let project = temporary.appendingPathComponent("project")
        let sources = project.appendingPathComponent("Sources")
        try manager.createDirectory(at: sources, withIntermediateDirectories: true)
        try Data().write(to: sources.appendingPathComponent("Selected.swift"))
        let alias = temporary.appendingPathComponent("alias")
        try manager.createSymbolicLink(at: alias, withDestinationURL: project)
        let result = graph(node("selected", file: alias.appendingPathComponent("Sources/Selected.swift").path))
        let output = GraphRenderer().render(result, options: GraphDisplayOptions(directory: project.path))

        #expect(output.contains("Location: Sources/Selected.swift:1:1"))
        #expect(!output.contains(temporary.path))
    }

    @Test func asciiModeUsesOnlyAsciiIncludingModelTextAndWarnings() {
        var result = graph(node("界", signature: "界(é: Int)"))
        result.warnings = ["Changed — verify → source…"]
        let output = GraphRenderer().render(result, options: GraphDisplayOptions(ascii: true))

        #expect(output.unicodeScalars.allSatisfy { $0.isASCII })
        #expect(output.hasPrefix("+"))
        #expect(output.contains("`-- (none)"))
        #expect(output.contains("Inbound dependents -> SELECTED"))
        #expect(output.contains("[OK] No incoming project references found; verify runtime/external uses."))
        #expect(output.contains("[!] Changed - verify -> source..."))
        #expect(output.contains("\\u{754c}"))
    }

    @Test func colorIsPerRenderAndDoesNotAffectVisibleOutput() {
        let renderer = GraphRenderer()
        let result = graph(node("selected"))
        let plain = renderer.render(result, options: GraphDisplayOptions(width: 40))
        let colored = renderer.render(result, options: GraphDisplayOptions(width: 40, color: true))
        let plainAgain = renderer.render(result, options: GraphDisplayOptions(width: 40))

        #expect(!plain.contains("\u{1B}"))
        #expect(colored.contains("\u{1B}[38;2;137;220;235m"))
        #expect(colored.contains("\u{1B}[38;2;166;227;161m"))
        #expect(colored.contains("\u{1B}[38;2;203;166;247m"))
        #expect(colored.contains("\u{1B}[38;2;249;226;175m"))
        #expect(!colored.contains("\u{1B}[36m"))
        #expect(removingColors(colored) == plain)
        #expect(plainAgain == plain)
    }

    @Test(arguments: [1, 2, 4, 5, 20, 40, 100]) func allLinesRespectTerminalCellWidth(width: Int) {
        let root = node("界Ａ한é", file: "/project/" + String(repeating: "verylongdirectory/", count: 10) + "Selected.swift", signature: String(repeating: "界Ａ한é", count: 30))
        let edges = [edge(node(String(repeating: "dependent", count: 20)), root)]
        var result = graph(root, edges: edges)
        result.warnings = [String(repeating: "界", count: 60) + "\nTab\tControl\u{1B}[99m"]
        result.unresolved = [ReferenceUsage(name: String(repeating: "界print", count: 20), kind: .call, file: root.file, line: 2, column: 5)]
        for ascii in [false, true] {
            for color in [false, true] {
                let output = removingColors(GraphRenderer().render(result, options: GraphDisplayOptions(width: width, ascii: ascii, color: color)))
                #expect(!output.contains("\u{1B}"))
                #expect(output.split(separator: "\n", omittingEmptySubsequences: false).allSatisfy { visibleWidth(String($0)) <= width })
            }
        }
    }

    @Test func unicodeBoxPaddingUsesTerminalCellsRatherThanCharacterCount() {
        let output = GraphRenderer().render(graph(node("界Ａ한é")), options: GraphDisplayOptions(width: 80))
        let box = output.split(separator: "\n", omittingEmptySubsequences: false).prefix(while: { !$0.isEmpty })

        #expect(Set(box.map { visibleWidth(String($0)) }).count == 1)
        #expect(output.contains("界Ａ한é"))
    }

    private func report(
        name: String = "selected",
        type: DeclarationType = .function,
        parent: String? = nil,
        reason: ExclusionReason = .none
    ) -> ReportItem {
        ReportItem(id: 42, name: name, type: type, file: "/project/Sources/Selected.swift", line: 1, exclusionReason: reason, parentType: parent)
    }

    private func node(
        _ name: String,
        parent: String? = nil,
        file: String = "/project/Sources/Selected.swift",
        line: Int = 1,
        column: Int = 1,
        kind: String = "function",
        signature: String? = nil
    ) -> DeclarationReference {
        DeclarationReference(name: name, parentType: parent, file: file, line: line, column: column, kind: kind, signature: signature)
    }

    private func edge(
        _ source: DeclarationReference,
        _ target: DeclarationReference,
        kind: ReferenceKind = .call,
        file: String? = nil,
        line: Int = 10,
        column: Int = 2,
        ambiguous: Bool = false
    ) -> ReferenceEdge {
        ReferenceEdge(
            source: source, target: target,
            usage: ReferenceUsage(name: target.name, kind: kind, file: file ?? source.file, line: line, column: column),
            isAmbiguous: ambiguous
        )
    }

    private func graph(
        _ root: DeclarationReference,
        edges: [ReferenceEdge] = [],
        target: ReportItem? = nil,
        scannedFiles: Int = 3,
        includesTests: Bool = true
    ) -> ReferenceGraphResult {
        ReferenceGraphResult(
            target: target ?? report(),

            root: root, edges: edges, scannedFileCount: scannedFiles, includesTests: includesTests
        )
    }

    private func removingColors(_ text: String) -> String {
        ["0", "38;2;137;220;235", "38;2;166;227;161", "38;2;203;166;247", "38;2;249;226;175"].reduce(text) {
            $0.replacing("\u{1B}[\($1)m", with: "")
        }
    }

    private func visibleWidth(_ text: String) -> Int {
        text.reduce(0) { width, character in
            let wide = character.unicodeScalars.contains {
                (0x4E00...0x9FFF).contains($0.value) || (0xFF01...0xFF60).contains($0.value) || (0xAC00...0xD7A3).contains($0.value)
            }
            return width + (wide ? 2 : 1)
        }
    }
}

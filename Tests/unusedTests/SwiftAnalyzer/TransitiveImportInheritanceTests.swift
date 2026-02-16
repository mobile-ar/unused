//
//  TransitiveImportInheritanceTests.swift
//

import Testing
import SwiftSyntax
import SwiftParser
@testable import unused

struct TransitiveImportInheritanceTests {

    private func makeAnalyzer() -> SwiftAnalyzer {
        SwiftAnalyzer(directory: "/tmp/test")
    }

    @Test
    func testBuildGlobalInheritanceGraphFromSingleFile() {
        let analyzer = makeAnalyzer()
        let results = [
            ImportUsageResult(
                imports: [],
                usedIdentifiers: [],
                typeInheritances: [
                    "Child": Set(["Parent"]),
                    "Parent": Set(["UIViewController"])
                ]
            )
        ]

        let graph = analyzer.buildGlobalInheritanceGraph(results)

        #expect(graph["Child"] == Set(["Parent"]))
        #expect(graph["Parent"] == Set(["UIViewController"]))
    }

    @Test
    func testBuildGlobalInheritanceGraphFromMultipleFiles() {
        let analyzer = makeAnalyzer()
        let results = [
            ImportUsageResult(
                imports: [],
                usedIdentifiers: [],
                typeInheritances: ["Parent": Set(["UIViewController"])]
            ),
            ImportUsageResult(
                imports: [],
                usedIdentifiers: [],
                typeInheritances: ["Child": Set(["Parent"])]
            )
        ]

        let graph = analyzer.buildGlobalInheritanceGraph(results)

        #expect(graph["Parent"] == Set(["UIViewController"]))
        #expect(graph["Child"] == Set(["Parent"]))
    }

    @Test
    func testBuildGlobalInheritanceGraphMergesDuplicateTypes() {
        let analyzer = makeAnalyzer()
        let results = [
            ImportUsageResult(
                imports: [],
                usedIdentifiers: [],
                typeInheritances: ["MyType": Set(["ProtocolA"])]
            ),
            ImportUsageResult(
                imports: [],
                usedIdentifiers: [],
                typeInheritances: ["MyType": Set(["ProtocolB"])]
            )
        ]

        let graph = analyzer.buildGlobalInheritanceGraph(results)

        #expect(graph["MyType"] == Set(["ProtocolA", "ProtocolB"]))
    }

    @Test
    func testBuildGlobalInheritanceGraphEmptyResults() {
        let analyzer = makeAnalyzer()
        let results: [ImportUsageResult] = []

        let graph = analyzer.buildGlobalInheritanceGraph(results)

        #expect(graph.isEmpty)
    }

    @Test
    func testHasTransitiveAncestorDirectParentInModule() {
        let analyzer = makeAnalyzer()

        let typeInheritances: [String: Set<String>] = [
            "MyViewController": Set(["UIViewController"])
        ]
        let globalGraph: [String: Set<String>] = [
            "MyViewController": Set(["UIViewController"])
        ]
        let moduleSymbols: Set<String> = ["UIViewController", "UIView", "UIColor"]

        let result = analyzer.hasTransitiveAncestorInModule(
            typeInheritances: typeInheritances,
            globalGraph: globalGraph,
            moduleSymbols: moduleSymbols
        )

        #expect(result == true)
    }

    @Test
    func testHasTransitiveAncestorThroughProjectType() {
        let analyzer = makeAnalyzer()

        // Child inherits from Parent (project type), Parent inherits from UIViewController (UIKit)
        let typeInheritances: [String: Set<String>] = [
            "Child": Set(["Parent"])
        ]
        let globalGraph: [String: Set<String>] = [
            "Child": Set(["Parent"]),
            "Parent": Set(["UIViewController"])
        ]
        let moduleSymbols: Set<String> = ["UIViewController", "UIView", "UIColor"]

        let result = analyzer.hasTransitiveAncestorInModule(
            typeInheritances: typeInheritances,
            globalGraph: globalGraph,
            moduleSymbols: moduleSymbols
        )

        #expect(result == true)
    }

    @Test
    func testHasTransitiveAncestorDeepChain() {
        let analyzer = makeAnalyzer()

        // GrandChild → Child → Parent → BaseController → UIViewController
        let typeInheritances: [String: Set<String>] = [
            "GrandChild": Set(["Child"])
        ]
        let globalGraph: [String: Set<String>] = [
            "GrandChild": Set(["Child"]),
            "Child": Set(["Parent"]),
            "Parent": Set(["BaseController"]),
            "BaseController": Set(["UIViewController"])
        ]
        let moduleSymbols: Set<String> = ["UIViewController", "UIView"]

        let result = analyzer.hasTransitiveAncestorInModule(
            typeInheritances: typeInheritances,
            globalGraph: globalGraph,
            moduleSymbols: moduleSymbols
        )

        #expect(result == true)
    }

    @Test
    func testHasTransitiveAncestorNoMatchReturnsfalse() {
        let analyzer = makeAnalyzer()

        let typeInheritances: [String: Set<String>] = [
            "Child": Set(["Parent"])
        ]
        let globalGraph: [String: Set<String>] = [
            "Child": Set(["Parent"]),
            "Parent": Set(["SomeProtocol"])
        ]
        // Module symbols do not include any ancestor
        let moduleSymbols: Set<String> = ["UIViewController", "UIView", "UIColor"]

        let result = analyzer.hasTransitiveAncestorInModule(
            typeInheritances: typeInheritances,
            globalGraph: globalGraph,
            moduleSymbols: moduleSymbols
        )

        #expect(result == false)
    }

    @Test
    func testHasTransitiveAncestorEmptyInheritancesReturnsFalse() {
        let analyzer = makeAnalyzer()

        let typeInheritances: [String: Set<String>] = [:]
        let globalGraph: [String: Set<String>] = [
            "Parent": Set(["UIViewController"])
        ]
        let moduleSymbols: Set<String> = ["UIViewController"]

        let result = analyzer.hasTransitiveAncestorInModule(
            typeInheritances: typeInheritances,
            globalGraph: globalGraph,
            moduleSymbols: moduleSymbols
        )

        #expect(result == false)
    }

    @Test
    func testHasTransitiveAncestorHandlesCyclicInheritance() {
        let analyzer = makeAnalyzer()

        // Artificial cycle: A → B → C → A (should not infinite loop)
        let typeInheritances: [String: Set<String>] = [
            "A": Set(["B"])
        ]
        let globalGraph: [String: Set<String>] = [
            "A": Set(["B"]),
            "B": Set(["C"]),
            "C": Set(["A"])
        ]
        let moduleSymbols: Set<String> = ["UIViewController"]

        let result = analyzer.hasTransitiveAncestorInModule(
            typeInheritances: typeInheritances,
            globalGraph: globalGraph,
            moduleSymbols: moduleSymbols
        )

        #expect(result == false)
    }

    @Test
    func testHasTransitiveAncestorMultipleTypesInFile() {
        let analyzer = makeAnalyzer()

        // File has two types: one with a matching ancestor, one without
        let typeInheritances: [String: Set<String>] = [
            "PlainStruct": Set(["Codable"]),
            "Child": Set(["Parent"])
        ]
        let globalGraph: [String: Set<String>] = [
            "PlainStruct": Set(["Codable"]),
            "Child": Set(["Parent"]),
            "Parent": Set(["UIViewController"])
        ]
        let moduleSymbols: Set<String> = ["UIViewController", "UIView"]

        let result = analyzer.hasTransitiveAncestorInModule(
            typeInheritances: typeInheritances,
            globalGraph: globalGraph,
            moduleSymbols: moduleSymbols
        )

        #expect(result == true)
    }

    @Test
    func testHasTransitiveAncestorWithProtocolConformanceFromModule() {
        let analyzer = makeAnalyzer()

        // Type conforms to a protocol from the module
        let typeInheritances: [String: Set<String>] = [
            "MyObject": Set(["NSCoding"])
        ]
        let globalGraph: [String: Set<String>] = [
            "MyObject": Set(["NSCoding"])
        ]
        let moduleSymbols: Set<String> = ["NSCoding", "NSObject", "NSCoder"]

        let result = analyzer.hasTransitiveAncestorInModule(
            typeInheritances: typeInheritances,
            globalGraph: globalGraph,
            moduleSymbols: moduleSymbols
        )

        #expect(result == true)
    }

    @Test
    func testHasTransitiveAncestorUnknownParentNotInGraph() {
        let analyzer = makeAnalyzer()

        // Parent is not in the global graph (maybe from a module not analyzed)
        let typeInheritances: [String: Set<String>] = [
            "Child": Set(["UnknownParent"])
        ]
        let globalGraph: [String: Set<String>] = [
            "Child": Set(["UnknownParent"])
        ]
        let moduleSymbols: Set<String> = ["UIViewController"]

        let result = analyzer.hasTransitiveAncestorInModule(
            typeInheritances: typeInheritances,
            globalGraph: globalGraph,
            moduleSymbols: moduleSymbols
        )

        #expect(result == false)
    }

    @Test
    func testHasTransitiveAncestorParentWithMultipleConformances() {
        let analyzer = makeAnalyzer()

        // Parent inherits from UIViewController and conforms to UITableViewDelegate
        let typeInheritances: [String: Set<String>] = [
            "Child": Set(["Parent"])
        ]
        let globalGraph: [String: Set<String>] = [
            "Child": Set(["Parent"]),
            "Parent": Set(["UIViewController", "UITableViewDelegate"])
        ]
        let moduleSymbols: Set<String> = ["UITableViewDelegate", "UITableViewDataSource"]

        let result = analyzer.hasTransitiveAncestorInModule(
            typeInheritances: typeInheritances,
            globalGraph: globalGraph,
            moduleSymbols: moduleSymbols
        )

        #expect(result == true)
    }

    @Test
    func testEndToEndVisitorCollectionAndTransitiveCheck() {
        let parentSource = """
        import UIKit

        class Parent: UIViewController {
        }
        """

        let childSource = """
        import UIKit

        class Child: Parent {
            override func viewDidLoad() {
                super.viewDidLoad()
                view.backgroundColor = .red
            }
        }
        """

        let parentFile = Parser.parse(source: parentSource)
        let parentVisitor = ImportUsageVisitor(
            filePath: "/test/Parent.swift",
            sourceFile: parentFile
        )
        parentVisitor.walk(parentFile)

        let childFile = Parser.parse(source: childSource)
        let childVisitor = ImportUsageVisitor(
            filePath: "/test/Child.swift",
            sourceFile: childFile
        )
        childVisitor.walk(childFile)

        let parentResult = parentVisitor.result
        let childResult = childVisitor.result

        let analyzer = makeAnalyzer()
        let globalGraph = analyzer.buildGlobalInheritanceGraph([parentResult, childResult])

        // Simulate UIKit module symbols
        let uikitSymbols: Set<String> = ["UIViewController", "UIView", "UIColor", "UITableView"]

        // Parent file directly references UIViewController — no transitive check needed
        let parentDirectMatch = !uikitSymbols.isDisjoint(with: parentResult.usedIdentifiers)
        #expect(parentDirectMatch == true)

        // Child file does NOT directly reference any UIKit top-level symbol
        let childDirectMatch = !uikitSymbols.isDisjoint(with: childResult.usedIdentifiers)
        #expect(childDirectMatch == false)

        // But Child has a transitive ancestor (UIViewController) in UIKit
        let childTransitiveMatch = analyzer.hasTransitiveAncestorInModule(
            typeInheritances: childResult.typeInheritances,
            globalGraph: globalGraph,
            moduleSymbols: uikitSymbols
        )
        #expect(childTransitiveMatch == true)
    }

    @Test
    func testEndToEndNoFalsePositiveForUnrelatedImport() {
        let source = """
        import SomeFramework

        class PlainClass {
            var x = 0
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ImportUsageVisitor(
            filePath: "/test/file.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let result = visitor.result
        let analyzer = makeAnalyzer()
        let globalGraph = analyzer.buildGlobalInheritanceGraph([result])

        let frameworkSymbols: Set<String> = ["FrameworkBaseClass", "FrameworkProtocol"]

        let directMatch = !frameworkSymbols.isDisjoint(with: result.usedIdentifiers)
        #expect(directMatch == false)

        let transitiveMatch = analyzer.hasTransitiveAncestorInModule(
            typeInheritances: result.typeInheritances,
            globalGraph: globalGraph,
            moduleSymbols: frameworkSymbols
        )
        #expect(transitiveMatch == false)
    }

    @Test
    func testEndToEndThreeLayerInheritanceAcrossFiles() {
        let grandparentSource = """
        import FrameworkX

        class GrandParent: FrameworkBaseClass {
        }
        """

        let parentSource = """
        class Parent: GrandParent {
        }
        """

        let childSource = """
        import FrameworkX

        class Child: Parent {
            func doWork() {
                someMethod()
            }
        }
        """

        let grandparentFile = Parser.parse(source: grandparentSource)
        let grandparentVisitor = ImportUsageVisitor(
            filePath: "/test/GrandParent.swift",
            sourceFile: grandparentFile
        )
        grandparentVisitor.walk(grandparentFile)

        let parentFile = Parser.parse(source: parentSource)
        let parentVisitor = ImportUsageVisitor(
            filePath: "/test/Parent.swift",
            sourceFile: parentFile
        )
        parentVisitor.walk(parentFile)

        let childFile = Parser.parse(source: childSource)
        let childVisitor = ImportUsageVisitor(
            filePath: "/test/Child.swift",
            sourceFile: childFile
        )
        childVisitor.walk(childFile)

        let allResults = [grandparentVisitor.result, parentVisitor.result, childVisitor.result]
        let analyzer = makeAnalyzer()
        let globalGraph = analyzer.buildGlobalInheritanceGraph(allResults)

        let frameworkSymbols: Set<String> = ["FrameworkBaseClass", "FrameworkHelper"]

        // GrandParent directly uses FrameworkBaseClass
        let grandparentDirect = !frameworkSymbols.isDisjoint(with: grandparentVisitor.result.usedIdentifiers)
        #expect(grandparentDirect == true)

        // Child does not directly reference any FrameworkX symbol
        let childDirect = !frameworkSymbols.isDisjoint(with: childVisitor.result.usedIdentifiers)
        #expect(childDirect == false)

        // But Child → Parent → GrandParent → FrameworkBaseClass, so transitive check passes
        let childTransitive = analyzer.hasTransitiveAncestorInModule(
            typeInheritances: childVisitor.result.typeInheritances,
            globalGraph: globalGraph,
            moduleSymbols: frameworkSymbols
        )
        #expect(childTransitive == true)
    }

    @Test
    func testCrossFileImportLeakingPreservesImport() {
        // Parent.swift imports FrameworkX but doesn't use any of its symbols.
        // Child.swift uses FrameworkWidget (a FrameworkX symbol) without importing it,
        // relying on import leaking within the same module.
        // The tool must NOT flag Parent.swift's import as unused.

        let parentResult = ImportUsageResult(
            imports: [ImportInfo(moduleName: "FrameworkX", line: 1, filePath: "/test/Parent.swift")],
            usedIdentifiers: [],
            typeInheritances: [:]
        )
        let childResult = ImportUsageResult(
            imports: [],
            usedIdentifiers: Set(["FrameworkWidget", "Parent"]),
            typeInheritances: ["Child": Set(["Parent"])]
        )

        let moduleSymbolCache: [String: Set<String>] = [
            "FrameworkX": Set(["FrameworkWidget", "FrameworkHelper", "FrameworkBase"])
        ]
        let alwaysNeeded: Set<String> = ["Swift", "Foundation"]

        let analyzer = makeAnalyzer()
        let dependentModules = analyzer.findCrossFileDependentModules(
            importResults: [parentResult, childResult],
            moduleSymbolCache: moduleSymbolCache,
            alwaysNeededModules: alwaysNeeded
        )

        // FrameworkX is cross-file dependent because Child.swift uses FrameworkWidget
        // without importing FrameworkX
        #expect(dependentModules.contains("FrameworkX"))
    }

    @Test
    func testCrossFileImportLeakingNotTriggeredWhenFileImportsModule() {
        // If the file that uses FrameworkX symbols also imports FrameworkX,
        // there is no cross-file leaking — the file is self-sufficient.

        let fileA = ImportUsageResult(
            imports: [ImportInfo(moduleName: "FrameworkX", line: 1, filePath: "/test/A.swift")],
            usedIdentifiers: Set(["FrameworkWidget"]),
            typeInheritances: [:]
        )
        let fileB = ImportUsageResult(
            imports: [ImportInfo(moduleName: "FrameworkX", line: 1, filePath: "/test/B.swift")],
            usedIdentifiers: [],
            typeInheritances: [:]
        )

        let moduleSymbolCache: [String: Set<String>] = [
            "FrameworkX": Set(["FrameworkWidget", "FrameworkHelper"])
        ]
        let alwaysNeeded: Set<String> = ["Swift", "Foundation"]

        let analyzer = makeAnalyzer()
        let dependentModules = analyzer.findCrossFileDependentModules(
            importResults: [fileA, fileB],
            moduleSymbolCache: moduleSymbolCache,
            alwaysNeededModules: alwaysNeeded
        )

        // No cross-file dependency: the file that uses FrameworkWidget also imports FrameworkX
        #expect(dependentModules.isEmpty)
    }

    @Test
    func testCrossFileImportLeakingSkipsAlwaysNeededModules() {
        let fileResult = ImportUsageResult(
            imports: [],
            usedIdentifiers: Set(["NSObject", "URL"]),
            typeInheritances: [:]
        )

        let moduleSymbolCache: [String: Set<String>] = [
            "Foundation": Set(["NSObject", "URL", "Data"])
        ]
        let alwaysNeeded: Set<String> = ["Swift", "Foundation"]

        let analyzer = makeAnalyzer()
        let dependentModules = analyzer.findCrossFileDependentModules(
            importResults: [fileResult],
            moduleSymbolCache: moduleSymbolCache,
            alwaysNeededModules: alwaysNeeded
        )

        #expect(dependentModules.isEmpty)
    }

    @Test
    func testCrossFileImportLeakingMultipleModules() {
        // File uses symbols from two different modules without importing either.
        let leakingFile = ImportUsageResult(
            imports: [],
            usedIdentifiers: Set(["WidgetA", "HelperB"]),
            typeInheritances: [:]
        )
        let providerA = ImportUsageResult(
            imports: [ImportInfo(moduleName: "ModuleA", line: 1, filePath: "/test/A.swift")],
            usedIdentifiers: Set(["WidgetA"]),
            typeInheritances: [:]
        )
        let providerB = ImportUsageResult(
            imports: [ImportInfo(moduleName: "ModuleB", line: 1, filePath: "/test/B.swift")],
            usedIdentifiers: [],
            typeInheritances: [:]
        )

        let moduleSymbolCache: [String: Set<String>] = [
            "ModuleA": Set(["WidgetA", "OtherA"]),
            "ModuleB": Set(["HelperB", "OtherB"])
        ]
        let alwaysNeeded: Set<String> = ["Swift", "Foundation"]

        let analyzer = makeAnalyzer()
        let dependentModules = analyzer.findCrossFileDependentModules(
            importResults: [leakingFile, providerA, providerB],
            moduleSymbolCache: moduleSymbolCache,
            alwaysNeededModules: alwaysNeeded
        )

        #expect(dependentModules.contains("ModuleA"))
        #expect(dependentModules.contains("ModuleB"))
    }

    @Test
    func testCrossFileImportLeakingNoMatchReturnsEmpty() {
        // File uses identifiers that don't match any module's exported symbols.
        let fileResult = ImportUsageResult(
            imports: [],
            usedIdentifiers: Set(["myLocalFunc", "localVar"]),
            typeInheritances: [:]
        )

        let moduleSymbolCache: [String: Set<String>] = [
            "SomeFramework": Set(["FrameworkWidget", "FrameworkHelper"])
        ]
        let alwaysNeeded: Set<String> = ["Swift", "Foundation"]

        let analyzer = makeAnalyzer()
        let dependentModules = analyzer.findCrossFileDependentModules(
            importResults: [fileResult],
            moduleSymbolCache: moduleSymbolCache,
            alwaysNeededModules: alwaysNeeded
        )

        #expect(dependentModules.isEmpty)
    }
}
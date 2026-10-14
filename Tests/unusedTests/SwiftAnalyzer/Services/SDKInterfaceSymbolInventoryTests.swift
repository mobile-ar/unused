import SwiftParser
import Synchronization
import Testing
@testable import unused

struct SDKInterfaceSymbolInventoryTests {
    @Test
    func parsesOperatorsMacrosAssociatedTypesAndImplicitCallableExports() {
        let source = """
        infix operator <~>
        prefix operator ~~~
        postfix operator ^^^
        public func <~> (lhs: Int, rhs: Int) -> Int
        public macro makeValue() -> Int = #externalMacro(module: "Plugin", type: "MakeValue")
        public protocol CollectionLike { associatedtype Element }
        public struct Container {
            public struct Nested {}
            public init()
            public subscript(index: Int) -> Int { get }
        }
        """
        let index = SDKInterfaceIndex(moduleInterface: source, moduleName: "Memory")
        #expect(index.symbolInventory.isComplete)
        #expect(index.symbolInventory.symbols == [
            "<~>", "~~~", "^^^", "makeValue", "CollectionLike", "Element", "Container", "Nested", "init", "subscript"
        ])
    }

    @Test
    func successfullyOpenedMalformedInterfacesRemainIncomplete() async {
        let client = SwiftInterfaceClient(moduleInterfaceProvider: { _ in "public struct Known {}\npublic struct Broken {" })
        let inventory = await client.getSymbolInventory(inModule: "Broken")
        #expect(inventory.symbols.contains("Known"))
        #expect(inventory.uncertainties.contains(.recoveredSyntax))
        #expect(!inventory.isComplete)
        #expect(await client.getSymbolInventory(inModule: "Broken") == inventory)
    }

    @Test(arguments: ["", "   \n", "// Interface stub", "import ClangOnly"])
    func declarationFreeInterfacesAreNotEvidenceOfCompleteEmptyExports(_ source: String) async {
        let client = SwiftInterfaceClient(moduleInterfaceProvider: { _ in source })
        let inventory = await client.getSymbolInventory(inModule: "Stub")
        #expect(inventory.symbols.isEmpty)
        #expect(inventory.uncertainties.contains(.emptyInterface))
        #expect(!inventory.isComplete)
        #expect(await client.getSymbolInventory(inModule: "Stub") == inventory)
    }

    @Test
    func reexportsResolveTransitivelyAndIgnoreOrdinaryDependencyImports() async {
        let loads = Mutex<[String: Int]>([:])
        let sources = [
            "Facade": "@_exported import Middle\nimport PrivateDependency\npublic struct Own {}",
            "Middle": "@_exported import Leaf",
            "Leaf": """
            public struct Nested {}
            infix operator <~>
            public macro create() -> Int = #externalMacro(module: "Plugin", type: "Create")
            """
        ]
        let client = SwiftInterfaceClient(moduleInterfaceProvider: { name in
            loads.withLock { $0[name, default: 0] += 1 }
            return sources[name]
        })
        let inventory = await client.getSymbolInventory(inModule: "Facade")
        #expect(inventory.isComplete)
        #expect(inventory.reexportedModules.isEmpty)
        #expect(inventory.symbols == ["Own", "Nested", "<~>", "create"])
        #expect(await client.getSymbolInventory(inModule: "Facade") == inventory)
        #expect(await client.getSymbolInventory(inModule: "Leaf").symbols == ["Nested", "<~>", "create"])
        #expect(loads.withLock { $0 } == ["Facade": 1, "Middle": 1, "Leaf": 1])
    }

    @Test
    func unavailableAndIncompleteReexportsPreserveKnownSymbolsAndUncertainty() async {
        let sources = [
            "Facade": "@_exported import Missing\n@_exported import Broken\npublic struct Own {}",
            "Broken": "public struct Known {}\npublic struct Incomplete {"
        ]
        let client = SwiftInterfaceClient(moduleInterfaceProvider: { sources[$0] })
        let inventory = await client.getSymbolInventory(inModule: "Facade")
        #expect(inventory.symbols.isSuperset(of: ["Own", "Known"]))
        #expect(inventory.uncertainties.contains(.unavailableModule("Missing")))
        #expect(inventory.uncertainties.contains(.recoveredSyntax))
        #expect(!inventory.isComplete)
        #expect(await client.getSymbolInventory(inModule: "Facade") == inventory)
    }

    @Test
    func cyclicAndDiamondReexportsHaveCompleteIndependentSnapshots() async {
        let loads = Mutex<[String: Int]>([:])
        let inventories = [
            "A": SDKInterfaceSymbolInventory(symbols: ["a"], reexportedModules: ["B", "C"]),
            "B": SDKInterfaceSymbolInventory(symbols: ["b"], reexportedModules: ["A", "D"]),
            "C": SDKInterfaceSymbolInventory(symbols: ["c"], reexportedModules: ["D"]),
            "D": SDKInterfaceSymbolInventory(symbols: ["d"])
        ]
        let client = SwiftInterfaceClient(symbolInventoryProvider: { name in
            loads.withLock { $0[name, default: 0] += 1 }
            return inventories[name]
        })
        let a = await client.getSymbolInventory(inModule: "A")
        let b = await client.getSymbolInventory(inModule: "B")
        let c = await client.getSymbolInventory(inModule: "C")
        #expect(a.isComplete && b.isComplete && c.isComplete)
        #expect(a.symbols == ["a", "b", "c", "d"])
        #expect(b.symbols == a.symbols)
        #expect(c.symbols == ["c", "d"])
        #expect(loads.withLock { $0 } == ["A": 1, "B": 1, "C": 1, "D": 1])
    }

    @Test
    func injectedInventoriesAreCachedIsolatedAndDoNotFallBackToSource() async {
        let loads = Mutex<[String: Int]>([:])
        let sourceLoads = Mutex<Int>(0)
        let first = SwiftInterfaceClient(
            moduleInterfaceProvider: { _ in
                sourceLoads.withLock { $0 += 1 }
                return "public struct ShouldNotLoad {}"
            },
            symbolInventoryProvider: { name in
                loads.withLock { $0[name, default: 0] += 1 }
                return name == "Empty" ? SDKInterfaceSymbolInventory() : nil
            }
        )
        let second = SwiftInterfaceClient(symbolInventoryProvider: { _ in SDKInterfaceSymbolInventory(symbols: ["Other"]) })
        let empty = await first.getSymbolInventory(inModule: "Empty")
        #expect(empty.isComplete)
        #expect(empty.symbols.isEmpty)
        #expect(await first.getSymbolInventory(inModule: "Empty") == empty)
        let missing = await first.getSymbolInventory(inModule: "Missing")
        #expect(missing.uncertainties == [.unavailableModule("Missing")])
        #expect(missing.symbols.isEmpty)
        #expect(!missing.isComplete)
        #expect(await first.getSymbolInventory(inModule: "Missing") == missing)
        #expect(await second.getSymbolInventory(inModule: "Empty").symbols == ["Other"])
        #expect(loads.withLock { $0 } == ["Empty": 1, "Missing": 1])
        #expect(sourceLoads.withLock { $0 } == 0)
    }

    @Test
    func concurrentInventoryQueriesReuseInjectedSnapshots() async {
        let loads = Mutex<Int>(0)
        let client = SwiftInterfaceClient(symbolInventoryProvider: { _ in
            loads.withLock { $0 += 1 }
            return SDKInterfaceSymbolInventory(symbols: ["Known"])
        })
        let results = await withTaskGroup(of: SDKInterfaceSymbolInventory.self, returning: [SDKInterfaceSymbolInventory].self) { group in
            for _ in 0..<20 {
                group.addTask { await client.getSymbolInventory(inModule: "Memory") }
            }
            var results: [SDKInterfaceSymbolInventory] = []
            for await result in group { results.append(result) }
            return results
        }
        #expect(results.count == 20)
        #expect(results.allSatisfy { $0.isComplete && $0.symbols == ["Known"] })
        #expect(loads.withLock { $0 } == 1)
    }

    @Test
    func sourceInventoryQueriesReuseTheProtocolAndWrapperCache() async {
        let loads = Mutex<Int>(0)
        let parses = Mutex<Int>(0)
        let cache = SDKInterfaceCache(
            moduleInterfaceProvider: { _ in
                loads.withLock { $0 += 1 }
                return "@propertyWrapper public struct Wrapper {}; public protocol P { func required() }"
            },
            indexParser: { source, name in
                parses.withLock { $0 += 1 }
                return SDKInterfaceIndex(moduleInterface: source, moduleName: name)
            }
        )
        let client = SwiftInterfaceClient(interfaceCache: cache)
        #expect(await client.getPropertyWrappers(inModule: "Memory") == ["Wrapper"])
        #expect(parses.withLock { $0 } == 0)
        #expect(await client.getSymbolInventory(inModule: "Memory").isComplete)
        #expect(await client.getProtocolRequirements(protocolName: "P", inModule: "Memory") == ["required"])
        #expect(loads.withLock { $0 } == 1)
        #expect(parses.withLock { $0 } == 1)
    }

    @Test
    func scopedReexportsCannotClaimCompleteWholeModuleResolution() async {
        let sources = [
            "Facade": "@_exported import struct Dependency.Known",
            "Dependency": "public struct Known {}"
        ]
        let client = SwiftInterfaceClient(moduleInterfaceProvider: { sources[$0] })
        let inventory = await client.getSymbolInventory(inModule: "Facade")
        #expect(inventory.symbols.contains("Known"))
        #expect(inventory.uncertainties.contains(.scopedReexport("Dependency.Known")))
        #expect(!inventory.isComplete)
    }

    @Test
    func retroactiveConformancesAndUnexpandedDeclarationsAreUncertain() {
        let conformance = SDKInterfaceIndex(moduleInterface: "extension Foreign.Type: Protocol {}", moduleName: "Memory")
        #expect(conformance.symbolInventory.uncertainties.contains(.implicitExports))
        #expect(!conformance.symbolInventory.isComplete)
        let expansion = SDKInterfaceIndex(moduleInterface: "#declareExports()", moduleName: "Memory")
        #expect(expansion.symbolInventory.uncertainties.contains(.macroExpansion))
        #expect(!expansion.symbolInventory.isComplete)
    }

    @Test
    func reexportedSymbolsKeepFacadeImportUsedWithoutNamingTheFacade() async {
        let sources = [
            "Facade": "@_exported import Original",
            "Original": "public struct Exported {}"
        ]
        let client = SwiftInterfaceClient(moduleInterfaceProvider: { sources[$0] })
        let syntax = Parser.parse(source: "import Facade\nlet value: Exported")
        let visitor = ImportUsageVisitor(filePath: "/fixtures/Facade.swift", sourceFile: syntax)
        visitor.walk(syntax)
        let result = visitor.result
        let inventory = await client.getSymbolInventory(inModule: "Facade")
        #expect(inventory.isComplete)
        #expect(!result.canProveUnused(result.imports[0], inventory: inventory))
    }

    @Test(arguments: [
        "@_exported import Overlay\npublic struct SwiftOnly {}",
        "import Overlay\npublic struct SwiftOnly {}",
        "// swift-module-flags: -module-name Overlay -import-underlying-module\npublic struct SwiftOnly {}"
    ])
    func swiftOverlaysDoNotClaimToInventoryUnderlyingClangSymbols(_ source: String) async {
        let client = SwiftInterfaceClient(moduleInterfaceProvider: { $0 == "Overlay" ? source : nil })
        let inventory = await client.getSymbolInventory(inModule: "Overlay")
        #expect(inventory.symbols == ["SwiftOnly"])
        #expect(inventory.uncertainties.contains(.underlyingModule))
        #expect(!inventory.isComplete)
        #expect(await client.getSymbolInventory(inModule: "Overlay") == inventory)
    }

    @Test(arguments: [
        "@GenerateMembers public struct Known {}",
        "@GenerateMembers public class Known {}",
        "@GenerateMembers public enum Known {}",
        "@GenerateMembers public actor Known {}",
        "@GenerateMembers public protocol Known {}",
        "@GenerateMembers public func known()",
        "@GenerateMembers public var known: Int { get }",
        "@GenerateMembers public typealias Known = Int",
        "@GenerateMembers public macro known() = #externalMacro(module: \"Plugin\", type: \"Known\")",
        "@GenerateMembers extension Known { public func known() }",
        "public protocol Known { @GenerateMembers associatedtype Element }",
        "public struct Known { @GenerateMembers public init() }",
        "public class Known { @GenerateMembers deinit {} }",
        "public struct Known { @GenerateMembers public subscript(_ index: Int) -> Int { get } }",
        "public enum Known { @GenerateMembers case value }",
        "#if ATTRIBUTES\n@GenerateMembers\n#endif\npublic struct Known {}"
    ])
    func unexpandedAttributeMacrosPreserveKnownExportsWithoutClaimingCompleteness(_ source: String) async {
        #expect(!Parser.parse(source: source).hasError)
        let client = SwiftInterfaceClient(moduleInterfaceProvider: { $0 == "Memory" ? source : nil })
        let inventory = await client.getSymbolInventory(inModule: "Memory")
        #expect(!inventory.symbols.isEmpty)
        #expect(inventory.uncertainties == [.attributeExpansion("GenerateMembers")])
        #expect(!inventory.isComplete)
    }

    @Test
    func qualifiedAttributeMacroUncertaintyPropagatesThroughReexports() async {
        let sources = [
            "Facade": "@_exported import Original",
            "Original": "@Generators.GenerateMembers public struct Known {}"
        ]
        let client = SwiftInterfaceClient(moduleInterfaceProvider: { sources[$0] })
        let inventory = await client.getSymbolInventory(inModule: "Facade")
        #expect(inventory.symbols == ["Known"])
        #expect(inventory.uncertainties == [.attributeExpansion("Generators.GenerateMembers")])
        #expect(!inventory.isComplete)
    }

    @Test
    func knownCompilerAnnotationsAndMacroRoleDeclarationsDoNotExpandExports() {
        let source = """
        @available(macOS 15, *) @frozen
        @propertyWrapper public struct Wrapper { public var wrappedValue: Int }
        @attached(member, names: arbitrary)
        public macro GenerateMembers() = #externalMacro(module: "Plugin", type: "GenerateMembers")
        @freestanding(expression)
        public macro makeValue() -> Int = #externalMacro(module: "Plugin", type: "MakeValue")
        """
        #expect(!Parser.parse(source: source).hasError)
        let inventory = SDKInterfaceIndex(moduleInterface: source, moduleName: "Memory").symbolInventory
        #expect(inventory.isComplete)
        #expect(inventory.symbols == ["Wrapper", "wrappedValue", "GenerateMembers", "makeValue"])
    }

    @Test
    func attributesInsideExecutableBodiesDoNotAffectTheExportInventory() {
        let source = "public func known() { @GenerateMembers struct Local {} }"
        #expect(!Parser.parse(source: source).hasError)
        let inventory = SDKInterfaceIndex(moduleInterface: source, moduleName: "Memory").symbolInventory
        #expect(inventory.isComplete)
        #expect(inventory.symbols == ["known"])
    }

    @Test
    func tupleBindingsAreFullyRepresentedRatherThanSilentlyOmitted() {
        let source = "public let (left, (middle, right)): (Int, (Int, Int))"
        #expect(!Parser.parse(source: source).hasError)
        let inventory = SDKInterfaceIndex(moduleInterface: source, moduleName: "Memory").symbolInventory
        #expect(inventory.isComplete)
        #expect(inventory.symbols == ["left", "middle", "right"])
    }

    @Test
    func precedenceRelationshipsAndMissingInitializersCannotSupportCompleteInventories() {
        let precedence = "precedencegroup Ordering { higherThan: AdditionPrecedence }"
        #expect(!Parser.parse(source: precedence).hasError)
        let precedenceInventory = SDKInterfaceIndex(moduleInterface: precedence, moduleName: "Memory").symbolInventory
        #expect(precedenceInventory.symbols == ["Ordering"])
        #expect(precedenceInventory.uncertainties == [.unrepresentedDeclaration])
        #expect(!precedenceInventory.isComplete)
        let missingInitializers = "@_hasMissingDesignatedInitializers public class Known {}"
        #expect(!Parser.parse(source: missingInitializers).hasError)
        let initializerInventory = SDKInterfaceIndex(moduleInterface: missingInitializers, moduleName: "Memory").symbolInventory
        #expect(initializerInventory.symbols == ["Known"])
        #expect(initializerInventory.uncertainties == [.implicitExports])
        #expect(!initializerInventory.isComplete)
    }

    @Test
    func unverifiedIndexesCannotClaimCompleteInventories() {
        #expect(!SDKInterfaceIndex(exportedSymbols: ["Known"]).symbolInventory.isComplete)
        #expect(!SDKInterfaceSymbolInventory(reexportedModules: ["Pending"]).isComplete)
    }
}

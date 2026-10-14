import Foundation
import Testing
@testable import unused

struct ImportFindingSafetyTests {
    private func analyze(_ sources: [String], inventories: [String: SDKInterfaceSymbolInventory]) async throws -> Report {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = try sources.enumerated().map { index, source in
            let file = directory.appendingPathComponent("Source\(index).swift")
            try source.write(to: file, atomically: true, encoding: .utf8)
            return file
        }
        let client = SwiftInterfaceClient(moduleInterfaceProvider: { _ in nil }, symbolInventoryProvider: { inventories[$0] })
        let analyzer = SwiftAnalyzer(directory: directory.path, swiftInterfaceClient: client,
            progressTrackerFactory: { total, prefix in
                ProgressTracker(total: total, prefix: prefix, render: { _ in }, finishLine: {})
            })
        return await analyzer.analyzeFiles(files)
    }

    @Test
    func completeInventoriesCanProveUnusedImports() async throws {
        let report = try await analyze(["import Library\nlet value = 1"], inventories: ["Library": SDKInterfaceSymbolInventory(symbols: ["LibraryType"])])
        #expect(report.unused.contains { $0.type == .import && $0.name == "Library" })
    }

    @Test
    func incompleteInventoriesCannotProveUnusedImports() async throws {
        let report = try await analyze(["import Library\nlet value = 1"], inventories: ["Library": SDKInterfaceSymbolInventory(symbols: ["LibraryType"], uncertainties: [.recoveredSyntax])])
        #expect(!report.unused.contains { $0.type == .import })
    }

    @Test
    func unavailableInventoriesCannotProveUnusedImports() async throws {
        let report = try await analyze(["import Unknown\nlet value = 1"], inventories: [:])
        #expect(!report.unused.contains { $0.type == .import })
    }

    @Test(arguments: [
        "let value: Library.Outer.Inner",
        "let value: Outer.Inner",
        "let value = lhs <~> rhs",
        "let value = ~~~input",
        "let value = input^^^",
        "let value = #makeValue()",
        "@Generate struct Subject {}",
        "let value = .inferredCase"
    ])
    func explicitAndUncertainUsesRetainImports(_ usage: String) async throws {
        let report = try await analyze(["import Library\n\(usage)"], inventories: [
            "Library": SDKInterfaceSymbolInventory(symbols: ["Inner", "<~>", "~~~", "^^^", "makeValue", "Generate"])
        ])
        #expect(!report.unused.contains { $0.type == .import })
    }

    @Test
    func symbolsReexportedByFacadesRetainFacadeImports() async throws {
        let report = try await analyze(["import Facade\nlet value: Exported"], inventories: [
            "Facade": SDKInterfaceSymbolInventory(symbols: ["Own"], reexportedModules: ["Original"]),
            "Original": SDKInterfaceSymbolInventory(symbols: ["Exported"])
        ])
        #expect(!report.unused.contains { $0.type == .import })
    }

    @Test
    func unresolvedReexportsRetainImports() async throws {
        let report = try await analyze(["import Facade\nlet value = 1"], inventories: [
            "Facade": SDKInterfaceSymbolInventory(symbols: ["Own"], reexportedModules: ["Unavailable"])
        ])
        #expect(!report.unused.contains { $0.type == .import })
    }

    @Test
    func exportedImportsRemainPublicDependencies() async throws {
        let report = try await analyze(["@_exported import Library"], inventories: ["Library": SDKInterfaceSymbolInventory(symbols: ["Exported"])])
        #expect(!report.unused.contains { $0.type == .import })
    }

    @Test(arguments: ["let value: Exported", "let value = lhs <~> rhs", "let value = #unknownMacro()"])
    func crossFileUsesAndUncertaintyRetainPotentiallyLeakedImports(_ usage: String) async throws {
        let report = try await analyze(["import Library", usage], inventories: ["Library": SDKInterfaceSymbolInventory(symbols: ["Exported", "<~>"])])
        #expect(!report.unused.contains { $0.type == .import })
    }

    @Test(arguments: [false, true])
    func implicitCallableExtensionsRetainImportsAcrossFiles(_ crossFile: Bool) async throws {
        for (usage, symbol) in [
            ("let result = action()", "callAsFunction"),
            (#"let result = "\(hex: 42)""#, "appendInterpolation")
        ] {
            let sources = crossFile ? ["import Extensions", usage] : ["import Extensions\n\(usage)"]
            let report = try await analyze(sources, inventories: ["Extensions": SDKInterfaceSymbolInventory(symbols: [symbol])])
            #expect(!report.unused.contains { $0.type == .import })
        }
    }

    @Test
    func qualifiedTransitiveAncestorsRetainImportsAcrossFiles() async throws {
        let report = try await analyze(["class Parent: Library.Base {}", "import Library\nclass Child: Parent {}"], inventories: ["Library": SDKInterfaceSymbolInventory(symbols: ["Base"])])
        #expect(!report.unused.contains { $0.type == .import })
    }
}

import SwiftParser
import Testing
@testable import unused

struct ImportInventoryUsageTests {
    private func usage(_ source: String) -> ImportUsageResult {
        let syntax = Parser.parse(source: source)
        let visitor = ImportUsageVisitor(filePath: "/fixtures/Imports.swift", sourceFile: syntax)
        visitor.walk(syntax)
        return visitor.result
    }

    @Test
    func qualifiedMemberTypesKeepLeavesAndCanonicalPaths() {
        let result = usage("""
        import Shapes
        struct Value: Shapes.Outer.`repeat`<Int> {}
        let value: Shapes.Outer.`repeat`<String>?
        """)
        #expect(result.usedIdentifiers.isSuperset(of: ["Shapes", "Outer", "repeat", "Int", "String"]))
        #expect(result.qualifiedReferences.contains("Shapes.Outer.repeat"))
        #expect(result.typeInheritances["Value"] == ["Shapes.Outer.repeat", "repeat"])
        #expect(result.uncertainties.isEmpty)
        #expect(!result.canProveUnused(result.imports[0], inventory: SDKInterfaceSymbolInventory(symbols: ["repeat"])))
    }

    @Test
    func qualifiedExpressionAndAttributeNamesAreNormalized() {
        let result = usage("""
        import Tools
        @Tools.`repeat` struct Value {}
        let value = Tools.Factory<Int>.`default`()
        """)
        #expect(result.usedIdentifiers.contains("default"))
        #expect(result.qualifiedReferences.contains("Tools.Factory.default"))
        #expect(result.qualifiedReferences.contains("Tools.repeat"))
        #expect(result.uncertainties.contains(.attributeExpansion("Tools.repeat")))
    }

    @Test
    func operatorOnlyUsesRetainTheirImports() async {
        let inventory = SDKInterfaceSymbolInventory(symbols: ["<~>", "~~~", "^^^"])
        let client = SwiftInterfaceClient(symbolInventoryProvider: { $0 == "Operators" ? inventory : nil })
        let result = usage("""
        import Operators
        let first = 1 <~> 2
        let second = ~~~first
        let third = second^^^
        """)
        #expect(result.usedIdentifiers.isSuperset(of: ["<~>", "~~~", "^^^"]))
        #expect(result.uncertainties.isEmpty)
        let resolved = await client.getSymbolInventory(inModule: "Operators")
        #expect(resolved.isComplete)
        #expect(!result.canProveUnused(result.imports[0], inventory: resolved))
    }

    @Test
    func unusedCompleteInjectedInventorySupportsALocalProof() async {
        let client = SwiftInterfaceClient(symbolInventoryProvider: { name in
            name == "UnusedLibrary" ? SDKInterfaceSymbolInventory(symbols: ["UnusedType"]) : nil
        })
        let result = usage("import UnusedLibrary\nlet number = 42")
        let inventory = await client.getSymbolInventory(inModule: "UnusedLibrary")
        #expect(result.canProveUnused(result.imports[0], inventory: inventory))
        #expect(result.canProveUnused(result.imports[0], inventory: SDKInterfaceSymbolInventory()))
    }

    @Test
    func partialInventoryNeverProvesAbsence() async {
        let client = SwiftInterfaceClient(symbolInventoryProvider: { _ in
            SDKInterfaceSymbolInventory(symbols: ["Known"], uncertainties: [.recoveredSyntax])
        })
        let result = usage("import Partial\nlet value = 1")
        let inventory = await client.getSymbolInventory(inModule: "Partial")
        #expect(!result.canProveUnused(result.imports[0], inventory: inventory))
        let missing = await SwiftInterfaceClient(symbolInventoryProvider: { _ in nil })
            .getSymbolInventory(inModule: "Missing")
        #expect(!result.canProveUnused(result.imports[0], inventory: missing))
    }

    @Test
    func recoveredSourceRetainsEvenCompleteInventories() {
        let result = usage("import Library\nlet value:")
        #expect(result.uncertainties.contains(.recoveredSyntax))
        #expect(!result.canProveUnused(result.imports[0], inventory: SDKInterfaceSymbolInventory(symbols: ["Other"])))
    }

    @Test
    func expressionAndDeclarationMacrosRetainPossibleGeneratedDependencies() {
        let result = usage("""
        import Macros
        import GeneratedDependency
        let value = #makeValue()
        #declareTypes()
        """)
        #expect(result.usedIdentifiers.isSuperset(of: ["makeValue", "declareTypes"]))
        #expect(result.uncertainties.contains(.macroExpansion("makeValue")))
        #expect(result.uncertainties.contains(.macroExpansion("declareTypes")))
        #expect(!result.canProveUnused(result.imports[1], inventory: SDKInterfaceSymbolInventory(symbols: ["HiddenGeneratedUse"])))
    }

    @Test
    func attachedMacrosAndWrappersAreConservativelyUncertain() {
        let result = usage("""
        import Attributes
        @GenerateMembers struct Value {}
        @Stored var value: Int
        """)
        #expect(result.usedIdentifiers.isSuperset(of: ["GenerateMembers", "Stored"]))
        #expect(result.uncertainties.contains(.attributeExpansion("GenerateMembers")))
        #expect(result.uncertainties.contains(.attributeExpansion("Stored")))
        #expect(!result.canProveUnused(result.imports[0], inventory: SDKInterfaceSymbolInventory()))
    }

    @Test
    func implicitMemberResolutionIsUncertainAndStillCollectsNames() {
        let result = usage("import Members\nlet value = .inferred")
        #expect(result.usedIdentifiers.contains("inferred"))
        #expect(result.uncertainties.contains(.implicitMember))
        #expect(!result.canProveUnused(result.imports[0], inventory: SDKInterfaceSymbolInventory(symbols: ["Other"])))
    }

    @Test
    func reexportedImportsRemainRequiredWithoutLocalUses() {
        let result = usage("@_exported import PublicDependency")
        #expect(result.imports[0].isReexported)
        #expect(result.uncertainties.isEmpty)
        #expect(result.imports[0].uncertainties.isEmpty)
        #expect(!result.canProveUnused(result.imports[0], inventory: SDKInterfaceSymbolInventory(symbols: ["Other"])))
    }

    @Test
    func restrictedAndSubmoduleImportsHaveImportLocalUncertainty() {
        let result = usage("""
        @testable import InternalLibrary
        @_spi(Testing) import SPILibrary
        import Library.Submodule
        import struct Shapes.Point
        """)
        #expect(result.imports[0].uncertainties == [.restrictedImport])
        #expect(result.imports[1].uncertainties == [.restrictedImport])
        #expect(result.imports[2].uncertainties == [.submoduleImport])
        #expect(result.imports[3].uncertainties.isEmpty)
        #expect(result.uncertainties.isEmpty)
        #expect(!result.canProveUnused(result.imports[0], inventory: SDKInterfaceSymbolInventory()))
        #expect(!result.canProveUnused(result.imports[2], inventory: SDKInterfaceSymbolInventory()))
    }

    @Test
    func explicitModuleQualificationRetainsAnImportEvenWithAnEmptyInventory() {
        let result = usage("import Library\nlet value: Library.Unknown")
        #expect(!result.canProveUnused(result.imports[0], inventory: SDKInterfaceSymbolInventory()))
    }

    @Test
    func keyPathsSubscriptsAndConstructorsCollectImplicitCallableNames() {
        let result = usage(#"""
        import Extensions
        let path = \Container.addedProperty
        let item = items[0]
        let value = Container()
        """#)
        #expect(result.usedIdentifiers.isSuperset(of: ["addedProperty", "subscript", "init"]))
        #expect(!result.canProveUnused(result.imports[0], inventory: SDKInterfaceSymbolInventory(symbols: ["subscript"])))
        #expect(!result.canProveUnused(result.imports[0], inventory: SDKInterfaceSymbolInventory(symbols: ["init"])))
    }

    @Test
    func implicitCallsAndCustomStringInterpolationCollectExportedMemberNames() {
        let result = usage(#"""
        import Extensions
        let first = action()
        let second = "\(hex: 42)"
        """#)
        #expect(result.uncertainties.isEmpty)
        #expect(result.usedIdentifiers.isSuperset(of: ["callAsFunction", "appendInterpolation"]))
        #expect(!result.canProveUnused(result.imports[0], inventory: SDKInterfaceSymbolInventory(symbols: ["callAsFunction"])))
        #expect(!result.canProveUnused(result.imports[0], inventory: SDKInterfaceSymbolInventory(symbols: ["appendInterpolation"])))
    }

    @Test
    func modelsRemainConstructibleWithExistingMemberwiseArguments() {
        let importInfo = ImportInfo(moduleName: "Library", line: 1, filePath: "/file.swift")
        let result = ImportUsageResult(imports: [importInfo], usedIdentifiers: [], typeInheritances: [:])
        #expect(!importInfo.isReexported)
        #expect(importInfo.uncertainties.isEmpty)
        #expect(result.uncertainties.isEmpty)
        #expect(result.qualifiedReferences.isEmpty)
    }
}

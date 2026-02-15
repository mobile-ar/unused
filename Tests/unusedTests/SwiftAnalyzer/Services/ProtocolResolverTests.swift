//
//  Created by Fernando Romiti on 14/02/2026.
//

import Testing
import SwiftSyntax
import SwiftParser
@testable import unused

struct ProtocolResolverTests {

    private let swiftInterfaceClient = SwiftInterfaceClient()

    @Test
    func testResolveInheritedRequirementsPropagatesFromParent() {
        let resolver = ProtocolResolver(
            protocolRequirements: [
                "ParentProtocol": Set(["parentMethod", "parentProperty"]),
                "ChildProtocol": Set(["childMethod"])
            ],
            protocolInheritance: [
                "ChildProtocol": Set(["ParentProtocol"])
            ],
            projectDefinedProtocols: Set(["ParentProtocol", "ChildProtocol"]),
            importedModules: Set(),
            conformedProtocols: Set(),
            swiftInterfaceClient: swiftInterfaceClient
        )

        resolver.resolveInheritedRequirements()

        #expect(resolver.protocolRequirements["ChildProtocol"]?.contains("childMethod") == true)
        #expect(resolver.protocolRequirements["ChildProtocol"]?.contains("parentMethod") == true)
        #expect(resolver.protocolRequirements["ChildProtocol"]?.contains("parentProperty") == true)
        #expect(resolver.protocolRequirements["ParentProtocol"]?.contains("parentMethod") == true)
        #expect(resolver.protocolRequirements["ParentProtocol"]?.contains("parentProperty") == true)
    }

    @Test
    func testResolveInheritedRequirementsMultiLevel() {
        let resolver = ProtocolResolver(
            protocolRequirements: [
                "Grandparent": Set(["grandMethod"]),
                "Parent": Set(["parentMethod"]),
                "Child": Set(["childMethod"])
            ],
            protocolInheritance: [
                "Parent": Set(["Grandparent"]),
                "Child": Set(["Parent"])
            ],
            projectDefinedProtocols: Set(["Grandparent", "Parent", "Child"]),
            importedModules: Set(),
            conformedProtocols: Set(),
            swiftInterfaceClient: swiftInterfaceClient
        )

        resolver.resolveInheritedRequirements()

        #expect(resolver.protocolRequirements["Child"]?.contains("childMethod") == true)
        #expect(resolver.protocolRequirements["Child"]?.contains("parentMethod") == true)
        #expect(resolver.protocolRequirements["Child"]?.contains("grandMethod") == true)
        #expect(resolver.protocolRequirements["Parent"]?.contains("parentMethod") == true)
        #expect(resolver.protocolRequirements["Parent"]?.contains("grandMethod") == true)
    }

    @Test
    func testResolveInheritedRequirementsDiamondInheritance() {
        let resolver = ProtocolResolver(
            protocolRequirements: [
                "Root": Set(["rootMethod"]),
                "BranchA": Set(["branchAMethod"]),
                "BranchB": Set(["branchBMethod"]),
                "Leaf": Set(["leafMethod"])
            ],
            protocolInheritance: [
                "BranchA": Set(["Root"]),
                "BranchB": Set(["Root"]),
                "Leaf": Set(["BranchA", "BranchB"])
            ],
            projectDefinedProtocols: Set(["Root", "BranchA", "BranchB", "Leaf"]),
            importedModules: Set(),
            conformedProtocols: Set(),
            swiftInterfaceClient: swiftInterfaceClient
        )

        resolver.resolveInheritedRequirements()

        #expect(resolver.protocolRequirements["Leaf"]?.contains("leafMethod") == true)
        #expect(resolver.protocolRequirements["Leaf"]?.contains("branchAMethod") == true)
        #expect(resolver.protocolRequirements["Leaf"]?.contains("branchBMethod") == true)
        #expect(resolver.protocolRequirements["Leaf"]?.contains("rootMethod") == true)
        #expect(resolver.protocolRequirements["BranchA"]?.contains("rootMethod") == true)
        #expect(resolver.protocolRequirements["BranchB"]?.contains("rootMethod") == true)
    }

    @Test
    func testResolveInheritedRequirementsMultipleParents() {
        let resolver = ProtocolResolver(
            protocolRequirements: [
                "ProtocolA": Set(["methodA"]),
                "ProtocolB": Set(["methodB"]),
                "Combined": Set(["ownMethod"])
            ],
            protocolInheritance: [
                "Combined": Set(["ProtocolA", "ProtocolB"])
            ],
            projectDefinedProtocols: Set(["ProtocolA", "ProtocolB", "Combined"]),
            importedModules: Set(),
            conformedProtocols: Set(),
            swiftInterfaceClient: swiftInterfaceClient
        )

        resolver.resolveInheritedRequirements()

        #expect(resolver.protocolRequirements["Combined"]?.contains("ownMethod") == true)
        #expect(resolver.protocolRequirements["Combined"]?.contains("methodA") == true)
        #expect(resolver.protocolRequirements["Combined"]?.contains("methodB") == true)
    }

    @Test
    func testResolveInheritedRequirementsNoInheritance() {
        let resolver = ProtocolResolver(
            protocolRequirements: [
                "Standalone": Set(["doSomething"])
            ],
            protocolInheritance: [:],
            projectDefinedProtocols: Set(["Standalone"]),
            importedModules: Set(),
            conformedProtocols: Set(),
            swiftInterfaceClient: swiftInterfaceClient
        )

        resolver.resolveInheritedRequirements()

        #expect(resolver.protocolRequirements["Standalone"]?.contains("doSomething") == true)
        #expect(resolver.protocolRequirements["Standalone"]?.count == 1)
    }

    @Test
    func testResolveInheritedRequirementsEmptyState() {
        let resolver = ProtocolResolver(
            protocolRequirements: [:],
            protocolInheritance: [:],
            projectDefinedProtocols: Set(),
            importedModules: Set(),
            conformedProtocols: Set(),
            swiftInterfaceClient: swiftInterfaceClient
        )

        resolver.resolveInheritedRequirements()

        #expect(resolver.protocolRequirements.isEmpty)
    }

    @Test
    func testResolveExternalProtocolsSkipsProjectDefined() async {
        let resolver = ProtocolResolver(
            protocolRequirements: [
                "MyProtocol": Set(["myMethod"])
            ],
            protocolInheritance: [:],
            projectDefinedProtocols: Set(["MyProtocol"]),
            importedModules: Set(),
            conformedProtocols: Set(["MyProtocol"]),
            swiftInterfaceClient: swiftInterfaceClient
        )

        await resolver.resolveExternalProtocols()

        // Project-defined protocol should not be overwritten
        #expect(resolver.protocolRequirements["MyProtocol"] == Set(["myMethod"]))
    }

    @Test
    func testResolveExternalProtocolsResolvesEquatable() async {
        let resolver = ProtocolResolver(
            protocolRequirements: [:],
            protocolInheritance: [:],
            projectDefinedProtocols: Set(),
            importedModules: Set(["Swift"]),
            conformedProtocols: Set(["Equatable"]),
            swiftInterfaceClient: swiftInterfaceClient
        )

        await resolver.resolveExternalProtocols()

        #expect(resolver.protocolRequirements["Equatable"] != nil)
    }

    @Test
    func testResolveExternalProtocolsResolvesHashableWithParent() async {
        let resolver = ProtocolResolver(
            protocolRequirements: [:],
            protocolInheritance: [:],
            projectDefinedProtocols: Set(),
            importedModules: Set(["Swift"]),
            conformedProtocols: Set(["Hashable"]),
            swiftInterfaceClient: swiftInterfaceClient
        )

        await resolver.resolveExternalProtocols()
        resolver.resolveInheritedRequirements()

        #expect(resolver.protocolRequirements["Hashable"]?.contains("hash") == true)
        // Hashable inherits Equatable, so == should be propagated
        #expect(resolver.protocolRequirements["Hashable"]?.contains("==") == true)
    }

    @Test
    func testMergedResultsConvenienceInit() async {
        let result1 = ProtocolVisitorResult(
            protocolRequirements: ["ProtocolA": Set(["methodA"])],
            protocolInheritance: [:],
            projectDefinedProtocols: Set(["ProtocolA"]),
            importedModules: Set(["Foundation"]),
            conformedProtocols: Set(["ProtocolA"])
        )

        let result2 = ProtocolVisitorResult(
            protocolRequirements: ["ProtocolB": Set(["methodB"])],
            protocolInheritance: ["ProtocolB": Set(["ProtocolA"])],
            projectDefinedProtocols: Set(["ProtocolB"]),
            importedModules: Set(["SwiftUI"]),
            conformedProtocols: Set(["ProtocolB"])
        )

        let resolver = ProtocolResolver(
            mergedResults: [result1, result2],
            swiftInterfaceClient: swiftInterfaceClient
        )

        #expect(resolver.protocolRequirements["ProtocolA"]?.contains("methodA") == true)
        #expect(resolver.protocolRequirements["ProtocolB"]?.contains("methodB") == true)
        #expect(resolver.protocolInheritance["ProtocolB"]?.contains("ProtocolA") == true)
        #expect(resolver.projectDefinedProtocols.contains("ProtocolA"))
        #expect(resolver.projectDefinedProtocols.contains("ProtocolB"))
        #expect(resolver.importedModules.contains("Foundation"))
        #expect(resolver.importedModules.contains("SwiftUI"))
        #expect(resolver.conformedProtocols.contains("ProtocolA"))
        #expect(resolver.conformedProtocols.contains("ProtocolB"))
    }

    @Test
    func testMergedResultsResolvesInheritance() {
        let result1 = ProtocolVisitorResult(
            protocolRequirements: ["Parent": Set(["parentMethod"])],
            protocolInheritance: [:],
            projectDefinedProtocols: Set(["Parent"]),
            importedModules: Set(),
            conformedProtocols: Set()
        )

        let result2 = ProtocolVisitorResult(
            protocolRequirements: ["Child": Set(["childMethod"])],
            protocolInheritance: ["Child": Set(["Parent"])],
            projectDefinedProtocols: Set(["Child"]),
            importedModules: Set(),
            conformedProtocols: Set(["Child", "Parent"])
        )

        let resolver = ProtocolResolver(
            mergedResults: [result1, result2],
            swiftInterfaceClient: swiftInterfaceClient
        )
        resolver.resolveInheritedRequirements()

        #expect(resolver.protocolRequirements["Child"]?.contains("childMethod") == true)
        #expect(resolver.protocolRequirements["Child"]?.contains("parentMethod") == true)
    }

    @Test
    func testResolveExternalProtocolsWithUnknownProtocol() async {
        let resolver = ProtocolResolver(
            protocolRequirements: [:],
            protocolInheritance: [:],
            projectDefinedProtocols: Set(),
            importedModules: Set(),
            conformedProtocols: Set(["CompletelyFakeProtocolThatDoesNotExist"]),
            swiftInterfaceClient: swiftInterfaceClient
        )

        await resolver.resolveExternalProtocols()

        // Unknown protocols get an empty set rather than nil
        #expect(resolver.protocolRequirements["CompletelyFakeProtocolThatDoesNotExist"] != nil)
        #expect(resolver.protocolRequirements["CompletelyFakeProtocolThatDoesNotExist"]?.isEmpty == true)
    }

    @Test
    func testResolveInheritedRequirementsDoesNotModifyUnrelatedProtocols() {
        let resolver = ProtocolResolver(
            protocolRequirements: [
                "Standalone": Set(["standaloneMethod"]),
                "Parent": Set(["parentMethod"]),
                "Child": Set(["childMethod"])
            ],
            protocolInheritance: [
                "Child": Set(["Parent"])
            ],
            projectDefinedProtocols: Set(["Standalone", "Parent", "Child"]),
            importedModules: Set(),
            conformedProtocols: Set(),
            swiftInterfaceClient: swiftInterfaceClient
        )

        resolver.resolveInheritedRequirements()

        #expect(resolver.protocolRequirements["Standalone"] == Set(["standaloneMethod"]))
        #expect(resolver.protocolRequirements["Child"]?.contains("parentMethod") == true)
        #expect(resolver.protocolRequirements["Child"]?.contains("childMethod") == true)
        #expect(!resolver.protocolRequirements["Standalone"]!.contains("parentMethod"))
        #expect(!resolver.protocolRequirements["Standalone"]!.contains("childMethod"))
    }

    @Test
    func testInheritanceExpansionIsTransitive() {
        let resolver = ProtocolResolver(
            protocolRequirements: [
                "A": Set(["a"]),
                "B": Set(["b"]),
                "C": Set(["c"])
            ],
            protocolInheritance: [
                "B": Set(["A"]),
                "C": Set(["B"])
            ],
            projectDefinedProtocols: Set(["A", "B", "C"]),
            importedModules: Set(),
            conformedProtocols: Set(),
            swiftInterfaceClient: swiftInterfaceClient
        )

        resolver.resolveInheritedRequirements()

        // After resolution, C's inheritance should include A transitively
        #expect(resolver.protocolInheritance["C"]?.contains("A") == true)
        #expect(resolver.protocolInheritance["C"]?.contains("B") == true)
        #expect(resolver.protocolRequirements["C"]?.contains("a") == true)
        #expect(resolver.protocolRequirements["C"]?.contains("b") == true)
        #expect(resolver.protocolRequirements["C"]?.contains("c") == true)
    }
}

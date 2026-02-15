//
//  Created by Fernando Romiti on 06/12/2025.
//

import Testing
import SwiftSyntax
import SwiftParser
@testable import unused

struct ProtocolVisitorTests {

    /// Shared SwiftInterfaceClient for resolving external protocol requirements
    private let swiftInterfaceClient = SwiftInterfaceClient()

    private func makeResolver(from visitor: ProtocolVisitor) -> ProtocolResolver {
        let result = visitor.result
        return ProtocolResolver(
            protocolRequirements: result.protocolRequirements,
            protocolInheritance: result.protocolInheritance,
            projectDefinedProtocols: result.projectDefinedProtocols,
            importedModules: result.importedModules,
            conformedProtocols: result.conformedProtocols,
            swiftInterfaceClient: swiftInterfaceClient
        )
    }

    @Test
    func testProjectDefinedProtocol() async throws {
        let source = """
        protocol MyProtocol {
            func myMethod()
            var myProperty: String { get }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)
        let resolver = makeResolver(from: visitor)
        await resolver.resolveExternalProtocols()

        #expect(resolver.protocolRequirements.keys.contains("MyProtocol"))
        #expect(resolver.protocolRequirements["MyProtocol"]?.contains("myMethod") == true)
        #expect(resolver.protocolRequirements["MyProtocol"]?.contains("myProperty") == true)
    }

    @Test
    func testExternalProtocolInStruct() async throws {
        let source = """
        struct MyStruct: Equatable {
            let value: Int

            static func == (lhs: MyStruct, rhs: MyStruct) -> Bool {
                return lhs.value == rhs.value
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)
        let resolver = makeResolver(from: visitor)
        await resolver.resolveExternalProtocols()

        // External protocols are resolved via SourceKit
        #expect(resolver.protocolRequirements["Equatable"] != nil)
    }

    @Test
    func testExternalProtocolInExtension() async throws {
        let source = """
        enum AppEnvironmentType: String {
            case production
            case development
        }

        extension AppEnvironmentType: Equatable {
            static func == (lhs: AppEnvironmentType, rhs: AppEnvironmentType) -> Bool {
                return lhs.rawValue == rhs.rawValue
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)
        let resolver = makeResolver(from: visitor)
        await resolver.resolveExternalProtocols()

        // External protocols are resolved via SourceKit
        #expect(resolver.protocolRequirements["Equatable"] != nil)
    }

    @Test
    func testCodableProtocol() async throws {
        let source = """
        struct User: Codable {
            let name: String
            let age: Int

            enum CodingKeys: String, CodingKey {
                case name
                case age
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(name, forKey: .name)
                try container.encode(age, forKey: .age)
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                name = try container.decode(String.self, forKey: .name)
                age = try container.decode(Int.self, forKey: .age)
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)
        let resolver = makeResolver(from: visitor)
        await resolver.resolveExternalProtocols()

        // External protocols are resolved via SourceKit
        #expect(resolver.protocolRequirements["Codable"] != nil)
    }

    @Test
    func testIdentifiableProtocol() async throws {
        let source = """
        struct Item: Identifiable {
            var id: String
            var name: String
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)
        let resolver = makeResolver(from: visitor)
        await resolver.resolveExternalProtocols()

        // Identifiable is resolved via SourceKit
        #expect(resolver.protocolRequirements["Identifiable"] != nil)
    }

    @Test
    func testCustomStringConvertible() async throws {
        let source = """
        struct Person: CustomStringConvertible {
            let name: String

            var description: String {
                return "Person: \\(name)"
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)
        let resolver = makeResolver(from: visitor)
        await resolver.resolveExternalProtocols()

        // CustomStringConvertible is resolved via SourceKit
        #expect(resolver.protocolRequirements["CustomStringConvertible"] != nil)
    }

    @Test
    func testMultipleProtocolsInClass() async throws {
        let source = """
        class MyClass: Equatable, Hashable {
            let id: Int

            static func == (lhs: MyClass, rhs: MyClass) -> Bool {
                return lhs.id == rhs.id
            }

            func hash(into hasher: inout Hasher) {
                hasher.combine(id)
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)
        let resolver = makeResolver(from: visitor)
        await resolver.resolveExternalProtocols()

        // External protocols are resolved via SourceKit
        #expect(resolver.protocolRequirements["Equatable"] != nil)
        #expect(resolver.protocolRequirements["Hashable"] != nil)
    }

    @Test
    func testProjectDefinedProtocolNotMixedWithExternal() async throws {
        let source = """
        protocol MyProtocol {
            func myMethod()
        }

        struct MyStruct: MyProtocol, Equatable {
            func myMethod() {}

            static func == (lhs: MyStruct, rhs: MyStruct) -> Bool {
                return true
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)
        let resolver = makeResolver(from: visitor)
        await resolver.resolveExternalProtocols()

        // Project-defined protocol should have its declared methods
        #expect(resolver.protocolRequirements["MyProtocol"]?.contains("myMethod") == true)
        // Project-defined protocol should NOT have methods from the implementation
        #expect(resolver.protocolRequirements["MyProtocol"]?.contains("==") != true)

        // External protocol (Equatable) should be resolved separately
        #expect(resolver.protocolRequirements["Equatable"] != nil)
        // External protocol should NOT have project protocol methods mixed in
        #expect(resolver.protocolRequirements["Equatable"]?.contains("myMethod") != true)
    }

    @Test
    func testEnumWithExternalProtocol() async throws {
        let source = """
        enum Status: String, CaseIterable {
            case active
            case inactive
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)
        let resolver = makeResolver(from: visitor)
        await resolver.resolveExternalProtocols()

        // CaseIterable is resolved via SourceKit
        #expect(resolver.protocolRequirements["CaseIterable"] != nil)
    }

    @Test
    func testNoProtocolConformance() async throws {
        let source = """
        struct SimpleStruct {
            let value: Int

            func doSomething() {
                print(value)
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)
        let resolver = makeResolver(from: visitor)
        await resolver.resolveExternalProtocols()

        #expect(resolver.protocolRequirements.isEmpty)
    }

    @Test
    func testKnownProtocolRequirements() async throws {
        // Test that the known protocols fallback contains expected requirements
        let source = """
        struct Test: Equatable, Hashable, Codable, Identifiable, CustomStringConvertible {
            var id: String
            var description: String { "" }
            static func == (lhs: Test, rhs: Test) -> Bool { true }
            func hash(into hasher: inout Hasher) {}
            func encode(to encoder: Encoder) throws {}
            init(from decoder: Decoder) throws { id = "" }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)
        let resolver = makeResolver(from: visitor)
        await resolver.resolveExternalProtocols()

        // All external protocols should be tracked
        #expect(resolver.protocolRequirements["Equatable"] != nil)
        #expect(resolver.protocolRequirements["Hashable"] != nil)
        #expect(resolver.protocolRequirements["Codable"] != nil)
        #expect(resolver.protocolRequirements["Identifiable"] != nil)
        #expect(resolver.protocolRequirements["CustomStringConvertible"] != nil)
    }

    @Test
    func testProtocolWithPropertyRequirements() async throws {
        let source = """
        protocol DataProvider {
            var data: [String] { get }
            var count: Int { get set }
            func refresh()
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)
        let resolver = makeResolver(from: visitor)
        await resolver.resolveExternalProtocols()

        #expect(resolver.protocolRequirements["DataProvider"]?.contains("data") == true)
        #expect(resolver.protocolRequirements["DataProvider"]?.contains("count") == true)
        #expect(resolver.protocolRequirements["DataProvider"]?.contains("refresh") == true)
    }

    @Test
    func testProtocolWithSubscriptRequirement() async throws {
        let source = """
        protocol Indexable {
            subscript(index: Int) -> String { get }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)
        let resolver = makeResolver(from: visitor)
        await resolver.resolveExternalProtocols()

        #expect(resolver.protocolRequirements["Indexable"]?.contains("subscript") == true)
    }

    @Test
    func testProtocolWithInitializerRequirement() async throws {
        let source = """
        protocol Constructible {
            init(value: Int)
            init()
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)
        let resolver = makeResolver(from: visitor)
        await resolver.resolveExternalProtocols()

        #expect(resolver.protocolRequirements["Constructible"]?.contains("init") == true)
    }

    @Test
    func testProtocolWithAllRequirementTypes() async throws {
        let source = """
        protocol FullProtocol {
            var property: String { get }
            func method()
            subscript(index: Int) -> Int { get }
            init(value: String)
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)
        let resolver = makeResolver(from: visitor)
        await resolver.resolveExternalProtocols()

        #expect(resolver.protocolRequirements["FullProtocol"]?.contains("property") == true)
        #expect(resolver.protocolRequirements["FullProtocol"]?.contains("method") == true)
        #expect(resolver.protocolRequirements["FullProtocol"]?.contains("subscript") == true)
        #expect(resolver.protocolRequirements["FullProtocol"]?.contains("init") == true)
    }

    @Test
    func testActorWithProtocolConformance() async throws {
        let source = """
        protocol Identifiable {
            var id: String { get }
        }

        actor UserSession: Identifiable {
            var id: String {
                return "session-123"
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)
        let resolver = makeResolver(from: visitor)
        await resolver.resolveExternalProtocols()

        #expect(resolver.protocolRequirements["Identifiable"]?.contains("id") == true)
    }

    @Test
    func testActorWithExternalProtocol() async throws {
        let source = """
        actor Counter: CustomStringConvertible {
            var count: Int = 0

            var description: String {
                return "Counter: \\(count)"
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)
        let resolver = makeResolver(from: visitor)
        await resolver.resolveExternalProtocols()

        #expect(resolver.protocolRequirements["CustomStringConvertible"] != nil)
    }

    @Test
    func testProjectProtocolInheritanceTracking() async throws {
        let source = """
        protocol ParentProtocol {
            func parentMethod()
            var parentProperty: String { get }
        }

        protocol ChildProtocol: ParentProtocol {
            func childMethod()
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)
        let resolver = makeResolver(from: visitor)
        await resolver.resolveExternalProtocols()

        #expect(resolver.protocolInheritance["ChildProtocol"]?.contains("ParentProtocol") == true)
        #expect(resolver.protocolRequirements["ChildProtocol"]?.contains("childMethod") == true)
        // Before resolving inherited requirements, ChildProtocol only has its own direct requirements
        #expect(resolver.protocolRequirements["ChildProtocol"]?.contains("parentMethod") != true)
    }

    @Test
    func testResolveInheritedRequirementsPropagatesParentRequirements() async throws {
        let source = """
        protocol ParentProtocol {
            func parentMethod()
            var parentProperty: String { get }
        }

        protocol ChildProtocol: ParentProtocol {
            func childMethod()
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)
        let resolver = makeResolver(from: visitor)
        await resolver.resolveExternalProtocols()
        resolver.resolveInheritedRequirements()

        // After resolving, ChildProtocol should include ParentProtocol requirements
        #expect(resolver.protocolRequirements["ChildProtocol"]?.contains("childMethod") == true)
        #expect(resolver.protocolRequirements["ChildProtocol"]?.contains("parentMethod") == true)
        #expect(resolver.protocolRequirements["ChildProtocol"]?.contains("parentProperty") == true)

        // ParentProtocol should still have its own requirements unchanged
        #expect(resolver.protocolRequirements["ParentProtocol"]?.contains("parentMethod") == true)
        #expect(resolver.protocolRequirements["ParentProtocol"]?.contains("parentProperty") == true)
    }

    @Test
    func testMultiLevelProtocolInheritance() async throws {
        let source = """
        protocol GrandparentProtocol {
            var configuration: String { get }
        }

        protocol ParentProtocol: GrandparentProtocol {
            func parentMethod()
        }

        protocol ChildProtocol: ParentProtocol {
            func childMethod()
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)
        let resolver = makeResolver(from: visitor)
        await resolver.resolveExternalProtocols()
        resolver.resolveInheritedRequirements()

        // ChildProtocol should have requirements from all ancestors
        #expect(resolver.protocolRequirements["ChildProtocol"]?.contains("childMethod") == true)
        #expect(resolver.protocolRequirements["ChildProtocol"]?.contains("parentMethod") == true)
        #expect(resolver.protocolRequirements["ChildProtocol"]?.contains("configuration") == true)

        // ParentProtocol should have its own + GrandparentProtocol requirements
        #expect(resolver.protocolRequirements["ParentProtocol"]?.contains("parentMethod") == true)
        #expect(resolver.protocolRequirements["ParentProtocol"]?.contains("configuration") == true)
    }

    @Test
    func testProtocolInheritanceFromMultipleParents() async throws {
        let source = """
        protocol ProtocolA {
            func methodA()
        }

        protocol ProtocolB {
            var propertyB: Int { get }
        }

        protocol ProtocolC: ProtocolA, ProtocolB {
            func methodC()
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)
        let resolver = makeResolver(from: visitor)
        await resolver.resolveExternalProtocols()
        resolver.resolveInheritedRequirements()

        #expect(resolver.protocolInheritance["ProtocolC"]?.contains("ProtocolA") == true)
        #expect(resolver.protocolInheritance["ProtocolC"]?.contains("ProtocolB") == true)
        #expect(resolver.protocolRequirements["ProtocolC"]?.contains("methodC") == true)
        #expect(resolver.protocolRequirements["ProtocolC"]?.contains("methodA") == true)
        #expect(resolver.protocolRequirements["ProtocolC"]?.contains("propertyB") == true)
    }

    @Test
    func testProtocolInheritingFromExternalProtocol() async throws {
        let source = """
        protocol MyProtocol: Equatable {
            func myMethod()
        }

        struct MyStruct: MyProtocol {
            func myMethod() {}
            static func == (lhs: MyStruct, rhs: MyStruct) -> Bool { true }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)
        let resolver = makeResolver(from: visitor)
        await resolver.resolveExternalProtocols()
        resolver.resolveInheritedRequirements()

        // MyProtocol should inherit Equatable's requirements
        #expect(resolver.protocolRequirements["MyProtocol"]?.contains("myMethod") == true)
        #expect(resolver.protocolRequirements["MyProtocol"]?.contains("==") == true)
    }

    @Test
    func testResolveInheritedRequirementsWithNoInheritance() async throws {
        let source = """
        protocol StandaloneProtocol {
            func doSomething()
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)
        let resolver = makeResolver(from: visitor)
        await resolver.resolveExternalProtocols()
        resolver.resolveInheritedRequirements()

        #expect(resolver.protocolRequirements["StandaloneProtocol"]?.contains("doSomething") == true)
        #expect(resolver.protocolRequirements["StandaloneProtocol"]?.count == 1)
        #expect(resolver.protocolInheritance["StandaloneProtocol"] == nil)
    }

    @Test
    func testDiamondProtocolInheritance() async throws {
        let source = """
        protocol Root {
            var id: String { get }
        }

        protocol BranchA: Root {
            func methodA()
        }

        protocol BranchB: Root {
            func methodB()
        }

        protocol Leaf: BranchA, BranchB {
            func leafMethod()
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)
        let resolver = makeResolver(from: visitor)
        await resolver.resolveExternalProtocols()
        resolver.resolveInheritedRequirements()

        // Leaf should have all requirements from the diamond
        #expect(resolver.protocolRequirements["Leaf"]?.contains("leafMethod") == true)
        #expect(resolver.protocolRequirements["Leaf"]?.contains("methodA") == true)
        #expect(resolver.protocolRequirements["Leaf"]?.contains("methodB") == true)
        #expect(resolver.protocolRequirements["Leaf"]?.contains("id") == true)

        // Both branches should have Root's id
        #expect(resolver.protocolRequirements["BranchA"]?.contains("id") == true)
        #expect(resolver.protocolRequirements["BranchB"]?.contains("id") == true)
    }

    @Test
    func testExternalProtocolInheritanceViaSwiftInterface() async throws {
        // Hashable inherits from Equatable in the Swift standard library
        let source = """
        struct MyStruct: Hashable {
            let value: Int

            static func == (lhs: MyStruct, rhs: MyStruct) -> Bool {
                return lhs.value == rhs.value
            }

            func hash(into hasher: inout Hasher) {
                hasher.combine(value)
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)
        let resolver = makeResolver(from: visitor)
        await resolver.resolveExternalProtocols()
        resolver.resolveInheritedRequirements()

        // Hashable should include Equatable's requirements after resolution
        #expect(resolver.protocolRequirements["Hashable"]?.contains("hash") == true)
        #expect(resolver.protocolRequirements["Hashable"]?.contains("==") == true)
    }

    @Test
    func testVisitorResultContainsConformedProtocols() {
        let source = """
        protocol MyProtocol {
            func doSomething()
        }

        struct MyStruct: MyProtocol, Equatable {
            func doSomething() {}
            static func == (lhs: MyStruct, rhs: MyStruct) -> Bool { true }
        }

        class MyClass: Hashable {
            func hash(into hasher: inout Hasher) {}
            static func == (lhs: MyClass, rhs: MyClass) -> Bool { true }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)
        let result = visitor.result

        #expect(result.conformedProtocols.contains("MyProtocol"))
        #expect(result.conformedProtocols.contains("Equatable"))
        #expect(result.conformedProtocols.contains("Hashable"))
        #expect(result.projectDefinedProtocols.contains("MyProtocol"))
        #expect(!result.projectDefinedProtocols.contains("Equatable"))
    }

    @Test
    func testVisitorResultContainsImportedModules() {
        let source = """
        import Foundation
        import SwiftUI

        protocol MyProtocol {}
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)
        let result = visitor.result

        #expect(result.importedModules.contains("Foundation"))
        #expect(result.importedModules.contains("SwiftUI"))
    }

}
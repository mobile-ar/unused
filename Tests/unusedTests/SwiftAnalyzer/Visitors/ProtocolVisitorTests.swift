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
        await visitor.resolveExternalProtocols()

        #expect(visitor.protocolRequirements.keys.contains("MyProtocol"))
        #expect(visitor.protocolRequirements["MyProtocol"]?.contains("myMethod") == true)
        #expect(visitor.protocolRequirements["MyProtocol"]?.contains("myProperty") == true)
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
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate, swiftInterfaceClient: swiftInterfaceClient)
        visitor.walk(sourceFile)
        await visitor.resolveExternalProtocols()

        // External protocols are resolved via SourceKit
        #expect(visitor.protocolRequirements["Equatable"] != nil)
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
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate, swiftInterfaceClient: swiftInterfaceClient)
        visitor.walk(sourceFile)
        await visitor.resolveExternalProtocols()

        // External protocols are resolved via SourceKit
        #expect(visitor.protocolRequirements["Equatable"] != nil)
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
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate, swiftInterfaceClient: swiftInterfaceClient)
        visitor.walk(sourceFile)
        await visitor.resolveExternalProtocols()

        // External protocols are resolved via SourceKit
        #expect(visitor.protocolRequirements["Codable"] != nil)
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
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate, swiftInterfaceClient: swiftInterfaceClient)
        visitor.walk(sourceFile)
        await visitor.resolveExternalProtocols()

        // Identifiable is resolved via SourceKit
        #expect(visitor.protocolRequirements["Identifiable"] != nil)
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
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate, swiftInterfaceClient: swiftInterfaceClient)
        visitor.walk(sourceFile)
        await visitor.resolveExternalProtocols()

        // CustomStringConvertible is resolved via SourceKit
        #expect(visitor.protocolRequirements["CustomStringConvertible"] != nil)
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
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate, swiftInterfaceClient: swiftInterfaceClient)
        visitor.walk(sourceFile)
        await visitor.resolveExternalProtocols()

        // External protocols are resolved via SourceKit
        #expect(visitor.protocolRequirements["Equatable"] != nil)
        #expect(visitor.protocolRequirements["Hashable"] != nil)
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
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate, swiftInterfaceClient: swiftInterfaceClient)
        visitor.walk(sourceFile)
        await visitor.resolveExternalProtocols()

        // Project-defined protocol should have its declared methods
        #expect(visitor.protocolRequirements["MyProtocol"]?.contains("myMethod") == true)
        // Project-defined protocol should NOT have methods from the implementation
        #expect(visitor.protocolRequirements["MyProtocol"]?.contains("==") != true)

        // External protocol (Equatable) should be resolved separately
        #expect(visitor.protocolRequirements["Equatable"] != nil)
        // External protocol should NOT have project protocol methods mixed in
        #expect(visitor.protocolRequirements["Equatable"]?.contains("myMethod") != true)
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
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate, swiftInterfaceClient: swiftInterfaceClient)
        visitor.walk(sourceFile)
        await visitor.resolveExternalProtocols()

        // CaseIterable is resolved via SourceKit
        #expect(visitor.protocolRequirements["CaseIterable"] != nil)
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
        await visitor.resolveExternalProtocols()

        #expect(visitor.protocolRequirements.isEmpty)
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
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate, swiftInterfaceClient: swiftInterfaceClient)
        visitor.walk(sourceFile)
        await visitor.resolveExternalProtocols()

        // All external protocols should be tracked
        #expect(visitor.protocolRequirements["Equatable"] != nil)
        #expect(visitor.protocolRequirements["Hashable"] != nil)
        #expect(visitor.protocolRequirements["Codable"] != nil)
        #expect(visitor.protocolRequirements["Identifiable"] != nil)
        #expect(visitor.protocolRequirements["CustomStringConvertible"] != nil)
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
        await visitor.resolveExternalProtocols()

        #expect(visitor.protocolRequirements["DataProvider"]?.contains("data") == true)
        #expect(visitor.protocolRequirements["DataProvider"]?.contains("count") == true)
        #expect(visitor.protocolRequirements["DataProvider"]?.contains("refresh") == true)
    }
}

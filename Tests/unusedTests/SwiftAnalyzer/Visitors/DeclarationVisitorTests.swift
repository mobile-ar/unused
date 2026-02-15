//
//  Created by Fernando Romiti on 06/12/2025.
//

import Testing
import SwiftSyntax
import SwiftParser
@testable import unused

struct DeclarationVisitorTests {

    /// Shared SwiftInterfaceClient for resolving external protocol requirements
    private let swiftInterfaceClient = SwiftInterfaceClient()

    private func resolvedRequirements(from visitor: ProtocolVisitor, resolveInherited: Bool = false) async -> [String: Set<String>] {
        let result = visitor.result
        let resolver = ProtocolResolver(
            protocolRequirements: result.protocolRequirements,
            protocolInheritance: result.protocolInheritance,
            projectDefinedProtocols: result.projectDefinedProtocols,
            importedModules: result.importedModules,
            conformedProtocols: result.conformedProtocols,
            swiftInterfaceClient: swiftInterfaceClient
        )
        await resolver.resolveExternalProtocols()
        if resolveInherited {
            resolver.resolveInheritedRequirements()
        }
        return resolver.protocolRequirements
    }

    @Test
    func testProjectPropertyWrapperDetectionForStruct() async throws {
        let source = """
        @propertyWrapper
        struct Clamped<Value: Comparable> {
            var wrappedValue: Value
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate)
        protocolVisitor.walk(sourceFile)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.projectPropertyWrappers.contains("Clamped"))
        #expect(visitor.projectPropertyWrappers.count == 1)
    }

    @Test
    func testProjectPropertyWrapperDetectionForClass() async throws {
        let source = """
        @propertyWrapper
        class Observable<Value> {
            var wrappedValue: Value
            init(wrappedValue: Value) {
                self.wrappedValue = wrappedValue
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate)
        protocolVisitor.walk(sourceFile)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.projectPropertyWrappers.contains("Observable"))
        #expect(visitor.projectPropertyWrappers.count == 1)
    }

    @Test
    func testProjectPropertyWrapperDetectionForEnum() async throws {
        let source = """
        @propertyWrapper
        enum OptionalValue<Value> {
            case none
            case some(Value)

            var wrappedValue: Value? {
                switch self {
                case .none: return nil
                case .some(let value): return value
                }
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate)
        protocolVisitor.walk(sourceFile)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.projectPropertyWrappers.contains("OptionalValue"))
        #expect(visitor.projectPropertyWrappers.count == 1)
    }

    @Test
    func testProjectPropertyWrapperDetectionMultipleWrappers() async throws {
        let source = """
        @propertyWrapper
        struct Wrapper1<Value> {
            var wrappedValue: Value
        }

        struct NotAWrapper {
            var value: Int
        }

        @propertyWrapper
        struct Wrapper2<Value> {
            var wrappedValue: Value
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate)
        protocolVisitor.walk(sourceFile)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.projectPropertyWrappers.contains("Wrapper1"))
        #expect(visitor.projectPropertyWrappers.contains("Wrapper2"))
        #expect(!visitor.projectPropertyWrappers.contains("NotAWrapper"))
        #expect(visitor.projectPropertyWrappers.count == 2)
    }

    @Test
    func testProjectPropertyWrapperNotDetectedForRegularTypes() async throws {
        let source = """
        struct RegularStruct {
            var value: Int
        }

        class RegularClass {
            var name: String = ""
        }

        enum RegularEnum {
            case one
            case two
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate)
        protocolVisitor.walk(sourceFile)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.projectPropertyWrappers.isEmpty)
    }

    @Test
    func testExtensionWithExternalProtocolConformance() async throws {
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
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate)
        protocolVisitor.walk(sourceFile)
        let requirements = await resolvedRequirements(from: protocolVisitor)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: requirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let equalsFunction = visitor.declarations.first { $0.name == "==" }
        #expect(equalsFunction != nil)
        #expect(equalsFunction?.exclusionReason == .protocolImplementation)
    }

    @Test
    func testExtensionWithProjectProtocolConformance() async throws {
        let source = """
        protocol MyProtocol {
            func myMethod()
        }

        struct MyStruct {
            let value: Int
        }

        extension MyStruct: MyProtocol {
            func myMethod() {
                print(value)
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate)
        protocolVisitor.walk(sourceFile)
        let requirements = await resolvedRequirements(from: protocolVisitor)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: requirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let method = visitor.declarations.first { $0.name == "myMethod" }
        #expect(method != nil)
        #expect(method?.exclusionReason == .protocolImplementation)
        #expect(method?.parentType == "MyStruct")
        #expect(visitor.typeProtocolConformance["MyStruct"]?.contains("MyProtocol") == true)
    }

    @Test
    func testExtensionWithMultipleProtocols() async throws {
        let source = """
        struct User {
            let id: Int
            let name: String
        }

        extension User: Equatable, Hashable {
            static func == (lhs: User, rhs: User) -> Bool {
                return lhs.id == rhs.id
            }

            func hash(into hasher: inout Hasher) {
                hasher.combine(id)
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate)
        protocolVisitor.walk(sourceFile)
        let requirements = await resolvedRequirements(from: protocolVisitor)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: requirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let equalsFunction = visitor.declarations.first { $0.name == "==" }
        let hashFunction = visitor.declarations.first { $0.name == "hash" }

        #expect(equalsFunction?.exclusionReason == .protocolImplementation)
        #expect(hashFunction?.exclusionReason == .protocolImplementation)
        #expect(visitor.typeProtocolConformance["User"]?.contains("Equatable") == true)
        #expect(visitor.typeProtocolConformance["User"]?.contains("Hashable") == true)
    }

    @Test
    func testExtensionWithoutProtocolConformance() async throws {
        let source = """
        struct MyStruct {
            let value: Int
        }

        extension MyStruct {
            func helperMethod() {
                print(value)
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate)
        protocolVisitor.walk(sourceFile)
        let requirements = await resolvedRequirements(from: protocolVisitor)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: requirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let method = visitor.declarations.first { $0.name == "helperMethod" }
        #expect(method != nil)
        #expect(method?.exclusionReason != .protocolImplementation)
    }

    @Test
    func testCodableImplementationInExtension() async throws {
        let source = """
        struct User {
            let name: String
            let age: Int
        }

        extension User: Codable {
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
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate)
        protocolVisitor.walk(sourceFile)
        let requirements = await resolvedRequirements(from: protocolVisitor)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: requirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let encodeFunction = visitor.declarations.first { $0.name == "encode" }

        #expect(encodeFunction?.exclusionReason == .protocolImplementation)
        #expect(visitor.typeProtocolConformance["User"]?.contains("Codable") == true)
    }

    @Test
    func testTypeProtocolConformanceAccumulation() async throws {
        let source = """
        struct MyType: Equatable {
            let value: Int
        }

        extension MyType: Hashable {
            func hash(into hasher: inout Hasher) {
                hasher.combine(value)
            }
        }

        extension MyType: CustomStringConvertible {
            var description: String {
                return "MyType(\\(value))"
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate)
        protocolVisitor.walk(sourceFile)
        let requirements = await resolvedRequirements(from: protocolVisitor)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: requirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let conformance = visitor.typeProtocolConformance["MyType"]
        #expect(conformance?.contains("Equatable") == true)
        #expect(conformance?.contains("Hashable") == true)
        #expect(conformance?.contains("CustomStringConvertible") == true)
        #expect(conformance?.count == 3)
    }

    @Test
    func testOperatorFunctionMarkedAsProtocolImplementation() async throws {
        let source = """
        struct Point: Equatable {
            let x: Int
            let y: Int

            static func == (lhs: Point, rhs: Point) -> Bool {
                return lhs.x == rhs.x && lhs.y == rhs.y
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate)
        protocolVisitor.walk(sourceFile)
        let requirements = await resolvedRequirements(from: protocolVisitor)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: requirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let equalsOperator = visitor.declarations.first { $0.name == "==" }
        #expect(equalsOperator != nil)
        #expect(equalsOperator?.exclusionReason == .protocolImplementation)
        #expect(equalsOperator?.parentType == "Point")
    }

    @Test
    func testVariableImplementingExternalProtocol() async throws {
        let source = """
        import Foundation

        enum MyError: Error, LocalizedError {
            case somethingWentWrong

            var errorDescription: String? {
                return "Something went wrong"
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate)
        protocolVisitor.walk(sourceFile)
        let requirements = await resolvedRequirements(from: protocolVisitor)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: requirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let errorDescription = visitor.declarations.first { $0.name == "errorDescription" }
        #expect(errorDescription != nil)
        #expect(errorDescription?.exclusionReason == .protocolImplementation)
        #expect(errorDescription?.parentType == "MyError")
    }

    @Test
    func testVariableImplementingProjectProtocol() async throws {
        let source = """
        protocol Describable {
            var title: String { get }
            var subtitle: String { get }
        }

        struct Item: Describable {
            var title: String {
                return "Item Title"
            }
            var subtitle: String {
                return "Item Subtitle"
            }
            var internalValue: Int = 0
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate)
        protocolVisitor.walk(sourceFile)
        let requirements = await resolvedRequirements(from: protocolVisitor)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: requirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let title = visitor.declarations.first { $0.name == "title" }
        let subtitle = visitor.declarations.first { $0.name == "subtitle" }
        let internalValue = visitor.declarations.first { $0.name == "internalValue" }

        #expect(title?.exclusionReason == .protocolImplementation)
        #expect(subtitle?.exclusionReason == .protocolImplementation)
        #expect(internalValue?.exclusionReason == ExclusionReason.none)
    }

    @Test
    func testDescriptionPropertyMarkedAsProtocolImplementation() async throws {
        let source = """
        struct Person: CustomStringConvertible {
            let name: String

            var description: String {
                return "Person: \\(name)"
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate)
        protocolVisitor.walk(sourceFile)
        let requirements = await resolvedRequirements(from: protocolVisitor)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: requirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let description = visitor.declarations.first { $0.name == "description" }
        #expect(description != nil)
        #expect(description?.exclusionReason == .protocolImplementation)
        #expect(description?.parentType == "Person")
    }

    @Test
    func testActorDeclaration() async throws {
        let source = """
        actor Counter {
            var count: Int = 0

            func increment() {
                count += 1
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate)
        protocolVisitor.walk(sourceFile)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let actor = visitor.declarations.first { $0.name == "Counter" }
        let count = visitor.declarations.first { $0.name == "count" }
        let increment = visitor.declarations.first { $0.name == "increment" }

        #expect(actor != nil)
        #expect(actor?.type == .class)
        #expect(count?.parentType == "Counter")
        #expect(increment?.parentType == "Counter")
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

            var token: String = ""
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate)
        protocolVisitor.walk(sourceFile)
        let requirements = await resolvedRequirements(from: protocolVisitor)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: requirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let id = visitor.declarations.first { $0.name == "id" }
        let token = visitor.declarations.first { $0.name == "token" }

        #expect(id?.exclusionReason == .protocolImplementation)
        #expect(token?.exclusionReason == ExclusionReason.none)
        #expect(visitor.typeProtocolConformance["UserSession"]?.contains("Identifiable") == true)
    }

    @Test
    func testSubscriptDeclaration() async throws {
        let source = """
        struct Matrix {
            var data: [[Int]] = []

            subscript(row: Int, col: Int) -> Int {
                return data[row][col]
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate)
        protocolVisitor.walk(sourceFile)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let subscriptDecl = visitor.declarations.first { $0.name == "subscript" }
        #expect(subscriptDecl != nil)
        #expect(subscriptDecl?.type == .function)
        #expect(subscriptDecl?.parentType == "Matrix")
    }

    @Test
    func testSubscriptImplementingProtocol() async throws {
        let source = """
        protocol Indexable {
            subscript(index: Int) -> String { get }
        }

        struct StringList: Indexable {
            var items: [String] = []

            subscript(index: Int) -> String {
                return items[index]
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate)
        protocolVisitor.walk(sourceFile)
        let requirements = await resolvedRequirements(from: protocolVisitor)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: requirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let subscriptDecl = visitor.declarations.first { $0.name == "subscript" && $0.parentType == "StringList" }
        #expect(subscriptDecl != nil)
        #expect(subscriptDecl?.exclusionReason == .protocolImplementation)
    }

    @Test
    func testInitializerDeclaration() async throws {
        let source = """
        struct Person {
            let name: String
            let age: Int

            init(name: String, age: Int) {
                self.name = name
                self.age = age
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate)
        protocolVisitor.walk(sourceFile)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let initDecl = visitor.declarations.first { $0.name == "init" }
        #expect(initDecl != nil)
        #expect(initDecl?.type == .function)
        #expect(initDecl?.parentType == "Person")
    }

    @Test
    func testInitializerImplementingProtocol() async throws {
        let source = """
        protocol Constructible {
            init(value: Int)
        }

        struct Number: Constructible {
            let value: Int

            init(value: Int) {
                self.value = value
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate)
        protocolVisitor.walk(sourceFile)
        let requirements = await resolvedRequirements(from: protocolVisitor)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: requirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let initDecl = visitor.declarations.first { $0.name == "init" }
        #expect(initDecl != nil)
        #expect(initDecl?.exclusionReason == .protocolImplementation)
    }

    @Test
    func testDecodableInitializerMarkedAsProtocolImplementation() async throws {
        let source = """
        struct Config: Decodable {
            let key: String
            let value: Int

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                key = try container.decode(String.self, forKey: .key)
                value = try container.decode(Int.self, forKey: .value)
            }

            enum CodingKeys: String, CodingKey {
                case key
                case value
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate)
        protocolVisitor.walk(sourceFile)
        let requirements = await resolvedRequirements(from: protocolVisitor)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: requirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let initDecl = visitor.declarations.first { $0.name == "init" }
        #expect(initDecl != nil)
        #expect(initDecl?.exclusionReason == .protocolImplementation)
        #expect(visitor.typeProtocolConformance["Config"]?.contains("Decodable") == true)
    }

    @Test
    func testOverrideSubscript() async throws {
        let source = """
        class BaseCollection {
            subscript(index: Int) -> Int {
                return index
            }
        }

        class DerivedCollection: BaseCollection {
            override subscript(index: Int) -> Int {
                return index * 2
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate)
        protocolVisitor.walk(sourceFile)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let derivedSubscript = visitor.declarations.first { $0.name == "subscript" && $0.parentType == "DerivedCollection" }
        #expect(derivedSubscript != nil)
        #expect(derivedSubscript?.exclusionReason == .override)
    }

    @Test
    func testOverrideInitializer() async throws {
        let source = """
        class Animal {
            init() {}
        }

        class Dog: Animal {
            override init() {
                super.init()
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate)
        protocolVisitor.walk(sourceFile)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let dogInit = visitor.declarations.first { $0.name == "init" && $0.parentType == "Dog" }
        #expect(dogInit != nil)
        #expect(dogInit?.exclusionReason == .override)
    }

    @Test
    func testObjcInitializer() async throws {
        let source = """
        class ViewController {
            @objc init(nibName: String?) {
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate)
        protocolVisitor.walk(sourceFile)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let initDecl = visitor.declarations.first { $0.name == "init" }
        #expect(initDecl != nil)
        #expect(initDecl?.exclusionReason == .objcAttribute)
    }

    @Test
    func testRegularVariableNotMarkedAsProtocolImplementation() async throws {
        let source = """
        struct Container {
            var items: [String] = []
            var count: Int {
                return items.count
            }
            let capacity: Int = 100
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate)
        protocolVisitor.walk(sourceFile)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let items = visitor.declarations.first { $0.name == "items" }
        let count = visitor.declarations.first { $0.name == "count" }
        let capacity = visitor.declarations.first { $0.name == "capacity" }

        #expect(items?.exclusionReason == ExclusionReason.none)
        #expect(count?.exclusionReason == ExclusionReason.none)
        #expect(capacity?.exclusionReason == ExclusionReason.none)
    }

    @Test
    func testVariableFromInheritedProtocolMarkedAsProtocolImplementation() async throws {
        let source = """
        protocol GrandparentProtocol {
            var configuration: String { get }
        }

        protocol ParentProtocol: GrandparentProtocol {
            func run()
        }

        struct MyCommand: ParentProtocol {
            var configuration: String { "test" }
            func run() {}
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate)
        protocolVisitor.walk(sourceFile)
        let requirements = await resolvedRequirements(from: protocolVisitor, resolveInherited: true)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: requirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let configuration = visitor.declarations.first { $0.name == "configuration" && $0.parentType == "MyCommand" }
        #expect(configuration != nil)
        #expect(configuration?.exclusionReason == .protocolImplementation)

        let run = visitor.declarations.first { $0.name == "run" && $0.parentType == "MyCommand" }
        #expect(run != nil)
        #expect(run?.exclusionReason == .protocolImplementation)
    }

    @Test
    func testFunctionFromMultiLevelInheritedProtocolMarkedAsProtocolImplementation() async throws {
        let source = """
        protocol Root {
            var id: String { get }
        }

        protocol Middle: Root {
            func process()
        }

        protocol Leaf: Middle {
            func execute()
        }

        struct Worker: Leaf {
            var id: String { "worker" }
            func process() {}
            func execute() {}
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate)
        protocolVisitor.walk(sourceFile)
        let requirements = await resolvedRequirements(from: protocolVisitor, resolveInherited: true)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: requirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let id = visitor.declarations.first { $0.name == "id" && $0.parentType == "Worker" }
        #expect(id?.exclusionReason == .protocolImplementation)

        let process = visitor.declarations.first { $0.name == "process" && $0.parentType == "Worker" }
        #expect(process?.exclusionReason == .protocolImplementation)

        let execute = visitor.declarations.first { $0.name == "execute" && $0.parentType == "Worker" }
        #expect(execute?.exclusionReason == .protocolImplementation)
    }

    @Test
    func testInheritedProtocolRequirementsNotMarkedWithoutResolution() async throws {
        let source = """
        protocol Base {
            var configuration: String { get }
        }

        protocol Child: Base {
            func run()
        }

        struct MyStruct: Child {
            var configuration: String { "test" }
            func run() {}
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate)
        protocolVisitor.walk(sourceFile)
        // Intentionally NOT calling resolveInherited to test without inheritance resolution
        let requirements = await resolvedRequirements(from: protocolVisitor, resolveInherited: false)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: requirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        // Without transitive resolution, configuration from Base is NOT recognized
        // via the Child conformance (only direct Child requirements are checked)
        let configuration = visitor.declarations.first { $0.name == "configuration" && $0.parentType == "MyStruct" }
        #expect(configuration?.exclusionReason == ExclusionReason.none)

        // run is a direct requirement of Child, so it IS recognized
        let run = visitor.declarations.first { $0.name == "run" && $0.parentType == "MyStruct" }
        #expect(run?.exclusionReason == .protocolImplementation)
    }

    @Test
    func testDiamondProtocolInheritanceInDeclarationVisitor() async throws {
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

        struct MyType: Leaf {
            var id: String { "1" }
            func methodA() {}
            func methodB() {}
            func leafMethod() {}
            func unrelatedMethod() {}
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate)
        protocolVisitor.walk(sourceFile)
        let requirements = await resolvedRequirements(from: protocolVisitor, resolveInherited: true)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: requirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let id = visitor.declarations.first { $0.name == "id" && $0.parentType == "MyType" }
        #expect(id?.exclusionReason == .protocolImplementation)

        let methodA = visitor.declarations.first { $0.name == "methodA" && $0.parentType == "MyType" }
        #expect(methodA?.exclusionReason == .protocolImplementation)

        let methodB = visitor.declarations.first { $0.name == "methodB" && $0.parentType == "MyType" }
        #expect(methodB?.exclusionReason == .protocolImplementation)

        let leafMethod = visitor.declarations.first { $0.name == "leafMethod" && $0.parentType == "MyType" }
        #expect(leafMethod?.exclusionReason == .protocolImplementation)

        let unrelated = visitor.declarations.first { $0.name == "unrelatedMethod" && $0.parentType == "MyType" }
        #expect(unrelated?.exclusionReason == ExclusionReason.none)
    }

    @Test
    func testEnumCaseDeclarationCollection() async throws {
        let source = """
        enum Direction {
            case north
            case south
            case east
            case west
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate)
        protocolVisitor.walk(sourceFile)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let enumCases = visitor.declarations.filter { $0.type == .enumCase }
        #expect(enumCases.count == 4)

        let north = try #require(enumCases.first { $0.name == "north" })
        #expect(north.parentType == "Direction")
        #expect(north.exclusionReason == ExclusionReason.none)

        let south = enumCases.first { $0.name == "south" }
        #expect(south != nil)
        #expect(south?.parentType == "Direction")
    }

    @Test
    func testEnumCaseMultipleCasesOnOneLine() async throws {
        let source = """
        enum Color {
            case red, green, blue
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate)
        protocolVisitor.walk(sourceFile)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let enumCases = visitor.declarations.filter { $0.type == .enumCase }
        #expect(enumCases.count == 3)
        #expect(enumCases.contains { $0.name == "red" })
        #expect(enumCases.contains { $0.name == "green" })
        #expect(enumCases.contains { $0.name == "blue" })
        #expect(enumCases.allSatisfy { $0.parentType == "Color" })
    }

    @Test
    func testEnumCaseWithAssociatedValues() async throws {
        let source = """
        enum Result {
            case success(value: String)
            case failure(error: Error)
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate)
        protocolVisitor.walk(sourceFile)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let enumCases = visitor.declarations.filter { $0.type == .enumCase }
        #expect(enumCases.count == 2)
        #expect(enumCases.contains { $0.name == "success" })
        #expect(enumCases.contains { $0.name == "failure" })
    }

    @Test
    func testEnumCaseWithRawValues() async throws {
        let source = """
        enum Status: String {
            case active = "active"
            case inactive = "inactive"
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate)
        protocolVisitor.walk(sourceFile)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let enumCases = visitor.declarations.filter { $0.type == .enumCase }
        #expect(enumCases.count == 2)
        #expect(enumCases.contains { $0.name == "active" })
        #expect(enumCases.contains { $0.name == "inactive" })
        #expect(enumCases.allSatisfy { $0.parentType == "Status" })
    }

    @Test
    func testCodingKeysEnumCasesSkipped() async throws {
        let source = """
        struct User: Codable {
            let name: String

            enum CodingKeys: String, CodingKey {
                case name
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate)
        protocolVisitor.walk(sourceFile)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let enumCases = visitor.declarations.filter { $0.type == .enumCase }
        #expect(enumCases.isEmpty)
    }

    @Test
    func testCaseIterableEnumCasesNotExcludedAtVisitorLevel() async throws {
        let source = """
        enum Season: CaseIterable {
            case spring
            case summer
            case autumn
            case winter
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate)
        protocolVisitor.walk(sourceFile)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        // At the visitor level, CaseIterable is NOT applied as an exclusion reason.
        // The post-processing step in SwiftAnalyzer handles this after all files are collected.
        let enumCases = visitor.declarations.filter { $0.type == .enumCase }
        #expect(enumCases.count == 4)
        #expect(enumCases.allSatisfy { $0.exclusionReason == ExclusionReason.none })

        // But the conformance IS tracked for later post-processing
        #expect(visitor.typeProtocolConformance["Season"]?.contains("CaseIterable") == true)
    }

    @Test
    func testCaseIterableViaExtensionConformanceNotDetectedAtVisitorLevel() async throws {
        let source = """
        enum Planet {
            case mercury
            case venus
        }

        extension Planet: CaseIterable {}
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate)
        protocolVisitor.walk(sourceFile)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        // At the visitor level, CaseIterable via extension is NOT detected
        // because the extension is visited after the enum cases.
        // The post-processing step in SwiftAnalyzer handles this.
        let enumCases = visitor.declarations.filter { $0.type == .enumCase }
        #expect(enumCases.count == 2)
        #expect(enumCases.allSatisfy { $0.exclusionReason == ExclusionReason.none })

        // But the conformance IS tracked for later post-processing
        #expect(visitor.typeProtocolConformance["Planet"]?.contains("CaseIterable") == true)
    }

    @Test
    func testNestedEnumCaseInsideClass() async throws {
        let source = """
        class ViewController {
            enum State {
                case loading
                case loaded
                case error
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate)
        protocolVisitor.walk(sourceFile)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let enumCases = visitor.declarations.filter { $0.type == .enumCase }
        #expect(enumCases.count == 3)
        #expect(enumCases.allSatisfy { $0.parentType == "State" })
    }

    @Test
    func testEnumCaseInsideProtocolSkipped() async throws {
        let source = """
        protocol MyProtocol {
            func doSomething()
        }
        enum Direction {
            case up
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate)
        protocolVisitor.walk(sourceFile)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let enumCases = visitor.declarations.filter { $0.type == .enumCase }
        #expect(enumCases.count == 1)
        #expect(enumCases.first?.name == "up")
        #expect(enumCases.first?.parentType == "Direction")
    }

    @Test
    func testProtocolDeclarationCollection() async throws {
        let source = """
        protocol Drawable {
            func draw()
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate)
        protocolVisitor.walk(sourceFile)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let protocols = visitor.declarations.filter { $0.type == .protocol }
        #expect(protocols.count == 1)
        let drawable = try #require(protocols.first)
        #expect(drawable.name == "Drawable")
        #expect(drawable.parentType == nil)
        #expect(drawable.exclusionReason == ExclusionReason.none)
    }

    @Test
    func testMultipleProtocolDeclarations() async throws {
        let source = """
        protocol Drawable {
            func draw()
        }

        protocol Resizable {
            var size: CGSize { get set }
        }

        protocol Animatable {
            func animate()
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate)
        protocolVisitor.walk(sourceFile)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let protocols = visitor.declarations.filter { $0.type == .protocol }
        #expect(protocols.count == 3)
        #expect(protocols.contains { $0.name == "Drawable" })
        #expect(protocols.contains { $0.name == "Resizable" })
        #expect(protocols.contains { $0.name == "Animatable" })
        #expect(protocols.allSatisfy { $0.parentType == nil })
    }

    @Test
    func testProtocolMembersNotCollectedAsDeclarations() async throws {
        let source = """
        protocol DataProvider {
            var count: Int { get }
            func fetchData()
            func reset()
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate)
        protocolVisitor.walk(sourceFile)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let protocols = visitor.declarations.filter { $0.type == .protocol }
        #expect(protocols.count == 1)
        #expect(protocols.first?.name == "DataProvider")

        let functions = visitor.declarations.filter { $0.type == .function }
        #expect(functions.isEmpty)

        let variables = visitor.declarations.filter { $0.type == .variable }
        #expect(variables.isEmpty)
    }

    @Test
    func testProtocolAndEnumCasesTogether() async throws {
        let source = """
        protocol Renderable {
            func render()
        }

        enum Shape {
            case circle
            case square
        }

        class Canvas: Renderable {
            func render() {}
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate)
        protocolVisitor.walk(sourceFile)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let protocols = visitor.declarations.filter { $0.type == .protocol }
        #expect(protocols.count == 1)
        #expect(protocols.first?.name == "Renderable")

        let enumCases = visitor.declarations.filter { $0.type == .enumCase }
        #expect(enumCases.count == 2)
        #expect(enumCases.contains { $0.name == "circle" })
        #expect(enumCases.contains { $0.name == "square" })

        let classes = visitor.declarations.filter { $0.type == .class }
        #expect(classes.count == 2)
        #expect(classes.contains { $0.name == "Shape" })
        #expect(classes.contains { $0.name == "Canvas" })
    }

    @Test
    func testProtocolDeclarationLineNumber() async throws {
        let source = """
        import Foundation

        protocol MyProtocol {
            func doWork()
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate)
        protocolVisitor.walk(sourceFile)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let protocols = visitor.declarations.filter { $0.type == .protocol }
        #expect(protocols.count == 1)
        #expect(protocols.first?.line == 3)
    }

    @Test
    func testEnumCaseLineNumbers() async throws {
        let source = """
        enum Fruit {
            case apple
            case banana
            case cherry
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate)
        protocolVisitor.walk(sourceFile)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let apple = visitor.declarations.first { $0.name == "apple" && $0.type == .enumCase }
        #expect(apple?.line == 2)

        let banana = visitor.declarations.first { $0.name == "banana" && $0.type == .enumCase }
        #expect(banana?.line == 3)

        let cherry = visitor.declarations.first { $0.name == "cherry" && $0.type == .enumCase }
        #expect(cherry?.line == 4)
    }

    @Test
    func testNonCaseIterableEnumCasesNotExcluded() async throws {
        let source = """
        enum Direction {
            case up
            case down
        }
        """

        let sourceFile = Parser.parse(source: source)
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate)
        protocolVisitor.walk(sourceFile)

        let visitor = DeclarationVisitor(
            filePath: "/test/file.swift",
            protocolRequirements: protocolVisitor.protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        let enumCases = visitor.declarations.filter { $0.type == .enumCase }
        #expect(enumCases.count == 2)
        #expect(enumCases.allSatisfy { $0.exclusionReason == ExclusionReason.none })
    }
}

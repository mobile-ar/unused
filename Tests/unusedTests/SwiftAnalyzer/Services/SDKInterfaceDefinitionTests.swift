import Testing
@testable import unused

struct SDKInterfaceDefinitionTests {
    private let parser = SwiftInterfaceParser(sdkPath: nil)

    @Test
    func parsesStructuredRequirementsAndPreservesOverloads() throws {
        let source = """
        public protocol Transform<Element>: Swift::Equatable where Element: Swift::Hashable {
            associatedtype Element: Swift::Hashable
            typealias Output = Swift::Array<Element>
            static var shared: Self { get }
            var value: Element { get async throws }
            static func == (_ lhs: Self, _ rhs: Self) -> Swift::Bool
            func transform<T>(_ value: T, using body: (T) -> Element) async throws -> Output where T: Swift::Equatable
            func transform(_ value: Swift::Int) -> Output
            subscript<T>(lookup key: T) -> Element where T: Swift::Hashable { get }
            init?<T>(_ seed: T) where T: Swift::Equatable
        }
        """
        let definition = try #require(parser.parseProtocolDefinition(protocolName: "Transform", from: source))
        #expect(definition.isComplete)
        #expect(definition.inheritedTypes == ["Swift.Equatable"])
        #expect(definition.requirements.count == 9)
        #expect(definition.requirements.filter { $0.name == "transform" }.count == 2)

        let genericFunction = try #require(definition.requirements.first { $0.name == "transform" && !$0.genericParameters.isEmpty })
        #expect(genericFunction.kind == .function)
        #expect(genericFunction.parameterLabels == ["_", "using"])
        #expect(genericFunction.parameterTypes == ["T", "(T)->Element"])
        #expect(genericFunction.resultType == "Output")
        #expect(genericFunction.genericParameters == ["T"])
        #expect(genericFunction.isAsync && genericFunction.isThrowing)
        let initializer = try #require(definition.requirements.first { $0.kind == .initializer })
        #expect(initializer.name == "init")
        #expect(initializer.resultType == "Self?")
        #expect(initializer.genericParameters == ["T"])
        let subscriptRequirement = try #require(definition.requirements.first { $0.kind == .subscript })
        #expect(subscriptRequirement.parameterLabels == ["lookup"])
        #expect(subscriptRequirement.parameterTypes == ["T"])
        #expect(subscriptRequirement.genericParameters == ["T"])
        #expect(definition.requirements.first { $0.name == "shared" }?.isStatic == true)
        #expect(definition.requirements.first { $0.name == "value" }?.isAsync == true)
        #expect(definition.requirements.first { $0.name == "value" }?.isThrowing == true)
        #expect(parser.parseProtocolRequirements(protocolName: "Transform", from: source) == [
            "Element", "Output", "shared", "value", "==", "transform", "subscript", "init"
        ])
    }

    @Test
    func indexesNominalKindsIncludingNestedAndConditionalTypes() {
        let source = """
        public struct String {}
        public class SDKClass {}
        public enum Choice {
            public struct Nested {}
        }
        public actor Worker {}
        public protocol Requirement {}
        #if FEATURE
        public class Conditional {}
        #endif
        public typealias Alias = String
        public func implementation() { struct Local {} }
        // public class Commented {}
        """
        let index = SDKInterfaceIndex(moduleInterface: source, moduleName: "SDK")
        #expect(index.typeKinds == [
            "String": "struct", "SDKClass": "class", "Choice": "enum", "Choice.Nested": "struct",
            "Worker": "actor", "Requirement": "protocol", "Conditional": "class"
        ])
        #expect(index.typeKind(named: "SDK::String") == "struct")
        #expect(index.typeKind(named: "SDK.Choice.Nested") == "struct")
        #expect(index.typeKind(named: "Foreign.String") == nil)
        #expect(index.typeKind(named: "Alias") == nil)
        #expect(index.protocolDefinition(named: "String") == nil)
        #expect(index.protocolDefinition(named: "SDKClass") == nil)
    }

    @Test
    func distinguishesKnownEmptyProtocolsFromUnknownNames() throws {
        let source = """
        public protocol Empty {}
        public protocol EmptySuffix { func extra() }
        public protocol `repeat` {}
        public typealias EmptyAlias = Empty
        """
        for name in ["Empty", "EmptyAlias", "repeat", "`repeat`"] {
            let definition = try #require(parser.parseProtocolDefinition(protocolName: name, from: source))
            #expect(definition.isComplete)
            #expect(definition.requirements.isEmpty)
            #expect(parser.parseProtocolRequirements(protocolName: name, from: source) == [])
        }
        #expect(parser.parseProtocolDefinition(protocolName: "Missing", from: source) == nil)
        #expect(parser.parseProtocolRequirements(protocolName: "Missing", from: source) == nil)
        #expect(parser.parseProtocolParents(protocolName: "Missing", from: source) == nil)
    }

    @Test
    func resolvesSDKQualifiedAliasesAndAliasChains() throws {
        let source = """
        // swift-module-flags: -target arm64-apple-macos -module-name Swift
        public protocol Encodable { func encode(to encoder: any Encoder) throws }
        public protocol Decodable { init(from decoder: any Decoder) throws }
        public protocol Equatable: ~Copyable, ~Escapable { static func == (_ lhs: Self, _ rhs: Self) -> Bool }
        public typealias Codable = Swift::Decodable & Swift::Encodable
        public typealias Coding = Codable
        public typealias Equality = Swift::Equatable
        """
        for name in ["Codable", "Swift.Codable", "Swift::Coding"] {
            let definition = try #require(parser.parseProtocolDefinition(protocolName: name, from: source))
            #expect(definition.isComplete)
            #expect(Set(definition.requirements.map(\.name)) == ["encode", "init"])
        }
        let equality = try #require(parser.parseProtocolDefinition(protocolName: "Equality", from: source))
        #expect(equality.isComplete)
        #expect(Set(equality.requirements.map(\.name)) == ["=="])
        #expect(parser.parseProtocolParents(protocolName: "Codable", from: source) == ["Decodable", "Encodable"])
        #expect(parser.parseProtocolParents(protocolName: "Equatable", from: source) == [])
    }

    @Test
    func preservesPartialAliasRequirementsWithoutResolvingForeignHomonyms() throws {
        let source = """
        // swift-module-flags: -module-name Example
        public protocol Known { func known() }
        public protocol Missing { func wrongModule() }
        public typealias Partial = Example::Known & Other::Missing
        public typealias Indirect = Partial & Unknown
        """
        for name in ["Partial", "Indirect"] {
            let definition = try #require(parser.parseProtocolDefinition(protocolName: name, from: source))
            #expect(!definition.isComplete)
            #expect(Set(definition.requirements.map(\.name)) == ["known"])
            #expect(parser.parseProtocolRequirements(protocolName: name, from: source) == ["known"])
        }
        #expect(parser.parseProtocolDefinition(protocolName: "Other.Known", from: source) == nil)
    }

    @Test
    func qualifiedQueriesSupplyModuleContextForHeaderlessInterfaces() throws {
        let source = """
        public protocol P { func requirement() }
        public typealias Alias = Example::P
        """
        let definition = try #require(parser.parseProtocolDefinition(protocolName: "Example::Alias", from: source))
        #expect(definition.isComplete)
        #expect(Set(definition.requirements.map(\.name)) == ["requirement"])
        #expect(parser.parseProtocolRequirements(protocolName: "Example.P", from: source) == ["requirement"])
        #expect(parser.parseProtocolDefinition(protocolName: "Alias", from: source)?.isComplete == false)
    }

    @Test
    func resolvesScopedNamesWithoutConflatingNestedProtocols() throws {
        let source = """
        // swift-module-flags: -module-name Example
        public protocol P { func global() }
        public struct Outer {
            public protocol P { func nested() }
            public typealias Alias = P
        }
        public struct Other { public protocol P { func other() } }
        public typealias Nested = Example::Outer.P
        """
        #expect(parser.parseProtocolRequirements(protocolName: "P", from: source) == ["global"])
        #expect(parser.parseProtocolRequirements(protocolName: "Outer.P", from: source) == ["nested"])
        #expect(parser.parseProtocolRequirements(protocolName: "Example::Outer.Alias", from: source) == ["nested"])
        #expect(parser.parseProtocolRequirements(protocolName: "Nested", from: source) == ["nested"])
        #expect(parser.parseProtocolRequirements(protocolName: "Other.P", from: source) == ["other"])
    }

    @Test
    func cyclesRemainIncompleteAndKeepKnownMembers() throws {
        let source = """
        public protocol Known { var known: Int { get } }
        public typealias First = Known & Second
        public typealias Second = First & Unknown
        public typealias SelfCycle = SelfCycle
        """
        for name in ["First", "Second"] {
            let definition = try #require(parser.parseProtocolDefinition(protocolName: name, from: source))
            #expect(!definition.isComplete)
            #expect(Set(definition.requirements.map(\.name)) == ["known"])
        }
        let cycle = try #require(parser.parseProtocolDefinition(protocolName: "SelfCycle", from: source))
        #expect(!cycle.isComplete)
        #expect(cycle.requirements.isEmpty)
    }

    @Test
    func parsesMultilineInheritanceWithoutWhereClauseContamination() throws {
        let source = """
        @available(macOS 15, *)
        public protocol Child<Element>:
            Example::Parent<Element>,
            Other.Base
        where Element: Swift::Hashable, Self.Element == Element {
            associatedtype Element
        }
        """
        let definition = try #require(parser.parseProtocolDefinition(protocolName: "Child", from: source))
        #expect(definition.isComplete)
        #expect(definition.inheritedTypes == ["Example.Parent", "Other.Base"])
        #expect(parser.parseProtocolParents(protocolName: "Child", from: source) == ["Parent", "Base"])
    }

    @Test
    func mergesConditionalProtocolAndAliasDeclarations() throws {
        let source = """
        #if FIRST
        public protocol Choice { func first() }
        public typealias Alias = Choice
        #else
        public protocol Choice { func second() }
        public typealias Alias = Missing & Choice
        #endif
        """
        let choice = try #require(parser.parseProtocolDefinition(protocolName: "Choice", from: source))
        #expect(choice.isComplete)
        #expect(Set(choice.requirements.map(\.name)) == ["first", "second"])
        let alias = try #require(parser.parseProtocolDefinition(protocolName: "Alias", from: source))
        #expect(!alias.isComplete)
        #expect(Set(alias.requirements.map(\.name)) == ["first", "second"])
    }

    @Test
    func handlesGenericAndParenthesizedCompositionsAndUnsupportedAliasTypes() throws {
        let source = """
        public protocol Container<Element> { associatedtype Element }
        public protocol Known { func known() }
        public typealias Specialized<T> = Container<T>
        public typealias Composition = (Known & Container<Int>)
        public typealias Existential = any Known
        public typealias Closure = () -> Void
        public typealias Partial = Known & (() -> Void)
        """
        for name in ["Specialized", "Composition", "Existential"] {
            #expect(parser.parseProtocolDefinition(protocolName: name, from: source)?.isComplete == true)
        }
        let closure = try #require(parser.parseProtocolDefinition(protocolName: "Closure", from: source))
        #expect(!closure.isComplete)
        #expect(closure.requirements.isEmpty)
        let partial = try #require(parser.parseProtocolDefinition(protocolName: "Partial", from: source))
        #expect(!partial.isComplete)
        #expect(Set(partial.requirements.map(\.name)) == ["known"])
    }

    @Test
    func malformedDeclarationsAreIncompleteButRetainParsedRequirements() throws {
        let definition = try #require(parser.parseProtocolDefinition(protocolName: "Broken", from: "protocol Broken { func known()"))
        #expect(!definition.isComplete)
        #expect(Set(definition.requirements.map(\.name)) == ["known"])
    }

    @Test
    func pureParserDoesNotRequireAnSDK() {
        #expect(parser.getModuleInterface(moduleName: "Swift") == nil)
        #expect(parser.getProtocolDefinition(protocolName: "Equatable", inModule: "Swift") == nil)
        #expect(parser.getProtocolRequirements(protocolName: "Equatable", inModule: "Swift") == nil)
        #expect(parser.getProtocolParents(protocolName: "Equatable", inModule: "Swift") == nil)
        #expect(parser.getExportedSymbols(inModule: "Swift") == nil)
        #expect(parser.getPropertyWrappers(inModule: "Swift") == nil)
    }
}

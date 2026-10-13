import Testing
@testable import unused

struct SynthesizedDependencyResolverTests {
    private func resolve(_ fixture: PropertyWrapperResolverFixture) -> Set<DeclarationIdentity> {
        SynthesizedDependencyResolver(
            declarations: fixture.declarations, parsedFiles: fixture.parsedFiles, graph: fixture.graph
        ).resolve()
    }

    @Test
    func enumAssociatedValueCodingKeyTypesAndAliasesAreCompilerDependencies() throws {
        let fixture = PropertyWrapperResolverFixture.parse(["Event.swift": """
            enum Event: Codable {
                case message(text: String), count(Int), empty
                enum CodingKeys: String, CodingKey { case message, count, empty }
                enum MessageCodingKeys: String, CodingKey { case text = "body" }
                typealias CountCodingKeys = CountKeys
                enum EmptyCodingKeys: String, CodingKey { case unused }
                enum UnrelatedCodingKeys: String, CodingKey { case unused }
            }
            enum CountKeys: String, CodingKey { case _0 = "number" }
            enum Manual: Codable {
                case message(text: String)
                enum MessageCodingKeys: String, CodingKey { case text }
                func encode(to encoder: any Encoder) throws {}
                init(from decoder: any Decoder) throws { self = .message(text: "") }
            }
            """])
        let used = resolve(fixture)
        for (owner, name) in [("Event", "MessageCodingKeys"), ("Event.MessageCodingKeys", "text"),
                              ("Event", "CountCodingKeys"), ("CountKeys", "_0")] {
            #expect(used.contains(try fixture.identity(owner, name)))
        }
        #expect(used.contains(try fixture.identity(nil, "CountKeys")))
        #expect(!used.contains(try fixture.identity("Event", "EmptyCodingKeys")))
        #expect(!used.contains(try fixture.identity("Event", "UnrelatedCodingKeys")))
        #expect(!used.contains(try fixture.identity("Manual", "MessageCodingKeys")))
    }

    @Test
    func subclassesDoNotSynthesizeDependenciesForInheritedCodableConformances() throws {
        let fixture = PropertyWrapperResolverFixture.parse(["Inheritance.swift": """
            class Base: Codable {
                var baseValue = 0
                func encode(to encoder: any Encoder) throws {}
                required init(from decoder: any Decoder) throws {}
            }
            class Child: Base {
                var childValue = 0
                enum CodingKeys: String, CodingKey { case childValue }
            }
            class EncodingBase: Encodable {
                func encode(to encoder: any Encoder) throws {}
            }
            class DecodingChild: EncodingBase, Decodable { var decodedValue = 0 }
            """])
        #expect(resolve(fixture) == [try fixture.identity("DecodingChild", "decodedValue")])
    }

    @Test(arguments: ["Equatable", "Hashable", "Encodable", "Decodable", "Codable"])
    func synthesisUsesStoredInstanceBindingsIncludingObserversOnly(_ conformance: String) throws {
        let fixture = PropertyWrapperResolverFixture.parse(["Model.swift": """
            struct Model: \(conformance) {
                let constant: Int
                var first = 0, second = 1
                var observed = 0 { willSet {} didSet {} }
                var willObserve = 0 { willSet {} }
                var didObserve = 0 { didSet {} }
                var computed: Int { 0 }
                var accessor: Int { get { 0 } set {} }
                static var shared = 0
                static let sharedConstant = 0
                static var sharedObserved = 0 { didSet {} }
                func helper() { let local = 0 }
                struct Nested { var unrelated = 0 }
            }
            struct Unrelated { var first = 0 }
            """])

        #expect(resolve(fixture) == [
            try fixture.identity("Model", "constant"),
            try fixture.identity("Model", "first"),
            try fixture.identity("Model", "second"),
            try fixture.identity("Model", "observed"),
            try fixture.identity("Model", "willObserve"),
            try fixture.identity("Model", "didObserve")
        ])
    }

    @Test(arguments: ["Swift.Equatable", "Swift.Hashable", "Swift.Codable"])
    func inheritedAndAliasedSDKConformancesWorkWithoutSDKDefinitions(_ conformance: String) throws {
        let fixture = PropertyWrapperResolverFixture.parse([
            "Protocol.swift": """
                protocol P: \(conformance) {}
                protocol Child: P {}
                typealias Alias = Child
                """,
            "Model.swift": """
                struct Model: Alias {
                    var value = 0
                    var computed: Int { 0 }
                }
                """
        ])

        #expect(fixture.graph.definitions[conformance] == nil)
        #expect(fixture.graph.closure(for: "Model").unknown.contains(conformance))
        #expect(resolve(fixture) == [try fixture.identity("Model", "value")])
    }

    @Test
    func manualEqualityDoesNotDisableSynthesizedHashing() throws {
        let fixture = PropertyWrapperResolverFixture.parse([
            "Model.swift": """
                struct Model: Hashable { var value = 0 }
                """,
            "Equality.swift": """
                extension Model {
                    static func == (_ lhs: Self, _ rhs: Self) -> Bool { true }
                }
                """
        ])

        #expect(resolve(fixture) == [try fixture.identity("Model", "value")])
    }

    @Test
    func manualHashingDoesNotDisableSynthesizedEquality() throws {
        let fixture = PropertyWrapperResolverFixture.parse([
            "Model.swift": """
                struct Model: Hashable { var value = 0 }
                """,
            "Hashing.swift": """
                extension Model {
                    func hash(into hasher: inout Swift.Hasher) {}
                }
                """
        ])

        #expect(resolve(fixture) == [try fixture.identity("Model", "value")])
    }

    @Test
    func manualEqualityAndHashingDisableOnlyTheirOwnSynthesis() {
        let fixture = PropertyWrapperResolverFixture.parse(["Model.swift": """
            struct EqualityOnly: Equatable {
                var value = 0
                static func == (_ lhs: EqualityOnly, _ rhs: EqualityOnly) -> Swift.Bool { true }
            }
            struct FullyManual: Hashable {
                var value = 0
                static func == (_ lhs: Self, _ rhs: Self) -> Bool { true }
                func hash(into hasher: inout Hasher) {}
            }
            """])

        #expect(resolve(fixture).isEmpty)
    }

    @Test
    func equalityOperatorParameterNamesDoNotPreventManualWitnessRecognition() {
        let fixture = PropertyWrapperResolverFixture.parse(["Model.swift": """
            struct Model: Equatable {
                var value = 0
                static func == (lhs: Self, rhs: Self) -> Bool { true }
            }
            """])

        #expect(resolve(fixture).isEmpty)
    }

    @Test
    func sameNamedWitnessOverloadsDoNotDisableSynthesis() throws {
        let fixture = PropertyWrapperResolverFixture.parse(["Model.swift": """
            struct Equality: Equatable {
                var value = 0
                static func == (_ lhs: Equality, _ rhs: Int) -> Bool { true }
            }
            struct Hashing: Hashable {
                var value = 0
                static func == (_ lhs: Self, _ rhs: Self) -> Bool { true }
                func hash(into hasher: inout Int) {}
                static func hash(into hasher: inout Hasher) {}
            }
            struct Encoding: Encodable {
                var value = 0
                func encode(to encoder: Int) {}
                static func encode(to encoder: Encoder) {}
            }
            struct Decoding: Decodable {
                var value = 0
                init(from decoder: Int) {}
                init<T>(from decoder: T) {}
            }
            """])

        #expect(resolve(fixture) == [
            try fixture.identity("Equality", "value"),
            try fixture.identity("Hashing", "value"),
            try fixture.identity("Encoding", "value"),
            try fixture.identity("Decoding", "value")
        ])
    }

    @Test
    func manualEncoderInAnotherFileLeavesDecodingActive() throws {
        let fixture = PropertyWrapperResolverFixture.parse([
            "Model.swift": """
                struct Model: Codable {
                    var value = 0
                    let defaulted = 1
                }
                """,
            "Encoding.swift": """
                extension Model {
                    func encode(to encoder: Encoder) throws {}
                }
                """
        ])

        #expect(resolve(fixture) == [try fixture.identity("Model", "value")])
    }

    @Test
    func manualDecoderInAnotherFileLeavesEncodingActive() throws {
        let fixture = PropertyWrapperResolverFixture.parse([
            "Model.swift": """
                struct Model: Codable {
                    var value = 0
                    let defaulted = 1
                }
                """,
            "Decoding.swift": """
                extension Model {
                    init(from decoder: Swift.Decoder) throws { value = 0 }
                }
                """
        ])

        #expect(resolve(fixture) == [
            try fixture.identity("Model", "value"),
            try fixture.identity("Model", "defaulted")
        ])
    }

    @Test
    func fullyManualCodableDoesNotRetainPropertiesOrCodingKeys() {
        let fixture = PropertyWrapperResolverFixture.parse([
            "Model.swift": """
                struct Model: Codable {
                    var value = 0
                    enum CodingKeys: String, CodingKey { case value }
                }
                """,
            "Encoding.swift": """
                extension Model { func encode(to encoder: Swift.Encoder) throws {} }
                """,
            "Decoding.swift": """
                extension Model { init(from decoder: Decoder) throws { value = 0 } }
                """
        ])

        #expect(resolve(fixture).isEmpty)
    }

    @Test(arguments: ["", "any "])
    func manualCodingWitnessesRecognizeExistentialParameterTypes(_ existential: String) {
        let fixture = PropertyWrapperResolverFixture.parse([
            "Models.swift": """
                struct Encoding: Encodable { var value = 0 }
                struct Decoding: Decodable { var value = 0 }
                """,
            "Witnesses.swift": """
                extension Encoding {
                    func encode(to encoder: \(existential)Swift.Encoder) throws {}
                }
                extension Decoding {
                    init(from decoder: \(existential)Swift.Decoder) throws { value = 0 }
                }
                """
        ])

        #expect(resolve(fixture).isEmpty)
    }

    @Test(arguments: ["Encodable", "Decodable", "Codable"])
    func codingKeysRetainsItsTypeAndCasesAndRestrictsStoredPropertyMembership(_ conformance: String) throws {
        let fixture = PropertyWrapperResolverFixture.parse(["Model.swift": """
            struct Model: \(conformance) {
                var included = 0
                var omitted = 0
                var computed: Int { 0 }
                static var shared = 0
                enum CodingKeys: String, CodingKey {
                    case included
                    var helper: Int { 0 }
                }
                enum UnrelatedKeys: String, CodingKey { case omitted }
            }
            struct Unrelated {
                var included = 0
                enum CodingKeys: String, CodingKey { case included }
            }
            """])

        #expect(resolve(fixture) == [
            try fixture.identity("Model", "included"),
            try fixture.identity("Model", "CodingKeys", kind: .type),
            try fixture.identity("Model.CodingKeys", "included", kind: .enumCase)
        ])
    }

    @Test(arguments: ["Encodable", "Decodable", "Codable"])
    func codingKeysAliasInAnExtensionRetainsTheResolvedKeyTypeAndCases(_ conformance: String) throws {
        let fixture = PropertyWrapperResolverFixture.parse([
            "Model.swift": """
                struct Model: \(conformance) {
                    var included = 0
                    var omitted = 0
                }
                """,
            "Schema.swift": """
                struct Schema {
                    enum Keys: String, CodingKey { case included }
                }
                typealias SchemaAlias = Schema
                typealias SharedKeys = SchemaAlias.Keys
                enum Keys: String, CodingKey { case omitted }
                """,
            "CodingKeys.swift": """
                extension Model { typealias CodingKeys = SharedKeys }
                """
        ])

        #expect(resolve(fixture) == [
            try fixture.identity("Model", "included"),
            try fixture.identity("Model", "CodingKeys", kind: .typealiasDeclaration),
            try fixture.identity("Schema", "Keys", kind: .type),
            try fixture.identity("Schema.Keys", "included", kind: .enumCase)
        ])
    }

    @Test
    func decodingDoesNotReadDefaultInitializedLetEvenWhenItHasACodingKey() throws {
        let fixture = PropertyWrapperResolverFixture.parse(["Model.swift": """
            struct Model: Decodable {
                let defaulted = 1
                let required: Int
                var mutable = 0
                var omitted = 0
                enum CodingKeys: String, CodingKey { case defaulted, required, mutable }
            }
            """])

        #expect(resolve(fixture) == [
            try fixture.identity("Model", "required"),
            try fixture.identity("Model", "mutable"),
            try fixture.identity("Model", "CodingKeys"),
            try fixture.identity("Model.CodingKeys", "defaulted"),
            try fixture.identity("Model.CodingKeys", "required"),
            try fixture.identity("Model.CodingKeys", "mutable")
        ])
    }

    @Test(arguments: ["Encodable", "Equatable", "Hashable", "Codable"])
    func otherSynthesisStillReadsDefaultInitializedLet(_ conformance: String) throws {
        let fixture = PropertyWrapperResolverFixture.parse(["Model.swift": """
            struct Model: \(conformance) {
                let defaulted = 1
                var mutable = 0
            }
            """])

        #expect(resolve(fixture) == [
            try fixture.identity("Model", "defaulted"),
            try fixture.identity("Model", "mutable")
        ])
    }

    @Test(arguments: [
        "let value = Status(rawValue: 1)",
        "let value = Status.init(rawValue: 1)",
        "let value = Alias(rawValue: 1)",
        "let value = Alias.init(rawValue: 1)",
        "let value: Status? = .init(rawValue: 1)",
        "let value: Alias? = .init(rawValue: 1)",
        "func make() -> Status? { .init(rawValue: 1) }",
        "let factory = Status.init(rawValue:)",
        "let factory = Alias.init(rawValue:)",
        "let value = App.Status(rawValue: 1)",
        "let factory = App.Status.init(rawValue:)"
    ])
    func rawInitializationRetainsAllCasesForTheExactEnum(_ usage: String) throws {
        let fixture = PropertyWrapperResolverFixture.parse([
            "Status.swift": """
                typealias Raw = Swift.Int
                enum Status: Raw { case ready = 1, finished = 2 }
                typealias Alias = Status
                struct Namespace { enum Status: Int { case unrelated = 1 } }
                enum Unused: Int { case unused = 1 }
                """,
            "Usage.swift": usage
        ], moduleName: "App")

        #expect(resolve(fixture) == [
            try fixture.identity("Status", "ready"),
            try fixture.identity("Status", "finished")
        ])
    }

    @Test(arguments: [
        "let value = Namespace.Status(rawValue: 1)",
        "let value = Scope.Status.init(rawValue: 1)",
        "let value = Alias(rawValue: 1)",
        "let value: Scope.Status? = .init(rawValue: 1)",
        "let factory = Namespace.Status.init(rawValue:)",
        "let factory = Scope.Status.init(rawValue:)",
        "extension Namespace { static func make() -> Status? { Status(rawValue: 1) } }"
    ])
    func qualifiedNestedRawInitializationDoesNotRetainSameNamedTopLevelCases(_ usage: String) throws {
        let fixture = PropertyWrapperResolverFixture.parse([
            "Status.swift": """
                struct Namespace { enum Status: Swift.Int { case ready = 1, finished = 2 } }
                typealias Scope = Namespace
                typealias Alias = Namespace.Status
                enum Status: Int { case unrelated = 1 }
                """,
            "Usage.swift": usage
        ])

        #expect(resolve(fixture) == [
            try fixture.identity("Namespace.Status", "ready"),
            try fixture.identity("Namespace.Status", "finished")
        ])
    }

    @Test
    func rawEnumsWithoutRawInitializationAndOtherRawValueCallsDoNotRetainCases() {
        let fixture = PropertyWrapperResolverFixture.parse(["Status.swift": """
            enum Status: Int { case ready = 1, finished = 2 }
            struct Other {
                var value = 0
                init(rawValue: Int) {}
            }
            func use() {
                _ = Status.ready.rawValue
                _ = Other(rawValue: 1)
            }
            """])

        #expect(resolve(fixture).isEmpty)
    }

    @Test
    func manualRawInitializerInAnotherFileDoesNotConsumeEveryCase() {
        let fixture = PropertyWrapperResolverFixture.parse([
            "Status.swift": """
                enum Status: Int { case ready = 1, finished = 2 }
                """,
            "Initializer.swift": """
                extension Status { init?(rawValue: Int) { return nil } }
                """,
            "Usage.swift": """
                let value = Status(rawValue: 1)
                let factory = Status.init(rawValue:)
                """
        ])

        #expect(resolve(fixture).isEmpty)
    }

    @Test(arguments: ["CaseIterable", "Swift.CaseIterable", "P", "Alias", "Namespace.Iterable"])
    func caseIterableRecognizesInheritedAliasedAndQualifiedConformances(_ conformance: String) throws {
        let fixture = PropertyWrapperResolverFixture.parse(["Status.swift": """
            protocol P: Swift.CaseIterable {}
            typealias Alias = P
            struct Namespace { typealias Iterable = Swift.CaseIterable }
            enum Status: \(conformance) {
                case ready, finished
                var helper: Int { 0 }
            }
            enum Unrelated { case ready, finished }
            """])

        #expect(resolve(fixture) == [
            try fixture.identity("Status", "ready"),
            try fixture.identity("Status", "finished")
        ])
    }

    @Test(arguments: [
        "static var allCases: [Self] { [] }",
        "static let allCases: [Self] = []"
    ])
    func manualAllCasesInAnotherFileDisablesCaseIterableSynthesis(_ member: String) {
        let fixture = PropertyWrapperResolverFixture.parse([
            "Status.swift": """
                enum Status: CaseIterable { case ready, finished }
                """,
            "AllCases.swift": """
                extension Status { \(member) }
                """
        ])

        #expect(resolve(fixture).isEmpty)
    }

    @Test
    func instanceOrUnrelatedAllCasesDoesNotDisableCaseIterableSynthesis() throws {
        let fixture = PropertyWrapperResolverFixture.parse(["Status.swift": """
            enum Status: CaseIterable {
                case ready, finished
                var allCases: [Self] { [] }
            }
            enum Other {
                case unrelated
                static var allCases: [Self] { [] }
            }
            """])

        #expect(resolve(fixture) == [
            try fixture.identity("Status", "ready"),
            try fixture.identity("Status", "finished")
        ])
    }

    @Test(arguments: ["Equatable", "Hashable", "Encodable", "Decodable", "Codable", "Swift.Codable"])
    func enumEqualityHashingAndCodingSynthesisConsumesEveryCase(_ conformance: String) throws {
        let fixture = PropertyWrapperResolverFixture.parse(["Choice.swift": """
            enum Choice: \(conformance) {
                case empty, number(Int), text(value: String)
                var helper: Int { 0 }
                static var shared = 0
                enum Nested { case unrelated }
            }
            enum Unrelated { case empty, number(Int) }
            """])

        #expect(resolve(fixture) == [
            try fixture.identity("Choice", "empty"),
            try fixture.identity("Choice", "number"),
            try fixture.identity("Choice", "text")
        ])
    }

    @Test
    func fullyManualEnumWitnessesDoNotConsumeCases() {
        let fixture = PropertyWrapperResolverFixture.parse(["Choice.swift": """
            enum Equality: Equatable {
                case first, second
                static func == (_ lhs: Self, _ rhs: Self) -> Bool { true }
            }
            enum Hashing: Hashable {
                case first, second
                static func == (_ lhs: Self, _ rhs: Self) -> Bool { true }
                func hash(into hasher: inout Hasher) {}
            }
            enum Coding: Codable {
                case first, second
                func encode(to encoder: Encoder) throws {}
                init(from decoder: Decoder) throws { self = .first }
            }
            """])

        #expect(resolve(fixture).isEmpty)
    }

    @Test
    func sameNamedOwnersAndUnrelatedManualWitnessesRemainIndependent() throws {
        let fixture = PropertyWrapperResolverFixture.parse([
            "Models.swift": """
                struct First { struct Model: Equatable { var value = 0 } }
                struct Second { struct Model: Equatable { var value = 0 } }
                struct Other { var value = 0 }
                """,
            "Witnesses.swift": """
                extension Second.Model {
                    static func == (_ lhs: Second.Model, _ rhs: Second.Model) -> Bool { true }
                }
                extension Other {
                    static func == (_ lhs: Other, _ rhs: Other) -> Bool { true }
                    func hash(into hasher: inout Hasher) {}
                    func encode(to encoder: Encoder) throws {}
                    init(from decoder: Decoder) throws {}
                }
                """
        ])

        #expect(resolve(fixture) == [try fixture.identity("First.Model", "value")])
    }

    @Test(arguments: ["Equatable", "Hashable", "Encodable", "Decodable", "Codable", "CaseIterable"])
    func projectProtocolsWithBuiltinNamesDoNotTriggerSynthesis(_ name: String) {
        let fixture = PropertyWrapperResolverFixture.parse(["Custom.swift": """
            protocol \(name) {}
            typealias Alias = \(name)
            struct Model: Alias { var value = 0 }
            enum Choice: \(name) { case first, second }
            """])

        #expect(resolve(fixture).isEmpty)
    }

    @Test(arguments: ["Equatable", "Hashable", "Encodable", "Decodable", "Codable", "CaseIterable"])
    func explicitSwiftProtocolsAreNotShadowedByProjectProtocols(_ name: String) throws {
        let fixture = PropertyWrapperResolverFixture.parse(["Custom.swift": """
            protocol \(name) {}
            enum Custom: \(name) { case unrelated }
            enum Builtin: Swift.\(name) { case first, second }
            """])

        #expect(resolve(fixture) == [
            try fixture.identity("Builtin", "first"),
            try fixture.identity("Builtin", "second")
        ])
    }

    @Test
    func unrelatedAndQualifiedCustomProtocolsDoNotTriggerSynthesis() {
        let fixture = PropertyWrapperResolverFixture.parse(["Custom.swift": """
            protocol Custom {}
            protocol Child: Custom {}
            struct Namespace { protocol Equatable {} }
            struct Model: Child { var value = 0 }
            struct Other: Namespace.Equatable { var value = 0 }
            enum Choice: Custom { case first, second }
            """])

        #expect(resolve(fixture).isEmpty)
    }

    @Test(arguments: [MemberKind.type, .property])
    func declarationsWithoutTypeOrMemberIdentitiesAreIgnored(_ kind: MemberKind) {
        let fixture = PropertyWrapperResolverFixture.parse(["Model.swift": """
            struct Model: Equatable { var value = 0 }
            """])
        let declarations = fixture.declarations.map { declaration in
            var declaration = declaration
            if declaration.identity?.signature.kind == kind {
                declaration.identity = nil
            }
            return declaration
        }

        #expect(SynthesizedDependencyResolver(
            declarations: declarations, parsedFiles: fixture.parsedFiles, graph: fixture.graph
        ).resolve().isEmpty)
    }

    @Test
    func missingMemberIdentityDoesNotDiscardOtherSynthesizedDependencies() throws {
        let fixture = PropertyWrapperResolverFixture.parse(["Model.swift": """
            struct Model: Equatable { var first = 0, second = 1 }
            """])
        let first = try fixture.identity("Model", "first")
        let declarations = fixture.declarations.map { declaration in
            var declaration = declaration
            if declaration.identity == first {
                declaration.identity = nil
            }
            return declaration
        }

        #expect(SynthesizedDependencyResolver(
            declarations: declarations, parsedFiles: fixture.parsedFiles, graph: fixture.graph
        ).resolve() == [try fixture.identity("Model", "second")])
    }

    @Test
    func emptyInputsAndMissingParsedFilesAreSafe() {
        let fixture = PropertyWrapperResolverFixture.parse(["Model.swift": """
            struct Model: Codable { var value = 0 }
            """])

        #expect(SynthesizedDependencyResolver(
            declarations: [], parsedFiles: [], graph: fixture.graph
        ).resolve().isEmpty)
        #expect(SynthesizedDependencyResolver(
            declarations: [], parsedFiles: fixture.parsedFiles, graph: fixture.graph
        ).resolve().isEmpty)
        #expect(SynthesizedDependencyResolver(
            declarations: fixture.declarations, parsedFiles: [], graph: fixture.graph
        ).resolve().isEmpty)
    }
}

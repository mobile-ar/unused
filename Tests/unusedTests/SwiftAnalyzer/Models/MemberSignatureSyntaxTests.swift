import SwiftParser
import SwiftSyntax
import Testing
@testable import unused

struct MemberSignatureSyntaxTests {
    @Test
    func functionSignaturesNormalizeEscapingTriviaAndCaptureEffects() throws {
        let declaration = try parseMember(
            "static func `default`<`Type`>(_ `repeat`: Namespace.Box<`Type`>, `class` value: String) async throws -> Namespace.Item<`Type`> {}",
            as: FunctionDeclSyntax.self
        )
        let signature = MemberSignature(function: declaration)
        #expect(signature.kind == .function)
        #expect(signature.name == "default")
        #expect(signature.isStatic)
        #expect(signature.parameterLabels == ["_", "class"])
        #expect(signature.parameterTypes == ["Namespace.Box<Type>", "String"])
        #expect(signature.resultType == "Namespace.Item<Type>")
        #expect(signature.genericParameters == ["Type"])
        #expect(signature.isAsync)
        #expect(signature.isThrowing)
    }

    @Test
    func overloadsKeepLabelsTypesSpecializationsAndEffectsDistinct() throws {
        let spellings = [
            "func run(_ value: Box<Int>) {}",
            "func run(_ value: Box<String>) {}",
            "func run(value: Box<Int>) {}",
            "static func run(_ value: Box<Int>) {}",
            "func run(_ value: Box<Int>) async {}",
            "func run(_ value: Box<Int>) throws {}"
        ]
        let signatures = try spellings.map { MemberSignature(function: try parseMember($0, as: FunctionDeclSyntax.self)) }
        #expect(Set(signatures).count == spellings.count)
    }

    @Test
    func parameterNamesAndFormattingDoNotChangeSignatures() throws {
        let first = try parseMember("func run(label first: Box < Int >) -> [ String ] {}", as: FunctionDeclSyntax.self)
        let second = try parseMember("func run(label second: Box<Int>) -> [String] {}", as: FunctionDeclSyntax.self)
        #expect(MemberSignature(function: first) == MemberSignature(function: second))
    }

    @Test
    func wordBoundariesAndVariadicTypesArePreserved() throws {
        let declaration = try parseMember("func run(_ value: any Drawable, values: Int...) {}", as: FunctionDeclSyntax.self)
        let signature = MemberSignature(function: declaration)
        #expect(signature.parameterTypes == ["any Drawable", "Int..."])
        #expect(signature.parameterLabels == ["_", "values"])
        #expect(signature.defaultParameterIndices.isEmpty)
        #expect(signature.variadicParameterIndices == [1])
        #expect(signature.resultType == nil)
        #expect(!signature.isStatic)
        #expect(!signature.isAsync)
        #expect(!signature.isThrowing)
    }

    @Test
    func initializersCaptureGenericParametersFailabilityAndEffects() throws {
        let declaration = try parseMember("init?<T>(`class` value: T) async throws {}", as: InitializerDeclSyntax.self)
        let signature = MemberSignature(initializer: declaration)
        #expect(signature.kind == .initializer)
        #expect(signature.name == "init")
        #expect(signature.parameterLabels == ["class"])
        #expect(signature.parameterTypes == ["T"])
        #expect(signature.genericParameters == ["T"])
        #expect(signature.resultType == "Self?")
        #expect(signature.isAsync)
        #expect(signature.isThrowing)
    }

    @Test
    func subscriptsUseImplicitUnderscoreLabelsAndGetterEffects() throws {
        let declaration = try parseMember(
            "static subscript<T>(index: Int, named value: T) -> Namespace.Item<T> { get async throws { fatalError() } }",
            as: SubscriptDeclSyntax.self
        )
        let signature = MemberSignature(subscript: declaration)
        #expect(signature.kind == .subscript)
        #expect(signature.name == "subscript")
        #expect(signature.isStatic)
        #expect(signature.parameterLabels == ["_", "named"])
        #expect(signature.parameterTypes == ["Int", "T"])
        #expect(signature.resultType == "Namespace.Item<T>")
        #expect(signature.genericParameters == ["T"])
        #expect(signature.isAsync)
        #expect(signature.isThrowing)
    }

    @Test
    func propertiesUseEachBindingAndClassMembersAreStatic() throws {
        let declaration = try parseMember("class var `repeat`: Namespace.Item, second: String", as: VariableDeclSyntax.self)
        let bindings = Array(declaration.bindings)
        #expect(bindings.count == 2)
        let first = MemberSignature(variable: declaration, binding: try #require(bindings.first))
        let second = MemberSignature(variable: declaration, binding: try #require(bindings.last))
        #expect(first.kind == .property)
        #expect(first.name == "repeat")
        #expect(first.resultType == "Namespace.Item")
        #expect(first.isStatic)
        #expect(second.name == "second")
        #expect(second.resultType == "String")
        #expect(first != second)
    }

    @Test
    func effectfulAndInferredPropertiesHaveExpectedSignatures() throws {
        let effectful = try parseMember("var value: Int { get async throws { 0 } }", as: VariableDeclSyntax.self)
        let inferred = try parseMember("let value = 0", as: VariableDeclSyntax.self)
        let signature = MemberSignature(variable: effectful, binding: try #require(effectful.bindings.first))
        #expect(signature.isAsync)
        #expect(signature.isThrowing)
        #expect(MemberSignature(variable: inferred, binding: try #require(inferred.bindings.first)).resultType == nil)
    }

    @Test
    func associatedTypesAndAliasesCaptureDefaultsAndTargets() throws {
        let associated = try parseMember("associatedtype `Type` = Namespace.Item", as: AssociatedTypeDeclSyntax.self)
        let alias = try parseMember("typealias `default`<`Type`> = Namespace.Box<`Type`>", as: TypeAliasDeclSyntax.self)
        let associatedSignature = MemberSignature(associatedType: associated)
        let aliasSignature = MemberSignature(typealiasDeclaration: alias)
        #expect(associatedSignature.kind == .associatedType)
        #expect(associatedSignature.name == "Type")
        #expect(associatedSignature.resultType == "Namespace.Item")
        #expect(aliasSignature.kind == .typealiasDeclaration)
        #expect(aliasSignature.name == "default")
        #expect(aliasSignature.resultType == "Namespace.Box<Type>")
        #expect(aliasSignature.genericParameters == ["Type"])
    }

    @Test
    func functionsCaptureDefaultAndVariadicIndicesByParameterPosition() throws {
        let declaration = try parseMember(
            "func run(prefix: String = \"\", value: Int, values: Double..., completion: () -> Void = {}) {}",
            as: FunctionDeclSyntax.self
        )
        let signature = MemberSignature(function: declaration)

        #expect(signature.parameterLabels == ["prefix", "value", "values", "completion"])
        #expect(signature.parameterTypes == ["String", "Int", "Double...", "()->Void"])
        #expect(signature.defaultParameterIndices == [0, 3])
        #expect(signature.variadicParameterIndices == [2])
    }

    @Test
    func initializersCaptureDefaultsVariadicsAndExternalLabels() throws {
        let declaration = try parseMember(
            "init(_ value: Int = 0, named name: String, values: Double..., completion: () -> Void = {}) {}",
            as: InitializerDeclSyntax.self
        )
        let signature = MemberSignature(initializer: declaration)

        #expect(signature.kind == .initializer)
        #expect(signature.parameterLabels == ["_", "named", "values", "completion"])
        #expect(signature.parameterTypes == ["Int", "String", "Double...", "()->Void"])
        #expect(signature.defaultParameterIndices == [0, 3])
        #expect(signature.variadicParameterIndices == [2])
    }

    @Test
    func subscriptsCaptureDefaultsVariadicsAndImplicitUnderscoreLabels() throws {
        let declaration = try parseMember(
            "subscript(index: Int = 0, named key: String, values: Double..., fallback value: Int = 1) -> Int { 0 }",
            as: SubscriptDeclSyntax.self
        )
        let signature = MemberSignature(subscript: declaration)

        #expect(signature.kind == .subscript)
        #expect(signature.parameterLabels == ["_", "named", "_", "fallback"])
        #expect(signature.parameterTypes == ["Int", "String", "Double...", "Int"])
        #expect(signature.defaultParameterIndices == [0, 3])
        #expect(signature.variadicParameterIndices == [2])
    }

    @Test
    func requiredNonvariadicParametersHaveEmptyIndexSetsForEveryCallableKind() throws {
        let function = MemberSignature(function: try parseMember(
            "func run(value: Int) {}", as: FunctionDeclSyntax.self
        ))
        let initializer = MemberSignature(initializer: try parseMember(
            "init(value: Int) {}", as: InitializerDeclSyntax.self
        ))
        let subscriptSignature = MemberSignature(subscript: try parseMember(
            "subscript(index: Int) -> Int { 0 }", as: SubscriptDeclSyntax.self
        ))

        for signature in [function, initializer, subscriptSignature] {
            #expect(signature.defaultParameterIndices.isEmpty)
            #expect(signature.variadicParameterIndices.isEmpty)
        }
    }

    @Test
    func parameterlessFunctionsAndInitializersHaveEmptyParameterMetadata() throws {
        let function = MemberSignature(function: try parseMember("func run() {}", as: FunctionDeclSyntax.self))
        let initializer = MemberSignature(initializer: try parseMember("init() {}", as: InitializerDeclSyntax.self))

        for signature in [function, initializer] {
            #expect(signature.parameterLabels.isEmpty)
            #expect(signature.parameterTypes.isEmpty)
            #expect(signature.defaultParameterIndices.isEmpty)
            #expect(signature.variadicParameterIndices.isEmpty)
        }
    }

    @Test
    func defaultExpressionContentsDoNotChangeSignatureIdentity() throws {
        let first = MemberSignature(function: try parseMember(
            "func run(value: Int = 1, completion: () -> Void = {}) {}", as: FunctionDeclSyntax.self
        ))
        let second = MemberSignature(function: try parseMember(
            "func run(value: Int = compute(2, 3), completion: () -> Void = { print(1) }) {}",
            as: FunctionDeclSyntax.self
        ))

        #expect(first.defaultParameterIndices == [0, 1])
        #expect(second.defaultParameterIndices == [0, 1])
        #expect(first == second)
        #expect(Set([first, second]).count == 1)
    }

    @Test
    func defaultParameterPositionsParticipateInSignatureEqualityAndHashing() throws {
        let spellings = [
            "func run(first: Int, second: Int) {}",
            "func run(first: Int = 0, second: Int) {}",
            "func run(first: Int, second: Int = 0) {}",
            "func run(first: Int = 0, second: Int = 0) {}"
        ]
        let signatures = try spellings.map {
            MemberSignature(function: try parseMember($0, as: FunctionDeclSyntax.self))
        }

        #expect(signatures.map(\.defaultParameterIndices) == [[], [0], [1], [0, 1]])
        #expect(Set(signatures).count == spellings.count)
    }

    @Test
    func variadicIndicesUseParameterPositionsRatherThanLabelOccurrences() throws {
        let declaration = try parseMember(
            "func run(value first: Int = 0, value remaining: Int..., end: String) {}",
            as: FunctionDeclSyntax.self
        )
        let signature = MemberSignature(function: declaration)

        #expect(signature.parameterLabels == ["value", "value", "end"])
        #expect(signature.defaultParameterIndices == [0])
        #expect(signature.variadicParameterIndices == [1])
        #expect(signature.parameterTypes == ["Int", "Int...", "String"])
    }

    private func parseMember<Node: DeclSyntaxProtocol>(_ source: String, as type: Node.Type) throws -> Node {
        let sourceFile = Parser.parse(source: "struct Fixture { \(source) }")
        let declaration = try #require(sourceFile.statements.first?.item.as(StructDeclSyntax.self))
        return try #require(declaration.memberBlock.members.first?.decl.as(type))
    }
}

import Testing
import SwiftSyntax
import SwiftParser
@testable import unused

struct WriteOnlyScopeSafetyTests {

    private func visitor(
        source: String,
        properties: [String: [String]] = ["Subject": ["value"]]
    ) -> WriteOnlyVariableVisitor {
        let typeProperties = properties.reduce(into: [String: [PropertyInfo]]()) { result, entry in
            result[entry.key] = entry.value.enumerated().map { index, name in
                PropertyInfo(name: name, line: index + 1, filePath: "test.swift", typeName: entry.key)
            }
        }
        return visitor(source: source, typeProperties: typeProperties)
    }

    private func visitor(
        source: String,
        typeProperties: [String: [PropertyInfo]],
        propertyWrappers: Set<String> = []
    ) -> WriteOnlyVariableVisitor {
        let sourceFile = Parser.parse(source: source)
        #expect(!sourceFile.hasError, "The scope regression fixture must parse without errors")
        let visitor = WriteOnlyVariableVisitor(
            filePath: "test.swift",
            typeProperties: typeProperties,
            propertyWrappers: propertyWrappers
        )
        visitor.walk(sourceFile)
        return visitor
    }

    private func methodVisitor(
        _ body: String,
        parameters: String = "",
        properties: [String] = ["value"]
    ) -> WriteOnlyVariableVisitor {
        let declarations = properties.map { "var \($0): Int? = nil" }.joined(separator: "\n")
        return visitor(
            source: """
            struct Subject {
                \(declarations)
                func inspect(\(parameters)) {
                    \(body)
                }
            }
            """,
            properties: ["Subject": properties]
        )
    }

    @Test(arguments: [
        "do { let value = 1; print(value) }",
        "if true { let value = 1; print(value) } else {}",
        "if false {} else { let value = 1; print(value) }",
        "if let value = Optional(1) { print(value) }",
        "while false { let value = 1; print(value) }",
        "while let value = Optional(1) { print(value); break }",
        "repeat { let value = 1; print(value) } while false",
        "switch 1 { case 1: let value = 1; print(value); default: break }",
        "switch Optional(1) { case let .some(value): print(value); case .none: break }",
        "switch Optional(1) { case .some(let value): print(value); case .none: break }",
        "do {} catch let value { print(value) }",
        "for value in [1] { print(value) }",
        "for (value, other) in [(1, 2)] { print(value, other) }",
        "for case let .some(value) in [Optional(1)] { print(value) }",
        "let handler = { (value: Int) in print(value) }; handler(1)",
        "let handler = { value in print(value) }; handler(1)",
        "do { guard let value = Optional(1) else { return }; print(value) }"
    ])
    func temporaryShadowsDoNotReadProperties(_ body: String) {
        let visitor = methodVisitor(body)
        #expect(visitor.propertyReads.isEmpty)
        #expect(visitor.propertyWrites.isEmpty)
    }

    @Test(arguments: [
        "do { let value = 1; print(value) }",
        "if true { let value = 1; print(value) } else {}",
        "if false {} else { let value = 1; print(value) }",
        "if let value = Optional(1) { print(value) }",
        "while false { let value = 1; print(value) }",
        "while let value = Optional(1) { print(value); break }",
        "repeat { let value = 1; print(value) } while false",
        "switch 1 { case 1: let value = 1; print(value); default: break }",
        "switch Optional(1) { case let .some(value): print(value); case .none: break }",
        "do {} catch let value { print(value) }",
        "for value in [1] { print(value) }",
        "for (value, other) in [(1, 2)] { print(value, other) }",
        "for case let .some(value) in [Optional(1)] { print(value) }",
        "let handler = { (value: Int) in print(value) }; handler(1)",
        "do { guard let value = Optional(1) else { return }; print(value) }"
    ])
    func propertyReadsResumeAfterTemporaryShadows(_ body: String) {
        let visitor = methodVisitor(body + "\nprint(value)")
        #expect(Set(visitor.propertyReads.map(\.name)) == ["value"])
    }

    @Test(arguments: [
        "if let value = Optional(1) { print(value) } else { print(value) }",
        "if let value = Optional(1) {} else if value != nil {}",
        "if true { let value = 1; print(value) } else { print(value) }",
        "switch 1 { case 0: let value = 1; print(value); default: print(value) }",
        "switch Optional(1) { case let .some(value): print(value); case .none: print(value) }",
        "do { let value = 1; print(value) } catch { print(value) }",
        "do {} catch let value { print(value) } catch { print(value) }"
    ])
    func siblingBranchesDoNotInheritBindings(_ body: String) {
        let visitor = methodVisitor(body)
        #expect(Set(visitor.propertyReads.map(\.name)) == ["value"])
    }

    @Test(arguments: [
        "if let value { print(value) }",
        "guard let value else { return }; print(value)",
        "while let value { print(value); break }"
    ])
    func shorthandOptionalBindingsReadTheOriginalProperty(_ body: String) {
        let visitor = methodVisitor(body)
        #expect(Set(visitor.propertyReads.map(\.name)) == ["value"])
    }

    @Test(arguments: [
        "if let value { print(value) }",
        "guard let value else { return }; print(value)",
        "while let value { print(value); break }"
    ])
    func shorthandOptionalBindingsDoNotReadShadowedProperties(_ body: String) {
        let localVisitor = methodVisitor("let value: Int? = 1\n" + body)
        #expect(localVisitor.propertyReads.isEmpty)

        let parameterVisitor = methodVisitor(body, parameters: "value: Int?")
        #expect(parameterVisitor.propertyReads.isEmpty)
    }

    @Test(arguments: [
        "if let value = Optional<Int?>(1), let value { print(value) }",
        "guard let value = Optional<Int?>(1), let value else { return }; print(value)",
        "while let value = Optional<Int?>(1), let value { print(value); break }"
    ])
    func shorthandBindingsSeeLocalsIntroducedByEarlierConditions(_ body: String) {
        let visitor = methodVisitor(body)
        #expect(visitor.propertyReads.isEmpty)
    }

    @Test(arguments: [
        "let value = value; print(value)",
        "if let value = value { print(value) }",
        "guard let value = value else { return }; print(value)",
        "while let value = value { print(value); break }",
        "if case let .some(value) = value { print(value) }",
        "guard case let .some(value) = value else { return }; print(value)",
        "while case let .some(value) = value { print(value); break }"
    ])
    func initializersReadPropertiesBeforeBindingTheirShadows(_ body: String) {
        let visitor = methodVisitor(body)
        #expect(Set(visitor.propertyReads.map(\.name)) == ["value"])
    }

    @Test(arguments: [
        "let value = value; print(value)",
        "if let value = value { print(value) }",
        "guard let value = value else { return }; print(value)",
        "while let value = value { print(value); break }",
        "if case let .some(value) = value { print(value) }",
        "guard case let .some(value) = value else { return }; print(value)",
        "while case let .some(value) = value { print(value); break }"
    ])
    func initializersReadExistingLocalsInsteadOfProperties(_ body: String) {
        let visitor = methodVisitor(body, parameters: "value: Int?")
        #expect(visitor.propertyReads.isEmpty)
    }

    @Test(arguments: [
        "let value = 1; print(value)",
        "var value: Int; value = 1; print(value)",
        "let (value, other) = (1, 2); print(value, other)",
        "let (value, (other, _)) = (1, (2, 3)); print(value, other)",
        "let value = Optional(1), other = value; print(value, other)"
    ])
    func ordinaryDeclarationsAreNotImplicitReads(_ body: String) {
        let visitor = methodVisitor(body, properties: ["value", "other"])
        #expect(visitor.propertyReads.isEmpty)
        #expect(visitor.propertyWrites.isEmpty)
    }

    @Test
    func tupleInitializerReadsAllPropertiesBeforeBindingThePattern() {
        let visitor = methodVisitor(
            "let (value, other) = (value, other); print(value, other)",
            properties: ["value", "other"]
        )
        #expect(Set(visitor.propertyReads.map(\.name)) == ["value", "other"])
    }

    @Test
    func multipleDeclarationsAreVisitedInSourceOrder() {
        let visitor = methodVisitor(
            "let other = value, value = Optional(1); print(value, other)",
            properties: ["value", "other"]
        )
        #expect(Set(visitor.propertyReads.map(\.name)) == ["value"])
    }

    @Test(arguments: [
        "if value != nil, let value = Optional(1) { print(value) }",
        "guard value != nil, let value = Optional(1) else { return }; print(value)",
        "while value != nil, let value = Optional(1) { print(value); break }"
    ])
    func conditionsBeforeABindingSeeTheOriginalProperty(_ body: String) {
        let visitor = methodVisitor(body)
        #expect(Set(visitor.propertyReads.map(\.name)) == ["value"])
    }

    @Test(arguments: [
        "if let value = Optional(1), let other = Optional(value), other > 0 { print(value, other) }",
        "guard let value = Optional(1), let other = Optional(value), other > 0 else { return }; print(value, other)",
        "while let value = Optional(1), let other = Optional(value), other > 0 { print(value, other); break }",
        "if case let .some(value) = Optional(1), value > 0 { print(value) }",
        "guard case let .some(value) = Optional(1), value > 0 else { return }; print(value)",
        "while case let .some(value) = Optional(1), value > 0 { print(value); break }"
    ])
    func laterConditionsSeeEarlierBindings(_ body: String) {
        let visitor = methodVisitor(body, properties: ["value", "other"])
        #expect(visitor.propertyReads.isEmpty)
    }

    @Test
    func guardElseSeesTheOriginalPropertyRatherThanSuccessfulBindings() {
        let visitor = methodVisitor("""
            guard let value = Optional(1), value > 0 else {
                print(value)
                return
            }
            print(value)
            """)
        #expect(Set(visitor.propertyReads.map(\.name)) == ["value"])
    }

    @Test
    func guardElseSeesAnExistingLocalRatherThanTheProperty() {
        let visitor = methodVisitor(
            "guard let value = Optional(1) else { print(value); return }; print(value)",
            parameters: "value: Int?"
        )
        #expect(visitor.propertyReads.isEmpty)
    }

    @Test
    func successfulGuardBindingsPersistButElseLocalsDoNot() {
        let visitor = methodVisitor(
            """
            guard let value = Optional(1) else {
                let other = 2
                print(other)
                return
            }
            print(value, other)
            """,
            properties: ["value", "other"]
        )
        #expect(Set(visitor.propertyReads.map(\.name)) == ["other"])
    }

    @Test
    func nestedGuardElseBindingsDoNotLeakIntoTheSuccessPath() {
        let visitor = methodVisitor(
            """
            guard let value = Optional(1) else {
                guard let other = Optional(2) else { return }
                print(other)
                return
            }
            print(value, other)
            """,
            properties: ["value", "other"]
        )
        #expect(Set(visitor.propertyReads.map(\.name)) == ["other"])
    }

    @Test(arguments: [
        "switch Optional(1) { case value: break; default: break }",
        "switch Optional(1) { case .some(value): break; default: break }"
    ])
    func caseExpressionPatternsRemainPropertyReads(_ body: String) {
        let visitor = methodVisitor(body)
        #expect(Set(visitor.propertyReads.map(\.name)) == ["value"])
    }

    @Test(arguments: [
        "evaluate({ let value = B(); return value.probe() })",
        "(evaluate({ let value = B(); return value.probe() }))",
        "evaluate({ let (value, _) = (B(), 0); return value.probe() })",
        "evaluate({ guard let value = Optional(B()) else { return 0 }; return value.probe() })",
        "evaluate({ let action = { let value = B(); return value.probe() }; return action() })",
        "(evaluate { let value = B(); return value.probe() })"
    ])
    func expressionPatternClosureLocalsDoNotBecomeCaseBindings(_ expression: String) {
        let source = """
            struct A {}
            struct B { func probe() -> Int { 1 } }
            func evaluate(_ body: () -> Int) -> Int { body() }
            struct Subject {
                var value: A?
                func inspect() {
                    switch 1 {
                    case \(expression):
                        if let value { print(value) }
                    default: break
                    }
                }
            }
            """
        let readVisitor = visitor(source: source)
        #expect(Set(readVisitor.propertyReads.map(\.name)) == ["value"])
        #expect(Set(readVisitor.propertyReads.map(\.typeName)) == ["Subject"])

        let shadowVisitor = visitor(source: source.replacing("if let value { print(value) }", with: "break"))
        #expect(shadowVisitor.propertyReads.isEmpty)
    }

    @Test(arguments: [
        "(evaluate { value })",
        "(evaluate({ 0 }) { value })",
        "(evaluate { let value = 1; return value } fallback: { value })",
        "(evaluate { 0 } fallback: { 0 } final: { value })"
    ])
    func expressionPatternTrailingClosuresRetainPropertyReads(_ expression: String) {
        let source = """
            func evaluate(_ body: () -> Int) -> Int { body() }
            func evaluate(_ body: () -> Int, fallback: () -> Int) -> Int { body() + fallback() }
            func evaluate(_ body: () -> Int, fallback: () -> Int, final: () -> Int) -> Int {
                body() + fallback() + final()
            }
            struct Subject {
                var value = 1
                func inspect() {
                    switch 1 {
                    case \(expression): break
                    default: break
                    }
                }
            }
            """
        let readVisitor = visitor(source: source)
        #expect(Set(readVisitor.propertyReads.map(\.name)) == ["value"])

        let shadowVisitor = visitor(source: source.replacing("func inspect()", with: "func inspect(value: Int)"))
        #expect(shadowVisitor.propertyReads.isEmpty)
    }

    @Test(arguments: [
        "(evaluate { let value = 1; return value })",
        "(evaluate { let value = 1; return value } fallback: { let value = 2; return value })"
    ])
    func expressionPatternTrailingClosuresKeepLocalShadowScopes(_ expression: String) {
        let source = """
            func evaluate(_ body: () -> Int) -> Int { body() }
            func evaluate(_ body: () -> Int, fallback: () -> Int) -> Int { body() + fallback() }
            struct Subject {
                var value: Int?
                func inspect() {
                    switch 1 {
                    case \(expression): break
                    default: break
                    }
                }
            }
            """
        let shadowVisitor = visitor(source: source)
        #expect(shadowVisitor.propertyReads.isEmpty)

        let readVisitor = visitor(source: source.replacing("case \(expression): break", with: "case \(expression): if let value { print(value) }"))
        #expect(Set(readVisitor.propertyReads.map(\.name)) == ["value"])
    }

    @Test
    func expressionPatternClosureParametersDoNotBecomeCaseBindings() {
        let visitor = visitor(source: """
            func evaluate(_ body: (Int) -> Int) -> Int { body(1) }
            struct Subject {
                var value: Int?
                func inspect() {
                    switch 1 {
                    case evaluate({ (value: Int) in value }):
                        if let value { print(value) }
                    default: break
                    }
                }
            }
            """)
        #expect(Set(visitor.propertyReads.map(\.name)) == ["value"])
    }

    @Test
    func expressionClosuresInsideTuplePatternsDoNotIntroduceBindings() {
        let visitor = visitor(source: """
            struct A {}
            struct B { func probe() -> Int { 1 } }
            func evaluate(_ body: () -> Int) -> Int { body() }
            struct Subject {
                var value: A?
                var other: Int?
                func inspect() {
                    switch (1, 2) {
                    case (evaluate({ let value = B(); return value.probe() }), let other):
                        if let value { print(value) }
                        print(other)
                    default: break
                    }
                }
            }
            """,
            properties: ["Subject": ["value", "other"]]
        )
        #expect(Set(visitor.propertyReads.map(\.name)) == ["value"])
    }

    @Test
    func tupleCaseBindingsShadowOnlyTheirBoundNames() {
        let visitor = methodVisitor(
            """
            switch (1, 2) {
            case (let value, 2) where value > 0: print(value)
            default: break
            }
            """,
            properties: ["value", "other"]
        )
        #expect(visitor.propertyReads.isEmpty)
    }

    @Test
    func expressionPatternsAreReadBeforeTupleBindingsEnterScope() {
        let visitor = methodVisitor("""
            switch (1, Optional(2)) {
            case (let value, value): print(value)
            default: break
            }
            """)
        #expect(Set(visitor.propertyReads.map(\.name)) == ["value"])
    }

    @Test(arguments: [
        "switch Optional(1) { case let value?: print(value); case nil: break }",
        "if case let value? = Optional(1) { print(value) }",
        "guard case let value? = Optional(1) else { return }; print(value)",
        "while case let value? = Optional(1) { print(value); break }"
    ])
    func optionalCasePatternsRegisterTheirBindings(_ body: String) {
        let visitor = methodVisitor(body)
        #expect(visitor.propertyReads.isEmpty)
    }

    @Test
    func caseAlternativesHaveIndependentWhereClauseBindings() {
        let visitor = methodVisitor(
            """
            enum Payload { case first(Int), second(Int) }
            switch Payload.first(1) {
            case .first(let value) where value > 0,
                 .second(let value) where value > 0:
                print(value)
            }
            """
        )
        #expect(visitor.propertyReads.isEmpty)
    }

    @Test
    func caseBindingsDoNotHidePropertiesInOtherCasePatterns() {
        let visitor = methodVisitor("""
            switch Optional(1) {
            case let .some(value): print(value)
            case value: break
            default: break
            }
            """)
        #expect(Set(visitor.propertyReads.map(\.name)) == ["value"])
    }

    @Test
    func enumCaseNamesAreNotRegisteredAsLocalBindings() {
        let visitor = methodVisitor(
            """
            enum Payload { case some(Int) }
            switch Payload.some(1) {
            case let Payload.some(value): print(some, value)
            }
            """,
            properties: ["some", "value"]
        )
        #expect(Set(visitor.propertyReads.map(\.name)) == ["some"])
    }

    @Test
    func forSequencesAreReadBeforeLoopBindings() {
        let visitor = visitor(source: """
            struct Subject {
                var value = [1, 2]
                func inspect() {
                    for value in value where value > 0 { print(value) }
                }
            }
            """)
        #expect(Set(visitor.propertyReads.map(\.name)) == ["value"])
    }

    @Test
    func forWhereClausesSeeTupleBindings() {
        let visitor = methodVisitor(
            "for (value, other) in [(1, 2)] where value < other { print(value, other) }",
            properties: ["value", "other"]
        )
        #expect(visitor.propertyReads.isEmpty)
    }

    @Test
    func implicitCatchErrorHasOnlyCatchLifetime() {
        let shadowVisitor = methodVisitor("do {} catch { print(error) }", properties: ["error"])
        #expect(shadowVisitor.propertyReads.isEmpty)

        let readVisitor = methodVisitor("do {} catch { print(error) }; print(error)", properties: ["error"])
        #expect(Set(readVisitor.propertyReads.map(\.name)) == ["error"])
    }

    @Test
    func catchWhereClausesSeeTheirBindings() {
        let visitor = methodVisitor("do {} catch let value where value != nil { print(value) }")
        #expect(visitor.propertyReads.isEmpty)
    }

    @Test
    func catchCastBindingsShadowOnlyWithinTheirClause() {
        let shadowVisitor = methodVisitor("do {} catch let value as SomeError { print(value) }")
        #expect(shadowVisitor.propertyReads.isEmpty)

        let readVisitor = methodVisitor("do {} catch let value as SomeError { print(value) }; print(value)")
        #expect(Set(readVisitor.propertyReads.map(\.name)) == ["value"])
    }

    @Test
    func implicitCatchErrorIsAvailableInWhereClauses() {
        let visitor = methodVisitor("do {} catch where error != nil { print(error) }", properties: ["error"])
        #expect(visitor.propertyReads.isEmpty)
    }

    @Test(arguments: [
        "func inspect(value: Int) { print(value) }",
        "func inspect(_ value: Int) { print(value) }",
        "func inspect(label value: Int) { print(value) }",
        "init(value: Int) { self.value = value }",
        "subscript(value: Int) -> Int { value }",
        "subscript(value: Int) -> Int { get { value } set { print(value, newValue) } }"
    ])
    func parametersShadowPropertiesOnlyWithinTheirDeclaration(_ declaration: String) {
        let shadowVisitor = visitor(
            source: "struct Subject { var value: Int?; var newValue: Int?; \(declaration) }",
            properties: ["Subject": ["value", "newValue"]]
        )
        #expect(shadowVisitor.propertyReads.isEmpty)

        let readVisitor = visitor(source: """
            struct Subject {
                var value: Int?
                \(declaration)
                func readProperty() { print(value) }
            }
            """)
        #expect(Set(readVisitor.propertyReads.map(\.name)) == ["value"])
    }

    @Test
    func parameterDefaultsAreEvaluatedBeforeRegisteringParameters() {
        let visitor = visitor(source: """
            struct Subject {
                static var value = 1
                func inspect(value: Int = value) { print(value) }
            }
            """)
        #expect(Set(visitor.propertyReads.map(\.name)) == ["value"])
    }

    @Test(arguments: [
        "var proxy: Int { get { 0 } set(value) { print(value) } }",
        "var proxy = 0 { willSet(value) { print(value) } didSet(value) { print(value) } }",
        "var proxy: Int { get { 0 } set { print(newValue) } }",
        "var proxy = 0 { willSet { print(newValue) } didSet { print(oldValue) } }",
        "var proxy: Int { let value = 1; return value }",
        "var proxy: Int { get { let value = 1; return value } }"
    ])
    func accessorBindingsDoNotReadPropertiesOrLeak(_ declaration: String) {
        let shadowVisitor = visitor(
            source: "struct Subject { var value: Int?; var newValue: Int?; var oldValue: Int?; \(declaration) }",
            properties: ["Subject": ["value", "newValue", "oldValue"]]
        )
        #expect(shadowVisitor.propertyReads.isEmpty)

        let readVisitor = visitor(
            source: """
            struct Subject {
                var value: Int?
                var newValue: Int?
                var oldValue: Int?
                \(declaration)
                func inspect() { print(value, newValue, oldValue) }
            }
            """,
            properties: ["Subject": ["value", "newValue", "oldValue"]]
        )
        #expect(Set(readVisitor.propertyReads.map(\.name)) == ["value", "newValue", "oldValue"])
    }

    @Test
    func setterParametersDoNotShadowSiblingGetters() {
        let visitor = visitor(source: """
            struct Subject {
                var value: Int?
                var proxy: Int {
                    set(value) { print(value) }
                    get { value ?? 0 }
                }
            }
            """)
        #expect(Set(visitor.propertyReads.map(\.name)) == ["value"])
    }

    @Test
    func computedPropertyLocalsDoNotShadowSiblingProperties() {
        let visitor = visitor(source: """
            struct Subject {
                var value: Int?
                var first: Int { let value = 1; return value }
                var second: Int { value ?? 0 }
            }
            """)
        #expect(Set(visitor.propertyReads.map(\.name)) == ["value"])
    }

    @Test(arguments: [
        "let handler = { [value = value] in print(value) }",
        "let handler = { [value] in print(value) }"
    ])
    func closureCapturesReadOriginalBindingsBeforeShadowing(_ body: String) {
        let propertyVisitor = methodVisitor(body)
        #expect(Set(propertyVisitor.propertyReads.map(\.name)) == ["value"])

        let localVisitor = methodVisitor(body, parameters: "value: Int?")
        #expect(localVisitor.propertyReads.isEmpty)
    }

    @Test
    func explicitClosureCaptureBindingsDoNotLeak() {
        let shadowVisitor = methodVisitor("let handler = { [value = 1] in print(value) }")
        #expect(shadowVisitor.propertyReads.isEmpty)

        let readVisitor = methodVisitor("let handler = { [value = 1] in print(value) }; print(value)")
        #expect(Set(readVisitor.propertyReads.map(\.name)) == ["value"])
    }

    @Test(arguments: ["class", "struct", "enum", "actor"])
    func nestedOwnersUseCanonicalPathsAndRestoreTheOuterOwner(_ kind: String) {
        let visitor = visitor(
            source: """
            struct Outer {
                var value: Int? { nil }
                \(kind) Inner {
                    var value: Int? { nil }
                    func inspect() { if let value { print(value) } }
                }
                func inspect() { print(value) }
            }
            """,
            properties: ["Outer": ["value"], "Outer.Inner": ["value"], "Inner": ["value"]]
        )
        #expect(Set(visitor.propertyReads.map(\.typeName)) == ["Outer", "Outer.Inner"])
    }

    @Test
    func nestedGenericExtensionOwnersAreCanonicalAndUnescaped() {
        let visitor = visitor(
            source: """
            struct `class`<T> {
                struct `actor` {
                    var `repeat`: Int?
                }
            }
            extension `class`.`actor` {
                func inspect() { guard let `repeat` else { return }; print(`repeat`) }
            }
            """,
            properties: ["class.actor": ["repeat"]]
        )
        #expect(Set(visitor.propertyReads.map(\.name)) == ["repeat"])
        #expect(Set(visitor.propertyReads.map(\.typeName)) == ["class.actor"])
    }

    @Test
    func specializedExtensionOwnersUseTheCanonicalType() {
        let visitor = visitor(
            source: """
            struct Container<T> { var value: Int? }
            extension Container<Int> {
                func inspect() { if let value { print(value) } }
            }
            """,
            properties: ["Container": ["value"]]
        )
        #expect(Set(visitor.propertyReads.map(\.name)) == ["value"])
    }

    @Test(arguments: [
        "print(value)",
        "print(self.value)",
        "if let value { print(value) }",
        "guard let value else { return }; print(value)",
        "while let value { print(value); break }",
        "let value = value; print(value)"
    ])
    func inheritedReadsPreserveTheBasePropertyIdentity(_ body: String) {
        let baseProperty = PropertyInfo(name: "value", line: 7, filePath: "Base.swift", typeName: "Base")
        let visitor = visitor(
            source: """
            class Base { var value: Int? }
            class Child: Base { func inspect() { \(body) } }
            """,
            typeProperties: ["Base": [baseProperty], "Child": [baseProperty]]
        )
        #expect(visitor.propertyReads == [baseProperty])
        #expect(visitor.propertyWrites.isEmpty)
    }

    @Test(arguments: ["value = nil", "self.value = nil"])
    func unambiguousInheritedWritesPreserveTheBasePropertyIdentity(_ body: String) {
        let baseProperty = PropertyInfo(name: "value", line: 7, filePath: "Base.swift", typeName: "Base")
        let visitor = visitor(
            source: """
            class Base { var value: Int? }
            class Child: Base { func inspect() { \(body) } }
            """,
            typeProperties: ["Base": [baseProperty], "Child": [baseProperty]]
        )
        #expect(visitor.propertyReads.isEmpty)
        #expect(visitor.propertyWrites == [baseProperty])
    }

    @Test
    func localShadowsDoNotReadInheritedProperties() {
        let baseProperty = PropertyInfo(name: "value", line: 7, filePath: "Base.swift", typeName: "Base")
        let visitor = visitor(
            source: """
            class Base { var value: Int? }
            class Child: Base {
                func inspect(value: Int?) { if let value { print(value) } }
                func inspectLocal() {
                    let value: Int? = 1
                    guard let value else { return }
                    print(value)
                }
            }
            """,
            typeProperties: ["Base": [baseProperty], "Child": [baseProperty]]
        )
        #expect(visitor.propertyReads.isEmpty)
        #expect(visitor.propertyWrites.isEmpty)
    }

    @Test(arguments: [
        "print(value)",
        "print(self.value)",
        "if let value { print(value) }",
        "guard let value else { return }; print(value)",
        "while let value { print(value); break }"
    ])
    func declaredPropertyReadsTakePrecedenceOverInheritedNames(_ body: String) {
        let baseProperty = PropertyInfo(name: "value", line: 7, filePath: "Base.swift", typeName: "Base")
        let childProperty = PropertyInfo(name: "value", line: 4, filePath: "Child.swift", typeName: "Child")
        for properties in [[baseProperty, childProperty], [childProperty, baseProperty]] {
            let visitor = visitor(
                source: """
                class Base { var value: Int? { nil } }
                class Child: Base {
                    override var value: Int? { nil }
                    func inspect() { \(body) }
                }
                """,
                typeProperties: ["Base": [baseProperty], "Child": properties]
            )
            #expect(visitor.propertyReads == [childProperty])
            #expect(visitor.propertyWrites.isEmpty)
        }
    }

    @Test(arguments: ["value = nil", "self.value = nil"])
    func declaredPropertyWritesTakePrecedenceOverInheritedNames(_ body: String) {
        let baseProperty = PropertyInfo(name: "value", line: 7, filePath: "Base.swift", typeName: "Base")
        let childProperty = PropertyInfo(name: "value", line: 4, filePath: "Child.swift", typeName: "Child")
        for properties in [[baseProperty, childProperty], [childProperty, baseProperty]] {
            let visitor = visitor(
                source: """
                class Base { var value: Int? }
                class Child: Base {
                    override var value: Int? { get { nil } set {} }
                    func inspect() { \(body) }
                }
                """,
                typeProperties: ["Base": [baseProperty], "Child": properties]
            )
            #expect(visitor.propertyReads.isEmpty)
            #expect(visitor.propertyWrites == [childProperty])
        }
    }

    @Test
    func declaredPropertyPrecedenceUsesCanonicalNestedOwners() {
        let baseProperty = PropertyInfo(name: "value", line: 7, filePath: "Base.swift", typeName: "Namespace.Base")
        let childProperty = PropertyInfo(name: "`value`", line: 4, filePath: "Child.swift", typeName: "`Namespace`.`Child`")
        let visitor = visitor(
            source: """
            struct Namespace {
                class Base { var value: Int? { nil } }
                class Child: Base {
                    override var `value`: Int? { nil }
                    func inspect() { if let `value` { print(`value`) } }
                }
            }
            """,
            typeProperties: ["Namespace.Base": [baseProperty], "`Namespace`.`Child`": [baseProperty, childProperty]]
        )
        #expect(visitor.propertyReads == [childProperty])
    }

    @Test(arguments: ["NSManaged", "Tracked"])
    func managedDeclaredPropertiesStillShadowInheritedNames(_ attribute: String) {
        let baseProperty = PropertyInfo(name: "value", line: 7, filePath: "Base.swift", typeName: "Base")
        let childProperty = PropertyInfo(
            name: "value", line: 4, filePath: "Child.swift", typeName: "Child", attributes: [attribute]
        )
        let visitor = visitor(
            source: """
            class Base { var value: Int? }
            class Child: Base {
                override var value: Int? { get { nil } set {} }
                func inspect() { if let value { print(value) }; self.value = nil }
            }
            """,
            typeProperties: ["Base": [baseProperty], "Child": [baseProperty, childProperty]],
            propertyWrappers: ["Tracked"]
        )
        #expect(visitor.propertyReads.isEmpty)
        #expect(visitor.propertyWrites.isEmpty)
    }

    @Test(arguments: ["print(value)", "print(self.value)", "if let value { print(value) }"])
    func ambiguousInheritedReadsProtectEveryMatchingProperty(_ body: String) {
        let rootProperty = PropertyInfo(name: "value", line: 7, filePath: "Root.swift", typeName: "Root")
        let baseProperty = PropertyInfo(name: "value", line: 4, filePath: "Base.swift", typeName: "Base")
        for properties in [[rootProperty, baseProperty], [baseProperty, rootProperty]] {
            let visitor = visitor(
                source: """
                class Root { var value: Int? { nil } }
                class Base: Root { override var value: Int? { nil } }
                class Child: Base { func inspect() { \(body) } }
                """,
                typeProperties: ["Root": [rootProperty], "Base": properties, "Child": properties]
            )
            #expect(visitor.propertyReads == [rootProperty, baseProperty])
            #expect(visitor.propertyWrites.isEmpty)
        }
    }

    @Test(arguments: ["value = nil", "self.value = nil"])
    func ambiguousInheritedWritesDoNotCreateWriteOnlyCandidates(_ body: String) {
        let rootProperty = PropertyInfo(name: "value", line: 7, filePath: "Root.swift", typeName: "Root")
        let baseProperty = PropertyInfo(name: "value", line: 4, filePath: "Base.swift", typeName: "Base")
        let visitor = visitor(
            source: """
            class Root { var value: Int? }
            class Base: Root { override var value: Int? { get { nil } set {} } }
            class Child: Base { func inspect() { \(body) } }
            """,
            typeProperties: ["Root": [rootProperty], "Base": [rootProperty, baseProperty], "Child": [rootProperty, baseProperty]]
        )
        #expect(visitor.propertyReads == [rootProperty, baseProperty])
        #expect(visitor.propertyWrites.isEmpty)
    }

    @Test(arguments: ["Child", "Alias"])
    func aliasDeclaredPropertiesRemainVisibleInCanonicalGroups(_ owner: String) {
        let baseProperty = PropertyInfo(name: "baseValue", line: 7, filePath: "Base.swift", typeName: "Base")
        let aliasProperty = PropertyInfo(name: "value", line: 4, filePath: "Alias.swift", typeName: "Alias")
        let visitor = visitor(
            source: """
            class Base { var baseValue: Int? }
            class Child: Base {}
            typealias Alias = Child
            extension Alias { var value: Int? { nil } }
            extension \(owner) { func inspect() { if let value { print(value) } } }
            """,
            typeProperties: ["Base": [baseProperty], "Child": [baseProperty, aliasProperty], "Alias": [baseProperty, aliasProperty]]
        )
        #expect(visitor.propertyReads == [aliasProperty])
        #expect(visitor.propertyWrites.isEmpty)
    }

    @Test
    func ambiguousAliasGroupReadsPreserveEveryPossibleDeclaringIdentity() {
        let firstProperty = PropertyInfo(name: "value", line: 7, filePath: "First.swift", typeName: "First")
        let secondProperty = PropertyInfo(name: "value", line: 4, filePath: "Second.swift", typeName: "Second")

        let visitor = visitor(
            source: """
            class First { var value: Int? }
            class Second { var value: Int? }
            #if FIRST
            typealias Alias = First
            #else
            typealias Alias = Second
            #endif
            extension Alias { func inspect() { if let value { print(value) } } }
            """,
            typeProperties: ["Alias": [firstProperty, secondProperty]]
        )
        #expect(visitor.propertyReads == [firstProperty, secondProperty])

    }

    @Test
    func ambiguousDeclaredWritesProtectConditionalDeclarations() {
        let firstProperty = PropertyInfo(name: "value", line: 7, filePath: "First.swift", typeName: "Subject")
        let secondProperty = PropertyInfo(name: "value", line: 4, filePath: "Second.swift", typeName: "Subject")
        let visitor = visitor(
            source: """
            #if FIRST
            class Subject { var value: Int? }
            #else
            class Subject { var value: Int? }
            #endif
            extension Subject { func inspect() { self.value = nil } }
            """,
            typeProperties: ["Subject": [firstProperty, secondProperty]]
        )
        #expect(visitor.propertyReads == [firstProperty, secondProperty])
        #expect(visitor.propertyWrites.isEmpty)
    }

    @Test
    func aliasOwnedWritesPreserveTheOriginalDeclarationIdentity() {
        let aliasProperty = PropertyInfo(name: "value", line: 4, filePath: "Alias.swift", typeName: "Alias")
        let visitor = visitor(
            source: """
            class Child {}
            typealias Alias = Child
            extension Alias { var value: Int? { get { nil } set {} } }
            extension Child { func inspect() { self.value = nil } }
            """,
            typeProperties: ["Child": [aliasProperty], "Alias": [aliasProperty]]
        )
        #expect(visitor.propertyReads.isEmpty)
        #expect(visitor.propertyWrites == [aliasProperty])
    }

    @Test
    func externalReadsAndKeyPathsProtectAllExpandedCandidates() {
        let baseProperty = PropertyInfo(name: "value", line: 7, filePath: "Base.swift", typeName: "Base")
        let childProperty = PropertyInfo(name: "value", line: 4, filePath: "Child.swift", typeName: "Child")
        let source = """
            class Base { var value: Int? { nil } }
            class Child: Base { override var value: Int? { nil } }
            func inspect(_ object: Child) { print(object.value) }
            """
        let readVisitor = visitor(source: source, typeProperties: ["Child": [baseProperty, childProperty]])
        #expect(readVisitor.propertyReads == [baseProperty, childProperty])

        let keyPathVisitor = visitor(
            source: "let path = \\Child.value",
            typeProperties: ["Child": [baseProperty, childProperty]]
        )
        #expect(keyPathVisitor.propertyReads == [baseProperty, childProperty])
    }

    @Test
    func repeatedInheritedEntriesDoNotMakeWritesAmbiguous() {
        let baseProperty = PropertyInfo(name: "value", line: 7, filePath: "Base.swift", typeName: "Base")
        let visitor = visitor(
            source: "class Child { func inspect() { self.value = nil } }",
            typeProperties: ["Child": [baseProperty, baseProperty]]
        )
        #expect(visitor.propertyReads.isEmpty)
        #expect(visitor.propertyWrites == [baseProperty])
    }

    @Test
    func outerParametersDoNotShadowPropertiesOfLocalTypes() {
        let visitor = visitor(
            source: """
            struct Subject {
                var value: Int?
                func inspect(value: Int) {
                    struct Inner {
                        var value: Int?
                        func inspect() { print(value) }
                    }
                    print(value)
                }
            }
            """,
            properties: ["Subject": ["value"], "Subject.Inner": ["value"]]
        )
        #expect(Set(visitor.propertyReads.map(\.typeName)) == ["Subject.Inner"])
    }

    @Test(arguments: [
        "if let `repeat` { print(`repeat`) }",
        "guard let `repeat` else { return }; print(`repeat`)",
        "while let `repeat` { print(`repeat`); break }",
        "let `repeat` = `repeat`; print(`repeat`)"
    ])
    func escapedIdentifiersUseTheSameReadAndShadowRules(_ body: String) {
        let propertyVisitor = visitor(
            source: "struct `class` { var `repeat`: Int?; func inspect() { \(body) } }",
            properties: ["class": ["repeat"]]
        )
        #expect(Set(propertyVisitor.propertyReads.map(\.name)) == ["repeat"])

        let localVisitor = visitor(
            source: "struct `class` { var `repeat`: Int?; func inspect(`repeat`: Int?) { \(body) } }",
            properties: ["class": ["repeat"]]
        )
        #expect(localVisitor.propertyReads.isEmpty)
    }

    @Test
    func escapedTupleAndCaseBindingsDoNotReadProperties() {
        let visitor = visitor(
            source: """
            struct Subject {
                var `repeat`: Int?
                var value: Int?
                func inspect() {
                    do { let (`repeat`, value) = (1, 2); print(`repeat`, value) }
                    switch Optional(1) { case let .some(`repeat`): print(`repeat`); case .none: break }
                    for (`repeat`, value) in [(1, 2)] { print(`repeat`, value) }
                }
            }
            """,
            properties: ["Subject": ["repeat", "value"]]
        )
        #expect(visitor.propertyReads.isEmpty)
    }

    @Test(arguments: [
        "do { var value = 1; value = 2 }; value = nil",
        "if let value = Optional(1) { print(value) } else { value = nil }",
        "guard let value = Optional(1) else { value = nil; return }; print(value)"
    ])
    func propertyWritesResumeOutsideTemporaryShadows(_ body: String) {
        let visitor = methodVisitor(body)
        #expect(visitor.propertyReads.isEmpty)
        #expect(Set(visitor.propertyWrites.map(\.name)) == ["value"])
    }

    @Test
    func assignmentClassificationIsUnchanged() {
        let visitor = methodVisitor("self.value = value", parameters: "value: Int?")
        #expect(visitor.propertyReads.isEmpty)
        #expect(Set(visitor.propertyWrites.map(\.name)) == ["value"])

        let readWriteVisitor = methodVisitor("value = value")
        #expect(Set(readWriteVisitor.propertyReads.map(\.name)) == ["value"])
        #expect(Set(readWriteVisitor.propertyWrites.map(\.name)) == ["value"])
    }
}

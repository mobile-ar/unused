import Testing
import SwiftParser
import SwiftSyntax
@testable import unused

struct ReferenceGraphVisitorTests {

    @Test func indexesAllTypesSignaturesAndUninitializedProperties() throws {
        let bodies = collect("""
        class Base {}
        protocol Requirement { var required: Base { get }; func perform() }
        class Container: Base, Requirement {
            var required: Base
            let first: Base, second: Base
            init(value: Base) { self.required = value }
            func perform() {}
            struct Nested { var value: Base }
        }
        enum Choice { case first, second(Base) }
        actor Worker { var value: Base }
        typealias Alias = Container
        """)

        #expect(bodies.filter { $0.declaration.kind == "class" }.map(\.declaration.name) == ["Base", "Container"])
        #expect(bodies.contains { $0.declaration.name == "Requirement" && $0.declaration.kind == "protocol" })
        #expect(bodies.contains { $0.declaration.name == "Nested" && $0.declaration.kind == "struct" })
        #expect(bodies.contains { $0.declaration.name == "Choice" && $0.declaration.kind == "enum" })
        #expect(bodies.contains { $0.declaration.name == "Worker" && $0.declaration.kind == "actor" })
        #expect(bodies.filter { $0.declaration.kind == "enumCase" }.map(\.declaration.name) == ["first", "second"])
        #expect(bodies.contains { $0.declaration.name == "required" && $0.declaration.parentType == "Requirement" })
        let container = try body("Container", in: bodies)
        #expect(container.references.map(\.name) == ["Base", "Requirement"])
        #expect(container.references.allSatisfy { $0.kind == .type })
        let properties = bodies.filter { $0.declaration.kind == "variable" && $0.declaration.parentType == "Container" }
        #expect(properties.map(\.declaration.name) == ["required", "first", "second"])
        #expect(properties.allSatisfy { $0.references.map(\.name) == ["Base"] })
        let alias = try body("Alias", in: bodies)
        #expect(alias.declaration.kind == "typealias")
        #expect(alias.references.map(\.name) == ["Container"])
        let initializer = try body("init", in: bodies)
        #expect(initializer.declaration.kind == "initializer")
        #expect(initializer.declaration.signature == "init(value:)")
        #expect(initializer.references.contains { $0.name == "required" && $0.kind == .write && $0.receiverType == "Container" })
    }

    @Test func multiBindingsHaveIndependentOwnersAndReportCompatibleLines() throws {
        let source = """
        struct Settings {
            let first = makeFirst(),
                second = makeSecond()
            var uninitialized: Int
        }
        enum Choice {
            case one,
                 two
        }
        """
        let bodies = collect(source)
        let first = try body("first", in: bodies)
        let second = try body("second", in: bodies)
        #expect(first.declaration.line == 2)
        #expect(second.declaration.line == 2)
        #expect(first.references.map(\.name) == ["makeFirst"])
        #expect(second.references.map(\.name) == ["makeSecond"])
        #expect(try body("uninitialized", in: bodies).declaration.line == 4)
        #expect(try body("one", in: bodies).declaration.line == 7)
        #expect(try body("two", in: bodies).declaration.line == 8)
    }

    @Test func nestedFunctionsHaveTheirOwnReferencesAndOrderedLexicalScopes() throws {
        let source = """
        struct Box {
            func outer() {
                outerOnly()
                func nested() {
                    nestedOnly()
                    func deepest() { deepestOnly() }
                    deepest()
                }
                nested()
                outerAfter()
            }
        }
        """
        let tree = Parser.parse(source: source)
        let visitor = ReferenceGraphVisitor(filePath: "test.swift", sourceFile: tree)
        visitor.walk(tree)
        let outer = try body("outer", in: visitor.declarationBodies)
        let nested = try body("nested", in: visitor.declarationBodies)
        let deepest = try body("deepest", in: visitor.declarationBodies)
        let box = try #require(tree.statements.first?.item.as(StructDeclSyntax.self))
        let outerNode = try #require(box.memberBlock.members.first?.decl.as(FunctionDeclSyntax.self))
        let nestedNode = try #require(outerNode.body?.statements.compactMap { $0.item.as(FunctionDeclSyntax.self) }.first)
        let deepestNode = try #require(nestedNode.body?.statements.compactMap { $0.item.as(FunctionDeclSyntax.self) }.first)
        let outerBlock = try #require(outerNode.body)
        let nestedBlock = try #require(nestedNode.body)
        let deepestBlock = try #require(deepestNode.body)
        #expect(outer.references.map(\.name) == ["outerOnly", "nested", "outerAfter"])
        #expect(nested.references.map(\.name) == ["nestedOnly", "deepest"])
        #expect(deepest.references.map(\.name) == ["deepestOnly"])
        #expect(outer.offset == outerNode.positionAfterSkippingLeadingTrivia.utf8Offset)
        #expect(nested.offset == nestedNode.positionAfterSkippingLeadingTrivia.utf8Offset)
        #expect(deepest.offset == deepestNode.positionAfterSkippingLeadingTrivia.utf8Offset)
        #expect(outer.lexicalScope == [box.positionAfterSkippingLeadingTrivia.utf8Offset])
        #expect(nested.lexicalScope == outer.lexicalScope + [outer.offset, outerBlock.positionAfterSkippingLeadingTrivia.utf8Offset])
        #expect(deepest.lexicalScope == nested.lexicalScope + [nested.offset, nestedBlock.positionAfterSkippingLeadingTrivia.utf8Offset])
        #expect(outer.references.allSatisfy { $0.lexicalScope == nested.lexicalScope })
        #expect(nested.references.allSatisfy { $0.lexicalScope == deepest.lexicalScope })
        #expect(deepest.references.allSatisfy {
            $0.lexicalScope == deepest.lexicalScope + [deepest.offset, deepestBlock.positionAfterSkippingLeadingTrivia.utf8Offset]
        })
        #expect(!deepest.lexicalScope.contains(deepestNode.positionAfterSkippingLeadingTrivia.utf8Offset))
        #expect(try body("Box", in: visitor.declarationBodies).references.isEmpty)
    }

    @Test func closuresStayWithEnclosingFunctionAndProperty() throws {
        let bodies = collect("""
        struct Container {
            let handler = { propertyHelper() }
            func execute() {
                run { functionHelper() }
                let callback = { closureHelper() }
                callback()
            }
        }
        """)
        #expect(try body("handler", in: bodies).references.map(\.name) == ["propertyHelper"])
        #expect(try body("execute", in: bodies).references.map(\.name) == ["run", "functionHelper", "closureHelper"])
        #expect(!bodies.contains { $0.declaration.name == "callback" })
        #expect(try body("Container", in: bodies).references.isEmpty)
    }

    @Test func resolvesTypedOptionalAndConstructorInferredReceivers() throws {
        let bodies = collect("""
        struct Client {}
        func execute(client: Client?, unrelated: External, opaque: Any) {
            client?.send()
            client!.send()
            unrelated.send()
            opaque.send()
            let local: Client? = client
            local?.send()
            let inferred = Client()
            inferred.send()
            Client().send()
            let unknown = factory()
            unknown.send()
        }
        """)
        let send = try body("execute", in: bodies).references.filter { $0.name == "send" }
        #expect(send.map(\.receiverType) == ["Client", "Client", "External", "Any", "Client", "Client", "Client", nil])
        #expect(send.allSatisfy { $0.isMember && $0.kind == .call })
        #expect(send.allSatisfy { $0.argumentLabels == [] })
    }

    @Test func unknownReceiversAreNeverGuessedToBeTypes() throws {
        let bodies = collect("""
        func execute(Unknown: Any) {
            Unknown.perform()
            Missing.perform()
            lowercase.perform()
            Factory.perform()
        }
        """, knownTypes: ["Factory", "Unknown"])
        let calls = try body("execute", in: bodies).references.filter { $0.name == "perform" }
        #expect(calls.map(\.receiverType) == ["Any", nil, nil, "Factory"])
        #expect(calls.allSatisfy { $0.isMember })
    }

    @Test func resolvesSelfCurrentTypeOtherTypesAndTypedProperties() throws {
        let bodies = collect("""
        struct Other { static func work() {} }
        struct Container {
            var client: Client?
            func execute(other: Other) {
                self.work()
                Self.work()
                Container.work()
                Other.work()
                other.work()
                self.client?.send()
                client?.send()
                super.work()
            }
            func work() {}
        }
        """, knownTypes: ["Client"])
        let references = try body("execute", in: bodies).references
        #expect(references.filter { $0.name == "work" }.map(\.receiverType)
                == ["Container", "Container", "Container", "Other", "Other", nil])
        #expect(references.filter { $0.name == "send" }.map(\.receiverType) == ["Client", "Client"])
        #expect(references.filter { $0.name == "client" }.allSatisfy { $0.kind == .read })
        #expect(!references.contains { ["self", "Self", "super", "other"].contains($0.name) })
    }

    @Test func extensionMembersUseExtendedTypeWithoutCreatingAnExtensionDeclaration() throws {
        let bodies = collect("""
        extension Namespace.Container {
            var value: Int { self.readValue() }
            func execute() { Self.helper(); self.helper() }
        }
        """)
        let members = bodies.filter { $0.declaration.kind != "file scope" }
        #expect(members.map(\.declaration.name) == ["value", "execute"])
        #expect(members.allSatisfy { $0.declaration.parentType == "Namespace.Container" })
        #expect(try body("<file scope>", in: bodies).references.map(\.name) == ["Container", "Namespace"])
        #expect(try body("execute", in: bodies).references.allSatisfy { $0.receiverType == "Namespace.Container" })
    }

    @Test func parametersLocalsAndClosureParametersBlockNameFallback() throws {
        let bodies = collect("""
        func execute(callback: () -> Void, unknown: Any) {
            callback()
            let helper = callback
            helper()
            unknown.perform()
            run { helper in helper() }
            helper()
            let Client = factory()
            Client.perform()
            let value = 1
            consume(value)
        }
        """, knownTypes: ["Client"])
        let references = try body("execute", in: bodies).references
        #expect(!references.contains { ["callback", "helper", "unknown", "Client", "value"].contains($0.name) })
        #expect(references.filter { $0.name == "perform" }.map(\.receiverType) == ["Any", nil])
        #expect(references.contains { $0.name == "factory" })
        #expect(references.contains { $0.name == "consume" })
    }

    @Test func blockShadowingEndsAtTheBlockBoundary() throws {
        let bodies = collect("""
        func execute() {
            helper()
            if flag {
                let helper = factory()
                helper()
            }
            helper()
            for helper in values { helper() }
            helper()
        }
        """)
        let references = try body("execute", in: bodies).references
        #expect(references.filter { $0.name == "helper" }.count == 3)
        #expect(references.contains { $0.name == "values" })
    }

    @Test func optionalBindingsTrackTypeWithoutLeakingIntoElse() throws {
        let bodies = collect("""
        func execute(client: Client?) {
            if let client { client.send() } else { client?.send() }
            if let helper = factory() { helper() } else { helper() }
            guard let client else { return }
            client.send()
        }
        """)
        let references = try body("execute", in: bodies).references
        #expect(references.filter { $0.name == "send" }.map(\.receiverType) == ["Client", "Client", "Client"])
        #expect(references.filter { $0.name == "helper" }.count == 1)
        #expect(references.filter { $0.name == "helper" }.first?.line == 3)
    }

    @Test func closureCapturesUseOuterReferencesButCaptureNamesAreLocal() throws {
        let bodies = collect("""
        func execute(client: Client) {
            run { [captured = globalValue, client] in
                consume(captured)
                client.send()
            }
        }
        """)
        let references = try body("execute", in: bodies).references
        #expect(references.filter { $0.name == "globalValue" }.count == 1)
        #expect(!references.contains { ["captured", "client"].contains($0.name) })
        #expect(references.first { $0.name == "send" }?.receiverType == "Client")
    }

    @Test func eachCallSiteIsRecordedOnceIncludingRecursion() throws {
        let bodies = collect("""
        func repeatWork() {
            repeatWork()
            Service.run(value: 1)
            Service.run(value: 2)
        }
        """, knownTypes: ["Service"])
        let function = try body("repeatWork", in: bodies)
        let calls = function.references.filter { $0.kind == .call }
        #expect(calls.map(\.name) == ["repeatWork", "run", "run"])
        #expect(calls.map(\.line) == [2, 3, 4])
        #expect(calls.map(\.column) == [5, 13, 13])
        #expect(calls.allSatisfy { $0.file == "test.swift" })
        #expect(calls.filter { $0.name == "run" }.allSatisfy { $0.argumentLabels == ["value"] })
        #expect(function.references.filter { $0.name == "run" }.count == 2)
        #expect(function.references.filter { $0.name == "repeatWork" }.count == 1)
    }

    @Test func propertyReadsWritesAndFunctionValuesHaveDistinctKinds() throws {
        let bodies = collect("""
        struct Container {
            var value: Int
            func helper() {}
            func execute() {
                self.value = globalValue
                globalValue = self.value
                self.value += 1
                mutate(&self.value)
                let callback = helper
                let memberCallback = self.helper
                consume(callback, memberCallback)
            }
        }
        """)
        let references = try body("execute", in: bodies).references
        #expect(references.filter { $0.name == "value" }.map(\.kind) == [.write, .read, .write, .write])
        #expect(references.filter { $0.name == "globalValue" }.map(\.kind) == [.read, .write])
        #expect(references.filter { $0.name == "helper" }.map(\.kind) == [.reference, .reference])
        #expect(references.contains { $0.name == "+=" && $0.kind == .call })
    }

    @Test func typeReferencesIncludeGenericConstraintsAndExcludeGenericParameterNames() throws {
        let bodies = collect("""
        struct Container<T: Requirement>: Base where T: OtherRequirement {
            var value: Payload?
            func fetch<U: Requirement>(_ value: U, id: Identifier) -> Result<Payload, Failure> where U: OtherRequirement {
                let local: Payload? = nil
                return factory()
            }
        }
        """)
        let container = try body("Container", in: bodies)
        #expect(container.references.map(\.name) == ["Requirement", "Base", "OtherRequirement"])
        let function = try body("fetch", in: bodies)
        #expect(function.declaration.signature == "fetch(_:id:)")
        #expect(function.parameterLabels == ["_", "id"])
        #expect(function.references.filter { $0.kind == .type }.map(\.name)
                == ["Requirement", "Identifier", "Result", "Payload", "Failure", "OtherRequirement", "Payload"])
        #expect(!function.references.contains { ["T", "U", "value", "id", "local"].contains($0.name) })
    }

    @Test func backtickIdentifiersAreNormalizedEverywhere() throws {
        let bodies = collect("""
        struct `class` {
            var `default`: `class`?
            func `repeat`(`switch` value: `class`) {
                self.`default` = value
                value.`repeat`(`switch`: value)
            }
        }
        """)
        let function = try body("repeat", in: bodies)
        #expect(function.declaration.parentType == "class")
        #expect(function.declaration.signature == "repeat(switch:)")
        #expect(function.parameterLabels == ["switch"])
        #expect(function.references.map(\.name) == ["class", "default", "repeat"])
        #expect(function.references.last?.receiverType == "class")
        #expect(function.references.last?.argumentLabels == ["switch"])
        #expect(try body("default", in: bodies).references.first?.name == "class")
    }

    @Test func fileScopeExecutableExpressionsHaveASyntheticOwner() throws {
        let bodies = collect("""
        start()
        Service.run()
        func helper() { inside() }
        finish()
        """, knownTypes: ["Service"])
        let fileScope = try body("<file scope>", in: bodies)
        #expect(fileScope.declaration.kind == "file scope")
        #expect(fileScope.declaration.parentType == nil)
        #expect(fileScope.lexicalScope.isEmpty)
        #expect(fileScope.references.filter { $0.kind == .call }.map(\.name) == ["start", "run", "finish"])
        #expect(fileScope.references.map(\.line) == [1, 2, 2, 4])
        #expect(try body("helper", in: bodies).references.map(\.name) == ["inside"])
    }

    @Test func constructorInferenceDoesNotInferFactoryReturnTypes() throws {
        let bodies = collect("""
        struct Client {}
        func execute() {
            let direct = Client()
            let initialized = Client.init()
            let specialized = Client<Int>()
            let factoryResult = Client.make()
            direct.send()
            initialized.send()
            specialized.send()
            factoryResult.send()
        }
        """)
        #expect(try body("execute", in: bodies).references.filter { $0.name == "send" }.map(\.receiverType)
                == ["Client", "Client", "Client", nil])
    }

    @Test func nestedTypePropertiesAndMethodsAreNotOwnedByTheEnclosingType() throws {
        let bodies = collect("""
        struct Outer {
            struct Inner {
                var value = propertyHelper()
                func execute() { self.helper() }
                func helper() {}
            }
        }
        """)
        #expect(try body("Outer", in: bodies).references.isEmpty)
        #expect(try body("Inner", in: bodies).declaration.parentType == "Outer")
        #expect(try body("Inner", in: bodies).references.isEmpty)
        #expect(try body("value", in: bodies).declaration.parentType == "Outer.Inner")
        #expect(try body("execute", in: bodies).references.first?.receiverType == "Outer.Inner")
    }

    @Test func straightforwardOperatorsAreCapturedAtTheirUsageSites() throws {
        let bodies = collect("""
        func execute(left: Value, right: Value) {
            consume(left + right)
            consume(-left)
            consume(left.custom)
        }
        """)
        let references = try body("execute", in: bodies).references
        #expect(references.filter { $0.name == "+" }.map(\.kind) == [.call])
        #expect(references.filter { $0.name == "-" }.map(\.kind) == [.call])
        #expect(references.first { $0.name == "custom" }?.receiverType == "Value")
    }

    @Test func sharedAnnotationsAndEarlierBindingsResolveLocalReceivers() throws {
        let bodies = collect("""
        struct Container { var first, second: Client }
        func execute() {
            var first, second: Client?
            first?.send()
            second?.send()
            let direct = Client(), copied = direct
            copied.send()
        }
        struct Client {}
        """)
        #expect(try body("first", in: bodies).references.map(\.name) == ["Client"])
        #expect(try body("second", in: bodies).references.map(\.name) == ["Client"])
        #expect(try body("execute", in: bodies).references.filter { $0.name == "send" }.map(\.receiverType)
                == ["Client", "Client", "Client"])
    }

    @Test func initializerReferencesPrecedeTheNewLocalBinding() throws {
        let bodies = collect("""
        func execute() {
            let helper = helper()
            helper()
            let value = globalValue
            consume(value)
        }
        """)
        let references = try body("execute", in: bodies).references
        #expect(references.filter { $0.name == "helper" }.map(\.kind) == [.call])
        #expect(references.filter { $0.name == "helper" }.map(\.line) == [2])
        #expect(!references.contains { $0.name == "value" })
    }

    @Test func switchCatchAndAccessorBindingsAreScopedLocals() throws {
        let bodies = collect("""
        struct Container {
            var value: Int {
                get { globalValue }
                set { consume(newValue) }
            }
            func execute(input: Result) {
                switch input {
                case .success(let helper): helper()
                default: helper()
                }
                do { try work() } catch { consume(error) }
                helper()
                consume(error)
            }
        }
        """)
        let property = try body("value", in: bodies)
        #expect(property.references.map(\.name) == ["Int", "globalValue", "consume"])
        let function = try body("execute", in: bodies)
        #expect(function.references.filter { $0.name == "helper" }.map(\.line) == [9, 12])
        #expect(function.references.filter { $0.name == "error" }.map(\.line) == [13])
        #expect(!function.references.contains { $0.name == "input" })
    }

    @Test func subscriptsDeinitializersAndAssociatedTypesDoNotLeakIntoTypes() throws {
        let bodies = collect("""
        protocol Requirement { associatedtype Element: Base }
        class Container {
            subscript(index: Index) -> Value { fetch(index) }
            deinit { cleanup() }
        }
        """)
        #expect(try body("Requirement", in: bodies).references.isEmpty)
        #expect(try body("Element", in: bodies).references.map(\.name) == ["Base"])
        #expect(try body("Container", in: bodies).references.isEmpty)
        let subscriptBody = try body("subscript", in: bodies)
        #expect(subscriptBody.declaration.kind == "subscript")
        #expect(subscriptBody.references.map(\.name) == ["Index", "Value", "fetch"])
        #expect(try body("deinit", in: bodies).references.map(\.name) == ["cleanup"])
    }

    @Test func knownTypeValuesAndQualifiedGenericTypesAreTypeReferences() throws {
        let bodies = collect("""
        struct Container {}
        func execute(value: Namespace.Container?) {
            consume(Container.self)
            value?.work()
            consume(Container)
        }
        """)
        let function = try body("execute", in: bodies)
        #expect(function.references.filter { $0.kind == .type }.map(\.name)
                == ["Container", "Namespace", "Container", "Container"])
        #expect(function.references.first { $0.name == "work" }?.receiverType == "Namespace.Container")
        #expect(function.references.first { $0.name == "Container" && $0.kind == .type }?.receiverType == "Namespace")
        #expect(function.references.first { $0.name == "Container" && $0.kind == .type }?.isMember == true)
        #expect(!function.references.contains { $0.name == "self" })
    }

    @Test func extensionInheritanceAndConstraintsRemainAsFileScopeTypeReferences() throws {
        let bodies = collect("""
        struct Container<T> {}
        extension Container: Requirement where T: OtherRequirement {
            func execute(value: T) { helper() }
        }
        """, knownTypes: ["T"])
        let fileScope = try body("<file scope>", in: bodies)
        #expect(fileScope.references.map(\.name) == ["Container", "Requirement", "OtherRequirement"])
        #expect(fileScope.references.allSatisfy { $0.kind == .type })
        #expect(fileScope.references.map(\.line) == [2, 2, 2])
        #expect(fileScope.offset == 0)
        #expect(fileScope.references.allSatisfy { $0.lexicalScope.isEmpty })
        #expect(try body("Container", in: bodies).references.isEmpty)
        #expect(try body("execute", in: bodies).references.map(\.name) == ["helper"])
        #expect(!bodies.contains { $0.declaration.kind == "extension" })
    }

    @Test func genericParametersCannotMasqueradeAsKnownProjectTypes() throws {
        let bodies = collect("""
        struct Container<T> {
            var value: T
            func execute<U>(other: U) {
                T.work()
                U.work()
                value.work()
                other.work()
            }
        }
        """, knownTypes: ["T", "U"])
        let function = try body("execute", in: bodies)
        #expect(function.references.filter { $0.name == "work" }.map(\.receiverType) == [nil, nil, nil, nil])
        #expect(!function.references.contains { ["T", "U", "other"].contains($0.name) })
        #expect(try body("value", in: bodies).references.isEmpty)
    }

    @Test func patternMatchingConditionsShadowOnlyTheirSuccessScopes() throws {
        let bodies = collect("""
        func execute(input: Result) {
            if case .success(let helper) = input { helper() } else { helper() }
            while case let .success(helper) = input { helper(); break }
            helper()
        }
        """)
        let function = try body("execute", in: bodies)
        #expect(function.references.filter { $0.name == "helper" }.map(\.line) == [2, 4])
        #expect(function.references.filter { $0.name == "success" }.count == 2)
        #expect(!function.references.contains { $0.name == "input" })
    }

    @Test func keyPathMembersRetainTheirReceiverTypesWithoutNameFallback() throws {
        let bodies = collect(#"""
        struct Child { var value: Int }
        struct Container { var child: Child? }
        func execute() {
            consume(\Container.child?.value)
            consume(\.unknown)
        }
        """#)
        let function = try body("execute", in: bodies)
        #expect(function.references.filter { $0.isMember }.map(\.name) == ["child", "value", "unknown"])
        #expect(function.references.filter { $0.isMember }.map(\.receiverType) == ["Container", "Child", nil])
        #expect(function.references.filter { $0.isMember }.allSatisfy { $0.kind == .reference })
        #expect(function.references.filter { $0.kind == .type }.map(\.name) == ["Container"])
    }

    @Test func optionalAndParenthesizedCalleesAreNotDoubleCounted() throws {
        let bodies = collect("""
        func helper() {}
        func execute(client: Client) {
            (helper)()
            client.callback?()
            (client.send)(value: 1)
        }
        """)
        let function = try body("execute", in: bodies)
        #expect(function.references.map(\.name) == ["Client", "helper", "callback", "send"])
        #expect(function.references.filter { $0.kind == .call }.map(\.name) == ["helper", "callback", "send"])
        #expect(function.references.last?.argumentLabels == ["value"])
    }

    @Test func localFunctionDeclarationsAndUsagesRetainTheirContainingBlockOffsets() throws {
        let source = """
        func helper() {}
        func caller() {
            if Bool.random() {
                func helper() {}
                helper()
            }
            helper()
        }
        helper()
        """
        let tree = Parser.parse(source: source)
        let callerNode = try #require(tree.statements.compactMap { $0.item.as(FunctionDeclSyntax.self) }.last)
        let callerBlock = try #require(callerNode.body)
        let conditional = try #require(callerBlock.statements.first?.item.as(ExpressionStmtSyntax.self)?.expression.as(IfExprSyntax.self))
        let bodies = collect(source)
        let caller = try body("caller", in: bodies)
        let localHelper = try #require(bodies.first { $0.declaration.name == "helper" && $0.declaration.line == 4 })
        let calls = caller.references.filter { $0.name == "helper" }
        let outerScope = [caller.offset, callerBlock.positionAfterSkippingLeadingTrivia.utf8Offset]
        let innerScope = outerScope + [conditional.body.positionAfterSkippingLeadingTrivia.utf8Offset]
        #expect(localHelper.lexicalScope == innerScope)
        #expect(calls.map(\.lexicalScope) == [innerScope, outerScope])
        #expect(calls.last?.lexicalScope.contains(conditional.body.positionAfterSkippingLeadingTrivia.utf8Offset) == false)
        #expect(try body("<file scope>", in: bodies).references.first?.lexicalScope == [])
        #expect(try body("helper", in: bodies).lexicalScope.isEmpty)
    }

    @Test func closureLocalFunctionVisibilityDoesNotLeakToItsEnclosingOwner() throws {
        let source = """
        func helper() {}
        func caller() {
            let callback = {
                func helper() {}
                helper()
            }
            helper()
        }
        """
        let tree = Parser.parse(source: source)
        let callerNode = try #require(tree.statements.compactMap { $0.item.as(FunctionDeclSyntax.self) }.last)
        let callerBlock = try #require(callerNode.body)
        let callback = try #require(callerBlock.statements.first?.item.as(VariableDeclSyntax.self))
        let closure = try #require(callback.bindings.first?.initializer?.value.as(ClosureExprSyntax.self))
        let bodies = collect(source)
        let caller = try body("caller", in: bodies)
        let localHelper = try #require(bodies.first { $0.declaration.name == "helper" && $0.declaration.line == 4 })
        let outerScope = [caller.offset, callerBlock.positionAfterSkippingLeadingTrivia.utf8Offset]
        let closureScope = outerScope + [closure.positionAfterSkippingLeadingTrivia.utf8Offset]
        #expect(localHelper.lexicalScope == closureScope)
        #expect(caller.references.filter { $0.name == "helper" }.map(\.lexicalScope) == [closureScope, outerScope])
        #expect(!localHelper.lexicalScope.contains(localHelper.offset))
        #expect(!bodies.contains { $0.declaration.name == "callback" })
    }

    @Test func callableDefaultsUseOuterBindingsAndPopulateParameterMetadata() throws {
        let bodies = collect("""
        func helper() {}
        func caller(helper: () -> Void = helper, value: Value = makeValue(), _ values: Value...) {
            helper()
            consume(value, values)
        }
        struct Container {
            init(helper: () -> Void = helper, _ values: Value...) { helper() }
            subscript(helper: () -> Void = helper, index: Index = makeIndex()) -> Value {
                helper()
                return fetch(index)
            }
        }
        """)
        let caller = try body("caller", in: bodies)
        #expect(caller.parameterLabels == ["helper", "value", "_"])
        #expect(caller.defaultedParameterIndices == [0, 1])
        #expect(caller.variadicParameterIndex == 2)
        #expect(caller.references.map(\.name) == ["Void", "helper", "Value", "makeValue", "Value", "consume"])
        #expect(caller.references.filter { $0.name == "helper" }.map(\.kind) == [.reference])
        #expect(caller.references.filter { $0.name == "helper" }.map(\.lexicalScope) == [[caller.offset]])
        let initializer = try body("init", in: bodies)
        #expect(initializer.parameterLabels == ["helper", "_"])
        #expect(initializer.defaultedParameterIndices == [0])
        #expect(initializer.variadicParameterIndex == 1)
        #expect(initializer.references.map(\.name) == ["Void", "helper", "Value"])
        #expect(initializer.references.filter { $0.name == "helper" }.first?.lexicalScope
                == initializer.lexicalScope + [initializer.offset])
        let subscriptBody = try body("subscript", in: bodies)
        #expect(subscriptBody.parameterLabels == ["helper", "index"])
        #expect(subscriptBody.defaultedParameterIndices == [0, 1])
        #expect(subscriptBody.variadicParameterIndex == nil)
        #expect(subscriptBody.references.map(\.name) == ["Void", "helper", "Index", "makeIndex", "Value", "fetch"])
        let globalHelper = try body("helper", in: bodies)
        #expect(globalHelper.defaultedParameterIndices.isEmpty)
        #expect(globalHelper.variadicParameterIndex == nil)
    }

    @Test func defaultsCanCallSameNamedGlobalFunctionsWithoutDoubleVisitingThem() throws {
        let bodies = collect("""
        func helper() -> Value { makeValue() }
        func caller(helper: Value = helper()) { consume(helper) }
        struct Container { init(helper: Value = helper()) { consume(helper) } }
        """)
        for name in ["caller", "init"] {
            let callable = try body(name, in: bodies)
            #expect(callable.references.map(\.name) == ["Value", "helper", "consume"])
            #expect(callable.references.filter { $0.name == "helper" }.map(\.kind) == [.call])
            #expect(callable.defaultedParameterIndices == [0])
        }
    }

    @Test func nestedCallableDefaultsKeepOuterParameterShadowing() throws {
        let bodies = collect("""
        func helper() {}
        func outer(helper: () -> Void) {
            func nested(helper: () -> Void = helper) { helper() }
            nested()
        }
        """)
        let nested = try body("nested", in: bodies)
        #expect(nested.references.map(\.name) == ["Void"])
        #expect(nested.defaultedParameterIndices == [0])
        #expect(try body("outer", in: bodies).references.filter { $0.name == "nested" }.count == 1)
    }

    @Test func closuresInDefaultsAreOwnedByTheCallableWithoutParameterShadowing() throws {
        let source = """
        func helper() {}
        func caller(helper: () -> Void = { helper() }) { helper() }
        """
        let bodies = collect(source)
        let caller = try body("caller", in: bodies)
        #expect(caller.references.map(\.name) == ["Void", "helper"])
        #expect(caller.references.last?.kind == .call)
        let tree = Parser.parse(source: source)
        let node = try #require(tree.statements.compactMap { $0.item.as(FunctionDeclSyntax.self) }.last)
        let closure = try #require(node.signature.parameterClause.parameters.first?.defaultValue?.value.as(ClosureExprSyntax.self))
        #expect(caller.references.last?.lexicalScope.count == 2)
        #expect(caller.references.last?.lexicalScope.first == caller.offset)
        #expect(caller.references.last?.lexicalScope.last
                == closure.positionAfterSkippingLeadingTrivia.utf8Offset)
    }

    @Test func extensionHeadersAndSubsequentDeclarationsDoNotKeepPriorBodyScopes() throws {
        let bodies = collect("""
        func earlier() { if flag { run { work() } } }
        extension Container: Requirement where Element: Constraint {
            func execute() { helper() }
        }
        func later() { helper() }
        """)
        let fileScope = try body("<file scope>", in: bodies)
        #expect(fileScope.references.allSatisfy { $0.lexicalScope.isEmpty })
        let execute = try body("execute", in: bodies)
        let later = try body("later", in: bodies)
        #expect(execute.lexicalScope.isEmpty)
        #expect(later.lexicalScope.isEmpty)
        #expect(execute.references.first?.lexicalScope.first == execute.offset)
        #expect(later.references.first?.lexicalScope.first == later.offset)
        #expect(execute.references.first?.lexicalScope.count == 2)
        #expect(later.references.first?.lexicalScope.count == 2)
    }

    @Test func switchCaseLocalFunctionsRetainDistinctCaseScopes() throws {
        let bodies = collect("""
        func helper() {}
        func caller(value: Value) {
            switch value {
            case .first:
                func helper() {}
                helper()
            default:
                helper()
            }
            helper()
        }
        """)
        let caller = try body("caller", in: bodies)
        let localHelper = try #require(bodies.first { $0.declaration.name == "helper" && $0.declaration.line == 5 })
        let calls = caller.references.filter { $0.name == "helper" }
        #expect(calls.count == 3)
        #expect(calls.first?.lexicalScope == localHelper.lexicalScope)
        #expect(calls[0].lexicalScope != calls[1].lexicalScope)
        #expect(calls[0].lexicalScope.dropLast() == calls[2].lexicalScope[...])
        #expect(calls[1].lexicalScope.dropLast() == calls[2].lexicalScope[...])
    }

    @Test func implicitGetterScopesAreSeparateFromSubscriptDefaults() throws {
        let source = """
        func helper() -> Value { makeValue() }
        struct Container {
            subscript(value: Value = helper()) -> Value {
                func helper() -> Value { makeLocalValue() }
                return helper()
            }
            var computed: Value {
                let local = makeValue()
                return local
            }
        }
        """
        let bodies = collect(source)
        let subscriptBody = try body("subscript", in: bodies)
        let localHelper = try #require(bodies.first { $0.declaration.name == "helper" && $0.declaration.line == 4 })
        let calls = subscriptBody.references.filter { $0.name == "helper" }
        #expect(calls.count == 2)
        #expect(calls[0].lexicalScope == subscriptBody.lexicalScope + [subscriptBody.offset])
        #expect(calls[1].lexicalScope == localHelper.lexicalScope)
        #expect(calls[1].lexicalScope.count == calls[0].lexicalScope.count + 1)
        #expect(subscriptBody.defaultedParameterIndices == [0])
        #expect(try body("computed", in: bodies).references.map(\.name) == ["Value", "makeValue"])
        #expect(!bodies.contains { $0.declaration.name == "local" })
    }

    @Test func nestedAndQualifiedOwnersUseCanonicalPathsForReceivers() throws {
        let bodies = collect("""
        struct `Outer` {
            struct `Inner`<T> {
                func helper() {}
                struct Leaf { func work() { self.helper() } }
            }
        }
        extension `Outer`.`Inner`<Int> {
            func execute(_ value: Outer.Inner<Int>) {
                self.helper()
                value.helper()
                Outer.Inner<Int>.helper()
            }
        }
        """)
        let execute = try body("execute", in: bodies)
        #expect(execute.declaration.parentType == "Outer.Inner")
        #expect(execute.references.filter { $0.name == "helper" }.map(\.receiverType) == ["Outer.Inner", "Outer.Inner", "Outer.Inner"])
        #expect(try body("work", in: bodies).declaration.parentType == "Outer.Inner.Leaf")
        #expect(try body("work", in: bodies).references.first?.receiverType == "Outer.Inner.Leaf")
    }

    @Test func bindingOffsetsMatchCanonicalDeclarationIdentitiesWithoutChangingReportLines() throws {
        let source = """
        struct Outer { struct Inner {
            var first: Int = 0,
                second: String = ""
        } }
        """
        let tree = Parser.parse(source: source)
        let declarations = DeclarationVisitor(filePath: "test.swift", protocolRequirements: [:], sourceFile: tree)
        declarations.walk(tree)
        let bodies = collect(source)
        for name in ["first", "second"] {
            let declaration = try #require(declarations.declarations.first { $0.name == name })
            let identity = try #require(declaration.identity)
            let body = try body(name, in: bodies)
            #expect(body.offset == identity.offset)
            #expect(body.declaration.line == declaration.line)
            #expect(body.declaration.parentType == declaration.parentType)
        }
        #expect(try body("first", in: bodies).offset != body("second", in: bodies).offset)
    }

    @Test func genericMemberTypeReceiversRemainUnknownRatherThanUsingTheirLeaf() throws {
        let bodies = collect("""
        struct Element {}
        struct Container<T> {
            var stored: T.Element
            func execute(_ value: T.Element) { value.work(); self.stored.work() }
        }
        """)
        let function = try body("execute", in: bodies)
        let calls = function.references.filter { $0.name == "work" }
        #expect(calls.count == 2)
        #expect(calls.allSatisfy { $0.receiverType == nil && $0.isMember })
    }

    private func collect(_ source: String, knownTypes: Set<String> = []) -> [DeclarationBody] {
        let tree = Parser.parse(source: source)
        let visitor = ReferenceGraphVisitor(filePath: "test.swift", sourceFile: tree, knownTypeNames: knownTypes)
        visitor.walk(tree)
        return visitor.declarationBodies
    }

    private func body(_ name: String, in bodies: [DeclarationBody]) throws -> DeclarationBody {
        try #require(bodies.first { $0.declaration.name == name })
    }
}

import SwiftParser
import SwiftSyntax
import Testing
@testable import unused

struct ExplicitReferenceVisitorTests {
    @Test
    func constructorsKeepLabelsAndOwnerContext() {
        let visitor = analyze("""
        struct Outer {
            struct Item {}
            func run() { _ = Item(1, `repeat`: 2) }
        }
        """)
        #expect(visitor.callUsages == [CallUsage(
            kind: .initializer, receiverType: "Outer.Item", argumentLabels: ["_", "repeat"],
            enclosingTypePath: ["Outer"]
        )])
    }

    @Test
    func nestedGenericAndAliasConstructorsKeepCanonicalPaths() {
        let visitor = analyze("""
        struct Outer<T> { struct Inner<U> {} }
        typealias Alias = Outer<Int>.Inner<String>
        _ = Outer<Int>.Inner<String>(value: 1)
        _ = Alias()
        _ = Outer<Int>.Inner<String>.init(value: 2)
        """)
        #expect(visitor.callUsages == [
            CallUsage(kind: .initializer, receiverType: "Outer.Inner", argumentLabels: ["value"]),
            CallUsage(kind: .initializer, receiverType: "Alias")
        ])
        #expect(visitor.referencedTypeNames.contains("Outer.Inner"))
        #expect(!visitor.referencedTypeNames.contains("Inner"))
    }

    @Test(arguments: [
        "Item.init(value: 1)",
        "(Item.init)(value: 1)",
        "((Item.init))(value: 1)",
        "Item.init<Int>(value: 1)",
        "(Item.init<Int>)(value: 1)",
        "Item.init!(value: 1)",
        "Item.init?(value: 1)",
        "try Item.init(value: 1)",
        "try await (Item.init)(value: 1)",
        "(try await Item.init)(value: 1)"
    ])
    func calledInitializersDoNotCreateNameOnlyMemberUsages(expression: String) {
        let visitor = analyze("""
        struct Item {}
        _ = \(expression)
        """)
        #expect(visitor.callUsages == [
            CallUsage(kind: .initializer, receiverType: "Item", argumentLabels: ["value"])
        ])
        #expect(!visitor.qualifiedMemberUsages.contains { $0.memberName == "init" })
        #expect(!visitor.unqualifiedMemberUsages.contains("init"))
        #expect(!visitor.bareIdentifierUsages.contains("init"))
        #expect(!visitor.usedIdentifiers.contains("init"))
        #expect(visitor.referencedTypeNames.contains("Item"))
        if expression.contains("<Int>") {
            #expect(visitor.referencedTypeNames.contains("Int"))
        }
    }

    @Test
    func calledInitializersKeepNestedGenericAndAliasTypeReferences() {
        let visitor = analyze("""
        struct Outer<T> { struct Inner<U> {} }
        typealias Alias = Outer<Int>.Inner<String>
        _ = Outer<Int>.Inner<String>.init(value: 1)
        _ = Alias.init(other: 1)
        """)
        #expect(visitor.callUsages == [
            CallUsage(kind: .initializer, receiverType: "Outer.Inner", argumentLabels: ["value"]),
            CallUsage(kind: .initializer, receiverType: "Alias", argumentLabels: ["other"])
        ])
        #expect(visitor.referencedTypeNames.isSuperset(of: ["Outer.Inner", "Outer", "Int", "String", "Alias"]))
        #expect(!visitor.referencedTypeNames.contains("Inner"))
        #expect(!visitor.qualifiedMemberUsages.contains { $0.memberName == "init" })
        #expect(!visitor.unqualifiedMemberUsages.contains("init"))
    }

    @Test
    func implicitUnknownAndDelegatingInitializerCallsDoNotCreateBlanketUsages() {
        let visitor = analyze("""
        struct Item {}
        class Owner {
            init() { self.init(value: 1); super.init(parent: 1) }
            func run(_ type: Item.Type, _ unknown: () -> Void) {
                let item: Item = .init(contextual: 1)
                _ = .init(implicit: 1)
                _ = unknown.init(unknown: 1)
                _ = type.init(metatype: 1)
            }
        }
        """)
        #expect(visitor.callUsages == [
            CallUsage(kind: .initializer, receiverType: "Owner", argumentLabels: ["value"], enclosingTypePath: ["Owner"]),
            CallUsage(kind: .initializer, argumentLabels: ["parent"], enclosingTypePath: ["Owner"]),
            CallUsage(kind: .initializer, receiverType: "Item", argumentLabels: ["contextual"], enclosingTypePath: ["Owner"]),
            CallUsage(kind: .initializer, argumentLabels: ["implicit"], enclosingTypePath: ["Owner"]),
            CallUsage(kind: .initializer, argumentLabels: ["unknown"], enclosingTypePath: ["Owner"]),
            CallUsage(kind: .initializer, receiverType: "Item", argumentLabels: ["metatype"], enclosingTypePath: ["Owner"])
        ])
        #expect(!visitor.qualifiedMemberUsages.contains { $0.memberName == "init" })
        #expect(!visitor.unqualifiedMemberUsages.contains("init"))
        #expect(!visitor.usedIdentifiers.contains("init"))
    }

    @Test
    func calledInitializersStillWalkUnknownReceiverExpressions() {
        let visitor = analyze("""
        _ = factory().init(selected: 1)
        """)
        #expect(visitor.callUsages == [CallUsage(kind: .initializer, argumentLabels: ["selected"])])
        #expect(visitor.bareIdentifierUsages.contains("factory"))
        #expect(!visitor.unqualifiedMemberUsages.contains("init"))
        #expect(!visitor.usedIdentifiers.contains("init"))
    }

    @Test(arguments: [
        "let constructor = Item.init",
        "let constructor = (Item.init)",
        "let constructor = Item.init<Int>",
        "let constructors = (Item.init, other)",
        "consume(Item.init)",
        "consume((Item.init))",
        "consume(factory(Item.init))()",
        "_ = Item.init.description()"
    ])
    func initializerFunctionValuesKeepConservativeMemberUsage(expression: String) {
        let visitor = analyze("""
        struct Item {}
        \(expression)
        """)
        expectQualified(visitor, "Item", "init")
        #expect(visitor.usedIdentifiers.contains("init"))
        #expect(!visitor.bareIdentifierUsages.contains("init"))
        #expect(visitor.referencedTypeNames.contains("Item"))
        #expect(visitor.callUsages.isEmpty)
    }

    @Test
    func unknownInitializerFunctionValuesRemainUnqualifiedUsages() {
        let visitor = analyze("""
        func run(_ unknown: () -> Void) {
            let constructor = unknown.init
            consume((unknown.init))
        }
        """)
        #expect(visitor.unqualifiedMemberUsages.contains("init"))
        #expect(!visitor.qualifiedMemberUsages.contains { $0.memberName == "init" })
        #expect(visitor.callUsages.isEmpty)
    }

    @Test
    func initializerFunctionValuesAreNotInferredAsMetatypesOrInstances() {
        let visitor = analyze("""
        struct Item {}
        let constructor = Item.init
        let copied = constructor
        constructor(value: 1)
        copied(other: 1)
        constructor.functionMember()
        _ = copied[0]
        """)
        expectQualified(visitor, "Item", "init")
        #expect(visitor.callUsages == [CallUsage(kind: .subscript, argumentLabels: ["_"])])
        #expect(visitor.unqualifiedMemberUsages.contains("functionMember"))
        #expect(!visitor.qualifiedMemberUsages.contains(QualifiedUsage(typeName: "Item", memberName: "functionMember")))
    }

    @Test
    func discardedFactoryCallsDoNotSupplyConstructorContext() {
        let visitor = analyze("""
        _ = factory(value: 1)
        _ = (factory(other: 1))
        _ = try await factory(async: 1)
        let annotated: Item = factory(contextual: 1)
        _ = External(explicitType: 1)
        _ = .init(explicitInit: 1)
        """)
        #expect(visitor.callUsages == Set(["contextual", "explicitType", "explicitInit"].map {
            CallUsage(kind: .initializer, argumentLabels: [$0])
        }))
        #expect(visitor.bareIdentifierUsages.contains("factory"))
        #expect(!visitor.unqualifiedMemberUsages.contains("init"))
    }

    @Test
    func discardedCallsToKnownTypeShadowsAreNotInferredAsConstructors() {
        let visitor = analyze("""
        func run(_ Item: () -> Void) { _ = Item(); _ = (Item()) }
        """, knownTypes: ["Item"])
        #expect(visitor.callUsages.isEmpty)
        #expect(!visitor.referencedTypeNames.contains("Item"))
        #expect(visitor.bareIdentifierUsages.contains("Item"))
    }

    @Test
    func aliasAndNestedInitSyntaxSupportsReceiverInference() {
        let visitor = analyze("""
        struct Outer { struct Item {} }
        typealias Alias = Outer.Item
        let first = Alias.init()
        let second = Outer.Item.init()
        first.firstMember()
        second.secondMember()
        _ = first[0]
        _ = second[index: 0]
        """)
        #expect(visitor.callUsages.contains(CallUsage(kind: .initializer, receiverType: "Alias")))
        #expect(visitor.callUsages.contains(CallUsage(kind: .initializer, receiverType: "Outer.Item")))
        #expect(visitor.callUsages.contains(CallUsage(kind: .subscript, receiverType: "Alias", argumentLabels: ["_"])))
        #expect(visitor.callUsages.contains(CallUsage(kind: .subscript, receiverType: "Outer.Item", argumentLabels: ["index"])))
        expectQualified(visitor, "Alias", "firstMember")
        expectQualified(visitor, "Outer.Item", "secondMember")
    }

    @Test
    func initializerDelegationUsesSelfAndConservativeSuper() {
        let visitor = analyze("""
        class Outer {
            class Child {
                init() { self.init(value: 1); super.init(2) }
                func make() { _ = Self(value: 3); _ = Self.init(value: 4) }
            }
        }
        """)
        #expect(visitor.callUsages == [
            CallUsage(kind: .initializer, receiverType: "Outer.Child", argumentLabels: ["value"],
                      enclosingTypePath: ["Outer", "Child"]),
            dynamicInitializerUsage("Outer.Child", labels: ["value"], owner: ["Outer", "Child"]),
            CallUsage(kind: .initializer, argumentLabels: ["_"], enclosingTypePath: ["Outer", "Child"])
        ])
    }

    @Test
    func contextualInitializersUseVariableAndOptionalBindingAnnotations() {
        let visitor = analyze("""
        struct Item {}
        func run() {
            let item: Item = .init(value: 1)
            let wrapped: Item? = try .init(value: 2)
            if let bound: Item = .init(other: 1) { _ = bound[0] }
        }
        """)
        #expect(visitor.callUsages == [
            CallUsage(kind: .initializer, receiverType: "Item", argumentLabels: ["value"]),
            CallUsage(kind: .initializer, receiverType: "Item", argumentLabels: ["other"]),
            CallUsage(kind: .subscript, receiverType: "Item", argumentLabels: ["_"])
        ])
    }

    @Test
    func contextualInitializersSupportParenthesesAwaitReturnsAndAssignments() {
        let visitor = analyze("""
        struct Item {}
        func make() async -> Item { return try await (.init(returned: 1)) }
        var value: Item
        value = .init(assigned: 1)
        let wrapped: Item = (.init(wrapped: 1))
        """)
        #expect(visitor.callUsages == [
            CallUsage(kind: .initializer, receiverType: "Item", argumentLabels: ["returned"]),
            CallUsage(kind: .initializer, receiverType: "Item", argumentLabels: ["assigned"]),
            CallUsage(kind: .initializer, receiverType: "Item", argumentLabels: ["wrapped"])
        ])
    }

    @Test
    func assignmentContextTraversesExpressionListsAndTransparentWrappers() {
        let visitor = analyze("""
        struct Item {}
        func run() async {
            var value: Item
            value = (.init(parenthesized: 1))
            value = try await (.init(effectful: 1))
            (value) = .init(wrappedTarget: 1)
            value = factory(contextual: 1)
        }
        """)
        #expect(visitor.callUsages == [
            CallUsage(kind: .initializer, receiverType: "Item", argumentLabels: ["parenthesized"]),
            CallUsage(kind: .initializer, receiverType: "Item", argumentLabels: ["effectful"]),
            CallUsage(kind: .initializer, receiverType: "Item", argumentLabels: ["wrappedTarget"]),
            CallUsage(kind: .initializer, argumentLabels: ["contextual"])
        ])
    }

    @Test
    func defaultParametersAndSingleExpressionResultsSupplyContext() {
        let visitor = analyze("""
        struct Item {}
        func take(_ item: Item = .init(defaulted: 1)) {}
        func make() -> Item { .init(function: 1) }
        let closure = { () -> Item in .init(closure: 1) }
        struct Owner {
            var value: Item { .init(property: 1) }
            subscript(_ index: Int) -> Item { get { .init(subscriptResult: 1) } }
        }
        """)
        #expect(visitor.callUsages == [
            CallUsage(kind: .initializer, receiverType: "Item", argumentLabels: ["defaulted"]),
            CallUsage(kind: .initializer, receiverType: "Item", argumentLabels: ["function"]),
            CallUsage(kind: .initializer, receiverType: "Item", argumentLabels: ["closure"]),
            CallUsage(kind: .initializer, receiverType: "Item", argumentLabels: ["property"], enclosingTypePath: ["Owner"]),
            CallUsage(kind: .initializer, receiverType: "Item", argumentLabels: ["subscriptResult"], enclosingTypePath: ["Owner"])
        ])
    }

    @Test
    func outerAnnotationDoesNotLeakIntoNestedCallArguments() {
        let visitor = analyze("""
        struct Item {}
        let item: Item = factory(.init(nested: 1))
        let tuple: Item = (.init(tupleElement: 1), 2)
        """)
        #expect(visitor.callUsages == [
            CallUsage(kind: .initializer, argumentLabels: ["_"]),
            CallUsage(kind: .initializer, argumentLabels: ["nested"]),
            CallUsage(kind: .initializer, argumentLabels: ["tupleElement"])
        ])
        #expect(!visitor.callUsages.contains { $0.receiverType == "Item" })
    }

    @Test
    func unknownConstructorsAndContextualFactoriesAreConservative() {
        let visitor = analyze("""
        _ = External(value: 1)
        _ = Namespace.External(other: 1)
        _ = unknown.init(explicit: 1)
        _ = .init(implicit: 1)
        let value: Item = factory(context: 1)
        ordinary(unrelated: 1)
        """)
        #expect(visitor.callUsages == Set(["value", "other", "explicit", "implicit", "context"].map {
            CallUsage(kind: .initializer, argumentLabels: [$0])
        }))
        #expect(visitor.bareIdentifierUsages.contains("ordinary"))
    }

    @Test
    func annotatedAndInferredMetatypesSupportConstructors() {
        let visitor = analyze("""
        struct Item {}
        func make(_ type: Item.Type) {
            _ = type(1)
            _ = type.init(value: 1)
            let inferred = Item.self
            _ = inferred(other: 1)
        }
        """)
        #expect(visitor.callUsages == Set([["_"], ["value"], ["other"]].map {
            CallUsage(kind: .initializer, receiverType: "Item", argumentLabels: $0)
        }))
    }

    @Test
    func genericMetatypesStayConservative() {
        let visitor = analyze("""
        func make<T>(_ type: T.Type) {
            _ = T(first: 1)
            _ = type(second: 1)
            _ = type.init(third: 1)
            let value: T = .init(fourth: 1)
        }
        """)
        #expect(visitor.callUsages == Set(["first", "second", "third", "fourth"].map {
            CallUsage(kind: .initializer, argumentLabels: [$0])
        }))
    }

    @Test
    func genericMetatypesHideOuterValueBindingsAndKnownTypeNames() {
        let visitor = analyze("""
        let T: Item
        func make<T>(_ type: T.Type) { _ = T(first: 1); _ = type.init(second: 1) }
        """, knownTypes: ["T", "Item"])
        #expect(visitor.callUsages == [
            CallUsage(kind: .initializer, argumentLabels: ["first"]),
            CallUsage(kind: .initializer, argumentLabels: ["second"])
        ])
        #expect(!visitor.referencedTypeNames.contains("T"))
    }

    @Test
    func genericQualifiedTypeReferencesDoNotLeakToKnownNominalTypes() {
        let visitor = analyze("""
        func make<T>(_ type: T.Type, _ value: T.Nested<Payload>) { _ = type.init(); _ = value[0]; value.work() }
        """, knownTypes: ["T", "T.Nested", "Payload"])
        #expect(visitor.referencedTypeNames == ["Payload"])
        #expect(visitor.callUsages == [
            CallUsage(kind: .initializer), CallUsage(kind: .subscript, argumentLabels: ["_"])
        ])
        #expect(visitor.unqualifiedMemberUsages.contains("work"))
    }

    @Test
    func nominalMetatypeParametersCanResolveNestedTypes() {
        let visitor = analyze("""
        struct Outer { struct Inner {} }
        func make(_ type: Outer.Type) { _ = type.Inner(value: 1) }
        """)
        #expect(visitor.callUsages == [
            CallUsage(kind: .initializer, receiverType: "Outer.Inner", argumentLabels: ["value"])
        ])
    }

    @Test
    func constructorTrailingClosuresRetainTheirLabelsAndFlag() {
        let visitor = analyze("""
        struct Item {}
        _ = Item(value: 1) { first() } completion: { second() }
        _ = Item { third() }
        """)
        #expect(visitor.callUsages == [
            CallUsage(kind: .initializer, receiverType: "Item", argumentLabels: ["value", "_", "completion"],
                      hasTrailingClosure: true, trailingClosureIndex: 1),
            CallUsage(kind: .initializer, receiverType: "Item", argumentLabels: ["_"], hasTrailingClosure: true,
                      trailingClosureIndex: 0)
        ])
        #expect(visitor.bareIdentifierUsages.isSuperset(of: ["first", "second", "third"]))
    }

    @Test
    func firstTrailingClosureIndexExcludesOrdinaryUnlabeledArguments() {
        let visitor = analyze("""
        struct Item {}
        _ = Item(1, { ordinaryClosure() }) { first() } completion: { second() } final: { third() }
        _ = Item(1, { parenthesizedClosure() })
        let value: Item
        _ = value[0, other: 1] { subscriptFirst() } completion: { subscriptSecond() }
        _ = value[0] { subscriptOnly() }
        """)
        #expect(visitor.callUsages == [
            CallUsage(kind: .initializer, receiverType: "Item", argumentLabels: ["_", "_", "_", "completion", "final"],
                      hasTrailingClosure: true, trailingClosureIndex: 2),
            CallUsage(kind: .initializer, receiverType: "Item", argumentLabels: ["_", "_"]),
            CallUsage(kind: .subscript, receiverType: "Item", argumentLabels: ["_", "other", "_", "completion"],
                      hasTrailingClosure: true, trailingClosureIndex: 2),
            CallUsage(kind: .subscript, receiverType: "Item", argumentLabels: ["_", "_"],
                      hasTrailingClosure: true, trailingClosureIndex: 1)
        ])
        #expect(visitor.bareIdentifierUsages.isSuperset(of: [
            "ordinaryClosure", "first", "second", "third", "parenthesizedClosure", "subscriptFirst", "subscriptSecond", "subscriptOnly"
        ]))
    }

    @Test
    func subscriptReceiversUseAnnotationsInferenceAndWrappers() {
        let visitor = analyze("""
        struct Item {}
        func run(_ annotated: Item, _ optional: Item?, _ unknown: () -> Void) {
            let inferred = Item()
            _ = annotated[0, key: key]
            _ = inferred[index: 1]
            _ = optional?[2]
            _ = optional![3]
            _ = (annotated)[position: 4]
            _ = Item()[temporary: 5]
            _ = unknown[unresolved: 6]
        }
        """)
        #expect(visitor.callUsages == [
            CallUsage(kind: .initializer, receiverType: "Item"),
            CallUsage(kind: .subscript, receiverType: "Item", argumentLabels: ["_", "key"]),
            CallUsage(kind: .subscript, receiverType: "Item", argumentLabels: ["index"]),
            CallUsage(kind: .subscript, receiverType: "Item", argumentLabels: ["_"]),
            CallUsage(kind: .subscript, receiverType: "Item", argumentLabels: ["position"]),
            CallUsage(kind: .subscript, receiverType: "Item", argumentLabels: ["temporary"]),
            CallUsage(kind: .subscript, argumentLabels: ["unresolved"])
        ])
        #expect(visitor.bareIdentifierUsages.contains("key"))
        #expect(!visitor.bareIdentifierUsages.contains("position"))
    }

    @Test
    func collectionTypeAnnotationsSupportSubscripts() {
        let visitor = analyze("""
        func run(_ array: [Item], _ dictionary: [String: Item]) {
            _ = array[0]
            _ = dictionary[key: "item"]
        }
        """)
        #expect(visitor.callUsages == [
            CallUsage(kind: .subscript, receiverType: "Array", argumentLabels: ["_"]),
            CallUsage(kind: .subscript, receiverType: "Dictionary", argumentLabels: ["key"])
        ])
    }

    @Test
    func subscriptTrailingClosuresKeepShapeAndAreWalked() {
        let visitor = analyze("""
        let value: Item
        _ = value[index: 0] { first() } completion: { second() }
        """)
        #expect(visitor.callUsages.contains(CallUsage(
            kind: .subscript, receiverType: "Item", argumentLabels: ["index", "_", "completion"],
            hasTrailingClosure: true, trailingClosureIndex: 1
        )))
        #expect(visitor.bareIdentifierUsages.isSuperset(of: ["first", "second"]))
    }

    @Test
    func unknownSubscriptsAlwaysEmitConservativeShapes() {
        let visitor = analyze("""
        _ = missing[index: 1]
        _ = factory()[0]
        class Owner { func run() { _ = super[parent: 1] } }
        """)
        #expect(visitor.callUsages == [
            CallUsage(kind: .subscript, argumentLabels: ["index"]),
            CallUsage(kind: .subscript, argumentLabels: ["_"]),
            CallUsage(kind: .subscript, argumentLabels: ["parent"], enclosingTypePath: ["Owner"])
        ])
    }

    @Test
    func memberPropertiesSupplySubscriptReceiverTypes() {
        let visitor = analyze("""
        struct Owner {
            func run() { _ = self.items[0]; if let optional { _ = optional[index: 1] } }
            var items: [Int]
            var optional: Item?
        }
        """)
        #expect(visitor.callUsages == [
            CallUsage(kind: .subscript, receiverType: "Array", argumentLabels: ["_"], enclosingTypePath: ["Owner"]),
            CallUsage(kind: .subscript, receiverType: "Item", argumentLabels: ["index"], enclosingTypePath: ["Owner"])
        ])
        #expect(visitor.bareIdentifierUsages.contains("optional"))
    }

    @Test
    func knownTypeShadowingLocalsAreNotConstructorsOrTypeReferences() {
        let visitor = analyze("""
        func run(_ `Widget`: () -> Void) {
            `Widget`()
            `Widget`.work()
            _ = `Widget`[0]
        }
        """, knownTypes: ["`Widget`"])
        #expect(visitor.callUsages == [CallUsage(kind: .subscript, argumentLabels: ["_"])])
        #expect(!visitor.referencedTypeNames.contains("Widget"))
        #expect(!visitor.qualifiedMemberUsages.contains(QualifiedUsage(typeName: "Widget", memberName: "work")))
        #expect(visitor.unqualifiedMemberUsages.contains("work"))
    }

    @Test
    func typedValueShadowsTypeButContextualCallsStillProtectUnknownInitializers() {
        let visitor = analyze("""
        func run(_ Widget: Other) {
            Widget()
            Widget.work()
            let result: Item = Widget(context: 1)
        }
        """, knownTypes: ["Widget", "Other", "Item"])
        #expect(visitor.callUsages == [CallUsage(kind: .initializer, argumentLabels: ["context"])])
        expectQualified(visitor, "Other", "work")
        #expect(!visitor.referencedTypeNames.contains("Widget"))
    }

    @Test
    func qualifiedKnownTypePathsCanBeShadowedAtTheirRoot() {
        let visitor = analyze("""
        func run(_ Namespace: () -> Void) {
            _ = Namespace.Item()
            Namespace.Item.work()
            _ = Namespace.Item.self
        }
        """, knownTypes: ["Namespace", "Namespace.Item"])
        #expect(visitor.callUsages.isEmpty)
        #expect(!visitor.referencedTypeNames.contains("Namespace.Item"))
        #expect(visitor.unqualifiedMemberUsages.contains("work"))
    }

    @Test
    func ordinaryBlocksRestoreOuterTypesAndUnknownShadowsStopLookup() {
        let visitor = analyze("""
        func run(_ value: First) {
            do { let value = unknown(); value.inner(); _ = value[inside: 0] }
            value.after()
            _ = value[outside: 0]
            do { let value: Second; value.second() }
            value.restored()
        }
        """)
        #expect(visitor.unqualifiedMemberUsages.contains("inner"))
        #expect(!visitor.qualifiedMemberUsages.contains(QualifiedUsage(typeName: "First", memberName: "inner")))
        expectQualified(visitor, "First", "after")
        expectQualified(visitor, "Second", "second")
        expectQualified(visitor, "First", "restored")
        #expect(visitor.callUsages == [
            CallUsage(kind: .subscript, argumentLabels: ["inside"]),
            CallUsage(kind: .subscript, receiverType: "First", argumentLabels: ["outside"])
        ])
    }

    @Test
    func writesDoNotNarrowUnknownBindingsOrRecoverOuterTypes() {
        let visitor = analyze("""
        struct Item {}
        func run(_ value: Outer) {
            do {
                var value = factory()
                value = Item()
                value.afterConcreteWrite()
                _ = value[index: 0]
                value = .init(contextualWrite: 1)
                value.afterContextualWrite()
            }
            value.outer()
        }
        """)
        #expect(visitor.callUsages == [
            CallUsage(kind: .initializer, receiverType: "Item"),
            CallUsage(kind: .initializer, argumentLabels: ["contextualWrite"]),
            CallUsage(kind: .subscript, argumentLabels: ["index"])
        ])
        #expect(visitor.unqualifiedMemberUsages.isSuperset(of: ["afterConcreteWrite", "afterContextualWrite"]))
        expectQualified(visitor, "Outer", "outer")
        for member in ["afterConcreteWrite", "afterContextualWrite"] {
            #expect(!visitor.qualifiedMemberUsages.contains { $0.memberName == member })
        }
        #expect(!visitor.unqualifiedMemberUsages.contains("init"))
    }

    @Test
    func writesPreserveKnownDeclaredAndInferredStaticTypes() {
        let visitor = analyze("""
        class Base {}
        class Derived: Base {}
        func run() {
            var annotated: Base = Derived()
            annotated = factory()
            annotated.annotatedMember()
            _ = annotated[declared: 0]
            var inferred = Base()
            inferred = factory()
            inferred.inferredMember()
            _ = inferred[inferred: 0]
            var type: Base.Type = Derived.self
            type = Derived.self
            _ = type.init(selected: 1)
        }
        """)
        expectQualified(visitor, "Base", "annotatedMember")
        expectQualified(visitor, "Base", "inferredMember")
        #expect(visitor.callUsages.contains(CallUsage(kind: .subscript, receiverType: "Base", argumentLabels: ["declared"])))
        #expect(visitor.callUsages.contains(CallUsage(kind: .subscript, receiverType: "Base", argumentLabels: ["inferred"])))
        #expect(visitor.callUsages.contains(CallUsage(kind: .initializer, receiverType: "Base", argumentLabels: ["selected"])))
        #expect(!visitor.qualifiedMemberUsages.contains { $0.memberName == "init" })
        #expect(!visitor.unqualifiedMemberUsages.contains("init"))
    }

    @Test
    func writesDoNotPromoteUnknownBindingsToMetatypes() {
        let visitor = analyze("""
        struct Item {}
        func run() {
            var type = unknownType()
            type = Item.self
            type(unresolved: 1)
            _ = type.init(explicit: 1)
            type.unknownMember()
        }
        """)
        #expect(visitor.callUsages == [CallUsage(kind: .initializer, argumentLabels: ["explicit"])])
        #expect(visitor.unqualifiedMemberUsages.contains("unknownMember"))
        #expect(!visitor.unqualifiedMemberUsages.contains("init"))
        #expect(!visitor.qualifiedMemberUsages.contains { $0.memberName == "init" })
    }

    @Test
    func destructuringLocalsShadowWithoutAssigningTheTupleTypeToEachName() {
        let visitor = analyze("""
        func run(_ value: First, _ other: Second) {
            do {
                let (value, other): (First, Second) = pair
                value.inside()
                other.otherInside()
                _ = value[0]
            }
            value.after()
            other.otherAfter()
        }
        """)
        #expect(visitor.unqualifiedMemberUsages.isSuperset(of: ["inside", "otherInside"]))
        expectQualified(visitor, "First", "after")
        expectQualified(visitor, "Second", "otherAfter")
        #expect(visitor.callUsages == [CallUsage(kind: .subscript, argumentLabels: ["_"])])
    }

    @Test
    func initializerReadsAndInferencePrecedeTheNewLocalBinding() {
        let visitor = analyze("""
        func run(_ value: Item) {
            do { let value = value; value.copied(); _ = value[0] }
            do { let value = value.work(); value.unknown() }
        }
        """)
        expectQualified(visitor, "Item", "copied")
        expectQualified(visitor, "Item", "work")
        #expect(visitor.unqualifiedMemberUsages.contains("unknown"))
        #expect(visitor.bareIdentifierUsages.contains("value"))
        #expect(visitor.callUsages == [CallUsage(kind: .subscript, receiverType: "Item", argumentLabels: ["_"])])
    }

    @Test
    func constructorShadowIsInstalledAfterItsInitializerAndRemovedAfterBlock() {
        let visitor = analyze("""
        struct Item {}
        func run() {
            do { let Item = Item(before: 1); Item.work(); Item() }
            _ = Item(after: 1)
        }
        """)
        #expect(visitor.callUsages == [
            CallUsage(kind: .initializer, receiverType: "Item", argumentLabels: ["before"]),
            CallUsage(kind: .initializer, receiverType: "Item", argumentLabels: ["after"])
        ])
        expectQualified(visitor, "Item", "work")
    }

    @Test
    func multipleBindingsAreRegisteredInSourceOrder() {
        let visitor = analyze("""
        struct Item {}
        func run() {
            let first = Item(), second = first, Item = second
            second.work()
            Item.shadowed()
            Item()
        }
        """)
        #expect(visitor.callUsages == [CallUsage(kind: .initializer, receiverType: "Item")])
        expectQualified(visitor, "Item", "work")
        expectQualified(visitor, "Item", "shadowed")
    }

    @Test
    func ifElseBindingsDoNotLeakAndConditionsUseSourceOrder() {
        let visitor = analyze("""
        func run(_ value: First, _ source: Second?, _ other: Third?) {
            if value.before(), let value = source, value.between(), let later = other, later.last() {
                value.success()
                later.body()
            } else if value.failureCondition() {
                value.failure()
            }
            value.after()
            later.outside()
        }
        """)
        expectQualified(visitor, "First", "before")
        expectQualified(visitor, "Second", "between")
        expectQualified(visitor, "Third", "last")
        expectQualified(visitor, "Second", "success")
        expectQualified(visitor, "Third", "body")
        expectQualified(visitor, "First", "failureCondition")
        expectQualified(visitor, "First", "failure")
        expectQualified(visitor, "First", "after")
        #expect(visitor.unqualifiedMemberUsages.contains("outside"))
        #expect(!visitor.qualifiedMemberUsages.contains(QualifiedUsage(typeName: "Second", memberName: "before")))
        #expect(!visitor.qualifiedMemberUsages.contains(QualifiedUsage(typeName: "First", memberName: "between")))
    }

    @Test
    func whileBindingsAreTemporaryAndConditionsUseSourceOrder() {
        let visitor = analyze("""
        func run(_ value: First, _ source: Second?) {
            while value.before(), let value = source, value.condition() {
                value.body()
                let onlyHere: Third
            }
            value.after()
            onlyHere.outside()
        }
        """)
        expectQualified(visitor, "First", "before")
        expectQualified(visitor, "Second", "condition")
        expectQualified(visitor, "Second", "body")
        expectQualified(visitor, "First", "after")
        #expect(visitor.unqualifiedMemberUsages.contains("outside"))
        #expect(!visitor.qualifiedMemberUsages.contains(QualifiedUsage(typeName: "First", memberName: "condition")))
    }

    @Test
    func guardBindingsSurviveSuccessButNotFailureOrTheEnclosingBlock() {
        let visitor = analyze("""
        func run(_ value: First, _ source: Second?) {
            do {
                guard value.before(), let value = source, value.condition() else {
                    value.failure()
                    let failureOnly: Third
                    return
                }
                value.success()
                failureOnly.outside()
            }
            value.after()
        }
        """)
        expectQualified(visitor, "First", "before")
        expectQualified(visitor, "Second", "condition")
        expectQualified(visitor, "First", "failure")
        expectQualified(visitor, "Second", "success")
        expectQualified(visitor, "First", "after")
        #expect(visitor.unqualifiedMemberUsages.contains("outside"))
        #expect(!visitor.qualifiedMemberUsages.contains(QualifiedUsage(typeName: "First", memberName: "condition")))
    }

    @Test
    func unknownGuardBindingHidesAnOuterTypeAfterSuccess() {
        let visitor = analyze("""
        func run(_ value: Item) {
            guard let value = unknown() else { value.failure(); return }
            value.success()
            _ = value[0]
        }
        """)
        expectQualified(visitor, "Item", "failure")
        #expect(visitor.unqualifiedMemberUsages.contains("success"))
        #expect(visitor.callUsages == [CallUsage(kind: .subscript, argumentLabels: ["_"])])
    }

    @Test(arguments: ["if", "guard", "while"])
    func shorthandOptionalBindingsRecordOriginalReadsAndInferTypes(keyword: String) {
        let condition = keyword == "guard"
            ? "guard let `repeat` else { return }; `repeat`.work()"
            : "\(keyword) let `repeat` { `repeat`.work() }"
        let visitor = analyze("""
        func run(_ `repeat`: Item?) { \(condition) }
        """)
        #expect(visitor.bareIdentifierUsages.contains("repeat"))
        #expect(visitor.usedIdentifiers.contains("repeat"))
        expectQualified(visitor, "Item", "work")
    }

    @Test(arguments: ["Item?", "Item!", "Optional<Item>", "Swift.Optional<Item>"])
    func shorthandOptionalBindingsUnwrapSupportedOptionalSpellings(type: String) {
        let visitor = analyze("""
        func run() {
            let value: \(type) = nil
            if let value { value.work(); _ = value[0] }
        }
        """)
        expectQualified(visitor, "Item", "work")
        #expect(visitor.bareIdentifierUsages.contains("value"))
        #expect(visitor.callUsages == [CallUsage(kind: .subscript, receiverType: "Item", argumentLabels: ["_"])])
    }

    @Test
    func shorthandOptionalBindingUnknownShadowDoesNotRecoverAnOuterType() {
        let visitor = analyze("""
        func run(_ value: Item?) {
            do {
                let value = unknown()
                if let value { value.work() }
            }
        }
        """)
        #expect(visitor.bareIdentifierUsages.contains("value"))
        #expect(visitor.unqualifiedMemberUsages.contains("work"))
        #expect(!visitor.qualifiedMemberUsages.contains(QualifiedUsage(typeName: "Item", memberName: "work")))
    }

    @Test
    func explicitOptionalBindingReadsItsInitializerNotItsPattern() {
        let visitor = analyze("""
        func run(_ source: Item?) {
            if let fresh = source {}
            guard let other = source else { return }
        }
        """)
        #expect(visitor.bareIdentifierUsages.contains("source"))
        #expect(!visitor.bareIdentifierUsages.contains("fresh"))
        #expect(!visitor.bareIdentifierUsages.contains("other"))
    }

    @Test
    func ordinaryDeclarationsAndPatternsAreNotReads() {
        let visitor = analyze("""
        func run(_ parameter: Int) {
            let ordinary = 1
            let (first, second) = (1, 2)
            for (loopFirst, loopSecond) in pairs {}
            for case .some(let element) in values {}
            switch source { case .some(let caseValue): break; default: break }
            if case .some(let ifValue) = source {}
            guard case .some(let guardValue) = source else { return }
            do { try action() } catch let caught {}
            let closure = { closureParameter in 1 }
        }
        """)
        for name in ["parameter", "ordinary", "first", "second", "loopFirst", "loopSecond", "element",
                     "caseValue", "ifValue", "guardValue", "caught", "closure", "closureParameter"] {
            #expect(!visitor.bareIdentifierUsages.contains(name))
        }
        #expect(visitor.bareIdentifierUsages.isSuperset(of: ["pairs", "values", "source", "action"]))
        #expect(visitor.unqualifiedMemberUsages.contains("some"))
        #expect(visitor.callUsages.isEmpty)
    }

    @Test
    func expressionPatternsStillRecordConstructorsSubscriptsAndOperators() {
        let visitor = analyze("""
        struct Item {}
        func run(_ value: Int, _ indices: [Int]) {
            switch value {
            case Item(): break
            case indices[0]: break
            case -1: break
            case 0...10: break
            default: break
            }
        }
        """)
        #expect(visitor.callUsages == [
            CallUsage(kind: .initializer, receiverType: "Item"),
            CallUsage(kind: .subscript, receiverType: "Array", argumentLabels: ["_"])
        ])
        #expect(visitor.bareIdentifierUsages.isSuperset(of: ["-", "...", "indices"]))
    }

    @Test
    func switchCasesIsolateLocalsAndRegisterAssociatedValuePatterns() {
        let visitor = analyze("""
        func run(_ value: First, _ input: Any) {
            switch input {
            case .some(let value) where value.condition():
                value.bound()
                let caseOnly: Second
            default:
                value.otherCase()
                caseOnly.outside()
            }
            value.after()
        }
        """)
        #expect(visitor.unqualifiedMemberUsages.isSuperset(of: ["condition", "bound", "outside"]))
        expectQualified(visitor, "First", "otherCase")
        expectQualified(visitor, "First", "after")
        #expect(!visitor.qualifiedMemberUsages.contains(QualifiedUsage(typeName: "First", memberName: "condition")))
        #expect(!visitor.qualifiedMemberUsages.contains(QualifiedUsage(typeName: "First", memberName: "bound")))
    }

    @Test
    func matchingPatternConditionsRegisterBindingsOnlyInSuccessScopes() {
        let visitor = analyze("""
        func run(_ value: First, _ input: Any) {
            if case .some(let value) = input { value.success() } else { value.failure() }
            value.afterIf()
            guard case .some(let value) = input else { value.guardFailure(); return }
            value.afterGuard()
        }
        """)
        #expect(visitor.unqualifiedMemberUsages.isSuperset(of: ["success", "afterGuard"]))
        expectQualified(visitor, "First", "failure")
        expectQualified(visitor, "First", "afterIf")
        expectQualified(visitor, "First", "guardFailure")
    }

    @Test
    func forSequenceSeesOuterBindingButPatternsShadowInWhereAndBody() {
        let visitor = analyze("""
        func run(_ value: First, _ second: Second) {
            for (value, second) in value.sequence() where value.condition() {
                value.body()
                second.bodySecond()
            }
            value.after()
            second.afterSecond()
        }
        """)
        expectQualified(visitor, "First", "sequence")
        #expect(visitor.unqualifiedMemberUsages.isSuperset(of: ["condition", "body", "bodySecond"]))
        expectQualified(visitor, "First", "after")
        expectQualified(visitor, "Second", "afterSecond")
    }

    @Test
    func typedForPatternsSupplyReceiverTypes() {
        let visitor = analyze("""
        for value: Item in items { value.work(); _ = value[0] }
        value.outside()
        """)
        expectQualified(visitor, "Item", "work")
        #expect(visitor.unqualifiedMemberUsages.contains("outside"))
        #expect(visitor.callUsages == [CallUsage(kind: .subscript, receiverType: "Item", argumentLabels: ["_"])])
    }

    @Test
    func catchPatternsAndImplicitErrorAreUnknownTemporaryBindings() {
        let visitor = analyze("""
        func run(_ value: First, _ error: Second) {
            do { try action() }
            catch .failure(let value) where value.condition() { value.body() }
            catch { error.implicit(); value.otherCatch() }
            value.after()
            error.afterError()
        }
        """)
        #expect(visitor.unqualifiedMemberUsages.isSuperset(of: ["condition", "body", "implicit"]))
        expectQualified(visitor, "First", "otherCatch")
        expectQualified(visitor, "First", "after")
        expectQualified(visitor, "Second", "afterError")
    }

    @Test
    func unsupportedFunctionInitializerAndSubscriptParametersStillShadow() {
        let visitor = analyze("""
        let value: Item
        func run(_ value: () -> Void) { value.function() }
        struct Owner {
            init(_ value: (Int, Int)) { value.initializer() }
            subscript(_ value: () -> Void) -> Int { value.subscriptBody(); return 0 }
        }
        value.outside()
        """)
        #expect(visitor.unqualifiedMemberUsages.isSuperset(of: ["function", "initializer", "subscriptBody"]))
        expectQualified(visitor, "Item", "outside")
        for member in ["function", "initializer", "subscriptBody"] {
            #expect(!visitor.qualifiedMemberUsages.contains(QualifiedUsage(typeName: "Item", memberName: member)))
        }
    }

    @Test
    func subscriptParametersAndAccessorValuesUseTheirDeclaredTypes() {
        let visitor = analyze("""
        struct Owner {
            subscript(_ `repeat`: Key) -> Item {
                get { `repeat`.keyMember(); return .init() }
                set(`new`) { `repeat`.setKey(); `new`.valueMember(); _ = `new`[0] }
            }
            var value: Item {
                get { return .init() }
                set { newValue.implicitValue() }
            }
            var observed: Item {
                willSet { newValue.willChange() }
                didSet { oldValue.didChange() }
            }
        }
        """)
        expectQualified(visitor, "Key", "keyMember")
        expectQualified(visitor, "Key", "setKey")
        for member in ["valueMember", "implicitValue", "willChange", "didChange"] {
            expectQualified(visitor, "Item", member)
        }
        #expect(visitor.callUsages == [
            CallUsage(kind: .initializer, receiverType: "Item", enclosingTypePath: ["Owner"]),
            CallUsage(kind: .subscript, receiverType: "Item", argumentLabels: ["_"], enclosingTypePath: ["Owner"])
        ])
        #expect(visitor.bareIdentifierUsages.contains("new"))
        #expect(!visitor.bareIdentifierUsages.contains("`new`"))
    }

    @Test
    func settersAndObserversDoNotInheritGetterResultContext() {
        let visitor = analyze("""
        struct Owner {
            var value: Item {
                get { .init(getter: 1) }
                set { newValue.setterMember() }
            }
            var observed: Item {
                willSet { newValue.willChange() }
                didSet { oldValue.didChange() }
            }
            var returned: Item {
                get { return .init(returned: 1) }
                set { return notify() }
            }
        }
        """)
        #expect(visitor.callUsages == [
            CallUsage(kind: .initializer, receiverType: "Item", argumentLabels: ["getter"], enclosingTypePath: ["Owner"]),
            CallUsage(kind: .initializer, receiverType: "Item", argumentLabels: ["returned"], enclosingTypePath: ["Owner"])
        ])
        for member in ["setterMember", "willChange", "didChange"] {
            expectQualified(visitor, "Item", member)
        }
        #expect(visitor.bareIdentifierUsages.contains("notify"))
        #expect(!visitor.unqualifiedMemberUsages.contains("init"))
    }

    @Test
    func accessorAndSubscriptParameterDeclarationsAreNotReads() {
        let visitor = analyze("""
        struct Owner {
            var value: Item { get { .init() } set(unusedSetter) {} }
            subscript(_ unusedIndex: Int) -> Item { get { .init() } set(unusedValue) {} }
        }
        """)
        for name in ["unusedSetter", "unusedIndex", "unusedValue", "newValue", "oldValue"] {
            #expect(!visitor.bareIdentifierUsages.contains(name))
        }
    }

    @Test
    func unknownAccessorValuesStopOuterReceiverLookup() {
        let visitor = analyze("""
        let newValue: Item
        struct Owner {
            var value: () -> Void { get { fatalError() } set { newValue.work(); _ = newValue[0] } }
        }
        newValue.after()
        """)
        #expect(visitor.unqualifiedMemberUsages.contains("work"))
        expectQualified(visitor, "Item", "after")
        #expect(visitor.callUsages.contains(CallUsage(
            kind: .subscript, argumentLabels: ["_"], enclosingTypePath: ["Owner"]
        )))
        #expect(!visitor.qualifiedMemberUsages.contains(QualifiedUsage(typeName: "Item", memberName: "work")))
    }

    @Test
    func implicitGetterLocalsAreIsolated() {
        let visitor = analyze("""
        struct Owner {
            var value: Item
            var first: Int { let value = unknown(); value.inside(); return 0 }
            var second: Int { value.outside(); return 0 }
        }
        """)
        #expect(visitor.unqualifiedMemberUsages.contains("inside"))
        expectQualified(visitor, "Item", "outside")
    }

    @Test
    func closureParametersIncludingUnknownTypesHaveTheirOwnScope() {
        let visitor = analyze("""
        func run(_ value: First) {
            let typed = { (value: Second) in value.typed() }
            let simple = { value in value.simple() }
            let unsupported = { (value: () -> Void) in value.unsupported() }
            value.after()
        }
        """)
        expectQualified(visitor, "Second", "typed")
        #expect(visitor.unqualifiedMemberUsages.isSuperset(of: ["simple", "unsupported"]))
        expectQualified(visitor, "First", "after")
        #expect(!visitor.qualifiedMemberUsages.contains(QualifiedUsage(typeName: "First", memberName: "simple")))
    }

    @Test
    func closureCapturesReadBeforeBindingAndKeepInferredTypes() {
        let visitor = analyze("""
        func run(_ value: Item) {
            let first = { [value] in value.first() }
            let second = { [value = value] in value.second() }
            let third = { [value = value.make()] in value.unknown() }
            value.after()
        }
        """)
        #expect(visitor.bareIdentifierUsages.contains("value"))
        for member in ["first", "second", "make", "after"] {
            expectQualified(visitor, "Item", member)
        }
        #expect(visitor.unqualifiedMemberUsages.contains("unknown"))
        #expect(!visitor.bareIdentifierUsages.contains("first"))
    }

    @Test
    func unsupportedAnnotationsDoNotFallBackToInitializerOrOuterTypes() {
        let visitor = analyze("""
        struct Item {}
        func run(_ value: Item) {
            do { let value: (Int, Int) = Item(); value.inside(); _ = value[0] }
            value.after()
        }
        """)
        #expect(visitor.unqualifiedMemberUsages.contains("inside"))
        #expect(visitor.callUsages.contains(CallUsage(kind: .subscript, argumentLabels: ["_"])))
        expectQualified(visitor, "Item", "after")
    }

    @Test
    func escapedOwnersTypesParametersAndLabelsAreNormalized() {
        let visitor = analyze("""
        struct `Outer` {
            struct `Item` {}
            func run(_ `repeat`: `Item`) {
                _ = `Item`(`default`: 1)
                _ = `repeat`[`case`: 0]
                `repeat`.`work`()
            }
        }
        """)
        #expect(visitor.callUsages == [
            CallUsage(kind: .initializer, receiverType: "Outer.Item", argumentLabels: ["default"],
                      enclosingTypePath: ["Outer"]),
            CallUsage(kind: .subscript, receiverType: "Outer.Item", argumentLabels: ["case"],
                      enclosingTypePath: ["Outer"])
        ])
        expectQualified(visitor, "Outer.Item", "work")
    }

    @Test
    func extensionCallsUseFullEnclosingOwnerPaths() {
        let visitor = analyze("""
        extension Outer.Inner {
            func run(_ value: Item) { _ = Item(); _ = value[0]; _ = self[1] }
        }
        """, knownTypes: ["Outer.Inner", "Outer.Inner.Item"])
        #expect(visitor.callUsages == [
            CallUsage(kind: .initializer, receiverType: "Outer.Inner.Item", enclosingTypePath: ["Outer", "Inner"]),
            CallUsage(kind: .subscript, receiverType: "Outer.Inner.Item", argumentLabels: ["_"],
                      enclosingTypePath: ["Outer", "Inner"]),
            CallUsage(kind: .subscript, receiverType: "Outer.Inner", argumentLabels: ["_"],
                      enclosingTypePath: ["Outer", "Inner"])
        ])
    }

    @Test(arguments: ["function", "initializer", "subscript"])
    func parameterDefaultsResolveOuterBindingsBeforeInstallingAnyParameters(kind: String) {
        let declaration: String
        switch kind {
        case "function":
            declaration = "func run(_ maker: Wrong.Type = Wrong.self, _ value: Live = maker.init(seed: 1)) { _ = maker.init(body: 1) }"
        case "initializer":
            declaration = "struct Owner { init(_ maker: Wrong.Type = Wrong.self, _ value: Live = maker.init(seed: 1)) { _ = maker.init(body: 1) } }"
        default:
            declaration = "struct Owner { subscript(_ maker: Wrong.Type = Wrong.self, _ value: Live = maker.init(seed: 1)) -> Int { _ = maker.init(body: 1); return 0 } }"
        }
        let owner = kind == "function" ? [] : ["Owner"]
        let visitor = analyze("""
        struct Live {}
        struct Wrong {}
        let maker: Live.Type
        \(declaration)
        """)
        #expect(visitor.callUsages == [
            CallUsage(kind: .initializer, receiverType: "Live", argumentLabels: ["seed"], enclosingTypePath: owner),
            CallUsage(kind: .initializer, receiverType: "Wrong", argumentLabels: ["body"], enclosingTypePath: owner)
        ])
        #expect(!visitor.qualifiedMemberUsages.contains { $0.memberName == "init" })
    }

    @Test
    func unsupportedParameterBindingsAreInstalledOnlyAfterAllDefaults() {
        let visitor = analyze("""
        struct Live {}
        let maker: Live.Type
        func run(_ maker: () -> Void = {}, _ value: Live = maker.init(seed: 1)) {
            _ = maker.init(body: 1)
        }
        """)
        #expect(visitor.callUsages == [
            CallUsage(kind: .initializer, receiverType: "Live", argumentLabels: ["seed"]),
            CallUsage(kind: .initializer, argumentLabels: ["body"])
        ])
    }

    @Test
    func closureCaptureInitializersAllResolveTheEnclosingScope() {
        let visitor = analyze("""
        func run(_ value: A, _ other: B) {
            let closure = { [value = other, copy = value] in
                value.first()
                copy.second()
                _ = value[0]
                _ = copy[index: 0]
            }
            value.after()
        }
        """)
        expectQualified(visitor, "B", "first")
        expectQualified(visitor, "A", "second")
        expectQualified(visitor, "A", "after")
        #expect(!visitor.qualifiedMemberUsages.contains(QualifiedUsage(typeName: "B", memberName: "second")))
        #expect(visitor.callUsages == [
            CallUsage(kind: .subscript, receiverType: "B", argumentLabels: ["_"]),
            CallUsage(kind: .subscript, receiverType: "A", argumentLabels: ["index"])
        ])
    }

    @Test
    func closureCapturesDoNotShadowTypesWhileEvaluatingLaterCaptures() {
        let visitor = analyze("""
        struct Token {}
        let closure = { [Token = unknown(), made = Token(seed: 1)] in
            Token()
            _ = made[0]
        }
        """)
        #expect(visitor.callUsages == [
            CallUsage(kind: .initializer, receiverType: "Token", argumentLabels: ["seed"]),
            CallUsage(kind: .subscript, receiverType: "Token", argumentLabels: ["_"])
        ])
        #expect(visitor.bareIdentifierUsages.contains("unknown"))
    }

    @Test
    func switchAlternativePatternsDoNotSeePreviousAlternativeBindings() {
        let visitor = analyze("""
        struct Token {}
        func run(_ input: Int) {
            switch input {
            case let Token where Token.first(), Token(used: 1) where condition():
                Token.body()
            default: break
            }
        }
        """)
        #expect(visitor.callUsages == [CallUsage(kind: .initializer, receiverType: "Token", argumentLabels: ["used"])])
        #expect(visitor.unqualifiedMemberUsages.contains("first"))
        expectQualified(visitor, "Token", "body")
        #expect(!visitor.qualifiedMemberUsages.contains(QualifiedUsage(typeName: "Token", memberName: "first")))
    }

    @Test
    func switchAlternativesHaveIndependentWhereBindingsAndOnlyCommonBodyBindings() {
        let visitor = analyze("""
        func run(_ first: A, _ second: B, _ input: Any) {
            switch input {
            case .one(let first) where first.firstWhere() && second.outerSecond(),
                 .two(let second) where second.secondWhere() && first.outerFirst():
                first.firstBody()
                second.secondBody()
            default: break
            }
        }
        """)
        #expect(visitor.unqualifiedMemberUsages.isSuperset(of: ["firstWhere", "secondWhere"]))
        expectQualified(visitor, "B", "outerSecond")
        expectQualified(visitor, "A", "outerFirst")
        expectQualified(visitor, "A", "firstBody")
        expectQualified(visitor, "B", "secondBody")
    }

    @Test
    func switchCommonBindingsRemainUnknownInTheBody() {
        let visitor = analyze("""
        func run(_ value: Outer, _ input: Any) {
            switch input {
            case .one(let value) where value.first(), .two(let value) where value.second():
                value.body()
                _ = value[0]
            default: break
            }
            value.after()
        }
        """)
        #expect(visitor.unqualifiedMemberUsages.isSuperset(of: ["first", "second", "body"]))
        expectQualified(visitor, "Outer", "after")
        #expect(visitor.callUsages == [CallUsage(kind: .subscript, argumentLabels: ["_"])])
    }

    @Test
    func catchWhereWithoutAPatternIntroducesImplicitErrorBeforeItsCondition() {
        let visitor = analyze("""
        func run(_ error: Wrong) {
            do { try action() }
            catch where error.helper() { error.body(); _ = error[index: 0] }
            error.after()
        }
        """)
        #expect(visitor.unqualifiedMemberUsages.isSuperset(of: ["helper", "body"]))
        expectQualified(visitor, "Wrong", "after")
        #expect(visitor.callUsages == [CallUsage(kind: .subscript, argumentLabels: ["index"])])
        #expect(!visitor.qualifiedMemberUsages.contains(QualifiedUsage(typeName: "Wrong", memberName: "helper")))
    }

    @Test
    func expressionPatternClosuresUseOrdinaryTraversalAndDoNotLeakBindings() {
        let visitor = analyze("""
        struct B {}
        func run(_ value: A, _ input: Int) {
            switch input {
            case evaluate({ let value = B(); return value.probe() }):
                value.afterPattern()
                _ = value[0]
            default: break
            }
            value.afterSwitch()
        }
        """)
        expectQualified(visitor, "B", "probe")
        expectQualified(visitor, "A", "afterPattern")
        expectQualified(visitor, "A", "afterSwitch")
        #expect(visitor.callUsages == [
            CallUsage(kind: .initializer, receiverType: "B"),
            CallUsage(kind: .subscript, receiverType: "A", argumentLabels: ["_"])
        ])
        #expect(visitor.bareIdentifierUsages.contains("evaluate"))
        #expect(!visitor.bareIdentifierUsages.contains("probe"))
    }

    @Test
    func expressionPatternClosuresKeepParameterTypesAndCaptureScopes() {
        let visitor = analyze("""
        func run(_ value: A, _ other: B, _ input: Int) {
            switch input {
            case evaluate({ [value = other, copy = value] in value.first(); copy.second(); return 0 }):
                value.afterCapture()
            case evaluate({ (value: B) in value.typed(); return 0 }):
                value.afterParameter()
            default: break
            }
        }
        """)
        expectQualified(visitor, "B", "first")
        expectQualified(visitor, "A", "second")
        expectQualified(visitor, "B", "typed")
        expectQualified(visitor, "A", "afterCapture")
        expectQualified(visitor, "A", "afterParameter")
    }

    @Test
    func enumCaseCalleesAreUsagesNotPatternBindingsOrBareReads() {
        let visitor = analyze("""
        func run(_ ready: Maker, _ input: Any) {
            if case let State.ready(value) = input { ready.work() }
        }
        """, knownTypes: ["State"])
        expectQualified(visitor, "Maker", "work")
        #expect(!visitor.bareIdentifierUsages.contains("value"))
        #expect(visitor.qualifiedMemberUsages.contains(QualifiedUsage(typeName: "State", memberName: "ready")))
    }

    @Test(arguments: ["Owner", "Child", "Alias", "Outer.Inner"])
    func injectedPropertyNamesShadowGlobalsEvenWithoutValueTypeMetadata(owner: String) {
        let properties = [owner: [PropertyInfo(name: "value", line: 1, filePath: "Other.swift", typeName: "Base")]]
        let visitor = analyze("""
        let value: Wrong
        extension \(owner) {
            func run() {
                value.work()
                _ = value[index: 0]
                _ = self.value[explicit: 0]
                if let value { value.unwrapped() }
            }
        }
        value.after()
        """, knownTypes: [owner], typeProperties: properties)
        let path = owner.split(separator: ".").map(String.init)
        #expect(visitor.unqualifiedMemberUsages.isSuperset(of: ["work", "unwrapped"]))
        expectQualified(visitor, "Wrong", "after")
        #expect(visitor.callUsages == [
            CallUsage(kind: .subscript, argumentLabels: ["index"], enclosingTypePath: path),
            CallUsage(kind: .subscript, argumentLabels: ["explicit"], enclosingTypePath: path)
        ])
        #expect(!visitor.qualifiedMemberUsages.contains(QualifiedUsage(typeName: "Wrong", memberName: "work")))
    }

    @Test
    func locallyTypedPropertiesOverrideInjectedUnknownBindings() {
        let visitor = analyze("""
        let value: Wrong
        extension Owner {
            var value: Live { .init() }
            func run() { value.work(); _ = value[0] }
        }
        """, typeProperties: ["Owner": [PropertyInfo(name: "value", line: 1, filePath: "Other.swift", typeName: "Owner")]])
        expectQualified(visitor, "Live", "work")
        #expect(visitor.callUsages == [
            CallUsage(kind: .initializer, receiverType: "Live", enclosingTypePath: ["Owner"]),
            CallUsage(kind: .subscript, receiverType: "Live", argumentLabels: ["_"], enclosingTypePath: ["Owner"])
        ])
    }

    @Test
    func injectedOwnerAndPropertyNamesAreNormalized() {
        let visitor = analyze("""
        let `value`: Wrong
        extension `Outer`.`Owner` { func run() { `value`.work(); _ = `value`[0] } }
        """, typeProperties: ["`Outer`.`Owner`": [PropertyInfo(name: "`value`", line: 1, filePath: "Other.swift", typeName: "Outer.Owner")]])
        #expect(visitor.unqualifiedMemberUsages.contains("work"))
        #expect(visitor.callUsages == [CallUsage(kind: .subscript, argumentLabels: ["_"], enclosingTypePath: ["Outer", "Owner"])])
    }

    @Test
    func sameFileExtensionPropertyNamesAreKnownBeforeTheirDeclaration() {
        let visitor = analyze("""
        let value: Wrong
        extension Owner { func run() { value.work(); _ = value[0] } }
        struct Owner { var value: Live }
        """)
        #expect(visitor.unqualifiedMemberUsages.contains("work"))
        #expect(!visitor.qualifiedMemberUsages.contains(QualifiedUsage(typeName: "Wrong", memberName: "work")))
        #expect(visitor.callUsages == [CallUsage(kind: .subscript, argumentLabels: ["_"], enclosingTypePath: ["Owner"])])
    }

    @Test
    func injectedExtensionGenericParametersHideUnrelatedNominalTypes() {
        let visitor = analyze("""
        extension Box where T: P {
            func run(_ type: T.Type, _ value: T) {
                _ = T(first: 1)
                _ = type.init(second: 1)
                _ = value[0]
            }
        }
        """, knownTypes: ["Box", "T", "P"], typeGenericParameters: ["Box": ["T"]])
        #expect(!visitor.referencedTypeNames.contains("T"))
        #expect(visitor.referencedTypeNames.contains("P"))
        #expect(visitor.callUsages == [
            CallUsage(kind: .initializer, argumentLabels: ["first"], enclosingTypePath: ["Box"]),
            CallUsage(kind: .initializer, argumentLabels: ["second"], enclosingTypePath: ["Box"]),
            CallUsage(kind: .subscript, argumentLabels: ["_"], enclosingTypePath: ["Box"])
        ])
    }

    @Test(arguments: ["struct", "class", "enum", "actor"])
    func sameFileGenericParametersAreCollectedBeforeSeparateExtensions(kind: String) {
        let visitor = analyze("""
        extension Box { func run(_ type: T.Type) { _ = T(first: 1); _ = type.init(second: 1) } }
        \(kind) Box<T> {}
        struct T {}
        """)
        #expect(!visitor.referencedTypeNames.contains("T"))
        #expect(visitor.callUsages == [
            CallUsage(kind: .initializer, argumentLabels: ["first"], enclosingTypePath: ["Box"]),
            CallUsage(kind: .initializer, argumentLabels: ["second"], enclosingTypePath: ["Box"])
        ])
    }

    @Test
    func nestedExtensionGenericScopesIncludeOwnerPrefixesAndNormalizeEscaping() {
        let visitor = analyze("""
        extension Outer.Box {
            func run(_ first: T.Type, _ second: U.Type, _ value: T.Associated<Payload>) {
                _ = first.init(t: 1)
                _ = second.init(u: 1)
                _ = value[0]
            }
        }
        """, knownTypes: ["T", "U", "Payload"],
            typeGenericParameters: ["`Outer`": ["`T`"], "`Outer`.`Box`": ["`U`"]])
        #expect(!visitor.referencedTypeNames.contains("T"))
        #expect(!visitor.referencedTypeNames.contains("U"))
        #expect(visitor.referencedTypeNames.contains("Payload"))
        #expect(visitor.callUsages == [
            CallUsage(kind: .initializer, argumentLabels: ["t"], enclosingTypePath: ["Outer", "Box"]),
            CallUsage(kind: .initializer, argumentLabels: ["u"], enclosingTypePath: ["Outer", "Box"]),
            CallUsage(kind: .subscript, argumentLabels: ["_"], enclosingTypePath: ["Outer", "Box"])
        ])
    }

    @Test(arguments: ["static", "class"])
    func classSelfConstructorsAndCopiedMetatypesHaveDynamicReceivers(modifier: String) {
        let visitor = analyze("""
        class Base {
            required init(direct: Int) {}
            required init(explicit: Int) {}
            required init(staticSelf: Int) {}
            required init(copied: Int) {}
            init(concrete: Int) {}
            \(modifier) func run() {
                _ = Self(direct: 1)
                _ = Self.init(explicit: 1)
                _ = self.init(staticSelf: 1)
                let type = Self
                _ = type.init(copied: 1)
                _ = Base(concrete: 1)
            }
        }
        """)
        #expect(visitor.callUsages == Set(["direct", "explicit", "staticSelf", "copied"].map {
            dynamicInitializerUsage("Base", labels: [$0], owner: ["Base"])
        } + [CallUsage(kind: .initializer, receiverType: "Base", argumentLabels: ["concrete"], enclosingTypePath: ["Base"])]))
        #expect(!visitor.qualifiedMemberUsages.contains { $0.memberName == "init" })
    }

    @Test
    func instanceClassMethodsStillUseDynamicUppercaseSelf() {
        let visitor = analyze("""
        class Base { func run() { _ = Self(value: 1); _ = Self.init(other: 1) } }
        """)
        #expect(visitor.callUsages == Set(["value", "other"].map {
            dynamicInitializerUsage("Base", labels: [$0], owner: ["Base"])
        }))
    }

    @Test
    func contextualSelfAndStaticAccessorSelfKeepDynamicReceiverMetadata() {
        let visitor = analyze("""
        class Base {
            class func make() -> Self { return .init(contextual: 1) }
            static var value: Self { self.init(accessor: 1) }
        }
        """)
        #expect(visitor.callUsages == Set(["contextual", "accessor"].map {
            dynamicInitializerUsage("Base", labels: [$0], owner: ["Base"])
        }))
    }

    @Test
    func staticSelfCapturedByClosuresAndLocalFunctionsRemainsDynamic() {
        let visitor = analyze("""
        class Base {
            static func run() {
                let closure = { [type = Self] in _ = type.init(capture: 1); _ = self.init(closure: 1) }
                func nested() { _ = self.init(localFunction: 1) }
            }
        }
        """)
        #expect(visitor.callUsages == Set(["capture", "closure", "localFunction"].map {
            dynamicInitializerUsage("Base", labels: [$0], owner: ["Base"])
        }))
    }

    @Test
    func valueTypeSelfDoesNotHaveDynamicClassReceiverMetadata() {
        let visitor = analyze("""
        extension Value { static func run() { _ = Self(value: 1); _ = self.init(value: 2) } }
        struct Value { init(value: Int) {} }
        """)
        #expect(visitor.callUsages == [CallUsage(kind: .initializer, receiverType: "Value", argumentLabels: ["value"],
                                               enclosingTypePath: ["Value"])])
    }

    @Test
    func crossFileClassExtensionSelfIsConservativelyDynamic() {
        let visitor = analyze("""
        extension Outer.Base { static func run() { _ = Self(value: 1); _ = self.init(other: 1) } }
        """, knownTypes: ["Outer.Base"])
        #expect(visitor.callUsages == Set(["value", "other"].map {
            dynamicInitializerUsage("Outer.Base", labels: [$0], owner: ["Outer", "Base"])
        }))
    }

    private func dynamicInitializerUsage(_ receiver: String, labels: [String], owner: [String]) -> CallUsage {
        var usage = CallUsage(kind: .initializer, receiverType: receiver, argumentLabels: labels, enclosingTypePath: owner)
        usage.isDynamicReceiver = true
        return usage
    }

    private func analyze(_ source: String, knownTypes: Set<String> = [], typeProperties: [String: [PropertyInfo]] = [:],
                         typeGenericParameters: [String: Set<String>] = [:]) -> UsageVisitor {
        let visitor = UsageVisitor(knownTypeNames: knownTypes, typeProperties: typeProperties,
                                   typeGenericParameters: typeGenericParameters)
        visitor.walk(Parser.parse(source: source))
        return visitor
    }

    private func expectQualified(_ visitor: UsageVisitor, _ type: String, _ member: String,
                                 sourceLocation: Testing.SourceLocation = #_sourceLocation) {
        #expect(visitor.qualifiedMemberUsages.contains(QualifiedUsage(typeName: type, memberName: member)),
                sourceLocation: sourceLocation)
    }
}

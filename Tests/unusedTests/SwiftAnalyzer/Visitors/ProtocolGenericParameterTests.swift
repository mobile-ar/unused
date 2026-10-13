import SwiftParser
import Testing

@testable import unused

struct ProtocolGenericParameterTests {
    @Test
    func emptySourceHasNoTypeGenericParameters() {
        #expect(collect("").typeGenericParameters.isEmpty)
    }

    @Test(arguments: ["class", "struct", "enum", "actor"])
    func collectsOwnGenericNamesIncludingConstrainedParametersAndPacks(kind: String) {
        let result = collect("""
            \(kind) Owner<Element: Collection, Key: Hashable, each Rest>
            where Element.Element == Key {}
            """)

        #expect(result.typeGenericParameters == ["Owner": ["Element", "Key", "Rest"]])
        #expect(result.typeKinds["Owner"] == kind)
    }

    @Test
    func nestedNominalTypesKeepOnlyTheirOwnNamesAndActorsParticipateInQualifiedPaths() {
        let result = collect("""
            class Outer<OuterElement> {
                struct Middle<MiddleElement> {
                    enum Inner<InnerElement> {
                        actor Worker<WorkerElement> {
                            struct Leaf<LeafElement> {}
                            struct Plain {}
                        }
                    }
                }
            }
            """)

        #expect(result.typeGenericParameters["Outer"] == ["OuterElement"])
        #expect(result.typeGenericParameters["Outer.Middle"] == ["MiddleElement"])
        #expect(result.typeGenericParameters["Outer.Middle.Inner"] == ["InnerElement"])
        #expect(result.typeGenericParameters["Outer.Middle.Inner.Worker"] == ["WorkerElement"])
        #expect(result.typeGenericParameters["Outer.Middle.Inner.Worker.Leaf"] == ["LeafElement"])
        #expect((result.typeGenericParameters["Outer.Middle.Inner.Worker.Plain"] ?? []).isEmpty)
        #expect(result.typeKinds["Outer.Middle.Inner.Worker"] == "actor")
        #expect(result.typeGenericParameters["Worker"] == nil)
        #expect(result.typeGenericParameters["Leaf"] == nil)
    }

    @Test
    func normalizesEscapedOwnerPathsAndGenericParameterNames() {
        let result = collect("""
            struct `class`<`where`> {
                actor `actor`<`repeat`> {
                    enum `case`<`switch`> {
                        class `protocol`<`associatedtype`> {}
                    }
                }
            }
            """)

        #expect(result.typeGenericParameters == [
            "class": ["where"],
            "class.actor": ["repeat"],
            "class.actor.case": ["switch"],
            "class.actor.case.protocol": ["associatedtype"]
        ])
    }

    @Test(arguments: ["class", "struct", "enum", "actor"])
    func nongenericTypesDoNotAcquireEnclosingOrMethodGenericNames(kind: String) {
        let result = collect("""
            struct Outer<OuterElement> {
                \(kind) Plain {
                    func work<MethodElement>(_ value: MethodElement) {}
                }
            }
            \(kind) TopLevel {}
            """)

        #expect(result.typeGenericParameters["Outer"] == ["OuterElement"])
        #expect((result.typeGenericParameters["Outer.Plain"] ?? []).isEmpty)
        #expect((result.typeGenericParameters["TopLevel"] ?? []).isEmpty)
        #expect(result.typeKinds["Outer.Plain"] == kind)
        #expect(result.typeKinds["TopLevel"] == kind)
    }

    @Test
    func collectsNestedExtensionDeclarationsWithoutErasingOwnerParametersOrAddingConstraints() {
        let declaration = "struct Box<Element> {}"
        let extensionSource = """
            extension Box where Element: Collection {
                actor Worker<WorkerElement> {}
                struct Plain {}
                func work<MethodElement>(_ value: MethodElement) {}
            }
            extension Box.Worker where WorkerElement: Hashable {
                enum Choice<ChoiceElement> {}
            }
            """
        let before = collect(extensionSource + "\n" + declaration)
        let after = collect(declaration + "\n" + extensionSource)

        #expect(before.typeGenericParameters == after.typeGenericParameters)
        #expect(before.typeGenericParameters["Box"] == ["Element"])
        #expect(before.typeGenericParameters["Box.Worker"] == ["WorkerElement"])
        #expect(before.typeGenericParameters["Box.Worker.Choice"] == ["ChoiceElement"])
        #expect((before.typeGenericParameters["Box.Plain"] ?? []).isEmpty)
        #expect(before.typeGenericParameters.values.allSatisfy { $0.isDisjoint(with: ["Collection", "Hashable", "MethodElement"]) })
    }

    @Test
    func superclassGenericNamesAndSpecializationArgumentsAreNotSubclassParameters() {
        let result = collect("""
            class Base<BaseElement> {}
            class Child<ChildElement>: Base<ChildElement> {}
            class Concrete: Base<Int> {}
            """)

        #expect(result.typeGenericParameters["Base"] == ["BaseElement"])
        #expect(result.typeGenericParameters["Child"] == ["ChildElement"])
        #expect((result.typeGenericParameters["Concrete"] ?? []).isEmpty)
        #expect(result.typeInheritance["Child"] == ["Base"])
        #expect(result.typeInheritance["Concrete"] == ["Base"])
    }

    @Test
    func excludesAssociatedTypesAndGenericsBelongingToFunctionsAliasesInitializersAndSubscripts() {
        let result = collect("""
            protocol Container<Element> {
                associatedtype Element
                func transform<MethodElement>(_ value: MethodElement) -> MethodElement
            }
            struct Owner<OwnElement> {
                typealias Alias<AliasElement> = Array<AliasElement>
                init<InitialElement>(_ value: InitialElement) {}
                func work<MethodElement>(_ value: MethodElement) {}
                subscript<IndexElement>(_ index: IndexElement) -> OwnElement { fatalError() }
            }
            typealias GlobalAlias<AliasElement> = Array<AliasElement>
            func standalone<GlobalElement>(_ value: GlobalElement) {}
            """)

        #expect(result.typeGenericParameters.filter { !$0.value.isEmpty } == ["Owner": ["OwnElement"]])
        #expect((result.typeGenericParameters["Container"] ?? []).isEmpty)
        #expect(result.typeGenericParameters["Owner.Alias"] == nil)
        #expect(result.typeGenericParameters["GlobalAlias"] == nil)
        #expect(result.typeGenericParameters["standalone"] == nil)
    }

    @Test
    func sameBasenameTypesInDifferentNamespacesKeepSeparateGenericNames() {
        let result = collect("""
            struct First<FirstElement> {
                actor Worker<FirstWorkerElement> {}
            }
            struct Second<SecondElement> {
                actor Worker<SecondWorkerElement> {}
            }
            actor Worker<TopLevelElement> {}
            """)

        #expect(result.typeGenericParameters == [
            "First": ["FirstElement"], "First.Worker": ["FirstWorkerElement"],
            "Second": ["SecondElement"], "Second.Worker": ["SecondWorkerElement"],
            "Worker": ["TopLevelElement"]
        ])
    }

    @Test
    func mergesOwnGenericNamesAcrossConditionalDeclarations() {
        let result = collect("""
            #if FEATURE
            struct Box<FirstElement> {}
            #else
            struct Box<SecondElement> {}
            #endif
            """)

        #expect(result.typeGenericParameters == ["Box": ["FirstElement", "SecondElement"]])
    }

    private func collect(_ source: String) -> ProtocolVisitorResult {
        let sourceFile = Parser.parse(source: source)
        #expect(!sourceFile.hasError, "Generic parameter fixtures must parse without errors")
        let visitor = ProtocolVisitor()
        visitor.walk(sourceFile)
        return visitor.result
    }
}

import SwiftParser
import Testing

@testable import unused

struct ReferenceBindingIndexTests {
    @Test
    func emptyGraphAndInventoriesProduceEmptyDictionaries() {
        let resolver = ExplicitReferenceResolver(declarations: [])

        let index = ReferenceBindingIndex.merging(
            typeProperties: [:], typeGenericParameters: [:], ownerResolver: resolver.ownerResolver
        )

        #expect(index.typeProperties.isEmpty)
        #expect(index.typeGenericParameters.isEmpty)
    }

    @Test
    func includesGraphOwnersAndOwnersKnownOnlyToEitherInventory() {
        let property = PropertyInfo(name: "value", line: 3, filePath: "PropertyOnly.swift", typeName: "PropertyOnly")
        let resolver = ExplicitReferenceResolver(declarations: [], typeKinds: ["Empty": "struct"])

        let index = ReferenceBindingIndex.merging(
            typeProperties: ["PropertyOnly": [property]],
            typeGenericParameters: ["GenericOnly": ["Element"]], ownerResolver: resolver.ownerResolver
        )

        #expect(index.typeProperties == ["Empty": [], "PropertyOnly": [property], "GenericOnly": []])
        #expect(index.typeGenericParameters == ["Empty": [], "PropertyOnly": [], "GenericOnly": ["Element"]])
    }

    @Test
    func expandsTransitiveSuperclassPropertiesWithoutRewritingTheirIdentities() throws {
        let root = PropertyInfo(name: "root", line: 4, filePath: "Root.swift", typeName: "Root", attributes: ["Wrapper"])
        let middle = PropertyInfo(name: "middle", line: 8, filePath: "Middle.swift", typeName: "Middle")
        let leaf = PropertyInfo(name: "leaf", line: 12, filePath: "Leaf.swift", typeName: "Leaf")
        let unrelated = PropertyInfo(name: "unrelated", line: 1, filePath: "Other.swift", typeName: "Other")
        let resolver = ExplicitReferenceResolver(
            declarations: [], typeInheritance: ["Leaf": ["Middle"], "Middle": ["Root"]],
            typeKinds: ["Root": "class", "Middle": "class", "Leaf": "class", "Other": "class"]
        )

        let index = ReferenceBindingIndex.merging(
            typeProperties: ["Root": [root], "Middle": [middle], "Leaf": [leaf], "Other": [unrelated]],
            typeGenericParameters: [:], ownerResolver: resolver.ownerResolver
        )

        #expect(index.typeProperties["Leaf"] == [leaf, middle, root])
        #expect(index.typeProperties["Middle"] == [middle, root])
        #expect(index.typeProperties["Root"] == [root])
        #expect(index.typeProperties["Other"] == [unrelated])
        let inherited = try #require(index.typeProperties["Leaf"]?.first { $0.name == "root" })
        #expect(inherited.filePath == root.filePath)
        #expect(inherited.line == root.line)
        #expect(inherited.typeName == root.typeName)
        #expect(inherited.attributes == root.attributes)
    }

    @Test
    func expandsProtocolExtensionProvidersThroughInheritedConformancesAndDiamondPaths() {
        let root = PropertyInfo(name: "root", line: 2, filePath: "Root+Defaults.swift", typeName: "Root")
        let left = PropertyInfo(name: "left", line: 3, filePath: "Left+Defaults.swift", typeName: "Left")
        let right = PropertyInfo(name: "right", line: 4, filePath: "Right+Defaults.swift", typeName: "Right")
        let unrelated = PropertyInfo(name: "unrelated", line: 5, filePath: "Other+Defaults.swift", typeName: "Other")
        let resolver = ExplicitReferenceResolver(
            declarations: [],
            protocolDefinitions: [
                "Root": ProtocolDefinition(name: "Root"),
                "Left": ProtocolDefinition(name: "Left", inheritedTypes: ["Root"]),
                "Right": ProtocolDefinition(name: "Right", inheritedTypes: ["Root"]),
                "Other": ProtocolDefinition(name: "Other")
            ],
            typeInheritance: ["Child": ["Base"], "Base": ["Left", "Right"]],
            typeKinds: ["Child": "class", "Base": "class"]
        )

        let index = ReferenceBindingIndex.merging(
            typeProperties: ["Root": [root], "Left": [left], "Right": [right], "Other": [unrelated]],
            typeGenericParameters: [:], ownerResolver: resolver.ownerResolver
        )

        #expect(index.typeProperties["Child"] == [left, right, root])
        #expect(index.typeProperties["Base"] == [left, right, root])
        #expect(index.typeProperties["Left"] == [left, root])
        #expect(index.typeProperties["Right"] == [right, root])
        #expect(index.typeProperties["Root"] == [root])
        #expect(index.typeProperties["Other"] == [unrelated])
    }

    @Test
    func canonicalizesAliasOwnedProvidersWithoutPromotingThemToSuperclasses() throws {
        let alias = PropertyInfo(name: "aliasValue", line: 7, filePath: "Alias+Properties.swift", typeName: "Alias", attributes: ["Wrapper"])
        let own = PropertyInfo(name: "ownValue", line: 8, filePath: "Worker.swift", typeName: "Worker")
        let inherited = PropertyInfo(name: "baseValue", line: 9, filePath: "Base.swift", typeName: "Base")
        let resolver = ExplicitReferenceResolver(
            declarations: [], typeInheritance: ["Worker": ["Base"]],
            typeKinds: ["Worker": "class", "Base": "class"],
            typeAliases: ["Alias": ["Intermediate"], "Intermediate": ["Worker"]]
        )

        let index = ReferenceBindingIndex.merging(
            typeProperties: ["Alias": [alias], "Worker": [own], "Base": [inherited]],
            typeGenericParameters: ["Worker": ["Element"], "Base": ["BaseElement"]],
            ownerResolver: resolver.ownerResolver
        )

        for owner in ["Alias", "Intermediate", "Worker"] {
            #expect(index.typeProperties[owner] == [alias, inherited, own])
            #expect(index.typeGenericParameters[owner] == ["Element"])
            let provider = try #require(index.typeProperties[owner]?.first { $0.name == "aliasValue" })
            #expect(provider.typeName == "Alias")
            #expect(provider.attributes == alias.attributes)
        }
        #expect(index.typeProperties["Base"] == [inherited])
        #expect(index.typeGenericParameters["Base"] == ["BaseElement"])
    }

    @Test
    func resolvesRelativeAliasAndInheritanceTargetsInTheirNamespace() {
        let local = PropertyInfo(name: "local", line: 1, filePath: "Local.swift", typeName: "Namespace.Base")
        let global = PropertyInfo(name: "global", line: 1, filePath: "Global.swift", typeName: "Base")
        let alias = PropertyInfo(name: "extra", line: 2, filePath: "Alias.swift", typeName: "Namespace.Alias")
        let resolver = ExplicitReferenceResolver(
            declarations: [], typeInheritance: ["Namespace.Worker": ["Base"]],
            typeKinds: ["Namespace": "enum", "Namespace.Worker": "class", "Namespace.Base": "class", "Base": "class"],
            typeAliases: ["Namespace.Alias": ["Worker"]]
        )

        let index = ReferenceBindingIndex.merging(
            typeProperties: ["Namespace.Base": [local], "Base": [global], "Namespace.Alias": [alias]],
            typeGenericParameters: [:], ownerResolver: resolver.ownerResolver
        )

        #expect(index.typeProperties["Namespace.Worker"] == [alias, local])
        #expect(index.typeProperties["Namespace.Alias"] == [alias, local])
        #expect(index.typeProperties["Namespace.Base"] == [local])
        #expect(index.typeProperties["Base"] == [global])
    }

    @Test
    func expandsNamespaceAliasesForNestedPropertiesAndEnclosingGenericParameters() {
        let property = PropertyInfo(name: "value", line: 6, filePath: "Alias+Nested.swift", typeName: "Alias.Inner")
        let resolver = ExplicitReferenceResolver(
            declarations: [], typeKinds: ["Outer": "struct", "Outer.Inner": "actor"],
            typeAliases: ["Alias": ["Outer"], "NestedAlias": ["Alias.Inner"]]
        )

        let index = ReferenceBindingIndex.merging(
            typeProperties: ["Alias.Inner": [property]],
            typeGenericParameters: ["Outer": ["Element"], "Outer.Inner": ["Value"]],
            ownerResolver: resolver.ownerResolver
        )

        for owner in ["Alias.Inner", "NestedAlias", "Outer.Inner"] {
            #expect(index.typeProperties[owner] == [property])
            #expect(index.typeGenericParameters[owner] == ["Element", "Value"])
        }
        #expect(index.typeProperties["Outer"] == [])
        #expect(index.typeProperties["Alias"] == [])
        #expect(index.typeGenericParameters["Alias"] == ["Element"])
    }

    @Test
    func retainsEveryPlausibleProviderForMultiTargetAliasesAndProtocolCompositions() {
        let first = PropertyInfo(name: "first", line: 1, filePath: "First.swift", typeName: "First")
        let second = PropertyInfo(name: "second", line: 1, filePath: "Second.swift", typeName: "Second")
        let shared = PropertyInfo(name: "shared", line: 2, filePath: "Both+Defaults.swift", typeName: "Both")
        let resolver = ExplicitReferenceResolver(
            declarations: [],
            protocolDefinitions: ["First": ProtocolDefinition(name: "First"), "Second": ProtocolDefinition(name: "Second")],
            typeInheritance: ["Worker": ["Both"]], typeKinds: ["Worker": "struct"],
            typeAliases: ["Both": ["First", "Second"]]
        )

        let index = ReferenceBindingIndex.merging(
            typeProperties: ["First": [first], "Second": [second], "Both": [shared]],
            typeGenericParameters: [:], ownerResolver: resolver.ownerResolver
        )

        #expect(index.typeProperties["Both"] == [first, second, shared])
        #expect(index.typeProperties["Worker"] == [first, second, shared])
        #expect(index.typeProperties["First"] == [first, shared])
        #expect(index.typeProperties["Second"] == [second, shared])
    }

    @Test
    func deduplicatesRepeatedIdentitiesButPreservesDistinctSameNamedProperties() throws {
        let first = PropertyInfo(name: "value", line: 2, filePath: "First.swift", typeName: "Owner", attributes: ["Wrapper"])
        let differentLine = PropertyInfo(name: "value", line: 3, filePath: "First.swift", typeName: "Owner")
        let differentFile = PropertyInfo(name: "value", line: 2, filePath: "Second.swift", typeName: "Owner")
        let differentOwner = PropertyInfo(name: "value", line: 2, filePath: "First.swift", typeName: "Alias")
        let resolver = ExplicitReferenceResolver(
            declarations: [], typeKinds: ["Owner": "struct"], typeAliases: ["Alias": ["Owner"]]
        )

        let index = ReferenceBindingIndex.merging(
            typeProperties: ["Owner": [first, differentLine, differentFile, first], "Alias": [first, differentOwner]],
            typeGenericParameters: [:], ownerResolver: resolver.ownerResolver
        )

        for owner in ["Owner", "Alias"] {
            let properties = try #require(index.typeProperties[owner])
            #expect(properties.count == 4)
            #expect(Set(properties) == [first, differentLine, differentFile, differentOwner])
            #expect(properties.first { $0 == first }?.attributes == first.attributes)
        }
    }

    @Test
    func sortsPropertyArraysByNameThenFileThenLineIndependentlyOfInputOrder() {
        let alpha = PropertyInfo(name: "alpha", line: 20, filePath: "Z.swift", typeName: "Owner")
        let early = PropertyInfo(name: "value", line: 2, filePath: "A.swift", typeName: "Owner")
        let late = PropertyInfo(name: "value", line: 8, filePath: "A.swift", typeName: "Owner")
        let otherFile = PropertyInfo(name: "value", line: 1, filePath: "Z.swift", typeName: "Owner")
        let resolver = ExplicitReferenceResolver(declarations: [], typeKinds: ["Owner": "struct"])
        let input = [otherFile, late, alpha, early]

        for properties in [input, Array(input.reversed())] {
            let index = ReferenceBindingIndex.merging(
                typeProperties: ["Owner": properties], typeGenericParameters: [:], ownerResolver: resolver.ownerResolver
            )

            #expect(index.typeProperties["Owner"] == [alpha, early, late, otherFile])
        }
    }

    @Test
    func mergesAllLexicalGenericScopesButNotSuperclassOrSiblingGenericSpellings() {
        let outerProperty = PropertyInfo(name: "outer", line: 1, filePath: "Outer.swift", typeName: "Outer")
        let baseProperty = PropertyInfo(name: "inherited", line: 2, filePath: "Base.swift", typeName: "Base")
        let resolver = ExplicitReferenceResolver(
            declarations: [], typeInheritance: ["Outer.Middle.Inner": ["Base<Payload>"]],
            typeKinds: [
                "Outer": "class", "Outer.Middle": "struct", "Outer.Middle.Inner": "class",
                "Outer.Middle.Plain": "enum", "Outer.Sibling": "actor", "Base": "class"
            ]
        )

        let index = ReferenceBindingIndex.merging(
            typeProperties: ["Outer": [outerProperty], "Base": [baseProperty]],
            typeGenericParameters: [
                "Outer": ["OuterElement", "Shared"], "Outer.Middle": ["MiddleElement", "Shared"],
                "Outer.Middle.Inner": ["InnerElement"], "Outer.Sibling": ["SiblingElement"],
                "Base": ["BaseElement"]
            ], ownerResolver: resolver.ownerResolver
        )

        #expect(index.typeGenericParameters["Outer"] == ["OuterElement", "Shared"])
        #expect(index.typeGenericParameters["Outer.Middle"] == ["OuterElement", "MiddleElement", "Shared"])
        #expect(index.typeGenericParameters["Outer.Middle.Inner"] == ["OuterElement", "MiddleElement", "InnerElement", "Shared"])
        #expect(index.typeGenericParameters["Outer.Middle.Plain"] == ["OuterElement", "MiddleElement", "Shared"])
        #expect(index.typeGenericParameters["Outer.Sibling"] == ["OuterElement", "SiblingElement", "Shared"])
        #expect(index.typeGenericParameters["Base"] == ["BaseElement"])
        #expect(index.typeProperties["Outer.Middle.Inner"] == [baseProperty])
        #expect(index.typeProperties["Outer.Middle.Plain"] == [])
    }

    @Test
    func inheritanceCyclesTerminateAndDoNotMergeGenericParameters() {
        let first = PropertyInfo(name: "first", line: 1, filePath: "First.swift", typeName: "First")
        let second = PropertyInfo(name: "second", line: 1, filePath: "Second.swift", typeName: "Second")
        let resolver = ExplicitReferenceResolver(
            declarations: [], typeInheritance: ["First": ["Second"], "Second": ["First"]],
            typeKinds: ["First": "class", "Second": "class"]
        )

        let index = ReferenceBindingIndex.merging(
            typeProperties: ["First": [first], "Second": [second]],
            typeGenericParameters: ["First": ["T"], "Second": ["U"]], ownerResolver: resolver.ownerResolver
        )

        #expect(index.typeProperties["First"] == [first, second])
        #expect(index.typeProperties["Second"] == [first, second])
        #expect(index.typeGenericParameters["First"] == ["T"])
        #expect(index.typeGenericParameters["Second"] == ["U"])
    }

    @Test(arguments: ["value", "self.value"])
    func derivedPropertyReadsAndWritesMustNotBindToSameNamedSuperclassProperty(reference: String) {
        let inherited = PropertyInfo(name: "value", line: 2, filePath: "ABase.swift", typeName: "Base")
        let own = PropertyInfo(name: "value", line: 2, filePath: "ZChild.swift", typeName: "Child")
        let resolver = ExplicitReferenceResolver(
            declarations: [], typeInheritance: ["Child": ["Base"]], typeKinds: ["Base": "class", "Child": "class"]
        )
        let index = ReferenceBindingIndex.merging(
            typeProperties: ["Base": [inherited], "Child": [own]],
            typeGenericParameters: [:], ownerResolver: resolver.ownerResolver
        )
        #expect(Set(index.typeProperties["Child"] ?? []) == [inherited, own])
        let sourceFile = Parser.parse(source: """
            class Child: Base {
                override var value: Int { get { 0 } set {} }
                func inspect() {
                    _ = \(reference)
                    \(reference) = 1
                }
            }
            """)
        #expect(!sourceFile.hasError)
        let visitor = WriteOnlyVariableVisitor(filePath: "ZChild.swift", typeProperties: index.typeProperties)
        visitor.walk(sourceFile)

        #expect(visitor.propertyReads == [own])
        #expect(visitor.propertyWrites == [own])
    }
}

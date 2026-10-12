import SwiftParser
import Testing

@testable import unused

struct SourceProtocolCollectionTests {
    private func collect(_ source: String) -> ProtocolVisitorResult {
        let visitor = ProtocolVisitor()
        visitor.walk(Parser.parse(source: source))
        return visitor.result
    }

    @Test
    func collectsConditionalRequirementsAndFullNestedNames() throws {
        let result = collect(
            """
            struct Outer {
                protocol `Protocol` {
                    associatedtype Element
                    func work(_ value: Int)
                    #if FEATURE
                    static var shared: String { get }
                    #else
                    subscript(index: Int) -> Element { get }
                    init(value: Int)
                    #endif
                }
            }
            protocol Other {
                func unrelated()
            }
            """)
        let definition = try #require(result.protocolDefinitions["Outer.Protocol"])
        #expect(definition.isComplete)
        #expect(
            definition.requirements.contains(
                MemberSignature(kind: .associatedType, name: "Element")))
        #expect(
            definition.requirements.contains(
                MemberSignature(
                    kind: .function, name: "work", parameterLabels: ["_"], parameterTypes: ["Int"]))
        )
        #expect(
            definition.requirements.contains(
                MemberSignature(
                    kind: .property, name: "shared", isStatic: true, resultType: "String")))
        #expect(
            definition.requirements.contains(
                MemberSignature(
                    kind: .subscript, name: "subscript", parameterLabels: ["_"],
                    parameterTypes: ["Int"], resultType: "Element")))
        #expect(
            definition.requirements.contains(
                MemberSignature(
                    kind: .initializer, name: "init", parameterLabels: ["value"],
                    parameterTypes: ["Int"])))
        #expect(
            result.protocolRequirements["Outer.Protocol"] == [
                "Element", "work", "shared", "subscript", "init",
            ])
        #expect(result.projectDefinedProtocols == ["Outer.Protocol", "Other"])
        #expect(result.protocolDefinitions["Other"]?.requirements.map(\.name) == ["unrelated"])
    }

    @Test
    func collectsAllTypeKindsSuperclassAndQualifiedExtensionConformances() {
        let result = collect(
            """
            import Foundation
            class Base<T> {}
            struct Outer {
                protocol `Protocol`: SDK.`Parent` {}
                class Child: Base<Int>, `Protocol` {}
                struct Value {}
                enum Choice {}
                actor Worker {}
            }
            extension Outer.Value: Outer.`Protocol`, SDK.External {}
            extension Outer.Choice: Outer.Protocol {}
            """)
        #expect(result.typeKinds["Base"] == "class")
        #expect(result.typeKinds["Outer"] == "struct")
        #expect(result.typeKinds["Outer.Protocol"] == "protocol")
        #expect(result.typeKinds["Outer.Child"] == "class")
        #expect(result.typeKinds["Outer.Value"] == "struct")
        #expect(result.typeKinds["Outer.Choice"] == "enum")
        #expect(result.typeKinds["Outer.Worker"] == "actor")
        #expect(result.typeInheritance["Outer.Child"] == ["Base", "Protocol"])
        #expect(result.typeInheritance["Outer.Value"] == ["Outer.Protocol", "SDK.External"])
        #expect(result.protocolInheritance["Outer.Protocol"] == ["SDK.Parent"])
        #expect(result.protocolDefinitions["Outer.Protocol"]?.inheritedTypes == ["SDK.Parent"])
        #expect(
            result.conformedProtocols.isSuperset(of: [
                "SDK.Parent", "Base", "Protocol", "Outer.Protocol", "SDK.External",
            ]))
        #expect(result.importedModules == ["Foundation"])
    }

    @Test
    func collectsAliasesAndCompositionTargetsInOwningNamespace() {
        let result = collect(
            """
            protocol P {}
            protocol Q {}
            typealias Global = P & Q
            struct Outer {
                protocol Local {}
                typealias Alias = Local & SDK.`External`
                struct Worker: Alias {}
            }
            extension Outer {
                typealias More = P & Q
                struct Nested: More {}
            }
            """)
        #expect(result.typeAliases["Global"] == ["P", "Q"])
        #expect(result.typeAliases["Outer.Alias"] == ["Local", "SDK.External"])
        #expect(result.typeAliases["Outer.More"] == ["P", "Q"])
        #expect(result.typeInheritance["Outer.Worker"] == ["Alias"])
        #expect(result.typeInheritance["Outer.Nested"] == ["More"])
        #expect(result.typeKinds["Outer.Nested"] == "struct")
    }

    @Test
    func extensionReferencesDoNotDependOnDeclarationOrderOrFile() {
        let extensionSource = """
            extension Outer.`Protocol` {
                func display() {
                    print(self.`value`)
                    work()
                    helper()
                }
            }
            """
        let protocolSource = """
            struct Outer {
                protocol `Protocol` {
                    var value: String { get }
                    func work()
                }
            }
            """
        let separate = collect(extensionSource)
        let before = collect(extensionSource + "\n" + protocolSource)
        let after = collect(protocolSource + "\n" + extensionSource)
        #expect(
            separate.protocolExtensionUsedMembers["Outer.Protocol"]?.isSuperset(of: [
                "value", "work", "helper",
            ]) == true)
        #expect(before.protocolExtensionUsedMembers == after.protocolExtensionUsedMembers)
        #expect(separate.protocolExtensionUsedMembers == before.protocolExtensionUsedMembers)
        #expect(separate.protocolDefinitions.isEmpty)
    }

    @Test
    func collectsEveryConditionalConformanceAndMergesRepeatedDefinitions() {
        let result = collect(
            """
            protocol P { func first() }
            #if FEATURE
            protocol P { func second() }
            extension Worker: P where T: Equatable {}
            #else
            protocol P: SDK.External { associatedtype Value }
            extension Worker: Q where T: Hashable {}
            #endif
            struct Worker<T> {}
            """)
        #expect(result.protocolRequirements["P"] == ["first", "second", "Value"])
        #expect(result.protocolDefinitions["P"]?.requirements.count == 3)
        #expect(result.protocolDefinitions["P"]?.inheritedTypes == ["SDK.External"])
        #expect(result.typeInheritance["Worker"] == ["P", "Q"])
        #expect(result.typeKinds["Worker"] == "struct")
    }

    @Test
    func keepsSameBasenameProtocolsAndTypesSeparate() {
        let result = collect(
            """
            struct A { protocol P { func a() }; struct Worker: P {} }
            struct B { protocol P { func b() }; struct Worker: P {} }
            """)
        #expect(result.projectDefinedProtocols == ["A.P", "B.P"])
        #expect(result.protocolRequirements["A.P"] == ["a"])
        #expect(result.protocolRequirements["B.P"] == ["b"])
        #expect(result.typeInheritance["A.Worker"] == ["P"])
        #expect(result.typeInheritance["B.Worker"] == ["P"])
        #expect(result.typeKinds["Worker"] == nil)
    }

    @Test
    func malformedProtocolDefinitionIsMarkedIncomplete() {
        let result = collect("protocol P { func work()")
        #expect(result.protocolDefinitions["P"]?.isComplete == false)
        #expect(result.protocolRequirements["P"] == ["work"])
    }

    @Test
    func aliasesUnwrapExistentialsAndParenthesizedCompositions() {
        let result = collect(
            """
            protocol P {}
            protocol Q {}
            typealias First = any (P & Q)
            typealias Second = (P & Q)
            """)
        #expect(result.typeAliases["First"] == ["P", "Q"])
        #expect(result.typeAliases["Second"] == ["P", "Q"])
    }

    @Test
    func globallyMergedSourceMetadataResolvesExtensionOnlyConformance() throws {
        let definitions = collect(
            """
            struct Namespace {
                protocol P { func work(_ value: Int) }
                typealias Alias = P
                struct Worker {}
            }
            """)
        let extensionMetadata = collect(
            """
            extension Namespace.Worker: Namespace.Alias {
                func work(_ value: Int) {}
                func work(other value: Int) {}
            }
            """)
        let signature = MemberSignature(
            kind: .function, name: "work", parameterLabels: ["_"], parameterTypes: ["Int"])
        let identity = DeclarationIdentity(
            file: "Worker+P.swift", offset: 42, signature: signature,
            enclosingTypePath: ["Namespace", "Worker"])
        let overloadIdentity = DeclarationIdentity(
            file: "Worker+P.swift", offset: 100,
            signature: MemberSignature(
                kind: .function, name: "work", parameterLabels: ["other"], parameterTypes: ["Int"]),
            enclosingTypePath: ["Namespace", "Worker"]
        )
        let declarations = [identity, overloadIdentity].map { identity in
            Declaration(
                name: "work", type: .function, file: identity.file, line: 1, exclusionReason: .none,
                parentType: "Namespace.Worker", identity: identity)
        }
        let resolver = WitnessResolver(
            protocolDefinitions: definitions.protocolDefinitions,
            typeInheritance: definitions.typeInheritance.merging(extensionMetadata.typeInheritance)
            { $0.union($1) },
            typeKinds: definitions.typeKinds,
            typeAliases: definitions.typeAliases,
            unresolvedProtocols: []
        )
        let result = resolver.resolve(declarations: declarations)
        #expect(result.required == [identity])
        #expect(result.uncertain.isEmpty)
        #expect(result.typeConformances["Namespace.Worker"] == ["Namespace.P"])
    }

    @Test
    func legacyResultInitializerHasEmptyNewMetadata() {
        let result = ProtocolVisitorResult(
            protocolRequirements: [:], protocolInheritance: [:], projectDefinedProtocols: [],
            importedModules: [], conformedProtocols: [], protocolExtensionUsedMembers: [:]
        )
        #expect(result.protocolDefinitions.isEmpty)
        #expect(result.typeInheritance.isEmpty)
        #expect(result.typeKinds.isEmpty)
        #expect(result.typeAliases.isEmpty)
        let resolution = WitnessResolution()
        #expect(resolution.required.isEmpty)
        #expect(resolution.uncertain.isEmpty)
        #expect(resolution.typeConformances.isEmpty)
        #expect(resolution.warnings.isEmpty)
    }
}

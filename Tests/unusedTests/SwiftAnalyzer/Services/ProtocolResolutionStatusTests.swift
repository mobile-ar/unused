import Testing
@testable import unused

struct ProtocolResolutionStatusTests {
    private func resolver(
        _ names: Set<String>, interface: String?,
        definitions: [String: ProtocolDefinition] = [:],
        inheritance: [String: Set<String>] = [:], kinds: [String: String] = [:],
        aliases: [String: Set<String>] = [:]
    ) -> ProtocolResolver {
        ProtocolResolver(
            protocolRequirements: definitions.mapValues { Set($0.requirements.map(\.name)) },
            protocolInheritance: definitions.mapValues(\.inheritedTypes),
            projectDefinedProtocols: Set(definitions.keys), importedModules: [], conformedProtocols: names,
            swiftInterfaceClient: SwiftInterfaceClient(moduleInterfaceProvider: { $0 == "Swift" ? interface : nil }),
            progressTrackerFactory: { ProgressTracker(total: $0, prefix: $1, render: { _ in }, finishLine: {}) },
            protocolDefinitions: definitions, typeInheritance: inheritance, typeKinds: kinds, typeAliases: aliases
        )
    }

    @Test func emptyProtocolAndUnavailableProtocolHaveDifferentStatuses() async {
        let resolver = resolver(["Empty", "Missing"], interface: "public protocol Empty {}")
        await resolver.resolveExternalProtocols()
        #expect(resolver.protocolRequirements["Empty"] == [])
        #expect(resolver.resolutionStatuses["Empty"] == .resolved)
        #expect(resolver.protocolRequirements["Missing"] == nil)
        #expect(resolver.resolutionStatuses["Missing"] == .unresolved)
    }

    @Test func missingParentMakesKnownProtocolPartialWithoutLosingRequirements() async {
        let resolver = resolver(["Known"], interface: "public protocol Known: Missing { func work<T>(_ value: T) }")
        await resolver.resolveExternalProtocols()
        resolver.resolveInheritedRequirements()
        #expect(resolver.protocolRequirements["Known"] == ["work"])
        #expect(resolver.resolutionStatuses["Known"] == .partial)
        #expect(resolver.resolutionStatuses["Swift.Missing"] == .unresolved)
        #expect(resolver.protocolDefinitions["Known"]?.isComplete == false)
    }

    @Test func partiallyAvailableCompositionKeepsResolvedRequirements() async {
        let resolver = resolver(["Alias"], interface: """
        public protocol Known { func work() }
        public typealias Alias = Known & Missing
        """)
        await resolver.resolveExternalProtocols()
        resolver.resolveInheritedRequirements()
        #expect(resolver.protocolRequirements["Alias"] == ["work"])
        #expect(resolver.resolutionStatuses["Alias"] == .partial)
        #expect(resolver.protocolRequirements["Swift.Missing"] == nil)
    }

    @Test func sourceAliasesResolveInTheirNamespaceWithoutQueryingTheirBareNames() async {
        let resolver = resolver(
            ["Contract"], interface: nil,
            definitions: ["Namespace.P": ProtocolDefinition(name: "Namespace.P")],
            inheritance: ["Namespace.Worker": ["Contract"]], kinds: ["Namespace.Worker": "struct"],
            aliases: ["Namespace.Contract": ["P"]]
        )
        await resolver.resolveExternalProtocols()
        #expect(resolver.resolutionStatuses["Namespace.P"] == .resolved)
        #expect(resolver.resolutionStatuses["Contract"] == nil)
        #expect(resolver.resolutionStatuses["P"] == nil)
    }

    @Test func nominalTypesAreNotUnavailableProtocols() async {
        let resolver = resolver(["String", "Base"], interface: "public struct String {} public class Base {}")
        await resolver.resolveExternalProtocols()
        #expect(resolver.externalTypeKinds == ["String": "struct", "Base": "class"])
        #expect(resolver.protocolDefinitions.isEmpty)
        #expect(resolver.resolutionStatuses.values.allSatisfy { $0 == .resolved })
    }

    @Test func qualifiedModuleDoesNotResolveAnUnrelatedHomonym() async {
        let resolver = resolver(["Other.P"], interface: "public protocol P {}")
        await resolver.resolveExternalProtocols()
        #expect(resolver.protocolRequirements["Other.P"] == nil)
        #expect(resolver.resolutionStatuses["Other.P"] == .unresolved)
    }

    @Test func sourceRequirementInheritancePropagatesPartialStatusTransitively() async {
        let resolver = resolver(
            [], interface: nil,
            definitions: [
                "Namespace.Parent": ProtocolDefinition(name: "Namespace.Parent", inheritedTypes: ["Missing"]),
                "Namespace.Child": ProtocolDefinition(name: "Namespace.Child", inheritedTypes: ["Parent"])
            ]
        )
        await resolver.resolveExternalProtocols()
        resolver.resolveInheritedRequirements()
        #expect(resolver.resolutionStatuses["Namespace.Parent"] == .partial)
        #expect(resolver.resolutionStatuses["Namespace.Child"] == .partial)
        #expect(resolver.protocolInheritance["Namespace.Child"]?.contains("Namespace.Parent") == true)
    }
}

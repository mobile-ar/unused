import Foundation

class ProtocolResolver {
    var protocolRequirements: [String: Set<String>]
    var protocolInheritance: [String: Set<String>]
    var protocolDefinitions: [String: ProtocolDefinition]
    private(set) var resolutionStatuses: [String: ProtocolResolutionStatus] = [:]
    private(set) var externalTypeKinds: [String: String] = [:]
    let projectDefinedProtocols: Set<String>
    let importedModules: Set<String>
    let conformedProtocols: Set<String>
    private let typeInheritance: [String: Set<String>]
    private let typeKinds: [String: String]
    private let typeAliases: [String: Set<String>]
    private let swiftInterfaceClient: SwiftInterfaceClient
    private let progressTrackerFactory: @Sendable (Int, String) -> ProgressTracker

    init(
        protocolRequirements: [String: Set<String>],
        protocolInheritance: [String: Set<String>],
        projectDefinedProtocols: Set<String>,
        importedModules: Set<String>,
        conformedProtocols: Set<String>,
        swiftInterfaceClient: SwiftInterfaceClient,
        progressTrackerFactory: @escaping @Sendable (Int, String) -> ProgressTracker = {
            ProgressTracker(total: $0, prefix: $1)
        },
        protocolDefinitions: [String: ProtocolDefinition] = [:],
        typeInheritance: [String: Set<String>] = [:],
        typeKinds: [String: String] = [:],
        typeAliases: [String: Set<String>] = [:]
    ) {
        self.protocolRequirements = protocolRequirements
        self.protocolInheritance = protocolInheritance
        self.projectDefinedProtocols = projectDefinedProtocols
        self.importedModules = importedModules
        self.conformedProtocols = conformedProtocols
        self.swiftInterfaceClient = swiftInterfaceClient
        self.progressTrackerFactory = progressTrackerFactory
        self.protocolDefinitions = protocolDefinitions
        self.typeInheritance = typeInheritance
        self.typeKinds = typeKinds
        self.typeAliases = typeAliases
    }

    func resolveExternalProtocols() async {
        let graph = WitnessTypeGraph(
            definitions: protocolDefinitions, inheritance: typeInheritance, kinds: typeKinds,
            aliases: typeAliases, unresolved: [],
            knownNames: Set(protocolDefinitions.keys).union(typeKinds.keys).union(typeAliases.keys)
        )
        for (name, parents) in protocolInheritance {
            let resolved = parents.reduce(into: Set<String>()) { result, parent in
                result.formUnion(graph.expandedNames(parent, relativeTo: name))
            }
            protocolInheritance[name] = resolved
            protocolDefinitions[name]?.inheritedTypes = resolved
        }
        var referenced: Set<String> = []
        if typeInheritance.isEmpty {
            referenced.formUnion(conformedProtocols)
        } else {
            for (owner, parents) in typeInheritance {
                for parent in parents {
                    referenced.formUnion(graph.expandedNames(parent, relativeTo: owner))
                }
            }
        }
        for (owner, parents) in protocolInheritance {
            for parent in parents {
                referenced.formUnion(graph.expandedNames(parent, relativeTo: owner))
            }
        }
        var queue = referenced.filter { shouldResolve($0) }.sorted()
        var scheduled = Set(queue)
        var completed = 0
        let tracker = progressTrackerFactory(queue.count, "Analyzing external protocols...")

        while !queue.isEmpty {
            let name = queue.removeFirst()
            let parents = await resolveProtocol(name)
            for parent in parents.sorted() where shouldResolve(parent) && scheduled.insert(parent).inserted {
                queue.append(parent)
            }
            completed += 1
            await tracker.increment(total: completed + queue.count)
        }
        await tracker.finish()
        propagateResolutionStatus()
    }

    private func shouldResolve(_ name: String) -> Bool {
        guard name != "AnyObject", name != "Swift.AnyObject" else { return false }
        if projectDefinedProtocols.contains(name) { return false }
        if let kind = typeKinds[name], kind != "protocol" { return false }
        if protocolRequirements[name] != nil, protocolDefinitions[name] == nil {
            // Callers may supply an already resolved name inventory without structured SDK metadata.
            return false
        }
        return resolutionStatuses[name] == nil
    }

    private func resolveProtocol(_ name: String) async -> Set<String> {
        let normalized = SwiftTypeName.normalized(name)
        let components = normalized.split(separator: ".")
        let qualifier = components.first.map(String.init)
        let modules: [String]
        if components.count > 1, let qualifier, importedModules.contains(qualifier) || qualifier == "Swift" {
            modules = [qualifier]
        } else {
            modules = importedModules.union(["Swift"]).sorted()
        }

        for module in modules {
            if let definition = await swiftInterfaceClient.getProtocolDefinition(protocolName: normalized, inModule: module) {
                var canonical = definition
                let canonicalName = module + "." + definition.name
                canonical.inheritedTypes = Set(definition.inheritedTypes.map { parent in
                    parent.contains(".") || parent == "AnyObject" ? parent : module + "." + parent
                })
                register(canonical, named: normalized)
                register(canonical, named: canonicalName)
                if !projectDefinedProtocols.contains(definition.name), typeKinds[definition.name] == nil {
                    register(canonical, named: definition.name)
                }
                return canonical.inheritedTypes
            }
            if let kind = await swiftInterfaceClient.getTypeKind(typeName: normalized, inModule: module), kind != "protocol" {
                externalTypeKinds[normalized] = kind
                resolutionStatuses[normalized] = .resolved
                return []
            }
        }
        // Unavailable requirements are not a verified empty protocol.
        resolutionStatuses[normalized] = .unresolved
        return []
    }

    private func register(_ definition: ProtocolDefinition, named name: String) {
        protocolDefinitions[name] = ProtocolDefinition(
            name: name, requirements: definition.requirements,
            inheritedTypes: definition.inheritedTypes, isComplete: definition.isComplete
        )
        protocolRequirements[name] = Set(definition.requirements.map(\.name))
        if !definition.inheritedTypes.isEmpty {
            protocolInheritance[name] = definition.inheritedTypes
        }
        resolutionStatuses[name] = definition.isComplete ? .resolved : .partial
    }

    private func propagateResolutionStatus() {
        for (name, definition) in protocolDefinitions where resolutionStatuses[name] == nil {
            resolutionStatuses[name] = definition.isComplete ? .resolved : .partial
        }
        for name in protocolRequirements.keys where resolutionStatuses[name] == nil {
            resolutionStatuses[name] = .resolved
        }
        var changed = true
        while changed {
            changed = false
            for (name, parents) in protocolInheritance {
                guard resolutionStatuses[name] != .unresolved else { continue }
                if parents.contains(where: { parent in
                    parent != "AnyObject" && parent != "Swift.AnyObject"
                        && resolutionStatuses[parent] != .resolved
                        && typeKinds[parent] == nil && externalTypeKinds[parent] == nil
                        && protocolRequirements[parent] == nil
                }) || parents.contains(where: { resolutionStatuses[$0] == .partial || resolutionStatuses[$0] == .unresolved }) {
                    if resolutionStatuses[name] != .partial {
                        resolutionStatuses[name] = .partial
                        protocolDefinitions[name]?.isComplete = false
                        changed = true
                    }
                }
            }
        }
    }

    func resolveInheritedRequirements() {
        var changed = true
        while changed {
            changed = false
            for (name, parents) in protocolInheritance {
                var requirements = protocolRequirements[name] ?? []
                let original = requirements
                var expandedParents = parents
                for parent in parents {
                    requirements.formUnion(protocolRequirements[parent] ?? [])
                    expandedParents.formUnion(protocolInheritance[parent] ?? [])
                }
                if requirements != original {
                    protocolRequirements[name] = requirements
                    changed = true
                }
                if expandedParents != parents {
                    protocolInheritance[name] = expandedParents
                    changed = true
                }
            }
        }
        propagateResolutionStatus()
    }
}

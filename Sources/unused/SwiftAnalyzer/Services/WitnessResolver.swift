/// Resolves witness providers after source and SDK protocol metadata have been merged across files.
/// Missing signatures or inheritance are handled conservatively without protecting unrelated owners.
struct WitnessResolver {
    let protocolDefinitions: [String: ProtocolDefinition]
    let typeInheritance: [String: Set<String>]
    let typeKinds: [String: String]
    let typeAliases: [String: Set<String>]
    let unresolvedProtocols: Set<String>

    func resolve(declarations: [Declaration]) -> WitnessResolution {
        let graph = makeGraph()
        let matcher = WitnessSignatureMatcher(graph: graph)
        var members: [String: Set<DeclarationIdentity>] = [:]
        for declaration in declarations {
            guard let identity = declaration.identity, let owner = graph.memberOwner(identity),
                identity.isTypeMember,
                declaration.type != .parameter, declaration.type != .import,
                declaration.type != .protocol,
                identity.signature.kind != .enumCase
            else { continue }
            let owners = graph.expandedNames(owner, relativeTo: "")
            for name in owners {
                members[name, default: []].insert(identity)
            }
        }

        var result = WitnessResolution()
        var warnings: Set<String> = []
        let types = Set(graph.inheritance.keys).union(graph.kinds.keys).union(members.keys)
        for type in types.sorted()
        where graph.definitions[type] == nil && graph.kinds[type] != "protocol"
            && graph.aliases[type] == nil
        {
            let closure = graph.closure(for: type)
            guard !closure.protocols.isEmpty else { continue }
            result.typeConformances[type] = closure.protocols
            let providerOwners = closure.providers.union(closure.protocols)
            let candidates = providerOwners.reduce(into: Set<DeclarationIdentity>()) {
                identities, owner in
                identities.formUnion(members[owner] ?? [])
            }

            for protocolName in closure.protocols.sorted() {
                guard let definition = graph.definitions[protocolName] else { continue }
                for requirement in definition.requirements {
                    for candidate in candidates {
                        let owner = graph.memberOwner(candidate) ?? type
                        if matcher.matches(
                            candidate.signature, requirement: requirement, providerOwner: owner,
                            protocolOwner: protocolName),
                            hasCompatibleResult(
                                candidate.signature, requirement: requirement, providerOwner: owner,
                                protocolOwner: protocolName, graph: graph, matcher: matcher)
                        {
                            // Keep every compatible provider: conditional extensions and generic substitutions
                            // are not represented by these inputs, so selecting just one would be unsafe.
                            result.required.insert(candidate)
                        }
                    }
                }
            }
            if !closure.unknown.isEmpty || !closure.partial.isEmpty {
                result.uncertain.formUnion(candidates)
                for name in closure.unknown.sorted() {
                    warnings.insert(
                        "Cannot resolve inherited type or protocol '\(name)' for '\(type)'. Potentially required members are excluded from unused results to avoid false positives."
                    )
                }
                for name in closure.partial.sorted() {
                    warnings.insert(
                        "Protocol requirements for '\(name)' used by '\(type)' are incomplete. Members that may satisfy missing requirements are excluded from unused results to avoid false positives."
                    )
                }
            }
        }
        result.uncertain.subtract(result.required)
        result.warnings = warnings.sorted()
        return result
    }

    private func hasCompatibleResult(
        _ provider: MemberSignature, requirement: MemberSignature, providerOwner: String,
        protocolOwner: String, graph: WitnessTypeGraph, matcher: WitnessSignatureMatcher
    ) -> Bool {
        guard
            provider.kind == .function || provider.kind == .property || provider.kind == .subscript
        else { return true }
        let implicitResult: String? = provider.kind == .function ? "Void" : nil
        guard let providedType = provider.resultType ?? implicitResult,
            let requiredType = requirement.resultType ?? implicitResult
        else { return true }
        let names = [providedType, requiredType].map(SwiftTypeName.normalized)
        // Composite types and reference-type covariance need semantic substitutions that are
        // not available here. Only disambiguate simple concrete value-type results.
        guard
            names.allSatisfy({ name in
                !name.isEmpty
                    && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }
            })
        else { return true }
        let providedName = graph.resolveName(names[0], relativeTo: providerOwner)
        let requiredName = graph.resolveName(names[1], relativeTo: protocolOwner)
        guard
            ![providedName, requiredName].contains(where: { name in
                graph.kinds[name] == "class" || graph.kinds[name] == "actor"
                    || name == "Never" || name == "Swift.Never"
            })
        else { return true }

        // Reuse the existing concrete-type/placeholder rules with results as synthetic parameters.
        var providedResult = provider
        providedResult.parameterLabels = ["_"]
        providedResult.parameterTypes = [providedType]
        var requiredResult = requirement
        requiredResult.parameterLabels = ["_"]
        requiredResult.parameterTypes = [requiredType]
        return matcher.matches(
            providedResult, requirement: requiredResult, providerOwner: providerOwner,
            protocolOwner: protocolOwner
        )
    }

    func makeGraph() -> WitnessTypeGraph {
        var definitions: [String: ProtocolDefinition] = [:]
        for (key, definition) in protocolDefinitions {
            let name = WitnessTypeGraph.nominalName(key)
            var merged = definitions[name] ?? ProtocolDefinition(name: name)
            merged.requirements.formUnion(definition.requirements)
            merged.inheritedTypes.formUnion(definition.inheritedTypes)
            merged.isComplete = merged.isComplete && definition.isComplete
            definitions[name] = merged
        }
        var inheritance: [String: Set<String>] = [:]
        for (name, parents) in typeInheritance {
            inheritance[WitnessTypeGraph.nominalName(name), default: []].formUnion(parents)
        }
        var aliases: [String: Set<String>] = [:]
        for (name, targets) in typeAliases {
            aliases[WitnessTypeGraph.nominalName(name), default: []].formUnion(targets)
        }
        var kinds: [String: String] = [:]
        for (name, kind) in typeKinds.sorted(by: { $0.key < $1.key }) {
            kinds[WitnessTypeGraph.nominalName(name)] = kind
        }
        let unresolved = Set(unresolvedProtocols.map(WitnessTypeGraph.nominalName))
        return WitnessTypeGraph(
            definitions: definitions, inheritance: inheritance, kinds: kinds, aliases: aliases,
            unresolved: unresolved,
            knownNames: Set(definitions.keys).union(kinds.keys).union(aliases.keys).union(
                inheritance.keys
            ).union(unresolved)
        )
    }
}

struct ExplicitReferenceResolver {
    let declarations: [Declaration]
    let ownerResolver: MemberOwnerResolver
    var argumentMatcher = CallArgumentMatcher()

    func resolve(
        memberUsages: Set<QualifiedUsage>, calls: Set<CallUsage>
    ) -> Set<DeclarationIdentity> {
        var membersByName: [String: Set<DeclarationIdentity>] = [:]
        var callablesByKind: [MemberKind: Set<DeclarationIdentity>] = [:]
        for declaration in declarations {
            guard let identity = declaration.identity, identity.isTypeMember,
                  identity.ownerName != nil else { continue }
            if ![.class, .protocol, .typealias].contains(declaration.type) {
                membersByName[declaration.name, default: []].insert(identity)
            }
            if [.initializer, .subscript].contains(identity.signature.kind) {
                callablesByKind[identity.signature.kind, default: []].insert(identity)
            }
        }

        var ownerCache: [String: (names: Set<String>, isUncertain: Bool)] = [:]
        func owners(for receiver: String, context: String = "") -> (names: Set<String>, isUncertain: Bool) {
            let key = context + "|" + receiver
            if let cached = ownerCache[key] { return cached }
            let resolved = ownerResolver.resolve(receiver, relativeTo: context)
            ownerCache[key] = resolved
            return resolved
        }
        func isProtocol(_ name: String) -> Bool {
            ownerResolver.graph.definitions[name] != nil || ownerResolver.graph.kinds[name] == "protocol"
        }

        var protocolProviders: [String: Set<String>]? = nil
        func providers(for protocols: Set<String>) -> Set<String> {
            if protocolProviders == nil {
                var inventory: [String: Set<String>] = [:]
                // Include types without members of their own: a subclass can introduce
                // conformance using a provider inherited from a nonconforming base.
                for type in ownerResolver.graph.knownNames where !isProtocol(type) {
                    let resolved = owners(for: type)
                    for name in resolved.names where isProtocol(name) {
                        inventory[name, default: []].formUnion(resolved.names)
                    }
                }
                protocolProviders = inventory
            }
            return protocols.reduce(into: []) { result, name in
                result.formUnion(protocolProviders?[name] ?? [])
            }
        }

        var canonicalOwnerCache: [DeclarationIdentity: Set<String>] = [:]
        func canonicalOwners(of identity: DeclarationIdentity) -> Set<String> {
            if let cached = canonicalOwnerCache[identity] { return cached }
            guard let owner = identity.ownerName else { return [] }
            var resolved = ownerResolver.resolve(owner, includeInheritance: false).names
            if let qualified = ownerResolver.graph.memberOwner(identity) {
                resolved.formUnion(ownerResolver.resolve(qualified, includeInheritance: false).names)
            }
            canonicalOwnerCache[identity] = resolved
            return resolved
        }

        func candidates(
            _ inventory: Set<DeclarationIdentity>, receiver: String?, context: String,
            isDynamic: Bool = false
        ) -> Set<DeclarationIdentity> {
            guard let receiver else { return inventory }
            let resolved = owners(for: receiver, context: context)
            guard !resolved.isUncertain else { return inventory }
            var names = resolved.names
            let receiverName = ownerResolver.graph.resolveName(receiver, relativeTo: context)
            if isProtocol(receiverName) || (!names.isEmpty && names.allSatisfy(isProtocol)) {
                names.formUnion(providers(for: names.filter(isProtocol)))
            }
            if isDynamic {
                let roots = ownerResolver.resolve(receiver, relativeTo: context, includeInheritance: false).names
                for type in ownerResolver.graph.knownNames where ownerResolver.graph.kinds[type] == "class" {
                    if !owners(for: type).names.isDisjoint(with: roots) { names.insert(type) }
                }
            }
            return inventory.filter { !canonicalOwners(of: $0).isDisjoint(with: names) }
        }

        var used: Set<DeclarationIdentity> = []
        for usage in memberUsages {
            used.formUnion(candidates(
                membersByName[usage.memberName] ?? [], receiver: usage.typeName, context: ""
            ))
        }
        for call in calls {
            let owned = candidates(
                callablesByKind[call.kind] ?? [], receiver: call.receiverType,
                context: call.enclosingTypePath.joined(separator: "."), isDynamic: call.isDynamicReceiver
            )
            used.formUnion(owned.filter { argumentMatcher.matches(call, signature: $0.signature) })
        }
        return used
    }
}

extension ExplicitReferenceResolver {
    init(
        declarations: [Declaration],
        protocolDefinitions: [String: ProtocolDefinition] = [:],
        typeInheritance: [String: Set<String>] = [:],
        typeKinds: [String: String] = [:],
        typeAliases: [String: Set<String>] = [:]
    ) {
        var knownNames = Set(typeKinds.keys).union(protocolDefinitions.keys).union(typeAliases.keys)
        for declaration in declarations {
            guard let identity = declaration.identity else { continue }
            if let owner = identity.ownerName {
                knownNames.insert(owner)
                if let module = identity.moduleName { knownNames.insert(module + "." + owner) }
            }
            if [.class, .protocol, .typealias].contains(declaration.type) {
                let name = (identity.enclosingTypePath + [declaration.name]).joined(separator: ".")
                knownNames.insert(name)
                if let module = identity.moduleName { knownNames.insert(module + "." + name) }
            }
        }
        var definitions = protocolDefinitions
        var inheritance = typeInheritance
        var kinds = typeKinds
        var aliases = typeAliases
        for declaration in declarations where [.class, .protocol, .typealias].contains(declaration.type) {
            guard let identity = declaration.identity, let module = identity.moduleName else { continue }
            let name = (identity.enclosingTypePath + [declaration.name]).joined(separator: ".")
            let qualified = module + "." + name
            if let definition = protocolDefinitions[name] { definitions[qualified] = definition }
            if let parents = typeInheritance[name] { inheritance[qualified] = parents }
            if let kind = typeKinds[name] { kinds[qualified] = kind }
            if let targets = typeAliases[name] { aliases[qualified] = targets }
        }
        let graph = WitnessTypeGraph(
            definitions: definitions, inheritance: inheritance, kinds: kinds,
            aliases: aliases, unresolved: [], knownNames: knownNames
        )
        let canonicalizer = MemberOwnerResolver(graph: graph)
        // A conformance written on a typealias belongs to the underlying type.
        for (name, parents) in inheritance {
            for owner in canonicalizer.resolve(name, includeInheritance: false).names {
                let qualifiedParents = parents.map { graph.resolveName($0, relativeTo: name) }
                inheritance[owner, default: []].formUnion(qualifiedParents)
            }
        }
        let canonicalGraph = WitnessTypeGraph(
            definitions: definitions, inheritance: inheritance, kinds: kinds,
            aliases: aliases, unresolved: [], knownNames: knownNames
        )
        self.init(declarations: declarations, ownerResolver: MemberOwnerResolver(graph: canonicalGraph))
    }
}

struct TypeReferenceResolver {
    let declarations: [Declaration]

    func resolve(_ references: Set<TypeReference>) -> Set<DeclarationIdentity> {
        var byName: [String: Set<DeclarationIdentity>] = [:]
        for declaration in declarations where [.class, .protocol, .typealias].contains(declaration.type) {
            guard let identity = declaration.identity else { continue }
            let name = (identity.enclosingTypePath + [declaration.name]).joined(separator: ".")
            byName[name, default: []].insert(identity)
            if let module = identity.moduleName {
                byName[module + "." + name, default: []].insert(identity)
            }
        }
        var result: Set<DeclarationIdentity> = []
        for reference in references {
            for depth in stride(from: reference.enclosingTypePath.count, through: 0, by: -1) {
                let name = (Array(reference.enclosingTypePath.prefix(depth)) + [reference.name]).joined(separator: ".")
                let candidates = (byName[name] ?? []).filter { identity in
                    identity.lexicalScope.isEmpty || (identity.file == reference.file
                        && identity.lexicalScope.allSatisfy(reference.lexicalScope.contains))
                }
                guard !candidates.isEmpty else { continue }
                let closestDepth = candidates.map { $0.lexicalScope.count }.max() ?? 0
                result.formUnion(candidates.filter { $0.lexicalScope.count == closestDepth })
                break
            }
        }
        return result
    }
}

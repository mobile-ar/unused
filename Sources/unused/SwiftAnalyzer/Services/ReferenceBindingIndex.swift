struct ReferenceBindingIndex {
    let typeProperties: [String: [PropertyInfo]]
    let typeGenericParameters: [String: Set<String>]

    static func merging(
        typeProperties: [String: [PropertyInfo]],
        typeGenericParameters: [String: Set<String>],
        ownerResolver: MemberOwnerResolver
    ) -> ReferenceBindingIndex {
        var propertiesByOwner: [String: Set<PropertyInfo>] = [:]
        for (owner, properties) in typeProperties {
            for name in ownerResolver.resolve(owner, includeInheritance: false).names {
                propertiesByOwner[name, default: []].formUnion(properties)
            }
        }
        var properties: [String: [PropertyInfo]] = [:]
        var parameters: [String: Set<String>] = [:]
        let names = ownerResolver.graph.knownNames.union(typeProperties.keys).union(typeGenericParameters.keys)
        for owner in names {
            let providers = ownerResolver.resolve(owner).names
            var visibleProperties: Set<PropertyInfo> = []
            for name in providers {
                visibleProperties.formUnion(propertiesByOwner[name] ?? [])
            }
            properties[owner] = visibleProperties.sorted {
                if $0.name != $1.name { return $0.name < $1.name }
                if $0.filePath != $1.filePath { return $0.filePath < $1.filePath }
                return $0.line < $1.line
            }
            for name in ownerResolver.resolve(owner, includeInheritance: false).names {
                var path = name.split(separator: ".").map(String.init)
                while !path.isEmpty {
                    parameters[owner, default: []].formUnion(typeGenericParameters[path.joined(separator: ".")] ?? [])
                    path.removeLast()
                }
            }
        }
        return ReferenceBindingIndex(typeProperties: properties, typeGenericParameters: parameters)
    }
}

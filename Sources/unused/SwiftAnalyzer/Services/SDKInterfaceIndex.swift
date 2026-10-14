/// A syntax-free module snapshot so repeated actor queries never retain or reparse a large syntax tree.
struct SDKInterfaceIndex: Sendable {
    var moduleName: String? = nil
    var protocols: [String: ProtocolDefinition] = [:]
    var aliases: [String: SDKInterfaceAlias] = [:]
    var typeKinds: [String: String] = [:]
    var exportedSymbols: Set<String> = []
    var importedModules: Set<String> = []
    var reexportedModules: Set<String> = []
    var symbolInventoryUncertainties: Set<SDKInterfaceSymbolInventoryUncertainty> = [.unverifiedInterface]
    var propertyWrappers: Set<String> = []

    var symbolInventory: SDKInterfaceSymbolInventory {
        SDKInterfaceSymbolInventory(
            symbols: exportedSymbols,
            reexportedModules: reexportedModules,
            uncertainties: symbolInventoryUncertainties
        )
    }

    func protocolDefinition(named name: String) -> ProtocolDefinition? {
        let name = SwiftTypeName.normalized(name)
        if moduleName == nil, protocols[name] == nil, aliases[name] == nil,
           let separator = name.firstIndex(of: ".") {
            // A qualified query supplies module context when an in-memory interface has no SDK header.
            var contextualIndex = self
            contextualIndex.moduleName = String(name[..<separator])
            return contextualIndex.resolve(name: name, scope: "", visiting: [])
        }
        return resolve(name: name, scope: "", visiting: [])
    }

    func typeKind(named name: String) -> String? {
        let name = SwiftTypeName.normalized(name)
        if let kind = typeKinds[name] { return kind }
        guard let moduleName else { return nil }
        let prefix = moduleName + "."
        if name.hasPrefix(prefix) {
            return typeKinds[String(name.dropFirst(prefix.count))]
        }
        // Nested declarations in a qualified extension can retain their receiver's module prefix.
        return typeKinds[prefix + name]
    }

    private func resolve(name: String, scope: String, visiting: Set<String>) -> ProtocolDefinition? {
        guard let key = declarationKey(for: name, scope: scope) else { return nil }
        if let definition = protocols[key] { return definition }
        guard let alias = aliases[key] else { return nil }

        var definition = ProtocolDefinition(name: alias.name)
        definition.inheritedTypes = alias.referencedTypes
        definition.isComplete = alias.isComplete
        guard !visiting.contains(key) else {
            definition.isComplete = false
            return definition
        }

        var visiting = visiting
        visiting.insert(key)
        let aliasScope = key.split(separator: ".").dropLast().joined(separator: ".")
        for referencedType in alias.referencedTypes.sorted() {
            guard let resolved = resolve(name: referencedType, scope: aliasScope, visiting: visiting) else {
                definition.isComplete = false
                continue
            }
            definition.requirements.formUnion(resolved.requirements)
            definition.isComplete = definition.isComplete && resolved.isComplete
        }
        return definition
    }

    private func declarationKey(for name: String, scope: String) -> String? {
        var scopes = scope.split(separator: ".").map(String.init)
        while !scopes.isEmpty {
            let scopedName = (scopes + [name]).joined(separator: ".")
            if protocols[scopedName] != nil || aliases[scopedName] != nil { return scopedName }
            scopes.removeLast()
        }
        if protocols[name] != nil || aliases[name] != nil { return name }

        // A loaded module can resolve its own qualified references, never another module's homonyms.
        if let moduleName {
            let prefix = moduleName + "."
            guard name.hasPrefix(prefix) else { return nil }
            let unqualifiedName = String(name.dropFirst(prefix.count))
            if protocols[unqualifiedName] != nil || aliases[unqualifiedName] != nil { return unqualifiedName }
        } else if name.hasPrefix("Swift.") {
            // Pure parsing has no module argument; standard-library interfaces routinely qualify their own names.
            let unqualifiedName = String(name.dropFirst("Swift.".count))
            if protocols[unqualifiedName] != nil || aliases[unqualifiedName] != nil { return unqualifiedName }
        }
        return nil
    }
}

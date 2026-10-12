struct WitnessTypeGraph {
    let definitions: [String: ProtocolDefinition]
    let inheritance: [String: Set<String>]
    let kinds: [String: String]
    let aliases: [String: Set<String>]
    let unresolved: Set<String>
    let knownNames: Set<String>

    func memberOwner(_ identity: DeclarationIdentity) -> String? {
        guard let owner = identity.ownerName else { return nil }
        let name = Self.nominalName(owner)
        if let module = identity.moduleName {
            let qualified = SwiftTypeName.normalized(module) + "." + name
            if knownNames.contains(qualified) {
                return qualified
            }
        }
        return name
    }

    static func nominalName(_ spelling: String) -> String {
        var depth = 0
        var name = ""
        for character in SwiftTypeName.normalized(spelling) {
            if character == "<" {
                depth += 1
            } else if character == ">", depth > 0 {
                depth -= 1
            } else if depth == 0 {
                name.append(character)
            }
        }
        return name
    }

    func resolveName(_ spelling: String, relativeTo owner: String) -> String {
        let name = Self.nominalName(spelling)
        var scope = owner.split(separator: ".").map(String.init)
        if name.hasPrefix("Self.") {
            return owner + "." + name.dropFirst(5)
        }
        while !scope.isEmpty {
            let candidate = scope.joined(separator: ".") + "." + name
            if knownNames.contains(candidate) {
                return candidate
            }
            scope.removeLast()
        }
        return name
    }

    func expandedNames(
        _ spelling: String, relativeTo owner: String, visiting: Set<String> = []
    ) -> Set<String> {
        let name = resolveName(spelling, relativeTo: owner)
        guard let targets = aliases[name], !targets.isEmpty, !visiting.contains(name) else {
            return [name]
        }
        var visited = visiting
        visited.insert(name)
        let namespace = name.split(separator: ".").dropLast().joined(separator: ".")
        return targets.reduce(into: []) { result, target in
            result.formUnion(expandedNames(target, relativeTo: namespace, visiting: visited))
        }
    }

    func closure(
        for type: String
    ) -> (
        protocols: Set<String>, providers: Set<String>, unknown: Set<String>, partial: Set<String>
    ) {
        var protocols: Set<String> = []
        var providers: Set<String> = [type]
        var unknown: Set<String> = []
        var partial: Set<String> = []
        var visited: Set<String> = []
        var pending = [type]

        while let owner = pending.popLast() {
            guard visited.insert(owner).inserted else { continue }
            if let definition = definitions[owner] {
                protocols.insert(owner)
                if !definition.isComplete || unresolved.contains(owner) {
                    partial.insert(owner)
                }
            } else if kinds[owner] == "class" {
                providers.insert(owner)
            }

            let parents = (inheritance[owner] ?? []).union(definitions[owner]?.inheritedTypes ?? [])
            for parent in parents.sorted() {
                for name in expandedNames(parent, relativeTo: owner).sorted() {
                    if name == "AnyObject" || name == "Swift.AnyObject" {
                        // The class-bound constraint has no witness requirements.
                        continue
                    }
                    if definitions[name] != nil {
                        pending.append(name)
                    } else if kinds[name] == "class" {
                        // A known superclass is not an unresolved external protocol.
                        pending.append(name)
                    } else if kinds[name] == nil || kinds[name] == "protocol" {
                        protocols.insert(name)
                        unknown.insert(name)
                    }
                }
            }
        }
        return (protocols, providers, unknown, partial)
    }
}

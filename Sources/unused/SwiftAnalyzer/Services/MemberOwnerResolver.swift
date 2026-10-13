struct MemberOwnerResolver {
    let graph: WitnessTypeGraph

    func resolve(
        _ receiver: String, relativeTo context: String = "", includeInheritance: Bool = true
    ) -> (names: Set<String>, isUncertain: Bool) {
        var names: Set<String> = []
        var uncertain = false
        var pending = [(receiver, context)]
        var visited: Set<String> = []
        while let (spelling, owner) = pending.popLast() {
            let name = graph.resolveName(spelling, relativeTo: owner)
            guard visited.insert(name).inserted else { continue }
            if let targets = graph.aliases[name] {
                if targets.isEmpty { uncertain = true }
                let namespace = name.split(separator: ".").dropLast().joined(separator: ".")
                for target in targets {
                    pending.append((target, namespace))
                }
                continue
            }
            // A member type can be named through an alias of its namespace.
            let parts = name.split(separator: ".").map(String.init)
            var expandedPrefix = false
            if parts.count > 1 {
                for depth in stride(from: parts.count - 1, through: 1, by: -1) {
                    let prefix = parts.prefix(depth).joined(separator: ".")
                    guard let targets = graph.aliases[prefix] else { continue }
                    let suffix = parts.dropFirst(depth).joined(separator: ".")
                    let namespace = parts.prefix(depth - 1).joined(separator: ".")
                    for target in targets {
                        let resolvedTarget = graph.resolveName(target, relativeTo: namespace)
                        pending.append((resolvedTarget + "." + suffix, ""))
                    }
                    expandedPrefix = true
                    break
                }
            }
            if expandedPrefix { continue }
            names.insert(name)
            if !graph.knownNames.contains(name) { uncertain = true }
            if includeInheritance {
                let parents = (graph.inheritance[name] ?? []).union(graph.definitions[name]?.inheritedTypes ?? [])
                for parent in parents where parent != "AnyObject" && parent != "Swift.AnyObject" {
                    pending.append((parent, name))
                }
            }
        }
        // Cyclic or empty aliases must not look like a verified empty owner set.
        return (names, uncertain || names.isEmpty)
    }
}

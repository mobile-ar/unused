//
//  Created by Fernando Romiti on 14/02/2026.
//

import Foundation

class ProtocolResolver {

    var protocolRequirements: [String: Set<String>]
    var protocolInheritance: [String: Set<String>]
    let projectDefinedProtocols: Set<String>
    let importedModules: Set<String>
    let conformedProtocols: Set<String>
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
        }
    ) {
        self.protocolRequirements = protocolRequirements
        self.protocolInheritance = protocolInheritance
        self.projectDefinedProtocols = projectDefinedProtocols
        self.importedModules = importedModules
        self.conformedProtocols = conformedProtocols
        self.swiftInterfaceClient = swiftInterfaceClient
        self.progressTrackerFactory = progressTrackerFactory
    }

    func resolveExternalProtocols() async {
        let allReferencedProtocols = conformedProtocols
            .union(protocolInheritance.values.reduce(into: Set<String>()) { $0.formUnion($1) })

        let externalProtocolsToResolve = allReferencedProtocols
            .subtracting(projectDefinedProtocols)
            .filter { protocolRequirements[$0] == nil }

        let modulesToTry = importedModules.union(["Swift"])

        var resolvedSet = Set<String>()
        var queue = Array(externalProtocolsToResolve)

        var completed = 0
        let tracker = progressTrackerFactory(queue.count, "Analyzing external protocols...")

        while !queue.isEmpty {
            let protocolName = queue.removeFirst()
            await resolveProtocol(protocolName, modules: modulesToTry, resolved: &resolvedSet, queue: &queue)
            completed += 1
            // Parent protocols can expand the queue; estimate only the currently known work.
            await tracker.increment(total: completed + queue.count)
        }

        await tracker.finish()
    }

    private func resolveProtocol(
        _ protocolName: String,
        modules: Set<String>,
        resolved: inout Set<String>,
        queue: inout [String]
    ) async {
        guard !resolved.contains(protocolName), !projectDefinedProtocols.contains(protocolName) else { return }
        if protocolRequirements[protocolName] != nil && protocolInheritance[protocolName] != nil {
            resolved.insert(protocolName)
            return
        }

        var foundRequirements: Set<String>?
        var foundParents: Set<String>?

        for moduleName in modules {
            if let requirements = await swiftInterfaceClient.getProtocolRequirements(protocolName: protocolName, inModule: moduleName) {
                foundRequirements = requirements
                foundParents = await swiftInterfaceClient.getProtocolParents(protocolName: protocolName, inModule: moduleName)
                break
            }
        }

        if protocolRequirements[protocolName] == nil {
            protocolRequirements[protocolName] = foundRequirements ?? Set()
        }

        if let parents = foundParents, !parents.isEmpty {
            protocolInheritance[protocolName] = parents
            for parent in parents {
                if !resolved.contains(parent) && !projectDefinedProtocols.contains(parent) && protocolRequirements[parent] == nil {
                    queue.append(parent)
                }
            }
        }

        resolved.insert(protocolName)
    }

    func resolveInheritedRequirements() {
        var changed = true
        while changed {
            changed = false
            for (protocolName, parents) in protocolInheritance {
                var currentRequirements = protocolRequirements[protocolName] ?? Set()
                let originalCount = currentRequirements.count

                for parent in parents {
                    if let parentRequirements = protocolRequirements[parent] {
                        currentRequirements.formUnion(parentRequirements)
                    }
                }

                if currentRequirements.count != originalCount {
                    protocolRequirements[protocolName] = currentRequirements
                    changed = true
                }
            }

            for (protocolName, parents) in protocolInheritance {
                var expandedParents = parents
                let originalParentCount = expandedParents.count

                for parent in parents {
                    if let grandparents = protocolInheritance[parent] {
                        expandedParents.formUnion(grandparents)
                    }
                }

                if expandedParents.count != originalParentCount {
                    protocolInheritance[protocolName] = expandedParents
                    changed = true
                }
            }
        }
    }

}

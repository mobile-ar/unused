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

    init(
        protocolRequirements: [String: Set<String>],
        protocolInheritance: [String: Set<String>],
        projectDefinedProtocols: Set<String>,
        importedModules: Set<String>,
        conformedProtocols: Set<String>,
        swiftInterfaceClient: SwiftInterfaceClient
    ) {
        self.protocolRequirements = protocolRequirements
        self.protocolInheritance = protocolInheritance
        self.projectDefinedProtocols = projectDefinedProtocols
        self.importedModules = importedModules
        self.conformedProtocols = conformedProtocols
        self.swiftInterfaceClient = swiftInterfaceClient
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

        var progressIndex = 0

        while !queue.isEmpty {
            let protocolName = queue.removeFirst()
            progressIndex += 1
            let displayTotal = progressIndex + queue.count
            printProgressBar(prefix: "Analyzing external protocols...", current: progressIndex, total: displayTotal)

            if resolvedSet.contains(protocolName) || projectDefinedProtocols.contains(protocolName) {
                continue
            }

            if protocolRequirements[protocolName] != nil && protocolInheritance[protocolName] != nil {
                resolvedSet.insert(protocolName)
                continue
            }

            var foundRequirements: Set<String>?
            var foundParents: Set<String>?

            for moduleName in modulesToTry {
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
                    if !resolvedSet.contains(parent) && !projectDefinedProtocols.contains(parent) && protocolRequirements[parent] == nil {
                        queue.append(parent)
                    }
                }
            }

            resolvedSet.insert(protocolName)
        }

        if progressIndex > 0 {
            print("")
        }
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

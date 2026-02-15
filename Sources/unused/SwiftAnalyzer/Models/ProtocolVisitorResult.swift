//
//  Created by Fernando Romiti on 14/02/2026.
//

struct ProtocolVisitorResult: Sendable {
    let protocolRequirements: [String: Set<String>]
    let protocolInheritance: [String: Set<String>]
    let projectDefinedProtocols: Set<String>
    let importedModules: Set<String>
    let conformedProtocols: Set<String>
}

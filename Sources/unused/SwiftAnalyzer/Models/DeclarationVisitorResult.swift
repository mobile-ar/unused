//
//  Created by Fernando Romiti on 14/02/2026.
//

struct DeclarationVisitorResult: Sendable {
    let declarations: [Declaration]
    let typeProtocolConformance: [String: Set<String>]
    let typePropertyDeclarations: [String: [PropertyInfo]]
    let projectPropertyWrappers: Set<String>
}

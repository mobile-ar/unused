//
//  Created by Fernando Romiti on 30/11/2025.
//

enum DeclarationType: String, Codable {
    case function
    case variable
    case `class`
    case enumCase
    case `protocol`
    case `typealias`
    case parameter
    case `import`
}

enum ExclusionReason: String, Codable {
    case override
    case protocolImplementation
    case unresolvedProtocol
    case unresolvedMacro
    case objcAttribute
    case ibAction
    case ibOutlet
    case writeOnly

    case mainAttribute
    case none

    var description: String {
        switch self {
        case .override: return "override"
        case .protocolImplementation: return "protocol"
        case .unresolvedProtocol: return "unresolved protocol"
        case .unresolvedMacro: return "unresolved macro"
        case .objcAttribute: return "@objc"
        case .ibAction: return "@IBAction"
        case .ibOutlet: return "@IBOutlet"
        case .writeOnly: return "write-only"

        case .mainAttribute: return "@main"
        case .none: return ""
        }
    }

}

struct Declaration: Sendable {

    let name: String
    let type: DeclarationType
    let file: String
    let line: Int
    let exclusionReason: ExclusionReason
    let parentType: String? // For tracking which class/struct the declaration belongs to
    var identity: DeclarationIdentity? = nil
    var isWriteOnly: Bool = false

    var shouldExcludeByDefault: Bool {
        return exclusionReason != .none
    }

}

//
//  Created by Fernando Romiti on 30/11/2025.
//

enum DeclarationType: String, Codable {
    case function
    case variable
    case `class`
    case enumCase
    case `protocol`
}

enum ExclusionReason: String, Codable {
    case override
    case protocolImplementation
    case objcAttribute
    case ibAction
    case ibOutlet
    case writeOnly
    case caseIterable
    case none

    var description: String {
        switch self {
        case .override: return "override"
        case .protocolImplementation: return "protocol"
        case .objcAttribute: return "@objc"
        case .ibAction: return "@IBAction"
        case .ibOutlet: return "@IBOutlet"
        case .writeOnly: return "write-only"
        case .caseIterable: return "CaseIterable"
        case .none: return ""
        }
    }

}

struct Declaration {

    let name: String
    let type: DeclarationType
    let file: String
    let line: Int
    let exclusionReason: ExclusionReason
    let parentType: String? // For tracking which class/struct the declaration belongs to

    var shouldExcludeByDefault: Bool {
        return exclusionReason != .none
    }

}

//
//  Created by Fernando Romiti on 30/11/2025.
//

enum DeclarationType: String {
    case function
    case variable
    case `class`
}

enum ExclusionReason: String {
    case override
    case protocolImplementation
    case objcAttribute
    case ibAction
    case ibOutlet
    case none

    var description: String {
        switch self {
        case .override: return "override"
        case .protocolImplementation: return "protocol"
        case .objcAttribute: return "@objc"
        case .ibAction: return "@IBAction"
        case .ibOutlet: return "@IBOutlet"
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

    func toCSV(id: Int) -> String {
        let escapedName = name.replacingOccurrences(of: "\"", with: "\"\"")
        let escapedFile = file.replacingOccurrences(of: "\"", with: "\"\"")
        let escapedParent = (parentType ?? "").replacingOccurrences(of: "\"", with: "\"\"")

        return "\(id),\"\(escapedName)\",\"\(type)\",\"\(escapedFile)\",\(line),\"\(exclusionReason)\",\"\(escapedParent)\""
    }

}

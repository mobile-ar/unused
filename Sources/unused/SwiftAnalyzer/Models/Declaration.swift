//
//  Created by Fernando Romiti on 30/11/2025.
//

enum DeclarationType {
    case function
    case variable
    case `class`
}

enum ExclusionReason {
    case override
    case protocolImplementation
    case objcAttribute
    case ibAction
    case ibOutlet
    case none
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

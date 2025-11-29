//
//  Created by Fernando Romiti on 30/11/2025.
//

enum DeclarationType {
    case function
    case variable
    case `class`
}

struct Declaration {
    let name: String
    let type: DeclarationType
    let file: String
}

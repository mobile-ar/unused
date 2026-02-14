//
//  Created by Fernando Romiti on 14/02/2026.
//

import SwiftSyntax

extension TokenSyntax {

    var identifierName: String {
        text.replacing("`", with: "")
    }

}

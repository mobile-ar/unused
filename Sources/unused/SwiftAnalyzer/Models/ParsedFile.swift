//
//  Created by Fernando Romiti on 14/02/2026.
//

import Foundation
import SwiftSyntax

struct ParsedFile: Sendable {
    let url: URL
    let source: String
    let sourceFile: SourceFileSyntax
}

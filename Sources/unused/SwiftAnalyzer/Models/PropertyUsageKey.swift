//
//  Created by Fernando Romiti on 01/02/2026.
//

struct PropertyUsageKey: Hashable {
    let filePath: String
    let typeName: String
    let propertyName: String
    let line: Int
}

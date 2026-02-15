//
//  Created by Fernando Romiti on 14/02/2026.
//

struct WriteOnlyVisitorResult: Sendable {
    let propertyReads: Set<PropertyInfo>
    let propertyWrites: Set<PropertyInfo>
}

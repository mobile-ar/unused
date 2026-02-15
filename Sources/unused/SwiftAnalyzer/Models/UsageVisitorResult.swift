//
//  Created by Fernando Romiti on 14/02/2026.
//

struct UsageVisitorResult: Sendable {
    let usedIdentifiers: Set<String>
    let qualifiedMemberUsages: Set<QualifiedUsage>
    let unqualifiedMemberUsages: Set<String>
    let bareIdentifierUsages: Set<String>
}

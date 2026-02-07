//
//  Created by Fernando Romiti on 07/02/2026.
//

struct DeletionTarget: Hashable {
    let name: String
    let line: Int
    let type: DeclarationType
}

extension DeletionTarget {
    init(from item: ReportItem) {
        self.name = item.name
        self.line = item.line
        self.type = item.type
    }
}

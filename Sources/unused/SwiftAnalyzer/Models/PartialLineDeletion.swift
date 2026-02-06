//
//  Created by Fernando Romiti on 02/02/2026.
//

struct PartialLineDeletion: Equatable, Hashable {
    let line: Int
    let startColumn: Int
    let endColumn: Int
    
    var columnRange: ClosedRange<Int> {
        startColumn...endColumn
    }
    
    init(line: Int, startColumn: Int, endColumn: Int) {
        self.line = line
        self.startColumn = startColumn
        self.endColumn = endColumn
    }
    
    init(line: Int, columnRange: ClosedRange<Int>) {
        self.line = line
        self.startColumn = columnRange.lowerBound
        self.endColumn = columnRange.upperBound
    }
}
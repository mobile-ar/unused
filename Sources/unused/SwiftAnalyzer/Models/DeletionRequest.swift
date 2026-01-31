//
//  Created by Fernando Romiti on 01/02/2026.
//

enum DeletionMode: Equatable, Hashable {
    case fullDeclaration
    case specificLines(Set<Int>)
}

struct DeletionRequest: Equatable {
    let item: ReportItem
    let mode: DeletionMode

    init(item: ReportItem, mode: DeletionMode = .fullDeclaration) {
        self.item = item
        self.mode = mode
    }

    var linesToDelete: Set<Int>? {
        if case .specificLines(let lines) = mode {
            return lines
        }
        return nil
    }

    var isFullDeclaration: Bool {
        if case .fullDeclaration = mode {
            return true
        }
        return false
    }
}

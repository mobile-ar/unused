//
//  Created by Fernando Romiti on 01/02/2026.
//

enum DeletionMode: Equatable, Hashable {
    case fullDeclaration
    case specificLines(Set<Int>)
    case lineRange(ClosedRange<Int>)
    case relatedCode(RelatedDeletion)
    case partialLine(PartialLineDeletion)
}

struct DeletionRequest: Equatable, Hashable {
    let item: ReportItem
    let mode: DeletionMode

    init(item: ReportItem, mode: DeletionMode = .fullDeclaration) {
        self.item = item
        self.mode = mode
    }

    static func fromRelatedDeletion(_ related: RelatedDeletion) -> DeletionRequest {
        DeletionRequest(
            item: related.parentDeclaration,
            mode: .relatedCode(related)
        )
    }

    var linesToDelete: Set<Int>? {
        switch mode {
        case .specificLines(let lines):
            return lines
        case .lineRange(let range):
            return Set(range)
        case .relatedCode(let related):
            if related.isPartialLineDeletion { return nil }
            return Set(related.lineRange)
        case .fullDeclaration, .partialLine:
            return nil
        }
    }

    var isFullDeclaration: Bool {
        if case .fullDeclaration = mode { return true }
        return false
    }

    var isRelatedCode: Bool {
        if case .relatedCode = mode { return true }
        return false
    }

    var isPartialLineDeletion: Bool {
        switch mode {
        case .partialLine:
            return true
        case .relatedCode(let related):
            return related.isPartialLineDeletion
        default:
            return false
        }
    }

    var relatedDeletion: RelatedDeletion? {
        if case .relatedCode(let related) = mode { return related }
        return nil
    }

    var partialLineDeletion: PartialLineDeletion? {
        switch mode {
        case .partialLine(let partial):
            return partial
        case .relatedCode(let related):
            return related.partialDeletion
        default:
            return nil
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(item)
        hasher.combine(mode)
    }
}

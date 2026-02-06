//
//  Created by Fernando Romiti on 02/02/2026.
//

struct RelatedDeletion: Equatable, Hashable {
    let filePath: String
    let lineRange: ClosedRange<Int>
    let sourceSnippet: String
    let description: String
    let parentDeclaration: ReportItem
    let partialDeletion: PartialLineDeletion?
    
    init(
        filePath: String,
        lineRange: ClosedRange<Int>,
        sourceSnippet: String,
        description: String,
        parentDeclaration: ReportItem,
        partialDeletion: PartialLineDeletion? = nil
    ) {
        self.filePath = filePath
        self.lineRange = lineRange
        self.sourceSnippet = sourceSnippet
        self.description = description
        self.parentDeclaration = parentDeclaration
        self.partialDeletion = partialDeletion
    }
    
    var isPartialLineDeletion: Bool {
        partialDeletion != nil
    }
}

struct RelatedDeletionGroup {
    let primaryItem: ReportItem
    let relatedDeletions: [RelatedDeletion]
}
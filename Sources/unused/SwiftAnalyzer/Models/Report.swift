//
//  Created by Fernando Romiti on 25/01/2026.
//

import Foundation

/// Represents a declaration item with an assigned ID for reporting
struct ReportItem: Codable, Equatable, Hashable {
    let id: Int
    let name: String
    let type: DeclarationType
    let file: String
    let line: Int
    let exclusionReason: ExclusionReason
    let parentType: String?

    var declaration: Declaration {
        Declaration(
            name: name,
            type: type,
            file: file,
            line: line,
            exclusionReason: exclusionReason,
            parentType: parentType
        )
    }
}

extension ReportItem {
    init(id: Int, declaration: Declaration) {
        self.id = id
        self.name = declaration.name
        self.type = declaration.type
        self.file = declaration.file
        self.line = declaration.line
        self.exclusionReason = declaration.exclusionReason
        self.parentType = declaration.parentType
    }
}

/// Container for excluded items categorized by exclusion reason
struct ExcludedItems: Codable, Equatable {
    let overrides: [ReportItem]
    let protocolImplementations: [ReportItem]
    let objcItems: [ReportItem]
    let mainTypes: [ReportItem]

    var totalCount: Int {
        overrides.count + protocolImplementations.count + objcItems.count + mainTypes.count
    }

    var allItems: [ReportItem] {
        overrides + protocolImplementations + objcItems + mainTypes
    }
}

/// Summary statistics for the analysis report
struct ReportSummary: Codable, Equatable {
    let totalExcluded: Int
    let testFilesExcluded: Int
}

/// Options that were used during the analysis
struct ReportOptions: Codable, Equatable {
    let includeOverrides: Bool
    let includeProtocols: Bool
    let includeObjc: Bool
    let includeTests: Bool
    let showExcluded: Bool

    init(from options: AnalyzerOptions) {
        self.includeOverrides = options.includeOverrides
        self.includeProtocols = options.includeProtocols
        self.includeObjc = options.includeObjc
        self.includeTests = options.includeTests
        self.showExcluded = options.showExcluded
    }

    init(
        includeOverrides: Bool = false,
        includeProtocols: Bool = false,
        includeObjc: Bool = false,
        includeTests: Bool = false,
        showExcluded: Bool = false
    ) {
        self.includeOverrides = includeOverrides
        self.includeProtocols = includeProtocols
        self.includeObjc = includeObjc
        self.includeTests = includeTests
        self.showExcluded = showExcluded
    }
}

/// The complete analysis report containing all findings and metadata
struct Report: Codable, Equatable {
    /// Schema version for future compatibility
    let version: String
    let generatedAt: Date
    let options: ReportOptions
    let summary: ReportSummary

    /// Unused declarations (the main findings)
    let unused: [ReportItem]

    /// Items excluded from results based on options
    let excluded: ExcludedItems

    /// Current schema version
    static let currentVersion = "1.0"

    init(unused: [ReportItem], excluded: ExcludedItems, options: ReportOptions, testFilesExcluded: Int) {
        self.version = Self.currentVersion
        self.generatedAt = Date()
        self.options = options
        self.unused = unused
        self.excluded = excluded
        self.summary = ReportSummary(totalExcluded: excluded.totalCount, testFilesExcluded: testFilesExcluded)
    }

    /// Returns all items (unused + excluded) for ID lookup
    var allItems: [ReportItem] {
        unused + excluded.allItems
    }

    /// Finds an item by its ID across all categories
    func item(withId id: Int) -> ReportItem? {
        allItems.first { $0.id == id }
    }

    /// Returns the maximum ID used in the report
    var maxId: Int {
        allItems.map(\.id).max() ?? 0
    }
}

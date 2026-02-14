//
//  Created by Fernando Romiti on 28/01/2026.
//

import Foundation

/// Service for filtering report items based on specified criteria
struct FilterService {

    /// Filters the unused items from a report based on the given criteria
    /// - Parameters:
    ///   - report: The analysis report containing unused declarations
    ///   - criteria: The filter criteria to apply
    /// - Returns: An array of report items matching all criteria
    func filter(report: Report, criteria: FilterCriteria) -> [ReportItem] {
        var items = report.unused

        if criteria.includeExcluded {
            items += report.excluded.allItems
        }

        guard !criteria.isEmpty else {
            return items
        }

        return items.filter { criteria.matches($0) }
    }

    /// Filters items by specific IDs
    /// - Parameters:
    ///   - report: The analysis report containing unused declarations
    ///   - ids: The IDs to filter by
    /// - Returns: An array of report items with matching IDs
    func filter(report: Report, byIds ids: [Int]) -> [ReportItem] {
        let criteria = FilterCriteria(ids: ids)
        return filter(report: report, criteria: criteria)
    }

    /// Filters items by declaration type
    /// - Parameters:
    ///   - report: The analysis report containing unused declarations
    ///   - types: The types to filter by
    /// - Returns: An array of report items with matching types
    func filter(report: Report, byTypes types: [DeclarationType]) -> [ReportItem] {
        let criteria = FilterCriteria(types: types)
        return filter(report: report, criteria: criteria)
    }

    /// Filters items by file path pattern
    /// - Parameters:
    ///   - report: The analysis report containing unused declarations
    ///   - filePattern: The glob pattern to match file paths
    /// - Returns: An array of report items with matching file paths
    func filter(report: Report, byFilePattern filePattern: String) -> [ReportItem] {
        let criteria = FilterCriteria(filePattern: filePattern)
        return filter(report: report, criteria: criteria)
    }

    /// Filters items by name pattern
    /// - Parameters:
    ///   - report: The analysis report containing unused declarations
    ///   - namePattern: The regex pattern to match names
    /// - Returns: An array of report items with matching names
    func filter(report: Report, byNamePattern namePattern: String) -> [ReportItem] {
        let criteria = FilterCriteria(namePattern: namePattern)
        return filter(report: report, criteria: criteria)
    }

    /// Returns a summary of the filtered items
    /// - Parameter items: The filtered items
    /// - Returns: A tuple containing counts by type
    func summary(_ items: [ReportItem]) -> (functions: Int, variables: Int, classes: Int, enumCases: Int, protocols: Int) {
        let functions = items.filter { $0.type == .function }.count
        let variables = items.filter { $0.type == .variable }.count
        let classes = items.filter { $0.type == .class }.count
        let enumCases = items.filter { $0.type == .enumCase }.count
        let protocols = items.filter { $0.type == .protocol }.count
        return (functions, variables, classes, enumCases, protocols)
    }
}

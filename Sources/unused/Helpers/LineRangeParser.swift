//
//  Created by Fernando Romiti on 01/02/2026.
//

import Foundation

enum LineRangeParserError: Error, LocalizedError {
    case invalidFormat(String)
    case invalidNumber(String)
    case invalidRange(String)
    case emptyInput

    var errorDescription: String? {
        switch self {
        case .invalidFormat(let input):
            return "Invalid format: '\(input)'. Expected numbers or ranges like '1-3 5 7-9'."
        case .invalidNumber(let input):
            return "Invalid number: '\(input)'."
        case .invalidRange(let input):
            return "Invalid range: '\(input)'. Start must be less than or equal to end."
        case .emptyInput:
            return "Empty input provided."
        }
    }
}

struct LineRangeParser {

    /// Parses a string containing numbers and ranges into a set of integers
    /// - Parameter input: A string like '1-3 5 7-9' or '1,2,3' or '1-3, 5, 7-9'
    /// - Returns: A set of integers represented by the input
    /// - Throws: LineRangeParserError if the input is invalid
    static func parse(_ input: String) throws -> Set<Int> {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            throw LineRangeParserError.emptyInput
        }

        var result = Set<Int>()

        // Split by spaces and/or commas
        let components = trimmed
            .replacing(",", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .map { String($0) }

        for component in components {
            if component.contains("-") {
                let rangeParts = component.split(separator: "-", omittingEmptySubsequences: false)

                guard rangeParts.count == 2 else {
                    throw LineRangeParserError.invalidFormat(component)
                }

                guard let start = Int(rangeParts[0]),
                      let end = Int(rangeParts[1]) else {
                    throw LineRangeParserError.invalidNumber(component)
                }

                guard start <= end else {
                    throw LineRangeParserError.invalidRange(component)
                }

                for i in start...end {
                    result.insert(i)
                }
            } else {
                guard let number = Int(component) else {
                    throw LineRangeParserError.invalidNumber(component)
                }
                result.insert(number)
            }
        }

        return result
    }

    /// Parses a string and returns an array of integers, sorted in ascending order
    /// - Parameter input: A string like '1-3 5 7-9'
    /// - Returns: A sorted array of integers
    /// - Throws: LineRangeParserError if the input is invalid
    static func parseSorted(_ input: String) throws -> [Int] {
        try parse(input).sorted()
    }

    /// Validates that all parsed numbers are within a valid range
    /// - Parameters:
    ///   - input: A string like '1-3 5 7-9'
    ///   - validRange: The range of valid values (e.g., 1...100)
    /// - Returns: A set of integers within the valid range
    /// - Throws: LineRangeParserError if the input is invalid
    static func parse(_ input: String, validRange: ClosedRange<Int>) throws -> Set<Int> {
        let parsed = try parse(input)
        return parsed.filter { validRange.contains($0) }
    }
}

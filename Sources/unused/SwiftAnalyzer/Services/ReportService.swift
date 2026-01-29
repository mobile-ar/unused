//
//  Created by Fernando Romiti on 25/01/2026.
//

import Foundation

/// Service for reading and writing analysis reports in JSON format
struct ReportService {

    /// The filename used for storing the analysis report
    static let reportFileName = ".unused.json"

    /// Writes an analysis report to the specified directory as JSON
    /// - Parameters:
    ///   - report: The analysis report to write
    ///   - directory: The directory path where the report file will be created
    /// - Throws: An error if the file cannot be written
    static func write(report: Report, to directory: String) throws {
        let directoryURL = URL(fileURLWithPath: directory)
        let outputURL = directoryURL.appendingPathComponent(reportFileName)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let jsonData = try encoder.encode(report)
        try jsonData.write(to: outputURL)
    }

    /// Reads an analysis report from the specified directory
    /// - Parameter directory: The directory path containing the report file
    /// - Returns: The decoded analysis report
    /// - Throws: An error if the file cannot be read or decoded
    static func read(from directory: String) throws -> Report {
        let directoryURL = URL(fileURLWithPath: directory)
        let inputURL = directoryURL.appendingPathComponent(reportFileName)

        let jsonData = try Data(contentsOf: inputURL)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try decoder.decode(Report.self, from: jsonData)
    }

    /// Checks if a report file exists in the specified directory
    /// - Parameter directory: The directory path to check
    /// - Returns: `true` if the report file exists, `false` otherwise
    static func reportExists(in directory: String) -> Bool {
        let directoryURL = URL(fileURLWithPath: directory)
        let reportURL = directoryURL.appendingPathComponent(reportFileName)
        return FileManager.default.fileExists(atPath: reportURL.path)
    }

}

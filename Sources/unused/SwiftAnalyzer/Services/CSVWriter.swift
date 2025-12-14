//
//  Created by Fernando Romiti on 06/12/2025.
//

import Foundation

struct CSVWriter {

    static func write(report: [Declaration], to directory: String) throws {
        let directoryURL = URL(fileURLWithPath: directory)
        let outputURL = directoryURL.appendingPathComponent(".unused")

        var csvContent = "id,name,type,file,line,exclusionReason,parentType\n"

        for (index, declaration) in report.enumerated() {
            csvContent += declaration.toCSV(id: index + 1) + "\n"
        }

        try csvContent.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    static func read(from directory: String) throws -> [(id: Int, declaration: Declaration)] {
        let directoryURL = URL(fileURLWithPath: directory)
        let inputURL = directoryURL.appendingPathComponent(".unused")

        let csvContent = try String(contentsOf: inputURL, encoding: .utf8)
        let lines = csvContent.components(separatedBy: .newlines)

        guard lines.count > 1 else {
            return []
        }

        var results: [(Int, Declaration)] = []

        for line in lines.dropFirst() where !line.isEmpty {
            guard let parsed = parseCSVLine(line) else {
                continue
            }
            results.append(parsed)
        }

        return results
    }

    private static func parseCSVLine(_ line: String) -> (Int, Declaration)? {
        var fields: [String] = []
        var currentField = ""
        var insideQuotes = false
        var i = line.startIndex

        while i < line.endIndex {
            let char = line[i]

            if char == "\"" {
                if insideQuotes {
                    let nextIndex = line.index(after: i)
                    if nextIndex < line.endIndex && line[nextIndex] == "\"" {
                        currentField.append("\"")
                        i = nextIndex
                    } else {
                        insideQuotes = false
                    }
                } else {
                    insideQuotes = true
                }
            } else if char == "," && !insideQuotes {
                fields.append(currentField)
                currentField = ""
            } else {
                currentField.append(char)
            }

            i = line.index(after: i)
        }
        fields.append(currentField)

        guard fields.count == 7,
            let id = Int(fields[0]),
            let line = Int(fields[4])
        else {
            return nil
        }

        let name = fields[1]
        let typeString = fields[2]
        let file = fields[3]
        let reasonString = fields[5]
        let parentType = fields[6].isEmpty ? nil : fields[6]

        guard let type = DeclarationType(rawValue: typeString) else { return nil }
        guard let exclusionReason = ExclusionReason(rawValue: reasonString) else { return nil }

        let declaration = Declaration(
            name: name,
            type: type,
            file: file,
            line: line,
            exclusionReason: exclusionReason,
            parentType: parentType
        )

        return (id, declaration)
    }

}

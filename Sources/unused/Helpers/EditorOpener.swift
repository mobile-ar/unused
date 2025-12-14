//
//  Created by Fernando Romiti on 14/12/2025.
//

import ArgumentParser
import Foundation

enum Editor {
    case xcode
    case zed

    var executable: String {
        switch self {
        case .xcode:
            return "/usr/bin/xed"
        case .zed:
            return "/usr/local/bin/zed"
        }
    }

    func arguments(filePath: String, lineNumber: Int) -> [String] {
        switch self {
        case .xcode:
            return ["-l", "\(lineNumber)", filePath]
        case .zed:
            return ["\(filePath):\(lineNumber)"]
        }
    }
}

struct EditorOpener {

    static func open(
        id: Int,
        inDirectory directory: String,
        using editor: Editor
    ) throws {
        let directoryURL = URL(fileURLWithPath: directory)

        guard let resourceValues = try? directoryURL.resourceValues(forKeys: [.isDirectoryKey]),
            let isDirectory = resourceValues.isDirectory,
            isDirectory
        else {
            throw ValidationError("Directory does not exist: \(directory)".red)
        }

        let unusedFilePath = directoryURL.appendingPathComponent(".unused").path
        guard FileManager.default.fileExists(atPath: unusedFilePath) else {
            throw ValidationError(
                ".unused file not found in directory: \(directory)".red
                    + "\nRun 'unused analyze' first.".peach)
        }

        let declarations = try CSVWriter.read(from: directory)

        guard let entry = declarations.first(where: { $0.id == id }) else {
            throw ValidationError(
                "ID \(id) not found in .unused file.".red
                    + " Valid IDs: 1-\(declarations.count)".peach)
        }

        let filePath = entry.declaration.file
        let lineNumber = entry.declaration.line

        let task = Process()
        task.executableURL = URL(fileURLWithPath: editor.executable)
        task.arguments = editor.arguments(filePath: filePath, lineNumber: lineNumber)

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus == 0 {
                print("Opened \(filePath) at line \(lineNumber)".green)
            } else {
                throw ValidationError("Failed to open file with \(editor.executable)".red)
            }
        } catch {
            throw ValidationError(
                "Error executing \(editor.executable): \(error.localizedDescription)".red)
        }
    }
}

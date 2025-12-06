//
//  Created by Fernando Romiti on 06/12/2025.
//

import ArgumentParser
import Foundation

struct Open: ParsableCommand {
    
    static let configuration = CommandConfiguration(
        abstract: "Open an unused declaration in Xcode by its ID"
    )
    
    @Argument(help: "The directory containing the .unused file")
    var directory: String
    
    @Argument(help: "The ID of the unused declaration to open")
    var open: Int
    
    func run() throws {
        let directoryURL = URL(fileURLWithPath: directory)
        
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ValidationError("Directory does not exist: \(directory)")
        }
        
        let unusedFilePath = directoryURL.appendingPathComponent(".unused").path
        guard FileManager.default.fileExists(atPath: unusedFilePath) else {
            throw ValidationError(".unused file not found in directory: \(directory)\nRun 'unused analyze' first.")
        }
        
        let declarations = try CSVWriter.read(from: directory)
        
        guard let entry = declarations.first(where: { $0.id == open }) else {
            throw ValidationError("ID \(open) not found in .unused file. Valid IDs: 1-\(declarations.count)")
        }
        
        let filePath = entry.declaration.file
        let lineNumber = entry.declaration.line
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/xed")
        task.arguments = ["-l", "\(lineNumber)", filePath]
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if task.terminationStatus == 0 {
                print("Opened \(filePath) at line \(lineNumber)".green)
            } else {
                throw ValidationError("Failed to open file with xed")
            }
        } catch {
            throw ValidationError("Error executing xed: \(error.localizedDescription)")
        }
    }
    
}

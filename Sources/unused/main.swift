//
//  Created by Fernando Romiti on 09/10/2024.
//

import Foundation

print("Running SwiftAnalyzer...".blue.bold)
let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    print("Usage: unused <directory>".yellow)
    exit(1)
}

let pathString = arguments[1]
let directoryURL = URL(fileURLWithPath: pathString)
let swiftFiles = getSwiftFiles(in: directoryURL)

print("Found \(swiftFiles.count) Swift files".teal)

let analyzer = SwiftAnalyzer()
analyzer.analyzeFiles(swiftFiles)

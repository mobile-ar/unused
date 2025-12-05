//
//  Created by Fernando Romiti on 09/10/2024.
//

import Foundation

print("Unused v0.0.1".blue.bold)
let arguments = CommandLine.arguments

// Check for help flag
if arguments.contains("--help") || arguments.contains("-h") {
    print("""
    Usage: unused <directory> [options]
    
    Options:
      --include-overrides    Include override methods in the results
      --include-protocols    Include protocol implementations in the results
      --include-objc         Include @objc/@IBAction/@IBOutlet items in the results
      --show-excluded        Show detailed list of all excluded items
      --help, -h             Show this help message
    
    By default, overrides, protocol implementations, and framework callbacks are
    excluded from the results as they are typically called by the framework/runtime.
    """.teal)
    exit(0)
}

if arguments.count > 1 {
    print("Running unused ...")
} else {
    print("Usage: unused <directory> [options]".yellow)
    print("Use --help for more information".gray)
    exit(1)
}

let pathString = arguments[1]
let directoryURL = URL(fileURLWithPath: pathString)
let swiftFiles = getSwiftFiles(in: directoryURL)

print("Found \(swiftFiles.count) Swift files".teal)

let options = AnalyzerOptions(arguments: arguments)
let analyzer = SwiftAnalyzer(options: options)
analyzer.analyzeFiles(swiftFiles)

//
//  main.swift
//  unused
//
//  Created by Fernando Romiti on 09/10/2024.
//

import Foundation

//print("Running unused...")

//Unused().find()

print("Running SwiftAnalyzer...")
let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    print("Usage: SwiftAnalyzerCLI <directory>")
    exit(1)
}

let directoryURL = URL(fileURLWithPath: arguments[1])
let swiftFiles = getSwiftFiles(in: directoryURL)

for file in swiftFiles {
    analyzeFile(at: file)
}

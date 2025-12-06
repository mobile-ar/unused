//
//  OpenCommandTests.swift
//  unused
//
//  Created by Fernando Romiti on 05/12/2025.
//

import Testing
import Foundation
@testable import unused

struct OpenCommandTests {
    
    @Test func testCSVWorkflowForOpenCommand() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let testFile = tempDir.appendingPathComponent("test.swift")
        try "// test file".write(to: testFile, atomically: true, encoding: .utf8)
        
        let declarations = [
            Declaration(
                name: "testFunction",
                type: .function,
                file: testFile.path,
                line: 1,
                exclusionReason: .none,
                parentType: nil
            )
        ]
        
        try CSVWriter.write(report: declarations, to: tempDir.path)
        
        let csvContent = try String(contentsOf: tempDir.appendingPathComponent(".unused"), encoding: .utf8)
        #expect(csvContent.contains("testFunction"))
        #expect(csvContent.contains(testFile.path))
    }
    
    @Test func testReadCSVForOpenCommand() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let declarations = [
            Declaration(
                name: "firstFunction",
                type: .function,
                file: "/path/to/file1.swift",
                line: 10,
                exclusionReason: .none,
                parentType: nil
            ),
            Declaration(
                name: "secondFunction",
                type: .function,
                file: "/path/to/file2.swift",
                line: 20,
                exclusionReason: .none,
                parentType: nil
            ),
            Declaration(
                name: "thirdFunction",
                type: .function,
                file: "/path/to/file3.swift",
                line: 30,
                exclusionReason: .none,
                parentType: nil
            )
        ]
        
        try CSVWriter.write(report: declarations, to: tempDir.path)
        let results = try CSVWriter.read(from: tempDir.path)
        
        #expect(results.count == 3)
        
        let entry = results.first(where: { $0.id == 2 })
        #expect(entry != nil)
        #expect(entry?.declaration.name == "secondFunction")
        #expect(entry?.declaration.file == "/path/to/file2.swift")
        #expect(entry?.declaration.line == 20)
    }
    
    @Test func testInvalidIDLookup() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let declarations = [
            Declaration(
                name: "testFunction",
                type: .function,
                file: "/path/to/file.swift",
                line: 1,
                exclusionReason: .none,
                parentType: nil
            )
        ]
        
        try CSVWriter.write(report: declarations, to: tempDir.path)
        let results = try CSVWriter.read(from: tempDir.path)
        
        let entry = results.first(where: { $0.id == 999 })
        #expect(entry == nil)
    }
    
    @Test func testValidIDLookup() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let declarations = [
            Declaration(
                name: "testFunction",
                type: .function,
                file: "/path/to/file.swift",
                line: 42,
                exclusionReason: .none,
                parentType: nil
            )
        ]
        
        try CSVWriter.write(report: declarations, to: tempDir.path)
        let results = try CSVWriter.read(from: tempDir.path)
        
        let entry = results.first(where: { $0.id == 1 })
        #expect(entry != nil)
        #expect(entry?.declaration.name == "testFunction")
        #expect(entry?.declaration.line == 42)
    }
    
    @Test func testMultipleDeclarationsIDSequence() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let declarations = [
            Declaration(name: "func1", type: .function, file: "/file1.swift", line: 1, exclusionReason: .none, parentType: nil),
            Declaration(name: "func2", type: .function, file: "/file2.swift", line: 2, exclusionReason: .none, parentType: nil),
            Declaration(name: "func3", type: .function, file: "/file3.swift", line: 3, exclusionReason: .none, parentType: nil),
            Declaration(name: "func4", type: .function, file: "/file4.swift", line: 4, exclusionReason: .none, parentType: nil),
            Declaration(name: "func5", type: .function, file: "/file5.swift", line: 5, exclusionReason: .none, parentType: nil)
        ]
        
        try CSVWriter.write(report: declarations, to: tempDir.path)
        let results = try CSVWriter.read(from: tempDir.path)
        
        #expect(results.count == 5)
        
        for i in 1...5 {
            let entry = results.first(where: { $0.id == i })
            #expect(entry != nil)
            #expect(entry?.declaration.name == "func\(i)")
            #expect(entry?.declaration.line == i)
        }
    }
    
}

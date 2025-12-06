//
//  CSVWriterTests.swift
//  unused
//
//  Created by Fernando Romiti on 05/12/2025.
//

import Testing
import Foundation
@testable import unused

struct CSVWriterTests {
    
    @Test func testWriteCSV() async throws {
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
                line: 10,
                exclusionReason: .none,
                parentType: nil
            ),
            Declaration(
                name: "testVariable",
                type: .variable,
                file: "/path/to/another.swift",
                line: 25,
                exclusionReason: .override,
                parentType: "TestClass"
            )
        ]
        
        try CSVWriter.write(report: declarations, to: tempDir.path)
        
        let outputPath = tempDir.appendingPathComponent(".unused")
        #expect(FileManager.default.fileExists(atPath: outputPath.path))
        
        let content = try String(contentsOf: outputPath, encoding: .utf8)
        #expect(content.contains("id,name,type,file,line,exclusionReason,parentType"))
        #expect(content.contains("testFunction"))
        #expect(content.contains("testVariable"))
    }
    
    @Test func testReadCSV() async throws {
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
                line: 10,
                exclusionReason: .none,
                parentType: nil
            ),
            Declaration(
                name: "testVariable",
                type: .variable,
                file: "/path/to/another.swift",
                line: 25,
                exclusionReason: .override,
                parentType: "TestClass"
            )
        ]
        
        try CSVWriter.write(report: declarations, to: tempDir.path)
        let results = try CSVWriter.read(from: tempDir.path)
        
        #expect(results.count == 2)
        #expect(results[0].id == 1)
        #expect(results[0].declaration.name == "testFunction")
        #expect(results[0].declaration.type == .function)
        #expect(results[0].declaration.line == 10)
        #expect(results[1].id == 2)
        #expect(results[1].declaration.name == "testVariable")
        #expect(results[1].declaration.type == .variable)
    }
    
    @Test func testCSVEscaping() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let declarations = [
            Declaration(
                name: "test\"Function",
                type: .function,
                file: "/path/to/\"file\".swift",
                line: 10,
                exclusionReason: .none,
                parentType: nil
            )
        ]
        
        try CSVWriter.write(report: declarations, to: tempDir.path)
        let results = try CSVWriter.read(from: tempDir.path)
        
        #expect(results.count == 1)
        #expect(results[0].declaration.name == "test\"Function")
        #expect(results[0].declaration.file == "/path/to/\"file\".swift")
    }
    
    @Test func testReadNonExistentFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        #expect(throws: Error.self) {
            try CSVWriter.read(from: tempDir.path)
        }
    }
    
    @Test func testEmptyDeclarations() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let declarations: [Declaration] = []
        
        try CSVWriter.write(report: declarations, to: tempDir.path)
        let results = try CSVWriter.read(from: tempDir.path)
        
        #expect(results.isEmpty)
    }
    
    @Test func testAllDeclarationTypes() async throws {
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
                line: 10,
                exclusionReason: .none,
                parentType: nil
            ),
            Declaration(
                name: "testVariable",
                type: .variable,
                file: "/path/to/file.swift",
                line: 20,
                exclusionReason: .none,
                parentType: nil
            ),
            Declaration(
                name: "TestClass",
                type: .class,
                file: "/path/to/file.swift",
                line: 30,
                exclusionReason: .none,
                parentType: nil
            )
        ]
        
        try CSVWriter.write(report: declarations, to: tempDir.path)
        let results = try CSVWriter.read(from: tempDir.path)
        
        #expect(results.count == 3)
        #expect(results[0].declaration.type == .function)
        #expect(results[1].declaration.type == .variable)
        #expect(results[2].declaration.type == .class)
    }
    
    @Test func testAllExclusionReasons() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let declarations = [
            Declaration(
                name: "test1",
                type: .function,
                file: "/path/to/file.swift",
                line: 10,
                exclusionReason: .none,
                parentType: nil
            ),
            Declaration(
                name: "test2",
                type: .function,
                file: "/path/to/file.swift",
                line: 20,
                exclusionReason: .override,
                parentType: nil
            ),
            Declaration(
                name: "test3",
                type: .function,
                file: "/path/to/file.swift",
                line: 30,
                exclusionReason: .protocolImplementation,
                parentType: nil
            ),
            Declaration(
                name: "test4",
                type: .function,
                file: "/path/to/file.swift",
                line: 40,
                exclusionReason: .objcAttribute,
                parentType: nil
            ),
            Declaration(
                name: "test5",
                type: .function,
                file: "/path/to/file.swift",
                line: 50,
                exclusionReason: .ibAction,
                parentType: nil
            ),
            Declaration(
                name: "test6",
                type: .function,
                file: "/path/to/file.swift",
                line: 60,
                exclusionReason: .ibOutlet,
                parentType: nil
            )
        ]
        
        try CSVWriter.write(report: declarations, to: tempDir.path)
        let results = try CSVWriter.read(from: tempDir.path)
        
        #expect(results.count == 6)
        #expect(results[0].declaration.exclusionReason == .none)
        #expect(results[1].declaration.exclusionReason == .override)
        #expect(results[2].declaration.exclusionReason == .protocolImplementation)
        #expect(results[3].declaration.exclusionReason == .objcAttribute)
        #expect(results[4].declaration.exclusionReason == .ibAction)
        #expect(results[5].declaration.exclusionReason == .ibOutlet)
    }
    
}

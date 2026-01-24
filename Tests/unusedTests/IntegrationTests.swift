//
//  Created by Fernando Romiti on 05/12/2025.
//

import Testing
import Foundation
@testable import unused

struct IntegrationTests {
    
    @Test func testCompleteWorkflow() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let testSwiftFile = tempDir.appendingPathComponent("Test.swift")
        let swiftContent = """
        class TestClass {
            func usedFunction() {
                print("Hello")
            }
            
            func unusedFunction() {
                print("Never called")
            }
            
            var usedVariable = "used"
            var unusedVariable = "unused"
        }
        
        let instance = TestClass()
        instance.usedFunction()
        print(instance.usedVariable)
        """
        
        try swiftContent.write(to: testSwiftFile, atomically: true, encoding: .utf8)
        
        let options = AnalyzerOptions(
            includeOverrides: false,
            includeProtocols: false,
            includeObjc: false,
            showExcluded: false
        )
        
        let analyzer = SwiftAnalyzer(options: options, directory: tempDir.path)
        await analyzer.analyzeFiles([testSwiftFile])
        
        let unusedFilePath = tempDir.appendingPathComponent(".unused")
        #expect(FileManager.default.fileExists(atPath: unusedFilePath.path))
        
        let csvContent = try String(contentsOf: unusedFilePath, encoding: .utf8)
        #expect(csvContent.contains("id,name,type,file,line,exclusionReason,parentType"))
        
        let declarations = try CSVWriter.read(from: tempDir.path)
        #expect(declarations.count > 0)
        
        let hasUnusedFunction = declarations.contains { $0.declaration.name.contains("unused") && $0.declaration.type == .function }
        let hasUnusedVariable = declarations.contains { $0.declaration.name.contains("unused") && $0.declaration.type == .variable }
        
        #expect(hasUnusedFunction || hasUnusedVariable)
    }
    
    @Test func testCSVPersistence() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let declarations = [
            Declaration(
                name: "testFunc1",
                type: .function,
                file: "/test/file1.swift",
                line: 10,
                exclusionReason: .none,
                parentType: nil
            ),
            Declaration(
                name: "testFunc2",
                type: .function,
                file: "/test/file2.swift",
                line: 20,
                exclusionReason: .override,
                parentType: "MyClass"
            ),
            Declaration(
                name: "testVar",
                type: .variable,
                file: "/test/file3.swift",
                line: 30,
                exclusionReason: .protocolImplementation,
                parentType: nil
            )
        ]
        
        try CSVWriter.write(report: declarations, to: tempDir.path)
        
        let readDeclarations = try CSVWriter.read(from: tempDir.path)
        
        #expect(readDeclarations.count == 3)
        
        for (index, original) in declarations.enumerated() {
            let read = readDeclarations[index]
            #expect(read.id == index + 1)
            #expect(read.declaration.name == original.name)
            #expect(read.declaration.type == original.type)
            #expect(read.declaration.file == original.file)
            #expect(read.declaration.line == original.line)
            #expect(read.declaration.exclusionReason == original.exclusionReason)
            #expect(read.declaration.parentType == original.parentType)
        }
    }
    
    @Test func testOpenCommandWorkflow() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let testFile = tempDir.appendingPathComponent("RealFile.swift")
        try "// Real Swift File\nfunc realFunction() {}\n".write(to: testFile, atomically: true, encoding: .utf8)
        
        let declarations = [
            Declaration(
                name: "realFunction",
                type: .function,
                file: testFile.path,
                line: 2,
                exclusionReason: .none,
                parentType: nil
            ),
            Declaration(
                name: "anotherFunction",
                type: .function,
                file: testFile.path,
                line: 3,
                exclusionReason: .none,
                parentType: nil
            )
        ]
        
        try CSVWriter.write(report: declarations, to: tempDir.path)
        
        let results = try CSVWriter.read(from: tempDir.path)
        
        #expect(results.count == 2)
        
        let firstEntry = results.first(where: { $0.id == 1 })
        #expect(firstEntry != nil)
        #expect(firstEntry?.declaration.name == "realFunction")
        #expect(firstEntry?.declaration.file == testFile.path)
        #expect(firstEntry?.declaration.line == 2)
        
        let secondEntry = results.first(where: { $0.id == 2 })
        #expect(secondEntry != nil)
        #expect(secondEntry?.declaration.name == "anotherFunction")
    }
    
    @Test func testLargeDataset() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        var declarations: [Declaration] = []
        for i in 1...100 {
            declarations.append(
                Declaration(
                    name: "function\(i)",
                    type: .function,
                    file: "/path/to/file\(i).swift",
                    line: i * 10,
                    exclusionReason: .none,
                    parentType: nil
                )
            )
        }
        
        try CSVWriter.write(report: declarations, to: tempDir.path)
        let results = try CSVWriter.read(from: tempDir.path)
        
        #expect(results.count == 100)
        
        for i in 1...100 {
            let entry = results.first(where: { $0.id == i })
            #expect(entry != nil)
            #expect(entry?.declaration.name == "function\(i)")
            #expect(entry?.declaration.line == i * 10)
        }
    }
    
}

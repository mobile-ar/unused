//
//  Created by Fernando Romiti on 05/12/2025.
//

import Testing
import Foundation
@testable import unused

struct FileHelperTests {
    
    @Test func testGetSwiftFilesReturnsOnlySwiftFiles() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let swiftFile1 = tempDir.appendingPathComponent("File1.swift")
        try "// swift file 1".write(to: swiftFile1, atomically: true, encoding: .utf8)
        
        let swiftFile2 = tempDir.appendingPathComponent("File2.swift")
        try "// swift file 2".write(to: swiftFile2, atomically: true, encoding: .utf8)
        
        let textFile = tempDir.appendingPathComponent("README.txt")
        try "readme".write(to: textFile, atomically: true, encoding: .utf8)
        
        let jsonFile = tempDir.appendingPathComponent("config.json")
        try "{}".write(to: jsonFile, atomically: true, encoding: .utf8)
        
        let files = getSwiftFiles(in: tempDir, includeTests: true)
        
        #expect(files.count == 2)
        #expect(files.allSatisfy { $0.pathExtension == "swift" })
    }
    
    @Test func testGetSwiftFilesExcludesBuildDirectory() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let regularFile = tempDir.appendingPathComponent("Regular.swift")
        try "// regular".write(to: regularFile, atomically: true, encoding: .utf8)
        
        let buildDir = tempDir.appendingPathComponent(".build")
        try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)
        let buildFile = buildDir.appendingPathComponent("Build.swift")
        try "// build file".write(to: buildFile, atomically: true, encoding: .utf8)
        
        let files = getSwiftFiles(in: tempDir, includeTests: true)
        
        #expect(files.count == 1)
        #expect(files.first?.lastPathComponent == "Regular.swift")
    }
    
    @Test func testGetSwiftFilesExcludesTestFilesByDefault() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let regularFile = tempDir.appendingPathComponent("Regular.swift")
        try "// regular".write(to: regularFile, atomically: true, encoding: .utf8)
        
        let testFile = tempDir.appendingPathComponent("RegularTest.swift")
        try "// test".write(to: testFile, atomically: true, encoding: .utf8)
        
        let files = getSwiftFiles(in: tempDir)
        
        #expect(files.count == 1)
        #expect(files.first?.lastPathComponent == "Regular.swift")
    }
    
    @Test func testGetSwiftFilesIncludesTestsWhenRequested() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let regularFile = tempDir.appendingPathComponent("Regular.swift")
        try "// regular".write(to: regularFile, atomically: true, encoding: .utf8)
        
        let testFile = tempDir.appendingPathComponent("RegularTest.swift")
        try "// test".write(to: testFile, atomically: true, encoding: .utf8)
        
        let files = getSwiftFiles(in: tempDir, includeTests: true)
        
        #expect(files.count == 2)
    }
    
    @Test func testIsTestFileDetectsTestInFileName() async throws {
        let url1 = URL(fileURLWithPath: "/path/to/MyTest.swift")
        #expect(isTestFile(url1))
        
        let url2 = URL(fileURLWithPath: "/path/to/MyTests.swift")
        #expect(isTestFile(url2))
        
        let url3 = URL(fileURLWithPath: "/path/to/TestHelper.swift")
        #expect(isTestFile(url3))
        
        let url4 = URL(fileURLWithPath: "/path/to/Regular.swift")
        #expect(!isTestFile(url4))
    }
    
    @Test func testIsTestFileDetectsTestsDirectory() async throws {
        let url1 = URL(fileURLWithPath: "/project/Tests/MyFile.swift")
        #expect(isTestFile(url1))
        
        let url2 = URL(fileURLWithPath: "/project/Tests/Unit/MyFile.swift")
        #expect(isTestFile(url2))
        
        let url3 = URL(fileURLWithPath: "/project/Sources/MyFile.swift")
        #expect(!isTestFile(url3))
    }
    
    @Test func testIsTestFileCombinedConditions() async throws {
        let url1 = URL(fileURLWithPath: "/project/Tests/MyTest.swift")
        #expect(isTestFile(url1))
        
        let url2 = URL(fileURLWithPath: "/project/Sources/MyTests.swift")
        #expect(isTestFile(url2))
        
        let url3 = URL(fileURLWithPath: "/project/Tests/Helper.swift")
        #expect(isTestFile(url3))
        
        let url4 = URL(fileURLWithPath: "/project/Sources/Regular.swift")
        #expect(!isTestFile(url4))
    }
    
    @Test func testGetSwiftFilesHandlesNestedDirectories() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let rootFile = tempDir.appendingPathComponent("Root.swift")
        try "// root".write(to: rootFile, atomically: true, encoding: .utf8)
        
        let srcDir = tempDir.appendingPathComponent("Sources")
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        let srcFile = srcDir.appendingPathComponent("Source.swift")
        try "// source".write(to: srcFile, atomically: true, encoding: .utf8)
        
        let nestedDir = srcDir.appendingPathComponent("Nested")
        try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)
        let nestedFile = nestedDir.appendingPathComponent("Nested.swift")
        try "// nested".write(to: nestedFile, atomically: true, encoding: .utf8)
        
        let files = getSwiftFiles(in: tempDir, includeTests: true)
        
        #expect(files.count == 3)
    }
    
    @Test func testGetSwiftFilesHandlesEmptyDirectory() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let files = getSwiftFiles(in: tempDir, includeTests: true)
        
        #expect(files.isEmpty)
    }
    
    @Test func testGetSwiftFilesExcludesMultipleTestPatterns() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let regularFile = tempDir.appendingPathComponent("Regular.swift")
        try "// regular".write(to: regularFile, atomically: true, encoding: .utf8)
        
        let testFile1 = tempDir.appendingPathComponent("MyTest.swift")
        try "// test 1".write(to: testFile1, atomically: true, encoding: .utf8)
        
        let testFile2 = tempDir.appendingPathComponent("MyTests.swift")
        try "// test 2".write(to: testFile2, atomically: true, encoding: .utf8)
        
        let testsDir = tempDir.appendingPathComponent("Tests")
        try FileManager.default.createDirectory(at: testsDir, withIntermediateDirectories: true)
        let testFile3 = testsDir.appendingPathComponent("SomeFile.swift")
        try "// test 3".write(to: testFile3, atomically: true, encoding: .utf8)
        
        let files = getSwiftFiles(in: tempDir)
        
        #expect(files.count == 1)
        #expect(files.first?.lastPathComponent == "Regular.swift")
    }
    
    @Test func testIsTestFileDetectsXCTestImport() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let testFile = tempDir.appendingPathComponent("MyFile.swift")
        try """
        import Foundation
        import XCTest
        
        class MyFileTests: XCTestCase {
            func testSomething() {}
        }
        """.write(to: testFile, atomically: true, encoding: .utf8)
        
        #expect(isTestFile(testFile))
    }
    
    @Test func testIsTestFileDetectsTestingImport() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let testFile = tempDir.appendingPathComponent("MyFile.swift")
        try """
        import Foundation
        import Testing
        
        struct MyFileTests {
            @Test func something() {}
        }
        """.write(to: testFile, atomically: true, encoding: .utf8)
        
        #expect(isTestFile(testFile))
    }
    
    @Test func testIsTestFileDetectsTestableImportWithXCTest() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let testFile = tempDir.appendingPathComponent("MyFile.swift")
        try """
        import XCTest
        @testable import MyModule
        
        class MyFileTests: XCTestCase {
            func testSomething() {}
        }
        """.write(to: testFile, atomically: true, encoding: .utf8)
        
        #expect(isTestFile(testFile))
    }
    
    @Test func testIsTestFileIgnoresNonTestImports() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let regularFile = tempDir.appendingPathComponent("MyFile.swift")
        try """
        import Foundation
        import SwiftUI
        
        struct MyView: View {
            var body: some View { Text("Hello") }
        }
        """.write(to: regularFile, atomically: true, encoding: .utf8)
        
        #expect(!isTestFile(regularFile))
    }
    
    @Test func testIsTestFileDetectsImportAmongMultipleImports() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let testFile = tempDir.appendingPathComponent("MyFile.swift")
        try """
        import Foundation
        import SwiftUI
        import Combine
        import Testing
        @testable import MyModule
        
        struct MyFileTests {
            @Test func something() {}
        }
        """.write(to: testFile, atomically: true, encoding: .utf8)
        
        #expect(isTestFile(testFile))
    }
    
    @Test func testIsTestFileWithTestInNameButNoImports() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let testFile = tempDir.appendingPathComponent("MyTest.swift")
        try """
        import Foundation
        
        struct MyTest {
            let value: String
        }
        """.write(to: testFile, atomically: true, encoding: .utf8)
        
        #expect(isTestFile(testFile))
    }
    
    @Test func testIsTestFileWithTestsInNameButNoImports() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let testFile = tempDir.appendingPathComponent("UserTests.swift")
        try """
        import Foundation
        
        class UserTests {
            var username: String
        }
        """.write(to: testFile, atomically: true, encoding: .utf8)
        
        #expect(isTestFile(testFile))
    }
}

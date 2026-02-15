//
//  Created by Fernando Romiti on 14/02/2026.
//

import Testing
import Foundation
@testable import unused

struct SwiftAnalyzerDependencyProtocolTests {

    @Test func testFindsProtocolAtEndOfFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        let checkoutsDir = tempDir.appendingPathComponent(".build/checkouts/SomePackage/Sources")
        try FileManager.default.createDirectory(at: checkoutsDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let largePrefix = String(repeating: "// This is a long comment line to pad the file\n", count: 200)
        let swiftContent = """
        \(largePrefix)
        struct SomeStruct {
            var name: String
        }

        protocol LateProtocol {
            func doSomething()
        }
        """

        let swiftFile = checkoutsDir.appendingPathComponent("LateProtocol.swift")
        try swiftContent.write(to: swiftFile, atomically: true, encoding: .utf8)

        let fileData = try Data(contentsOf: swiftFile)
        #expect(fileData.count > 4096, "Test file must be larger than 4KB to validate the fix")

        let analyzer = SwiftAnalyzer(directory: tempDir.path)
        let result = analyzer.parseDependencyProtocolFiles(in: tempDir.path)

        #expect(result.map(\.url.standardizedFileURL).contains(swiftFile.standardizedFileURL))
    }

    @Test func testFindsProtocolAtBeginningOfFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        let checkoutsDir = tempDir.appendingPathComponent(".build/checkouts/SomePackage/Sources")
        try FileManager.default.createDirectory(at: checkoutsDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let swiftContent = """
        protocol EarlyProtocol {
            func doSomething()
        }
        """

        let swiftFile = checkoutsDir.appendingPathComponent("EarlyProtocol.swift")
        try swiftContent.write(to: swiftFile, atomically: true, encoding: .utf8)

        let analyzer = SwiftAnalyzer(directory: tempDir.path)
        let result = analyzer.parseDependencyProtocolFiles(in: tempDir.path)

        #expect(result.map(\.url.standardizedFileURL).contains(swiftFile.standardizedFileURL))
    }

    @Test func testExcludesFileWithNoProtocol() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        let checkoutsDir = tempDir.appendingPathComponent(".build/checkouts/SomePackage/Sources")
        try FileManager.default.createDirectory(at: checkoutsDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let swiftContent = """
        struct PlainStruct {
            var name: String
        }
        """

        let swiftFile = checkoutsDir.appendingPathComponent("PlainStruct.swift")
        try swiftContent.write(to: swiftFile, atomically: true, encoding: .utf8)

        let analyzer = SwiftAnalyzer(directory: tempDir.path)
        let result = analyzer.parseDependencyProtocolFiles(in: tempDir.path)

        #expect(!result.map(\.url.standardizedFileURL).contains(swiftFile.standardizedFileURL))
    }

    @Test func testExcludesTestFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        let testsDir = tempDir.appendingPathComponent(".build/checkouts/SomePackage/Tests")
        try FileManager.default.createDirectory(at: testsDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let swiftContent = """
        protocol TestProtocol {
            func verify()
        }
        """

        let swiftFile = testsDir.appendingPathComponent("TestProtocol.swift")
        try swiftContent.write(to: swiftFile, atomically: true, encoding: .utf8)

        let analyzer = SwiftAnalyzer(directory: tempDir.path)
        let result = analyzer.parseDependencyProtocolFiles(in: tempDir.path)

        #expect(!result.map(\.url.standardizedFileURL).contains(swiftFile.standardizedFileURL))
    }

    @Test func testExcludesBenchmarkFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        let benchmarksDir = tempDir.appendingPathComponent(".build/checkouts/SomePackage/Benchmarks")
        try FileManager.default.createDirectory(at: benchmarksDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let swiftContent = """
        protocol BenchmarkProtocol {
            func run()
        }
        """

        let swiftFile = benchmarksDir.appendingPathComponent("BenchmarkProtocol.swift")
        try swiftContent.write(to: swiftFile, atomically: true, encoding: .utf8)

        let analyzer = SwiftAnalyzer(directory: tempDir.path)
        let result = analyzer.parseDependencyProtocolFiles(in: tempDir.path)

        #expect(!result.map(\.url.standardizedFileURL).contains(swiftFile.standardizedFileURL))
    }

    @Test func testExcludesExampleFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        let examplesDir = tempDir.appendingPathComponent(".build/checkouts/SomePackage/Examples")
        try FileManager.default.createDirectory(at: examplesDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let swiftContent = """
        protocol ExampleProtocol {
            func example()
        }
        """

        let swiftFile = examplesDir.appendingPathComponent("ExampleProtocol.swift")
        try swiftContent.write(to: swiftFile, atomically: true, encoding: .utf8)

        let analyzer = SwiftAnalyzer(directory: tempDir.path)
        let result = analyzer.parseDependencyProtocolFiles(in: tempDir.path)

        #expect(!result.map(\.url.standardizedFileURL).contains(swiftFile.standardizedFileURL))
    }

    @Test func testReturnsEmptyWhenNoCheckoutsDirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let analyzer = SwiftAnalyzer(directory: tempDir.path)
        let result = analyzer.parseDependencyProtocolFiles(in: tempDir.path)

        #expect(result.isEmpty)
    }

    @Test func testIgnoresNonSwiftFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        let checkoutsDir = tempDir.appendingPathComponent(".build/checkouts/SomePackage/Sources")
        try FileManager.default.createDirectory(at: checkoutsDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let content = """
        protocol SomeProtocol {
            func doSomething()
        }
        """

        let txtFile = checkoutsDir.appendingPathComponent("NotSwift.txt")
        try content.write(to: txtFile, atomically: true, encoding: .utf8)

        let analyzer = SwiftAnalyzer(directory: tempDir.path)
        let result = analyzer.parseDependencyProtocolFiles(in: tempDir.path)

        #expect(!result.map(\.url.standardizedFileURL).contains(txtFile.standardizedFileURL))
    }

    @Test func testFindsMultipleProtocolFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        let checkoutsDir = tempDir.appendingPathComponent(".build/checkouts/SomePackage/Sources")
        try FileManager.default.createDirectory(at: checkoutsDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let firstContent = """
        protocol FirstProtocol {
            func first()
        }
        """

        let secondContent = """
        protocol SecondProtocol {
            func second()
        }
        """

        let firstFile = checkoutsDir.appendingPathComponent("First.swift")
        try firstContent.write(to: firstFile, atomically: true, encoding: .utf8)

        let secondFile = checkoutsDir.appendingPathComponent("Second.swift")
        try secondContent.write(to: secondFile, atomically: true, encoding: .utf8)

        let analyzer = SwiftAnalyzer(directory: tempDir.path)
        let result = analyzer.parseDependencyProtocolFiles(in: tempDir.path)
        let standardizedResult = result.map(\.url.standardizedFileURL)

        #expect(standardizedResult.contains(firstFile.standardizedFileURL))
        #expect(standardizedResult.contains(secondFile.standardizedFileURL))
    }

    @Test func testParsedFilesContainValidSourceTrees() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        let checkoutsDir = tempDir.appendingPathComponent(".build/checkouts/SomePackage/Sources")
        try FileManager.default.createDirectory(at: checkoutsDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let swiftContent = """
        protocol MyProtocol {
            func doWork()
            var name: String { get }
        }
        """

        let swiftFile = checkoutsDir.appendingPathComponent("MyProtocol.swift")
        try swiftContent.write(to: swiftFile, atomically: true, encoding: .utf8)

        let analyzer = SwiftAnalyzer(directory: tempDir.path)
        let result = analyzer.parseDependencyProtocolFiles(in: tempDir.path)

        #expect(result.count == 1)
        let parsed = try #require(result.first)
        #expect(parsed.source.contains("protocol MyProtocol"))
        #expect(parsed.sourceFile.statements.count > 0)
    }
}
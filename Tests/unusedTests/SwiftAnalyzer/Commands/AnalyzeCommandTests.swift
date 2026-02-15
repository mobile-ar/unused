//
//  Created by Fernando Romiti on 05/12/2025.
//

import Testing
import Foundation
@testable import unused

struct AnalyzeCommandTests {

    @Test func testAnalyzeFindsUnusedDeclarations() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let testFile = tempDir.appendingPathComponent("Test.swift")
        let content = """
        func usedFunction() {
            print("used")
        }

        func unusedFunction() {
            print("unused")
        }

        class TestClass {
            func test() {
                usedFunction()
            }
        }
        """
        try content.write(to: testFile, atomically: true, encoding: .utf8)

        let options = AnalyzerOptions()
        let analyzer = SwiftAnalyzer(options: options, directory: tempDir.path)
        await analyzer.analyzeFiles([testFile])

        let unusedFile = tempDir.appendingPathComponent(ReportService.reportFileName)
        #expect(FileManager.default.fileExists(atPath: unusedFile.path))
    }

    @Test func testAnalyzeWithIncludeOverridesOption() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let testFile = tempDir.appendingPathComponent("Override.swift")
        let content = """
        class Base {
            func method() {}
        }

        class Derived: Base {
            override func method() {}
        }
        """
        try content.write(to: testFile, atomically: true, encoding: .utf8)

        let optionsWithOverrides = AnalyzerOptions(includeOverrides: true)
        let analyzer = SwiftAnalyzer(options: optionsWithOverrides, directory: tempDir.path)
        await analyzer.analyzeFiles([testFile])

        let unusedFile = tempDir.appendingPathComponent(ReportService.reportFileName)
        #expect(FileManager.default.fileExists(atPath: unusedFile.path))
    }

    @Test func testAnalyzeWithIncludeProtocolsOption() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let testFile = tempDir.appendingPathComponent("Protocol.swift")
        let content = """
        protocol TestProtocol {
            func required()
        }

        struct Implementation: TestProtocol {
            func required() {
                print("implemented")
            }
        }
        """
        try content.write(to: testFile, atomically: true, encoding: .utf8)

        let optionsWithProtocols = AnalyzerOptions(includeProtocols: true)
        let analyzer = SwiftAnalyzer(options: optionsWithProtocols, directory: tempDir.path)
        await analyzer.analyzeFiles([testFile])

        let unusedFile = tempDir.appendingPathComponent(ReportService.reportFileName)
        #expect(FileManager.default.fileExists(atPath: unusedFile.path))
    }

    @Test func testAnalyzeWithIncludeObjcOption() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let testFile = tempDir.appendingPathComponent("Objc.swift")
        let content = """
        import Foundation

        class ViewController {
            @IBOutlet weak var label: UILabel!

            @IBAction func buttonTapped(_ sender: Any) {
                print("tapped")
            }

            @objc func exposed() {
                print("exposed")
            }
        }
        """
        try content.write(to: testFile, atomically: true, encoding: .utf8)

        let optionsWithObjc = AnalyzerOptions(includeObjc: true)
        let analyzer = SwiftAnalyzer(options: optionsWithObjc, directory: tempDir.path)
        await analyzer.analyzeFiles([testFile])

        let unusedFile = tempDir.appendingPathComponent(ReportService.reportFileName)
        #expect(FileManager.default.fileExists(atPath: unusedFile.path))
    }

    @Test func testAnalyzeTracksTypeReferences() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let shellFile = tempDir.appendingPathComponent("Shell.swift")
        let shellContent = """
        import ArgumentParser

        enum Shell: String, ExpressibleByArgument {
            case bash, zsh, fish

            var completionShell: CompletionShell {
                switch self {
                case .bash: return .bash
                case .zsh: return .zsh
                case .fish: return .fish
                }
            }
        }
        """
        try shellContent.write(to: shellFile, atomically: true, encoding: .utf8)

        let commandFile = tempDir.appendingPathComponent("GenerateCompletionScript.swift")
        let commandContent = """
        import ArgumentParser

        struct GenerateCompletionScript: ParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "generate-completion-script",
                abstract: "Generate shell completion script"
            )

            @Option(help: "The shell for which to generate completions")
            var shell: Shell = .bash

            func run() throws {
                print(shell)
            }
        }
        """
        try commandContent.write(to: commandFile, atomically: true, encoding: .utf8)

        let options = AnalyzerOptions()
        let analyzer = SwiftAnalyzer(options: options, directory: tempDir.path)
        await analyzer.analyzeFiles([commandFile, shellFile])

        let unusedFile = tempDir.appendingPathComponent(ReportService.reportFileName)

        if FileManager.default.fileExists(atPath: unusedFile.path) {
            let report = try ReportService.read(from: tempDir.path)
            let hasShellEnum = report.unused.contains { item in
                item.name == "Shell" && item.type == .class
            }
            #expect(!hasShellEnum, "Shell enum should not be reported as unused")
        }
    }

    @Test func testAnalyzeWithShowExcludedOption() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let testFile = tempDir.appendingPathComponent("Test.swift")
        let content = """
        class Base {
            func method() {}
        }

        class Derived: Base {
            override func method() {}
        }

        func unusedFunction() {}
        """
        try content.write(to: testFile, atomically: true, encoding: .utf8)

        let optionsWithShowExcluded = AnalyzerOptions(showExcluded: true)
        let analyzer = SwiftAnalyzer(options: optionsWithShowExcluded, directory: tempDir.path)
        await analyzer.analyzeFiles([testFile])

        let unusedFile = tempDir.appendingPathComponent(ReportService.reportFileName)
        #expect(FileManager.default.fileExists(atPath: unusedFile.path))
    }

    @Test func testAnalyzeWithAllOptions() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let testFile = tempDir.appendingPathComponent("Complete.swift")
        let content = """
        import Foundation

        protocol TestProtocol {
            func protocolMethod()
        }

        class Base {
            @objc func objcMethod() {}
            @IBAction func action(_ sender: Any) {}
        }

        class Derived: Base, TestProtocol {
            override func objcMethod() {
                super.objcMethod()
            }

            func protocolMethod() {
                print("protocol")
            }
        }

        func unusedFunction() {}
        """
        try content.write(to: testFile, atomically: true, encoding: .utf8)

        let allOptions = AnalyzerOptions(
            includeOverrides: true,
            includeProtocols: true,
            includeObjc: true,
            showExcluded: true
        )
        let analyzer = SwiftAnalyzer(options: allOptions, directory: tempDir.path)
        await analyzer.analyzeFiles([testFile])

        let unusedFile = tempDir.appendingPathComponent(ReportService.reportFileName)
        #expect(FileManager.default.fileExists(atPath: unusedFile.path))
    }

    @Test func testAnalyzeEmptyDirectory() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let options = AnalyzerOptions()
        let analyzer = SwiftAnalyzer(options: options, directory: tempDir.path)
        await analyzer.analyzeFiles([])

        let unusedFile = tempDir.appendingPathComponent(ReportService.reportFileName)
        #expect(FileManager.default.fileExists(atPath: unusedFile.path))
    }

    @Test func testAnalyzeMultipleFiles() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let file1 = tempDir.appendingPathComponent("File1.swift")
        let content1 = """
        func functionInFile1() {
            print("file1")
        }
        """
        try content1.write(to: file1, atomically: true, encoding: .utf8)

        let file2 = tempDir.appendingPathComponent("File2.swift")
        let content2 = """
        func functionInFile2() {
            functionInFile1()
        }

        func unusedInFile2() {
            print("unused")
        }
        """
        try content2.write(to: file2, atomically: true, encoding: .utf8)

        let options = AnalyzerOptions()
        let analyzer = SwiftAnalyzer(options: options, directory: tempDir.path)
        await analyzer.analyzeFiles([file1, file2])

        let unusedFile = tempDir.appendingPathComponent(ReportService.reportFileName)
        #expect(FileManager.default.fileExists(atPath: unusedFile.path))

        let report = try ReportService.read(from: tempDir.path)
        #expect(report.unused.contains { $0.name == "unusedInFile2" })
        #expect(!report.unused.contains { $0.name == "functionInFile1" })
        #expect(report.unused.contains { $0.name == "functionInFile2" })
    }

    @Test func testGetSwiftFilesExcludesTestsByDefault() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let regularFile = tempDir.appendingPathComponent("Regular.swift")
        try "// regular file".write(to: regularFile, atomically: true, encoding: .utf8)

        let testFile = tempDir.appendingPathComponent("RegularTests.swift")
        try "// test file".write(to: testFile, atomically: true, encoding: .utf8)

        let testsDir = tempDir.appendingPathComponent("Tests")
        try FileManager.default.createDirectory(at: testsDir, withIntermediateDirectories: true)
        let testInTestsDir = testsDir.appendingPathComponent("SomeTest.swift")
        try "// test in Tests dir".write(to: testInTestsDir, atomically: true, encoding: .utf8)

        let result = await getSwiftFiles(in: tempDir, includeTests: false)

        #expect(result.files.count == 1)
        #expect(result.files.first?.lastPathComponent == "Regular.swift")
    }

    @Test func testGetSwiftFilesIncludesTestsWhenFlagSet() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let regularFile = tempDir.appendingPathComponent("Regular.swift")
        try "// regular file".write(to: regularFile, atomically: true, encoding: .utf8)

        let testFile = tempDir.appendingPathComponent("RegularTests.swift")
        try "// test file".write(to: testFile, atomically: true, encoding: .utf8)

        let testsDir = tempDir.appendingPathComponent("Tests")
        try FileManager.default.createDirectory(at: testsDir, withIntermediateDirectories: true)
        let testInTestsDir = testsDir.appendingPathComponent("SomeTest.swift")
        try "// test in Tests dir".write(to: testInTestsDir, atomically: true, encoding: .utf8)

        let result = await getSwiftFiles(in: tempDir, includeTests: true)

        #expect(result.files.count == 3)
    }

    @Test func testIsTestFileDetectsTestFiles() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let regularFile = tempDir.appendingPathComponent("Regular.swift")
        #expect(!isTestFile(regularFile))

        let testFile = tempDir.appendingPathComponent("RegularTest.swift")
        #expect(isTestFile(testFile))

        let testsFile = tempDir.appendingPathComponent("RegularTests.swift")
        #expect(isTestFile(testsFile))

        let testsDir = tempDir.appendingPathComponent("Tests")
        try FileManager.default.createDirectory(at: testsDir, withIntermediateDirectories: true)
        let fileInTestsDir = testsDir.appendingPathComponent("SomeFile.swift")
        #expect(isTestFile(fileInTestsDir))
    }

    @Test func testAnalyzeWithIncludeTestsOption() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let regularFile = tempDir.appendingPathComponent("Regular.swift")
        let regularContent = """
        func usedFunction() {
            print("used")
        }

        func unusedFunction() {
            print("unused")
        }
        """
        try regularContent.write(to: regularFile, atomically: true, encoding: .utf8)

        let testFile = tempDir.appendingPathComponent("RegularTests.swift")
        let testContent = """
        func testFunction() {
            usedFunction()
        }

        func unusedTestHelper() {
            print("unused test helper")
        }
        """
        try testContent.write(to: testFile, atomically: true, encoding: .utf8)

        let optionsWithoutTests = AnalyzerOptions(includeTests: false)
        let discoveryWithoutTests = await getSwiftFiles(in: tempDir, includeTests: false)
        let analyzerWithoutTests = SwiftAnalyzer(
            options: optionsWithoutTests,
            directory: tempDir.path,
            excludedTestFileCount: discoveryWithoutTests.excludedTestFileCount
        )
        await analyzerWithoutTests.analyzeFiles(discoveryWithoutTests.files)

        #expect(discoveryWithoutTests.files.count == 1)

        let optionsWithTests = AnalyzerOptions(includeTests: true)
        let discoveryWithTests = await getSwiftFiles(in: tempDir, includeTests: true)
        let analyzerWithTests = SwiftAnalyzer(
            options: optionsWithTests,
            directory: tempDir.path,
            excludedTestFileCount: discoveryWithTests.excludedTestFileCount
        )
        await analyzerWithTests.analyzeFiles(discoveryWithTests.files)

        #expect(discoveryWithTests.files.count == 2)
    }

    @Test func testDisplayExistingResultsFromUnusedFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let testFile = tempDir.appendingPathComponent("Test.swift")
        let content = """
        func usedFunction() {
            print("used")
        }

        func unusedFunction() {
            print("unused")
        }

        var unusedVariable = "test"

        class UnusedClass {}

        class TestClass {
            func test() {
                usedFunction()
            }
        }
        """
        try content.write(to: testFile, atomically: true, encoding: .utf8)

        let options = AnalyzerOptions()
        let analyzer = SwiftAnalyzer(options: options, directory: tempDir.path)
        await analyzer.analyzeFiles([testFile])

        let unusedFile = tempDir.appendingPathComponent(ReportService.reportFileName)
        #expect(FileManager.default.fileExists(atPath: unusedFile.path))

        let report = try ReportService.read(from: tempDir.path)

        #expect(!report.unused.isEmpty || report.excluded.totalCount > 0)

        let functions = report.unused.filter { $0.type == .function }
        let variables = report.unused.filter { $0.type == .variable }
        let classes = report.unused.filter { $0.type == .class }

        #expect(functions.count >= 1)
        #expect(variables.count >= 1)
        #expect(classes.count >= 1)

        #expect(functions.contains { $0.name == "unusedFunction" })
        #expect(variables.contains { $0.name == "unusedVariable" })
        #expect(classes.contains { $0.name == "UnusedClass" })
    }

}

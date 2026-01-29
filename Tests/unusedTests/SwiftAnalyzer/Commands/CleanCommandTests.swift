//
//  Created by Fernando Romiti on 11/12/2025.
//

import Testing
import Foundation
@testable import unused

struct CleanCommandTests {

    @Test func testCleanRemovesSingleUnusedFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let unusedFile = tempDir.appendingPathComponent(ReportService.reportFileName)
        try "test content".write(to: unusedFile, atomically: true, encoding: .utf8)

        #expect(FileManager.default.fileExists(atPath: unusedFile.path))

        var clean = Clean()
        clean.directory = tempDir.path
        clean.dryRun = false

        try clean.run()

        #expect(!FileManager.default.fileExists(atPath: unusedFile.path))
    }

    @Test func testCleanRemovesMultipleUnusedFiles() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let unusedFile1 = tempDir.appendingPathComponent(ReportService.reportFileName)
        let subDir = tempDir.appendingPathComponent("subdir")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        let unusedFile2 = subDir.appendingPathComponent(ReportService.reportFileName)

        try "content1".write(to: unusedFile1, atomically: true, encoding: .utf8)
        try "content2".write(to: unusedFile2, atomically: true, encoding: .utf8)

        #expect(FileManager.default.fileExists(atPath: unusedFile1.path))
        #expect(FileManager.default.fileExists(atPath: unusedFile2.path))

        var clean = Clean()
        clean.directory = tempDir.path
        clean.dryRun = false

        try clean.run()

        #expect(!FileManager.default.fileExists(atPath: unusedFile1.path))
        #expect(!FileManager.default.fileExists(atPath: unusedFile2.path))
    }

    @Test func testCleanRecursivelySearchesSubfolders() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let level1 = tempDir.appendingPathComponent("level1")
        let level2 = level1.appendingPathComponent("level2")
        let level3 = level2.appendingPathComponent("level3")

        try FileManager.default.createDirectory(at: level3, withIntermediateDirectories: true)

        let unusedFile1 = tempDir.appendingPathComponent(ReportService.reportFileName)
        let unusedFile2 = level1.appendingPathComponent(ReportService.reportFileName)
        let unusedFile3 = level2.appendingPathComponent(ReportService.reportFileName)
        let unusedFile4 = level3.appendingPathComponent(ReportService.reportFileName)

        try "root".write(to: unusedFile1, atomically: true, encoding: .utf8)
        try "level1".write(to: unusedFile2, atomically: true, encoding: .utf8)
        try "level2".write(to: unusedFile3, atomically: true, encoding: .utf8)
        try "level3".write(to: unusedFile4, atomically: true, encoding: .utf8)

        var clean = Clean()
        clean.directory = tempDir.path
        clean.dryRun = false

        try clean.run()

        #expect(!FileManager.default.fileExists(atPath: unusedFile1.path))
        #expect(!FileManager.default.fileExists(atPath: unusedFile2.path))
        #expect(!FileManager.default.fileExists(atPath: unusedFile3.path))
        #expect(!FileManager.default.fileExists(atPath: unusedFile4.path))
    }

    @Test func testCleanDryRunDoesNotDeleteFiles() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let unusedFile = tempDir.appendingPathComponent(ReportService.reportFileName)
        try "test content".write(to: unusedFile, atomically: true, encoding: .utf8)

        #expect(FileManager.default.fileExists(atPath: unusedFile.path))

        var clean = Clean()
        clean.directory = tempDir.path
        clean.dryRun = true

        try clean.run()

        #expect(FileManager.default.fileExists(atPath: unusedFile.path))
    }

    @Test func testCleanIgnoresBuildDirectory() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let buildDir = tempDir.appendingPathComponent(".build")
        try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)

        let unusedFileInRoot = tempDir.appendingPathComponent(ReportService.reportFileName)
        let unusedFileInBuild = buildDir.appendingPathComponent(ReportService.reportFileName)

        try "root content".write(to: unusedFileInRoot, atomically: true, encoding: .utf8)
        try "build content".write(to: unusedFileInBuild, atomically: true, encoding: .utf8)

        var clean = Clean()
        clean.directory = tempDir.path
        clean.dryRun = false

        try clean.run()

        #expect(!FileManager.default.fileExists(atPath: unusedFileInRoot.path))
        #expect(FileManager.default.fileExists(atPath: unusedFileInBuild.path))
    }

    @Test func testCleanWithNoUnusedFiles() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        var clean = Clean()
        clean.directory = tempDir.path
        clean.dryRun = false

        try clean.run()
    }

    @Test func testCleanOnlyRemovesUnusedFiles() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let unusedFile = tempDir.appendingPathComponent(ReportService.reportFileName)
        let otherFile = tempDir.appendingPathComponent("other.txt")
        let swiftFile = tempDir.appendingPathComponent("test.swift")

        try "unused".write(to: unusedFile, atomically: true, encoding: .utf8)
        try "other".write(to: otherFile, atomically: true, encoding: .utf8)
        try "swift".write(to: swiftFile, atomically: true, encoding: .utf8)

        var clean = Clean()
        clean.directory = tempDir.path
        clean.dryRun = false

        try clean.run()

        #expect(!FileManager.default.fileExists(atPath: unusedFile.path))
        #expect(FileManager.default.fileExists(atPath: otherFile.path))
        #expect(FileManager.default.fileExists(atPath: swiftFile.path))
    }

    @Test func testCleanThrowsErrorForNonExistentDirectory() async throws {
        let nonExistentPath = "/path/that/does/not/exist/\(UUID().uuidString)"

        var clean = Clean()
        clean.directory = nonExistentPath
        clean.dryRun = false

        #expect(throws: (any Error).self) {
            try clean.run()
        }
    }

    @Test func testCleanThrowsErrorForFileInsteadOfDirectory() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let testFile = tempDir.appendingPathComponent("test.txt")
        try "test".write(to: testFile, atomically: true, encoding: .utf8)

        var clean = Clean()
        clean.directory = testFile.path
        clean.dryRun = false

        #expect(throws: (any Error).self) {
            try clean.run()
        }
    }

}

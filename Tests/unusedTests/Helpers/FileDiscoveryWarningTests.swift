import Foundation
import Synchronization
import Testing
@testable import unused

struct FileDiscoveryWarningTests {
    private func directory(with paths: [String]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for path in paths {
            let file = directory.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "// fixture".write(to: file, atomically: true, encoding: .utf8)
        }
        return directory
    }

    @Test(arguments: [1, 3, 5])
    func warnsOnceAtTheThresholdWithoutChangingResults(threshold: Int) async throws {
        let directory = try directory(with: (1...5).map { "Sources/File\($0).swift" })
        defer { try? FileManager.default.removeItem(at: directory) }
        let events = Mutex<[Int]>([])
        let result = await getSwiftFiles(in: directory, fileCountWarningThreshold: threshold) {
            count in events.withLock { $0.append(count) }
        }
        #expect(events.withLock { $0 } == [threshold])
        #expect(result.files.count == 5)
        #expect(result.excludedTestFileCount == 0)
    }

    @Test func doesNotWarnBelowTheThreshold() async throws {
        let directory = try directory(with: ["File.swift", "notes.txt"])
        defer { try? FileManager.default.removeItem(at: directory) }
        let events = Mutex<[Int]>([])
        let result = await getSwiftFiles(in: directory, fileCountWarningThreshold: 2) {
            count in events.withLock { $0.append(count) }
        }
        #expect(events.withLock { $0.isEmpty })
        #expect(result.files.count == 1)
    }

    @Test(arguments: [nil, 0, -1] as [Int?])
    func noThresholdMeansNoWarning(threshold: Int?) async throws {
        let directory = try directory(with: ["File.swift"])
        defer { try? FileManager.default.removeItem(at: directory) }
        let events = Mutex<[Int]>([])
        let result = await getSwiftFiles(in: directory, fileCountWarningThreshold: threshold) {
            count in events.withLock { $0.append(count) }
        }
        #expect(events.withLock { $0.isEmpty })
        #expect(result.files.count == 1)
    }

    @Test(arguments: [false, true])
    func countsExcludedTestsBeforeFiltering(includeTests: Bool) async throws {
        let directory = try directory(with: ["Main.swift", "Tests/Fixture.swift", "OtherTests.swift"])
        defer { try? FileManager.default.removeItem(at: directory) }
        let events = Mutex<[Int]>([])
        let result = await getSwiftFiles(in: directory, includeTests: includeTests, fileCountWarningThreshold: 3) {
            count in events.withLock { $0.append(count) }
        }
        #expect(events.withLock { $0 } == [3])
        #expect(result.files.count == (includeTests ? 3 : 1))
        #expect(result.excludedTestFileCount == (includeTests ? 0 : 2))
    }

    @Test func skippedBuildTreesAndSwiftNamedDirectoriesDoNotCount() async throws {
        let directory = try directory(with: [
            "Main.swift", ".build/Generated.swift", ".build/deep/More.swift", "Nested/.build/Hidden.swift",
            "Folder.swift/notes.txt", "Readme.md"
        ])
        defer { try? FileManager.default.removeItem(at: directory) }
        let events = Mutex<[Int]>([])
        let result = await getSwiftFiles(in: directory, fileCountWarningThreshold: 2) {
            count in events.withLock { $0.append(count) }
        }
        #expect(events.withLock { $0.isEmpty })
        #expect(result.files.map(\.lastPathComponent) == ["Main.swift"])
    }

    @Test func swiftFilesInsideSwiftNamedDirectoriesAreStillDiscovered() async throws {
        let directory = try directory(with: ["Folder.swift/Child.swift"])
        defer { try? FileManager.default.removeItem(at: directory) }
        let events = Mutex<[Int]>([])
        let result = await getSwiftFiles(in: directory, fileCountWarningThreshold: 1) {
            count in events.withLock { $0.append(count) }
        }
        #expect(events.withLock { $0 } == [1])
        #expect(result.files.map(\.lastPathComponent) == ["Child.swift"])
    }

    @Test func emptyDirectoriesDoNotWarn() async throws {
        let directory = try directory(with: [])
        defer { try? FileManager.default.removeItem(at: directory) }
        let events = Mutex<[Int]>([])
        let result = await getSwiftFiles(in: directory, fileCountWarningThreshold: 1) {
            count in events.withLock { $0.append(count) }
        }
        #expect(events.withLock { $0.isEmpty })
        #expect(result.files.isEmpty)
    }
}

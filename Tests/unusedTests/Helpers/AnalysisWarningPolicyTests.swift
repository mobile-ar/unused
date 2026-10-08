import Foundation
import Testing
@testable import unused

struct AnalysisWarningPolicyTests {
    @Test func warnsBeforeScanningTheFilesystemRoot() {
        let policy = AnalysisWarningPolicy()
        let message = policy.directoryWarning(for: URL(fileURLWithPath: "/"))
        #expect(message?.contains("filesystem root") == true)
        #expect(message?.contains("Ctrl-C") == true)
    }

    @Test func warnsForHomeButNotAProjectWithinIt() {
        let home = URL(fileURLWithPath: "/Users/example")
        let policy = AnalysisWarningPolicy(homeDirectory: home)
        #expect(policy.directoryWarning(for: home)?.contains("home directory") == true)
        #expect(policy.directoryWarning(for: home.appendingPathComponent("Projects/App")) == nil)
        #expect(policy.directoryWarning(for: URL(fileURLWithPath: "/Users/example-other")) == nil)
    }

    @Test func canonicalAndSymlinkHomePathsAreRecognized() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let home = directory.appendingPathComponent("Home")
        let alias = directory.appendingPathComponent("Alias")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: home)
        let policy = AnalysisWarningPolicy(homeDirectory: home)
        #expect(policy.directoryWarning(for: alias)?.contains("home directory") == true)
        #expect(policy.directoryWarning(for: home.appendingPathComponent("."))?.contains("home directory") == true)
    }

    @Test func defaultsToOneThousandFiles() {
        let policy = AnalysisWarningPolicy()
        let directory = URL(fileURLWithPath: "/project")
        #expect(policy.fileCountThreshold == 1_000)
        #expect(policy.fileCountWarning(for: 999, in: directory) == nil)
        #expect(policy.fileCountWarning(for: 1_000, in: directory)?.contains("at least 1000 Swift files") == true)
    }

    @Test func thresholdBoundariesAndMessagesAreActionable() {
        let policy = AnalysisWarningPolicy(fileCountThreshold: 3)
        let directory = URL(fileURLWithPath: "/project")
        #expect(policy.fileCountWarning(for: 0, in: directory) == nil)
        #expect(policy.fileCountWarning(for: 2, in: directory) == nil)
        for count in [3, 4, 10_000] {
            let message = policy.fileCountWarning(for: count, in: directory)
            #expect(message?.contains("at least \(count) Swift files") == true)
            #expect(message?.contains("/project") == true)
            #expect(message?.contains("threshold: 3") == true)
            #expect(message?.contains("--file-count-warning-threshold") == true)
            #expect(message?.contains("Ctrl-C") == true)
            #expect(message?.unicodeScalars.allSatisfy { $0.isASCII } == true)
        }
    }

    @Test func singularFileCountsUseASingularLabel() {
        let policy = AnalysisWarningPolicy(fileCountThreshold: 1)
        let message = policy.fileCountWarning(for: 1, in: URL(fileURLWithPath: "/project"))
        #expect(message?.contains("at least 1 Swift file in") == true)
        #expect(message?.contains("1 Swift files") == false)
    }

    @Test(arguments: [0, -1])
    func invalidInjectedThresholdDoesNotWarn(threshold: Int) {
        let policy = AnalysisWarningPolicy(fileCountThreshold: threshold)
        #expect(policy.fileCountWarning(for: 10, in: URL(fileURLWithPath: "/project")) == nil)
    }
}

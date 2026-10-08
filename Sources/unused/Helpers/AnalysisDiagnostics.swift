import Foundation

struct AnalysisDiagnostics: Sendable {
    var warningPolicy = AnalysisWarningPolicy()
    var memoryReporter = MemoryUsageReporter()
    var writeWarning: @Sendable (String) -> Void = Self.writeToStandardError
    var writeMemoryReport: @Sendable (String, OutputFormat) -> Void = { message, format in
        if format == .xcode {
            Self.writeToStandardError(message)
        } else {
            print(message)
        }
    }

    func warnAboutDirectory(_ directory: URL) {
        if let message = warningPolicy.directoryWarning(for: directory) {
            writeWarning(message)
        }
    }

    func warnAboutFileCount(_ count: Int, in directory: URL) {
        if let message = warningPolicy.fileCountWarning(for: count, in: directory) {
            writeWarning(message)
        }
    }

    func reportMemory(format: OutputFormat) {
        writeMemoryReport(memoryReporter.report(), format)
    }

    private static func writeToStandardError(_ message: String) {
        try? FileHandle.standardError.write(contentsOf: Data((message + "\n").utf8))
    }
}

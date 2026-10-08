import Foundation
import Synchronization
import Testing
@testable import unused

struct AnalysisDiagnosticsTests {
    @Test func warningsAndMemoryUseIndependentInjectedOutputs() {
        let warnings = Mutex<[String]>([])
        let reports = Mutex<[String]>([])
        let diagnostics = AnalysisDiagnostics(
            warningPolicy: AnalysisWarningPolicy(fileCountThreshold: 2, homeDirectory: URL(fileURLWithPath: "/home/example")),
            memoryReporter: MemoryUsageReporter(readPeakResidentBytes: { 1_048_576 }),
            writeWarning: { message in warnings.withLock { $0.append(message) } },
            writeMemoryReport: { message, format in reports.withLock { $0.append("\(format.rawValue): \(message)") } }
        )
        diagnostics.warnAboutDirectory(URL(fileURLWithPath: "/project"))
        diagnostics.warnAboutFileCount(1, in: URL(fileURLWithPath: "/project"))
        #expect(warnings.withLock { $0.isEmpty })
        diagnostics.warnAboutDirectory(URL(fileURLWithPath: "/home/example"))
        diagnostics.warnAboutFileCount(2, in: URL(fileURLWithPath: "/project"))
        diagnostics.reportMemory(format: .console)
        diagnostics.reportMemory(format: .xcode)
        #expect(warnings.withLock { $0.count } == 2)
        #expect(reports.withLock { $0 } == [
            "console: Peak memory usage: 1.0 MiB (process peak RSS)",
            "xcode: Peak memory usage: 1.0 MiB (process peak RSS)"
        ])
    }

    @Test func missingMemoryMeasurementDoesNotBecomeZero() {
        let output = Mutex<[String]>([])
        let diagnostics = AnalysisDiagnostics(
            memoryReporter: MemoryUsageReporter(readPeakResidentBytes: { nil }),
            writeMemoryReport: { message, _ in output.withLock { $0.append(message) } }
        )
        diagnostics.reportMemory(format: .console)
        #expect(output.withLock { $0 } == ["Peak memory usage: unavailable"])
    }
}

import Darwin
import Testing
@testable import unused

struct MemoryUsageReporterTests {

    @Test(arguments: [
        (Int64(0), "0.0 MiB"),
        (Int64(1), "0.0 MiB"),
        (Int64(1_048_576), "1.0 MiB"),
        (Int64(1_572_864), "1.5 MiB"),
        (Int64(129_368_064), "123.4 MiB"),
        (Int64(1_073_741_823), "1024.0 MiB"),
        (Int64(1_073_741_824), "1.0 GiB"),
        (Int64(1_610_612_736), "1.5 GiB"),
        (Int64(1_325_399_801_856), "1234.4 GiB"),
        (Int64.max, "8589934592.0 GiB")
    ])
    func testFormatsPeakResidentBytes(bytes: Int64, expectedValue: String) {
        let reporter = MemoryUsageReporter(readPeakResidentBytes: { bytes })

        #expect(reporter.report() == "Peak memory usage: \(expectedValue) (process peak RSS)")
    }

    @Test(arguments: [nil, Int64(-1), Int64.min] as [Int64?])
    func testUnavailablePeakResidentBytes(bytes: Int64?) {
        let reporter = MemoryUsageReporter(readPeakResidentBytes: { bytes })

        #expect(reporter.report() == "Peak memory usage: unavailable")
    }

    @Test func testLabelIdentifiesProcessPeakRSS() {
        let reporter = MemoryUsageReporter(readPeakResidentBytes: { 1_048_576 })

        #expect(reporter.report() == "Peak memory usage: 1.0 MiB (process peak RSS)")
    }

    @Test func testLiveDarwinReaderReturnsSensibleBytes() throws {
        let bytes = try #require(MemoryUsageReporter.processPeakResidentBytes())
        var usage = rusage()
        let result = getrusage(RUSAGE_SELF, &usage)

        #expect(result == 0)
        #expect(bytes >= 1_048_576)
        // A later kernel reading must be at least as high, in the same byte units.
        #expect(bytes <= Int64(usage.ru_maxrss))
    }

    @Test func testDefaultReaderReportsProcessPeakRSS() {
        let report = MemoryUsageReporter().report()

        #expect(report.hasPrefix("Peak memory usage: "))
        #expect(report.hasSuffix(" (process peak RSS)"))
        #expect(report.contains(" MiB ") || report.contains(" GiB "))
    }
}

import Darwin
import Foundation

struct MemoryUsageReporter: Sendable {

    var readPeakResidentBytes: @Sendable () -> Int64? = Self.processPeakResidentBytes

    func report() -> String {
        guard let bytes = readPeakResidentBytes(), bytes >= 0 else {
            return "Peak memory usage: unavailable"
        }

        let bytesPerMiB: Int64 = 1_048_576
        let bytesPerGiB: Int64 = 1_073_741_824
        let usesGiB = bytes >= bytesPerGiB
        let value = Double(bytes) / Double(usesGiB ? bytesPerGiB : bytesPerMiB)
        let formattedValue = value.formatted(
            .number
                .locale(Locale(identifier: "en_US_POSIX"))
                .precision(.fractionLength(1))
                .grouping(.never)
        )
        let unit = usesGiB ? "GiB" : "MiB"
        return "Peak memory usage: \(formattedValue) \(unit) (process peak RSS)"
    }

    /// Returns the process-lifetime resident memory high-water mark in bytes.
    /// This is not an analysis-local peak; subtracting a baseline cannot isolate one.
    static func processPeakResidentBytes() -> Int64? {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0, usage.ru_maxrss >= 0 else {
            return nil
        }

        // Darwin reports ru_maxrss in bytes, unlike Linux's kilobytes.
        return Int64(usage.ru_maxrss)
    }
}

import Foundation

struct ProgressBarFormatter {
    var colorEnabled = false

    func render(_ update: ProgressUpdate) -> String {
        let total = max(update.total, 0)
        let current = min(max(update.current, 0), total)
        let progress = total > 0 ? Double(current) / Double(total) : 0
        let filledLength = Int(progress * 50)
        let filledBar = styled(String(repeating: "█", count: filledLength), color: "203;166;247")
        let emptyBar = styled(String(repeating: "░", count: 50 - filledLength), color: "180;190;254")
        let percentage = (progress * 100).formatted(
            .number.precision(.fractionLength(1)).grouping(.never).locale(Locale(identifier: "en_US_POSIX"))
        )
        let prefix = styled(update.prefix, color: "116;199;236", bold: true)
        let timing: String
        if total > 0, current == total, let elapsed = update.elapsed,
           elapsed >= .zero, elapsed < .seconds(Int64.max) + .seconds(1) {
            timing = "Done in \(formatDuration(elapsed, estimated: false))"
        } else {
            timing = "ETA: \(formatDuration(update.estimatedRemaining, estimated: true))"
        }
        let status = styled(timing, color: "180;190;254")

        return " \(prefix) [\(filledBar)\(emptyBar)] \(percentage)% (\(current)/\(total)) \(status)"
    }

    private func formatDuration(_ duration: Duration?, estimated: Bool) -> String {
        guard let duration, duration >= .zero else { return "calculating..." }
        guard duration > .zero else { return "0ms" }
        guard duration >= .milliseconds(1) else { return "<1ms" }
        guard duration < .seconds(Int64.max) + .seconds(1) else { return "calculating..." }

        let approximation = estimated ? "~" : ""
        let components = duration.components
        if duration < .seconds(1) {
            let attosecondsPerMillisecond: Int64 = 1_000_000_000_000_000
            let milliseconds = components.attoseconds / attosecondsPerMillisecond
                + (components.attoseconds % attosecondsPerMillisecond > 0 ? 1 : 0)
            return "\(approximation)\(milliseconds)ms"
        }
        let seconds = UInt64(components.seconds) + (components.attoseconds > 0 ? 1 : 0)
        if seconds >= 3_600 {
            return "\(approximation)\(seconds / 3_600)h \(seconds % 3_600 / 60)m"
        }
        if seconds >= 60 {
            return "\(approximation)\(seconds / 60)m \(seconds % 60)s"
        }
        return "\(approximation)\(seconds)s"
    }

    private func styled(_ text: String, color: String, bold: Bool = false) -> String {
        guard colorEnabled else { return text }
        let weight = bold ? "1;" : ""
        return "\u{1B}[\(weight)38;2;\(color)m\(text)\u{1B}[0m"
    }
}

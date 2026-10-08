enum ProgressEstimate {

    static func remainingTime(completed: Int, total: Int, elapsed: Duration) -> Duration? {
        guard total >= 0 else { return nil }
        guard total > 0 else { return .zero }
        guard completed >= 0, elapsed >= .zero else { return nil }
        guard completed < total else { return .zero }
        guard completed > 0, elapsed > .zero else { return nil }
        guard elapsed < .seconds(Int64.max) + .seconds(1) else { return nil }

        let components = elapsed.components
        let elapsedSeconds = Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
        guard elapsedSeconds.isFinite, elapsedSeconds > 0 else { return nil }

        let remainingFiles = total - completed
        let estimate = elapsedSeconds / Double(completed) * Double(remainingFiles)
        guard estimate.isFinite, estimate >= 0, estimate < Double(Int64.max) else { return nil }

        return .seconds(estimate)
    }
}

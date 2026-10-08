actor ProgressTracker {
    private var total: Int
    private let prefix: String
    private let elapsed: @Sendable () -> Duration
    private let render: @Sendable (ProgressUpdate) -> Void
    private let finishLine: @Sendable () -> Void
    private let renderInterval: Duration
    private var current = 0
    private var finished = false
    private var lastRenderedCurrent = 0
    private var lastRenderedElapsed: Duration?

    init(
        total: Int,
        prefix: String,
        elapsed: (@Sendable () -> Duration)? = nil,
        renderInterval: Duration = .milliseconds(100),
        render: @escaping @Sendable (ProgressUpdate) -> Void = {
            printProgressBar(
                prefix: $0.prefix, current: $0.current, total: $0.total,
                estimatedRemaining: $0.estimatedRemaining, elapsed: $0.elapsed
            )
        },
        finishLine: @escaping @Sendable () -> Void = {
            if OutputConfig.interactiveEnabled { print("") }
        }
    ) {
        self.total = max(0, total)
        self.prefix = prefix
        let clock = ContinuousClock()
        let start = clock.now
        self.elapsed = elapsed ?? { start.duration(to: clock.now) }
        self.renderInterval = max(.zero, renderInterval)
        self.render = render
        self.finishLine = finishLine
    }

    func increment(total updatedTotal: Int? = nil) {
        guard !finished else { return }
        if let updatedTotal {
            total = max(current, updatedTotal)
        }
        guard current < total else { return }
        current += 1
        let elapsed = max(.zero, elapsed())
        let intervalPassed = lastRenderedElapsed.map { elapsed - $0 >= renderInterval } ?? true
        if current == 1 || current == total || intervalPassed {
            renderProgress(elapsed: elapsed)
        }
    }

    func finish() {
        guard !finished else { return }
        finished = true
        guard current > 0 else { return }
        if lastRenderedCurrent != current {
            renderProgress(elapsed: max(.zero, elapsed()))
        }
        finishLine()
    }

    private func renderProgress(elapsed: Duration) {
        render(ProgressUpdate(
            prefix: prefix,
            current: current,
            total: total,
            estimatedRemaining: ProgressEstimate.remainingTime(completed: current, total: total, elapsed: elapsed),
            elapsed: elapsed
        ))
        lastRenderedCurrent = current
        lastRenderedElapsed = elapsed
    }
}

//
//  Created by Fernando Romiti on 25/01/2026.
//

import Foundation

protocol ConsoleSpinnerProtocol: Sendable {
    func start(message: String) async
    func stop(success: Bool) async
}

actor ConsoleSpinner: ConsoleSpinnerProtocol {

    private let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    private let interval: Duration
    private let showsElapsed: Bool
    private let now: @Sendable () -> ContinuousClock.Instant
    private let interactiveEnabled: @Sendable () -> Bool
    private let write: @Sendable (String) -> Void
    private var startTime: ContinuousClock.Instant?
    private var currentFrame = 0
    private var animationTask: Task<Void, Never>?
    private var message = ""
    private(set) var isRunning = false

    init(
        showsElapsed: Bool = false,
        interval: Duration = .milliseconds(50),
        now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock().now },
        interactiveEnabled: @escaping @Sendable () -> Bool = { OutputConfig.interactiveEnabled },
        write: @escaping @Sendable (String) -> Void = {
            print($0, terminator: "")
            fflush(stdout)
        }
    ) {
        self.showsElapsed = showsElapsed
        self.interval = max(.milliseconds(1), interval)
        self.now = now
        self.interactiveEnabled = interactiveEnabled
        self.write = write
    }

    func start(message: String) async {
        guard !isRunning else { return }

        self.message = message
        self.isRunning = true
        self.currentFrame = 0
        self.startTime = now()

        guard interactiveEnabled() else { return }

        renderFrame()
        animationTask = Task { [weak self, interval] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await self?.renderFrame()
            }
        }
    }

    /// Stops the spinner animation and displays a final status.
    /// - Parameter success: Whether to show a success (`✓`) or failure (`✗`) indicator.
    func stop(success: Bool) async {
        guard isRunning else { return }

        animationTask?.cancel()
        animationTask = nil
        isRunning = false

        guard interactiveEnabled() else { return }

        let symbol = success ? "✓".green : "✗".red
        let timing: String
        if showsElapsed, let startTime {
            let elapsed = max(.zero, startTime.duration(to: now()))
            timing = " Done in \(ProgressBarFormatter().formatDuration(elapsed, estimated: false))"
        } else {
            timing = ""
        }
        write("\r\u{1B}[K\(symbol) \(message)\(timing)\n")
    }

    private func renderFrame() {
        guard isRunning else { return }
        let frame = frames[currentFrame]
        write("\r\u{1B}[K\(frame.teal) \(message)")
        currentFrame = (currentFrame + 1) % frames.count
    }

}

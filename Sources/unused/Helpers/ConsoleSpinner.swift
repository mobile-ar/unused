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
    private let interval: Duration = .milliseconds(50)
    private var currentFrame = 0
    private var animationTask: Task<Void, Never>?
    private var message = ""
    private(set) var isRunning = false

    func start(message: String) async {
        guard OutputConfig.interactiveEnabled else { return }
        guard !isRunning else { return }

        self.message = message
        self.isRunning = true
        self.currentFrame = 0

        animationTask = Task {
            while !Task.isCancelled {
                self.renderFrame()
                do {
                    try await Task.sleep(for: self.interval)
                } catch {
                    break
                }
            }
        }
    }

    /// Stops the spinner animation and displays a final status.
    /// - Parameter success: Whether to show a success (`✓`) or failure (`✗`) indicator.
    func stop(success: Bool) async {
        guard OutputConfig.interactiveEnabled else { return }
        guard isRunning else { return }

        animationTask?.cancel()
        animationTask = nil
        isRunning = false

        clearLine()
        let symbol = success ? "✓".green : "✗".red
        print("\(symbol) \(message)")
        fflush(stdout)
    }

    private func renderFrame() {
        let frame = frames[currentFrame]
        print("\r\u{1B}[K\(frame.teal) \(message)", terminator: "")
        fflush(stdout)
        currentFrame = (currentFrame + 1) % frames.count
    }

    private func clearLine() {
        print("\r\u{1B}[K", terminator: "")
        fflush(stdout)
    }

}

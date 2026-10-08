import Foundation

func printProgressBar(
    prefix: String,
    current: Int,
    total: Int,
    estimatedRemaining: Duration? = nil,
    elapsed: Duration? = nil,
    interactiveEnabled: Bool = OutputConfig.interactiveEnabled,
    colorEnabled: Bool = OutputConfig.colorEnabled,
    write: @Sendable (String) -> Void = {
        print($0, terminator: "")
        fflush(stdout)
    }
) {
    guard interactiveEnabled else { return }
    let update = ProgressUpdate(
        prefix: prefix, current: current, total: total, estimatedRemaining: estimatedRemaining, elapsed: elapsed
    )
    let line = ProgressBarFormatter(colorEnabled: colorEnabled).render(update)
    write("\r\u{1B}[K" + line)
}

//
//  Created by Fernando Romiti on 25/01/2026.
//

import Foundation

func printProgressBar(prefix: String, current: Int, total: Int) {
    let barLength = 50
    let progress = Double(current) / Double(total)
    let filledLength = Int(progress * Double(barLength))
    let emptyLength = barLength - filledLength

    let filledBar = String(repeating: "█", count: filledLength).mauve
    let emptyBar = String(repeating: "░", count: emptyLength).lavender
    let percentage = String(format: "%.1f", progress * 100)

    print("\r\u{1B}[K \(prefix.sapphire.bold) [\(filledBar)\(emptyBar)] \(percentage)% (\(current)/\(total))", terminator: "")
    fflush(stdout)
}

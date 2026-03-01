//
//  Created by Fernando Romiti on 14/02/2026.
//

import Foundation

actor ProgressTracker {

    private let total: Int
    private let prefix: String
    private var current: Int = 0

    init(total: Int, prefix: String) {
        self.total = total
        self.prefix = prefix
    }

    func increment() {
        current += 1
        printProgressBar(prefix: prefix, current: current, total: total)
    }

    func finish() {
        guard OutputConfig.interactiveEnabled else { return }
        print("")
    }

}

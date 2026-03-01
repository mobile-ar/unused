//
//  Created by Fernando Romiti on 01/03/2026.
//

import Foundation
import Synchronization

enum OutputConfig {

    /// Whether ANSI color codes are emitted. Defaults based on TTY detection and NO_COLOR convention.
    private static let _colorEnabled = Mutex<Bool>({
        // Respect NO_COLOR convention (https://no-color.org/)
        if ProcessInfo.processInfo.environment["NO_COLOR"] != nil { return false }
        return isatty(STDOUT_FILENO) != 0
    }())

    /// Whether interactive elements (spinners, progress bars) are shown. Defaults based on TTY detection.
    private static let _interactiveEnabled = Mutex<Bool>(
        isatty(STDOUT_FILENO) != 0
    )

    static var colorEnabled: Bool {
        get { _colorEnabled.withLock { $0 } }
        set { _colorEnabled.withLock { $0 = newValue } }
    }

    static var interactiveEnabled: Bool {
        get { _interactiveEnabled.withLock { $0 } }
        set { _interactiveEnabled.withLock { $0 = newValue } }
    }

}

//
//  Created by Fernando Romiti on 14/12/2025.
//

import ArgumentParser
import Foundation

struct Xcode: ParsableCommand {

    static let configuration = CommandConfiguration(
        abstract: "Open an unused declaration in Xcode by its ID"
    )

    @Argument(help: "The directory containing the .unused file")
    var directory: String

    @Argument(help: "The ID of the unused declaration to open")
    var xcode: Int

    func run() throws {
        try EditorOpener.open(
            id: xcode,
            inDirectory: directory,
            using: .xcode
        )
    }

}

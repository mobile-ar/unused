//
//  Created by Fernando Romiti on 05/12/2025.
//

import ArgumentParser

@main
struct Unused: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "unused",
        abstract: "Find unused Swift declarations in your codebase",
        version: "0.0.1",
        subcommands: [Analyze.self, Clean.self, Filter.self, InstallCompletions.self, Xcode.self, Zed.self],
        defaultSubcommand: Analyze.self
    )

}

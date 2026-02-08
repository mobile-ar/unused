//
//  Created by Fernando Romiti on 05/12/2025.
//

import ArgumentParser
import Foundation

struct InstallCompletions: ParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "install-completions",
        abstract: "Automatically install shell completions for your current shell"
    )

    func run() throws {
        print("→ Installing shell completions...".blue.bold)

        let helper = InstallCompletionsHelper()

        let shell: Shell
        do {
            shell = try helper.detectShell()
        } catch {
            print("⚠ Could not detect your shell. Set the SHELL environment variable.".red)
            throw ExitCode.failure
        }

        print("✓ Detected shell: \(shell.rawValue)".green)

        do {
            try helper.install(shell: shell)
        } catch {
            print("⚠ Installation failed: \(error.localizedDescription)".red)
            throw ExitCode.failure
        }
    }
}
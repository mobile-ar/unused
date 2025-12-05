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

    @Flag(name: .long, help: "Force reinstallation even if already installed")
    var force: Bool = false

    func run() throws {
        print("→ Installing shell completions...".blue.bold)

        guard let shellPath = ProcessInfo.processInfo.environment["SHELL"] else {
            print("⚠ Could not detect your shell. Set the SHELL environment variable.".red)
            throw ExitCode.failure
        }

        let shell = detectShell(from: shellPath)
        print("✓ Detected shell: \(shell.rawValue)".green)

        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path

        do {
            switch shell {
            case .bash:
                try installBashCompletions(homeDir: homeDir)
            case .zsh:
                try installZshCompletions(homeDir: homeDir)
            case .fish:
                try installFishCompletions(homeDir: homeDir)
            }
        } catch {
            print("⚠ Installation failed: \(error)".red)
            throw ExitCode.failure
        }
    }

    private func detectShell(from path: String) -> Shell {
        if path.contains("zsh") {
            return .zsh
        } else if path.contains("fish") {
            return .fish
        } else {
            return .bash
        }
    }

    private func installBashCompletions(homeDir: String) throws {
        let rcFile = "\(homeDir)/.bashrc"
        let completionLine = """
        # Unused CLI completions
        if command -v unused &> /dev/null; then
            eval "$(unused generate-completion-script --shell bash)"
        fi
        """

        if fileContainsCompletions(rcFile) && !force {
            print("✓ Completions already installed in ~/.bashrc".yellow)
            print("  Use --force to reinstall".gray)
            return
        }

        try appendToFile(rcFile, content: completionLine)
        print("✓ Successfully installed completions to ~/.bashrc".green)
        print("\n" + "To activate completions, run:".teal)
        print("  source ~/.bashrc".bold)
        print("\nOr restart your terminal.".gray)
    }

    private func installZshCompletions(homeDir: String) throws {
        let rcFile = "\(homeDir)/.zshrc"
        let completionLine = """
        # Unused CLI completions
        if command -v unused &> /dev/null; then
            eval "$(unused generate-completion-script --shell zsh)"
        fi
        """

        if fileContainsCompletions(rcFile) && !force {
            print("✓ Completions already installed in ~/.zshrc".yellow)
            print("  Use --force to reinstall".gray)
            return
        }

        try appendToFile(rcFile, content: completionLine)
        print("✓ Successfully installed completions to ~/.zshrc".green)
        print("\n" + "To activate completions, run:".teal)
        print("  source ~/.zshrc".bold)
        print("\nOr restart your terminal.".gray)
    }

    private func installFishCompletions(homeDir: String) throws {
        let completionsDir = "\(homeDir)/.config/fish/completions"
        let completionFile = "\(completionsDir)/unused.fish"

        // Check if already installed
        if FileManager.default.fileExists(atPath: completionFile) && !force {
            print("✓ Completions already installed at \(completionFile)".yellow)
            print("  Use --force to reinstall".gray)
            return
        }

        // Create directory if it doesn't exist
        try FileManager.default.createDirectory(
            atPath: completionsDir,
            withIntermediateDirectories: true
        )

        // Generate and write completion script
        let script = Unused.completionScript(for: .fish)
        try script.write(toFile: completionFile, atomically: true, encoding: .utf8)

        print("✓ Successfully installed completions to \(completionFile)".green)
        print("\n" + "Completions are now active!".teal.bold)
        print("Fish loads completions automatically.".gray)
    }

    private func fileContainsCompletions(_ path: String) -> Bool {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return false
        }
        return content.contains("unused generate-completion-script")
    }

    private func appendToFile(_ path: String, content: String) throws {
        let fileManager = FileManager.default

        // Create file if it doesn't exist
        if !fileManager.fileExists(atPath: path) {
            fileManager.createFile(atPath: path, contents: nil)
        }

        // Read existing content
        var existingContent = ""
        if let data = fileManager.contents(atPath: path),
           let content = String(data: data, encoding: .utf8) {
            existingContent = content
        }

        // Append new content
        let newContent = existingContent + content + "\n"
        try newContent.write(toFile: path, atomically: true, encoding: .utf8)
    }

}

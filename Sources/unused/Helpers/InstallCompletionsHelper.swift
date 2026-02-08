//
//  Created by Fernando Romiti on 08/02/2025.
//

import ArgumentParser
import Foundation

enum Shell: String, ExpressibleByArgument {
    case bash, zsh, fish

    var completionShell: CompletionShell {
        switch self {
        case .bash: .bash
        case .zsh: .zsh
        case .fish: .fish
        }
    }
}

enum ZshVariant {
    case standard
    case ohMyZsh(customPath: String)
}

enum InstallCompletionsError: Error, LocalizedError {
    case shellDetectionFailed
    case installationFailed(String)
    case fileOperationFailed(String)

    var errorDescription: String? {
        switch self {
        case .shellDetectionFailed:
            "Could not detect your shell. Set the SHELL environment variable."
        case .installationFailed(let reason):
            "Installation failed: \(reason)"
        case .fileOperationFailed(let reason):
            "File operation failed: \(reason)"
        }
    }
}

protocol EnvironmentProviderProtocol {
    func environmentVariable(_ name: String) -> String?
}

struct SystemEnvironmentProvider: EnvironmentProviderProtocol {
    func environmentVariable(_ name: String) -> String? {
        ProcessInfo.processInfo.environment[name]
    }
}

protocol CompletionScriptProviderProtocol {
    func completionScript(for shell: Shell) -> String
}

struct DefaultCompletionScriptProvider: CompletionScriptProviderProtocol {
    func completionScript(for shell: Shell) -> String {
        Unused.completionScript(for: shell.completionShell)
    }
}

struct InstallCompletionsHelper {

    let fileManager: FileManagerProtocol
    let environment: EnvironmentProviderProtocol
    let completionScriptProvider: CompletionScriptProviderProtocol

    init(
        fileManager: FileManagerProtocol = FileManagerWrapper(),
        environment: EnvironmentProviderProtocol = SystemEnvironmentProvider(),
        completionScriptProvider: CompletionScriptProviderProtocol = DefaultCompletionScriptProvider()
    ) {
        self.fileManager = fileManager
        self.environment = environment
        self.completionScriptProvider = completionScriptProvider
    }

    func detectShell() throws -> Shell {
        guard let shellPath = environment.environmentVariable("SHELL") else {
            throw InstallCompletionsError.shellDetectionFailed
        }

        if shellPath.contains("zsh") {
            return .zsh
        } else if shellPath.contains("fish") {
            return .fish
        } else {
            return .bash
        }
    }

    func detectZshVariant() -> ZshVariant {
        let homeDir = fileManager.homeDirectoryForCurrentUser.path

        if let zshCustom = environment.environmentVariable("ZSH_CUSTOM") {
            return .ohMyZsh(customPath: zshCustom)
        }

        if let zshPath = environment.environmentVariable("ZSH") {
            let customPath = "\(zshPath)/custom"
            return .ohMyZsh(customPath: customPath)
        }

        let defaultOhMyZshPath = "\(homeDir)/.oh-my-zsh"
        if fileManager.fileExists(atPath: defaultOhMyZshPath) {
            return .ohMyZsh(customPath: "\(defaultOhMyZshPath)/custom")
        }

        return .standard
    }

    func install(shell: Shell, force: Bool) throws {
        let homeDir = fileManager.homeDirectoryForCurrentUser.path

        switch shell {
        case .bash:
            try installBashCompletions(homeDir: homeDir, force: force)
        case .zsh:
            try installZshCompletions(homeDir: homeDir, force: force)
        case .fish:
            try installFishCompletions(homeDir: homeDir, force: force)
        }
    }

    private func installBashCompletions(homeDir: String, force: Bool) throws {
        let rcFile = "\(homeDir)/.bashrc"
        let completionLine = """

        # Unused CLI completions
        if command -v unused &> /dev/null; then
            eval "$(unused --generate-completion-script=bash)"
        fi
        """

        if fileContainsUnusedCompletions(atPath: rcFile) && !force {
            print("✓ Completions already installed in ~/.bashrc".yellow)
            print("  Use --force to reinstall".overlay0)
            return
        }

        if force && fileContainsUnusedCompletions(atPath: rcFile) {
            try removeExistingCompletionBlock(from: rcFile)
        }

        try appendToFile(atPath: rcFile, content: completionLine)
        print("✓ Successfully installed completions to ~/.bashrc".green)
        printActivationInstructions(shell: .bash)
    }

    private func installZshCompletions(homeDir: String, force: Bool) throws {
        let variant = detectZshVariant()

        switch variant {
        case .ohMyZsh(let customPath):
            try installZshCompletionsForOhMyZsh(customPath: customPath, force: force)
        case .standard:
            try installZshCompletionsStandard(homeDir: homeDir, force: force)
        }
    }

    private func installZshCompletionsForOhMyZsh(customPath: String, force: Bool) throws {
        let completionsDir = "\(customPath)/completions"
        let completionFile = "\(completionsDir)/_unused"

        if fileManager.fileExists(atPath: completionFile) && !force {
            print("✓ Completions already installed at \(completionFile)".yellow)
            print("  Use --force to reinstall".overlay0)
            return
        }

        try fileManager.createDirectory(atPath: completionsDir, withIntermediateDirectories: true)

        let script = completionScriptProvider.completionScript(for: .zsh)
        try fileManager.writeString(script, toFile: completionFile)

        print("✓ Successfully installed completions to \(completionFile)".green)
        print("  (oh-my-zsh detected)".overlay0)
        printActivationInstructions(shell: .zsh, isOhMyZsh: true)
    }

    private func installZshCompletionsStandard(homeDir: String, force: Bool) throws {
        let completionsDir = "\(homeDir)/.zsh/completions"
        let completionFile = "\(completionsDir)/_unused"
        let rcFile = "\(homeDir)/.zshrc"

        if fileManager.fileExists(atPath: completionFile) && !force {
            print("✓ Completions already installed at \(completionFile)".yellow)
            print("  Use --force to reinstall".overlay0)
            return
        }

        try fileManager.createDirectory(atPath: completionsDir, withIntermediateDirectories: true)

        let script = completionScriptProvider.completionScript(for: .zsh)
        try fileManager.writeString(script, toFile: completionFile)

        if !fileContainsFpathSetup(atPath: rcFile) {
            let fpathSetup = """

            # Unused CLI completions - fpath setup (must be before compinit)
            fpath=(~/.zsh/completions $fpath)
            autoload -Uz compinit && compinit
            """
            try prependToZshrc(atPath: rcFile, content: fpathSetup)
        }

        print("✓ Successfully installed completions to \(completionFile)".green)
        printActivationInstructions(shell: .zsh, isOhMyZsh: false)
    }

    private func installFishCompletions(homeDir: String, force: Bool) throws {
        let completionsDir = "\(homeDir)/.config/fish/completions"
        let completionFile = "\(completionsDir)/unused.fish"

        if fileManager.fileExists(atPath: completionFile) && !force {
            print("✓ Completions already installed at \(completionFile)".yellow)
            print("  Use --force to reinstall".overlay0)
            return
        }

        try fileManager.createDirectory(atPath: completionsDir, withIntermediateDirectories: true)

        let script = completionScriptProvider.completionScript(for: .fish)
        try fileManager.writeString(script, toFile: completionFile)

        print("✓ Successfully installed completions to \(completionFile)".green)
        print("\n" + "Completions are now active!".teal.bold)
        print("Fish loads completions automatically.".overlay0)
    }

    private func fileContainsUnusedCompletions(atPath path: String) -> Bool {
        guard let data = fileManager.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else {
            return false
        }
        return content.contains("# Unused CLI completions")
    }

    private func fileContainsFpathSetup(atPath path: String) -> Bool {
        guard let data = fileManager.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else {
            return false
        }
        return content.contains("/.zsh/completions")
    }

    private func removeExistingCompletionBlock(from path: String) throws {
        guard let data = fileManager.contents(atPath: path),
              var content = String(data: data, encoding: .utf8) else {
            return
        }

        if let startRange = content.range(of: "\n# Unused CLI completions") {
            var endIndex = startRange.upperBound
            let lines = content[startRange.upperBound...].split(separator: "\n", omittingEmptySubsequences: false)

            for line in lines {
                if line.isEmpty || (!line.hasPrefix("#") && !line.hasPrefix("if ") &&
                   !line.hasPrefix("    ") && !line.hasPrefix("fi") && !line.hasPrefix("fpath") &&
                   !line.hasPrefix("autoload") && !line.hasPrefix("eval")) {
                    break
                }
                if line.hasPrefix("fi") || line.contains("compinit") {
                    endIndex = content.index(endIndex, offsetBy: line.count + 1, limitedBy: content.endIndex) ?? content.endIndex
                    break
                }
                endIndex = content.index(endIndex, offsetBy: line.count + 1, limitedBy: content.endIndex) ?? content.endIndex
            }

            content.removeSubrange(startRange.lowerBound..<endIndex)
            try fileManager.writeString(content, toFile: path)
        }
    }

    private func prependToZshrc(atPath path: String, content: String) throws {
        if !fileManager.fileExists(atPath: path) {
            fileManager.createFile(atPath: path, contents: nil)
        }

        guard let data = fileManager.contents(atPath: path),
              let existingContent = String(data: data, encoding: .utf8) else {
            try fileManager.writeString(content, toFile: path)
            return
        }

        let newContent = content + "\n" + existingContent
        try fileManager.writeString(newContent, toFile: path)
    }

    private func appendToFile(atPath path: String, content: String) throws {
        if !fileManager.fileExists(atPath: path) {
            fileManager.createFile(atPath: path, contents: nil)
        }

        var existingContent = ""
        if let data = fileManager.contents(atPath: path),
           let text = String(data: data, encoding: .utf8) {
            existingContent = text
        }

        let newContent = existingContent + content + "\n"
        try fileManager.writeString(newContent, toFile: path)
    }

    private func printActivationInstructions(shell: Shell, isOhMyZsh: Bool = false) {
        print("")
        print("To activate completions:".teal)

        switch shell {
        case .bash:
            print("  exec bash".bold)
            print("\nOr restart your terminal.".overlay0)
        case .zsh:
            print("  exec zsh".bold)
            if !isOhMyZsh {
                print("\nNote: If completions don't work, ensure compinit is called".overlay0)
                print("after fpath is set in your ~/.zshrc".overlay0)
            }
            print("\nOr restart your terminal.".overlay0)
        case .fish:
            break
        }
    }
}

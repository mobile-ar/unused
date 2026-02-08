//
//  Created by Fernando Romiti on 08/02/2025.
//

import Foundation
import Testing
@testable import unused

struct MockEnvironmentProvider: EnvironmentProviderProtocol {
    var variables: [String: String] = [:]

    func environmentVariable(_ name: String) -> String? {
        variables[name]
    }
}

struct MockCompletionScriptProvider: CompletionScriptProviderProtocol {
    func completionScript(for shell: Shell) -> String {
        "# Mock completion script for \(shell.rawValue)"
    }
}

struct InstallCompletionsHelperTests {

    @Test func detectShellReturnsZshWhenShellEnvContainsZsh() throws {
        var environment = MockEnvironmentProvider()
        environment.variables["SHELL"] = "/bin/zsh"

        let helper = InstallCompletionsHelper(
            fileManager: MockFileManager(),
            environment: environment,
            completionScriptProvider: MockCompletionScriptProvider()
        )

        let shell = try helper.detectShell()
        #expect(shell == .zsh)
    }

    @Test func detectShellReturnsBashWhenShellEnvContainsBash() throws {
        var environment = MockEnvironmentProvider()
        environment.variables["SHELL"] = "/bin/bash"

        let helper = InstallCompletionsHelper(
            fileManager: MockFileManager(),
            environment: environment,
            completionScriptProvider: MockCompletionScriptProvider()
        )

        let shell = try helper.detectShell()
        #expect(shell == .bash)
    }

    @Test func detectShellReturnsFishWhenShellEnvContainsFish() throws {
        var environment = MockEnvironmentProvider()
        environment.variables["SHELL"] = "/usr/local/bin/fish"

        let helper = InstallCompletionsHelper(
            fileManager: MockFileManager(),
            environment: environment,
            completionScriptProvider: MockCompletionScriptProvider()
        )

        let shell = try helper.detectShell()
        #expect(shell == .fish)
    }

    @Test func detectShellThrowsWhenShellEnvNotSet() {
        let environment = MockEnvironmentProvider()

        let helper = InstallCompletionsHelper(
            fileManager: MockFileManager(),
            environment: environment,
            completionScriptProvider: MockCompletionScriptProvider()
        )

        #expect(throws: InstallCompletionsError.self) {
            try helper.detectShell()
        }
    }

    @Test func detectZshVariantReturnsOhMyZshWhenZshCustomSet() {
        let fileManager = MockFileManager()
        var environment = MockEnvironmentProvider()
        environment.variables["ZSH_CUSTOM"] = "/Users/testuser/.oh-my-zsh/custom"

        let helper = InstallCompletionsHelper(
            fileManager: fileManager,
            environment: environment,
            completionScriptProvider: MockCompletionScriptProvider()
        )

        let variant = helper.detectZshVariant()

        if case .ohMyZsh(let customPath) = variant {
            #expect(customPath == "/Users/testuser/.oh-my-zsh/custom")
        } else {
            Issue.record("Expected oh-my-zsh variant")
        }
    }

    @Test func detectZshVariantReturnsOhMyZshWhenZshEnvSet() {
        let fileManager = MockFileManager()
        var environment = MockEnvironmentProvider()
        environment.variables["ZSH"] = "/Users/testuser/.oh-my-zsh"

        let helper = InstallCompletionsHelper(
            fileManager: fileManager,
            environment: environment,
            completionScriptProvider: MockCompletionScriptProvider()
        )

        let variant = helper.detectZshVariant()

        if case .ohMyZsh(let customPath) = variant {
            #expect(customPath == "/Users/testuser/.oh-my-zsh/custom")
        } else {
            Issue.record("Expected oh-my-zsh variant")
        }
    }

    @Test func detectZshVariantReturnsOhMyZshWhenDirectoryExists() {
        let fileManager = MockFileManager()
        fileManager.existingPaths.insert("/Users/testuser/.oh-my-zsh")
        let environment = MockEnvironmentProvider()

        let helper = InstallCompletionsHelper(
            fileManager: fileManager,
            environment: environment,
            completionScriptProvider: MockCompletionScriptProvider()
        )

        let variant = helper.detectZshVariant()

        if case .ohMyZsh(let customPath) = variant {
            #expect(customPath == "/Users/testuser/.oh-my-zsh/custom")
        } else {
            Issue.record("Expected oh-my-zsh variant")
        }
    }

    @Test func detectZshVariantReturnsStandardWhenNoOhMyZsh() {
        let fileManager = MockFileManager()
        let environment = MockEnvironmentProvider()

        let helper = InstallCompletionsHelper(
            fileManager: fileManager,
            environment: environment,
            completionScriptProvider: MockCompletionScriptProvider()
        )

        let variant = helper.detectZshVariant()

        if case .standard = variant {
            // Expected
        } else {
            Issue.record("Expected standard variant")
        }
    }

    @Test func installFishCreatesCompletionFile() throws {
        let fileManager = MockFileManager()
        var environment = MockEnvironmentProvider()
        environment.variables["SHELL"] = "/usr/local/bin/fish"

        let helper = InstallCompletionsHelper(
            fileManager: fileManager,
            environment: environment,
            completionScriptProvider: MockCompletionScriptProvider()
        )

        try helper.install(shell: .fish)

        #expect(fileManager.createdDirectories.contains("/Users/testuser/.config/fish/completions"))
        #expect(fileManager.writtenFiles["/Users/testuser/.config/fish/completions/unused.fish"] != nil)
    }

    @Test func installFishReinstallsWhenAlreadyInstalled() throws {
        let fileManager = MockFileManager()
        fileManager.existingPaths.insert("/Users/testuser/.config/fish/completions/unused.fish")
        var environment = MockEnvironmentProvider()
        environment.variables["SHELL"] = "/usr/local/bin/fish"

        let helper = InstallCompletionsHelper(
            fileManager: fileManager,
            environment: environment,
            completionScriptProvider: MockCompletionScriptProvider()
        )

        try helper.install(shell: .fish)

        #expect(fileManager.removedPaths.contains("/Users/testuser/.config/fish/completions/unused.fish"))
        #expect(fileManager.createdDirectories.contains("/Users/testuser/.config/fish/completions"))
    }

    @Test func installZshForOhMyZshUsesCustomCompletionsDir() throws {
        let fileManager = MockFileManager()
        var environment = MockEnvironmentProvider()
        environment.variables["SHELL"] = "/bin/zsh"
        environment.variables["ZSH_CUSTOM"] = "/Users/testuser/.oh-my-zsh/custom"

        let helper = InstallCompletionsHelper(
            fileManager: fileManager,
            environment: environment,
            completionScriptProvider: MockCompletionScriptProvider()
        )

        try helper.install(shell: .zsh)

        #expect(fileManager.createdDirectories.contains("/Users/testuser/.oh-my-zsh/custom/completions"))
        #expect(fileManager.writtenFiles["/Users/testuser/.oh-my-zsh/custom/completions/_unused"] != nil)
    }

    @Test func installZshStandardUsesZshCompletionsDir() throws {
        let fileManager = MockFileManager()
        var environment = MockEnvironmentProvider()
        environment.variables["SHELL"] = "/bin/zsh"

        let helper = InstallCompletionsHelper(
            fileManager: fileManager,
            environment: environment,
            completionScriptProvider: MockCompletionScriptProvider()
        )

        try helper.install(shell: .zsh)

        #expect(fileManager.createdDirectories.contains("/Users/testuser/.zsh/completions"))
        #expect(fileManager.writtenFiles["/Users/testuser/.zsh/completions/_unused"] != nil)
    }

    @Test func installZshCleansUpDuplicateCompletions() throws {
        let fileManager = MockFileManager()
        fileManager.existingPaths.insert("/Users/testuser/.zsh/completions/_unused")
        fileManager.existingPaths.insert("/Users/testuser/.oh-my-zsh/custom/completions/_unused")
        var environment = MockEnvironmentProvider()
        environment.variables["SHELL"] = "/bin/zsh"

        let helper = InstallCompletionsHelper(
            fileManager: fileManager,
            environment: environment,
            completionScriptProvider: MockCompletionScriptProvider()
        )

        try helper.install(shell: .zsh)

        #expect(fileManager.removedPaths.contains("/Users/testuser/.zsh/completions/_unused"))
        #expect(fileManager.removedPaths.contains("/Users/testuser/.oh-my-zsh/custom/completions/_unused"))
    }

    @Test func installZshOhMyZshCleansUpStandardLocation() throws {
        let fileManager = MockFileManager()
        fileManager.existingPaths.insert("/Users/testuser/.zsh/completions/_unused")
        var environment = MockEnvironmentProvider()
        environment.variables["SHELL"] = "/bin/zsh"
        environment.variables["ZSH_CUSTOM"] = "/Users/testuser/.oh-my-zsh/custom"

        let helper = InstallCompletionsHelper(
            fileManager: fileManager,
            environment: environment,
            completionScriptProvider: MockCompletionScriptProvider()
        )

        try helper.install(shell: .zsh)

        #expect(fileManager.removedPaths.contains("/Users/testuser/.zsh/completions/_unused"))
        #expect(fileManager.createdDirectories.contains("/Users/testuser/.oh-my-zsh/custom/completions"))
    }

    @Test func installBashAppendsToBashrc() throws {
        let fileManager = MockFileManager()
        fileManager.setFileContent("# existing content\n", atPath: "/Users/testuser/.bashrc")
        var environment = MockEnvironmentProvider()
        environment.variables["SHELL"] = "/bin/bash"

        let helper = InstallCompletionsHelper(
            fileManager: fileManager,
            environment: environment,
            completionScriptProvider: MockCompletionScriptProvider()
        )

        try helper.install(shell: .bash)

        let content = fileManager.writtenFiles["/Users/testuser/.bashrc"] ?? ""
        #expect(content.contains("# Unused CLI completions"))
        #expect(content.contains("eval"))
    }

    @Test func installBashReinstallsWhenAlreadyInstalled() throws {
        let fileManager = MockFileManager()
        fileManager.setFileContent("# existing\n# Unused CLI completions\nif command -v unused &> /dev/null; then\n    eval \"$(unused --generate-completion-script=bash)\"\nfi\n", atPath: "/Users/testuser/.bashrc")
        var environment = MockEnvironmentProvider()
        environment.variables["SHELL"] = "/bin/bash"

        let helper = InstallCompletionsHelper(
            fileManager: fileManager,
            environment: environment,
            completionScriptProvider: MockCompletionScriptProvider()
        )

        try helper.install(shell: .bash)

        let content = fileManager.writtenFiles["/Users/testuser/.bashrc"] ?? ""
        let occurrences = content.components(separatedBy: "# Unused CLI completions").count - 1
        #expect(occurrences == 1)
    }

    @Test func installFishCleansUpSystemLocations() throws {
        let fileManager = MockFileManager()
        fileManager.existingPaths.insert("/usr/local/share/fish/vendor_completions.d/unused.fish")
        fileManager.existingPaths.insert("/opt/homebrew/share/fish/vendor_completions.d/unused.fish")
        var environment = MockEnvironmentProvider()
        environment.variables["SHELL"] = "/usr/local/bin/fish"

        let helper = InstallCompletionsHelper(
            fileManager: fileManager,
            environment: environment,
            completionScriptProvider: MockCompletionScriptProvider()
        )

        try helper.install(shell: .fish)

        #expect(fileManager.removedPaths.contains("/usr/local/share/fish/vendor_completions.d/unused.fish"))
        #expect(fileManager.removedPaths.contains("/opt/homebrew/share/fish/vendor_completions.d/unused.fish"))
    }
}
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

        try helper.install(shell: .fish, force: false)

        #expect(fileManager.createdDirectories.contains("/Users/testuser/.config/fish/completions"))
    }

    @Test func installFishSkipsWhenAlreadyInstalledAndNoForce() throws {
        let fileManager = MockFileManager()
        fileManager.existingPaths.insert("/Users/testuser/.config/fish/completions/unused.fish")
        var environment = MockEnvironmentProvider()
        environment.variables["SHELL"] = "/usr/local/bin/fish"

        let helper = InstallCompletionsHelper(
            fileManager: fileManager,
            environment: environment,
            completionScriptProvider: MockCompletionScriptProvider()
        )

        try helper.install(shell: .fish, force: false)

        #expect(fileManager.createdDirectories.isEmpty)
    }

    @Test func installFishReinstallsWhenForced() throws {
        let fileManager = MockFileManager()
        fileManager.existingPaths.insert("/Users/testuser/.config/fish/completions/unused.fish")
        var environment = MockEnvironmentProvider()
        environment.variables["SHELL"] = "/usr/local/bin/fish"

        let helper = InstallCompletionsHelper(
            fileManager: fileManager,
            environment: environment,
            completionScriptProvider: MockCompletionScriptProvider()
        )

        try helper.install(shell: .fish, force: true)

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

        try helper.install(shell: .zsh, force: false)

        #expect(fileManager.createdDirectories.contains("/Users/testuser/.oh-my-zsh/custom/completions"))
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

        try helper.install(shell: .zsh, force: false)

        #expect(fileManager.createdDirectories.contains("/Users/testuser/.zsh/completions"))
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

        try helper.install(shell: .bash, force: false)

        #expect(fileManager.existingPaths.contains("/Users/testuser/.bashrc"))
    }

    @Test func installBashSkipsWhenAlreadyInstalledAndNoForce() throws {
        let fileManager = MockFileManager()
        fileManager.setFileContent("# Unused CLI completions\neval", atPath: "/Users/testuser/.bashrc")
        var environment = MockEnvironmentProvider()
        environment.variables["SHELL"] = "/bin/bash"

        let helper = InstallCompletionsHelper(
            fileManager: fileManager,
            environment: environment,
            completionScriptProvider: MockCompletionScriptProvider()
        )

        let originalContent = fileManager.fileContents["/Users/testuser/.bashrc"]

        try helper.install(shell: .bash, force: false)

        #expect(fileManager.fileContents["/Users/testuser/.bashrc"] == originalContent)
    }
}

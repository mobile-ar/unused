//
//  Created by Fernando Romiti on 25/01/2026.
//

@testable import unused

actor MockConsoleSpinner: ConsoleSpinnerProtocol {
    private(set) var startCalled = false
    private(set) var stopCalled = false
    private(set) var lastMessage: String?
    private(set) var lastSuccessValue: Bool?

    func start(message: String) async {
        startCalled = true
        lastMessage = message
    }

    func stop(success: Bool) async {
        stopCalled = true
        lastSuccessValue = success
    }

    func reset() {
        startCalled = false
        stopCalled = false
        lastMessage = nil
        lastSuccessValue = nil
    }
}

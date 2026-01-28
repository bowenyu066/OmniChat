import Foundation
import SwiftUI
import LocalAuthentication

final class AuthManager: ObservableObject {
    static let shared = AuthManager()
    private let lastAuthKey = "last_auth_time"
    private var lastAuthTime: Double {
        get { UserDefaults.standard.double(forKey: lastAuthKey) }
        set { UserDefaults.standard.set(newValue, forKey: lastAuthKey) }
    }

    // 30 days grace period
    let graceInterval: TimeInterval = 30 * 24 * 60 * 60

    var needsAppUnlock: Bool {
        let now = Date().timeIntervalSince1970
        return lastAuthTime == 0 || (now - lastAuthTime) > graceInterval
    }

    func markAuthenticated() {
        lastAuthTime = Date().timeIntervalSince1970
    }

    @MainActor
    func authenticateAppIfNeeded() async {
        guard needsAppUnlock else { return }
        do {
            try await authenticate(defaultBiometrics: true)
            markAuthenticated()
        } catch {
            // You may decide to handle cancellation or failure differently (e.g., lock UI)
            // For now, simply do nothing; user can retry by re-opening app or entering settings.
            print("App authentication failed: \(error.localizedDescription)")
        }
    }

    func requireKeychainAuth() async throws {
        try await authenticate(defaultBiometrics: true)
    }

    private func authenticate(defaultBiometrics: Bool) async throws {
        let context = LAContext()
        var authError: NSError?

        if defaultBiometrics, context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) {
            do {
                try await context.evaluatePolicyAsync(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Please authenticate with biometrics")
                return
            } catch {
                // Fallback to passcode if possible
                let fallbackContext = LAContext()
                if fallbackContext.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) {
                    try await fallbackContext.evaluatePolicyAsync(.deviceOwnerAuthentication, localizedReason: "Please enter your password to authenticate")
                    return
                } else {
                    throw error
                }
            }
        }

        // Directly use passcode (and biometrics if available) authentication
        let passcodeContext = LAContext()
        guard passcodeContext.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            throw authError ?? NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Device does not support authentication"])
        }
        try await passcodeContext.evaluatePolicyAsync(.deviceOwnerAuthentication, localizedReason: "Please enter your password to authenticate")
    }
}

private extension LAContext {
    func evaluatePolicyAsync(_ policy: LAPolicy, localizedReason: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.evaluatePolicy(policy, localizedReason: localizedReason) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: NSError(domain: "Auth", code: -2, userInfo: [NSLocalizedDescriptionKey: "Authentication was not successful"]))
                }
            }
        }
    }
}

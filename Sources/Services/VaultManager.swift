import Foundation
import LocalAuthentication
import CryptoKit
import Security

/// Tiny Keychain wrapper for storing the vault PIN hash securely.
enum KeychainStore {
    static func save(_ data: Data, for key: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(base as CFDictionary)
        var attrs = base
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(attrs as CFDictionary, nil)
    }

    static func load(_ key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
}

/// Owns the locked/unlocked state of the private vault.
@MainActor
final class VaultManager: ObservableObject {
    @Published var isUnlocked = false

    private let pinKey = "bingebuddy.vault.pinHash"

    var hasPIN: Bool { KeychainStore.load(pinKey) != nil }

    var biometryAvailable: Bool {
        let context = LAContext()
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    func authenticateWithBiometrics() async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = ""   // we use our own PIN, not the device passcode
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return false
        }
        let success = await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                   localizedReason: "Unlock your private vault") { ok, _ in
                continuation.resume(returning: ok)
            }
        }
        if success { isUnlocked = true }
        return success
    }

    func setPIN(_ pin: String) {
        KeychainStore.save(Self.hash(pin), for: pinKey)
        isUnlocked = true
    }

    func verifyPIN(_ pin: String) -> Bool {
        guard let stored = KeychainStore.load(pinKey) else { return false }
        let ok = (stored == Self.hash(pin))
        if ok { isUnlocked = true }
        return ok
    }

    func lock() { isUnlocked = false }

    private static func hash(_ pin: String) -> Data {
        let salted = "BingeBuddyVault.v1." + pin
        return Data(SHA256.hash(data: Data(salted.utf8)))
    }
}

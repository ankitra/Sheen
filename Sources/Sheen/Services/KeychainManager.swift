import Foundation
import KeychainAccess

final class KeychainManager {
    private let keychain = Keychain(service: "com.ankitra.sheen.app")
    private let tokenKey = "github_pat"

    var hasToken: Bool {
        getToken() != nil
    }

    func saveToken(_ token: String) {
        keychain[tokenKey] = token
    }

    func getToken() -> String? {
        keychain[tokenKey]
    }

    func deleteToken() {
        try? keychain.remove(tokenKey)
    }
}

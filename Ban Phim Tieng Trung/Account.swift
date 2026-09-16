//
//  Account.swift
//  Tài khoản người dùng: đăng nhập bằng Apple để đồng bộ tiến độ giữa các thiết bị.
//  Mã người dùng giữ trong Keychain; Apple chỉ gửi tên và email ở lần đăng nhập đầu tiên,
//  nên lần sau phải dùng lại thông tin đã lưu.
//

import AuthenticationServices
import SwiftUI

struct Account: Codable, Equatable {
    enum Provider: String, Codable {
        case apple, google

        var label: String {
            switch self {
            case .apple: "Apple"
            case .google: "Google"
            }
        }
    }

    var userID: String
    var name: String
    var email: String
    var provider: Provider
    var signedInAt: Date

    var displayName: String {
        if !name.isEmpty { return name }
        if !email.isEmpty { return email.components(separatedBy: "@").first ?? email }
        return "Bạn"
    }

    /// Chữ cái đầu để vẽ ảnh đại diện khi không có ảnh.
    var initials: String {
        let parts = displayName.split(separator: " ")
        let letters = parts.suffix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}

final class AccountStore: ObservableObject {
    static let shared = AccountStore()

    @Published private(set) var account: Account?
    @Published var errorMessage: String?

    var isSignedIn: Bool { account != nil }

    private static let keychainService = "hihi.banphimtrung.account"
    private static let keychainAccount = "signedInUser"

    private init() {
        account = Self.load()
        refreshCredentialState()
    }

    // MARK: - Đăng nhập bằng Apple

    func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = "Không đọc được thông tin đăng nhập từ Apple."
                return
            }
            // Apple chỉ gửi tên và email lần đầu; những lần sau giữ lại thông tin cũ.
            let previous = account?.userID == credential.user ? account : nil
            let name = [credential.fullName?.familyName, credential.fullName?.givenName]
                .compactMap { $0 }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            let signedIn = Account(
                userID: credential.user,
                name: name.isEmpty ? (previous?.name ?? "") : name,
                email: credential.email ?? previous?.email ?? "",
                provider: .apple,
                signedInAt: Date()
            )
            save(signedIn)
            errorMessage = nil
            CloudSync.shared.start()
            CloudSync.shared.syncNow()
        case let .failure(error):
            // Người dùng bấm huỷ thì không phải lỗi, đừng doạ họ bằng thông báo đỏ.
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            errorMessage = "Đăng nhập không thành công: \(error.localizedDescription)"
        }
    }

    /// Người dùng có thể thu hồi quyền trong Cài đặt → Apple ID → Đăng nhập bằng Apple.
    func refreshCredentialState() {
        guard let account, account.provider == .apple else { return }
        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: account.userID) { [weak self] state, _ in
            guard state == .revoked || state == .notFound else { return }
            DispatchQueue.main.async { self?.signOut() }
        }
    }

    func signOut() {
        account = nil
        Self.deleteFromKeychain()
    }

    private func save(_ account: Account) {
        self.account = account
        guard let data = try? JSONEncoder().encode(account) else { return }
        Self.deleteFromKeychain()
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        SecItemAdd(attributes as CFDictionary, nil)
    }

    private static func load() -> Account? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return try? JSONDecoder().decode(Account.self, from: data)
    }

    private static func deleteFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

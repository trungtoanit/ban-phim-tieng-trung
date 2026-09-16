//
//  AccountView.swift
//  Màn hình tài khoản: đăng nhập bằng Apple để đồng bộ tiến độ, xem hồ sơ và đăng xuất.
//

import AuthenticationServices
import SwiftUI

private let accentRed = Color(red: 0.86, green: 0.17, blue: 0.16)

/// Mục "Hồ sơ" (giống web): đã đăng nhập website thì là tường của chính mình (có nút Đăng xuất);
/// chưa đăng nhập thì là thẻ đăng nhập. Cài đặt cũ (iCloud, tài khoản Apple…) nằm sau nút ⚙️.
struct AccountTabView: View {
    @ObservedObject private var web = WebAccountStore.shared
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if web.isSignedIn, let me = web.user {
                    SocialProfileView(user: SocialUser(id: me.id, name: me.name, username: me.username, avatar: me.avatar),
                                      onSignOut: { WebAccountStore.shared.signOut() })
                        .id(me.id)
                } else {
                    SocialSignInCard(
                        icon: "person.crop.circle.fill",
                        title: "Đăng nhập",
                        message: "Đăng nhập tài khoản website để xem tường của bạn, huân chương, bài đăng và học cùng bạn bè."
                    )
                    .navigationTitle("Hồ sơ")
                }
            }
            .homeBackButton()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Cài đặt")
                }
            }
            .navigationDestination(for: SocialUser.self) { user in
                SocialProfileView(user: user)
            }
            .roomDestinations()
            .sheet(isPresented: $showSettings) {
                AccountSettingsView()
            }
        }
        .tint(socialRed)
    }
}

/// Cài đặt tài khoản trên máy: đăng nhập Apple, đồng bộ iCloud, tài khoản website.
struct AccountSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = AccountStore.shared
    @ObservedObject private var sync = CloudSync.shared
    @State private var syncOn = CloudSync.shared.isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            List {
                if let account = store.account {
                    profileSection(account)
                    syncSection
                    WebAccountSection()
                    Section {
                        Button("Đăng xuất", role: .destructive) { confirmSignOut = true }
                    } footer: {
                        Text("Đăng xuất chỉ thoát tài khoản trên máy này. Bài học, câu đã lưu và chuỗi ngày vẫn còn trong máy.")
                    }
                } else {
                    signInSection
                    WebAccountSection()
                }
            }
            .navigationTitle("Cài đặt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { dismiss() }
                }
            }
            .confirmationDialog("Đăng xuất khỏi tài khoản?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Đăng xuất", role: .destructive) { store.signOut() }
            }
            .alert("Đăng nhập", isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(store.errorMessage ?? "")
            }
        }
    }

    // MARK: - Chưa đăng nhập

    private var signInSection: some View {
        Section {
            VStack(spacing: 14) {
                MascotView(mood: .happy, size: 96, animated: false)
                Text("Đăng nhập để giữ tiến độ")
                    .font(.title3.weight(.bold))
                Text("Có tài khoản thì đổi máy hay cài lại app vẫn còn chuỗi ngày, câu đã lưu và từ vựng của bạn.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    store.handleAppleSignIn(result)
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 48)
                .cornerRadius(12)

                Label("Đăng nhập Google: sẽ bổ sung sau", systemImage: "g.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Nút Apple chỉ chạy khi app được ký bằng tài khoản Apple Developer trả phí (tài khoản cá nhân miễn phí không bật được Sign in with Apple và iCloud).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        } footer: {
            Text("App không giữ mật khẩu của bạn. Apple chỉ gửi tên và email (bạn có thể chọn ẩn email), lưu ngay trên máy này.")
        }
    }

    // MARK: - Đã đăng nhập

    private func profileSection(_ account: Account) -> some View {
        Section {
            HStack(spacing: 14) {
                Text(account.initials)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(LinearGradient(colors: AppTab.account.colors,
                                                            startPoint: .topLeading, endPoint: .bottomTrailing)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(account.displayName)
                        .font(.headline)
                    if !account.email.isEmpty {
                        Text(account.email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Label("Đăng nhập bằng \(account.provider.label)", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var syncSection: some View {
        Section {
            Toggle("Đồng bộ qua iCloud", isOn: Binding(
                get: { syncOn },
                set: { syncOn = $0; sync.isEnabled = $0 }
            ))
            HStack {
                Button("Đồng bộ ngay") { sync.syncNow() }
                    .disabled(!syncOn || sync.isSyncing)
                Spacer()
                if sync.isSyncing {
                    ProgressView()
                } else if let last = sync.lastSynced {
                    Text(Self.timeFormatter.localizedString(for: last, relativeTo: Date()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let error = sync.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Đồng bộ")
        } footer: {
            Text("Câu đã thuộc, câu đã lưu, từ vựng, tình huống tự tạo và chuỗi ngày được giữ trong iCloud của bạn, máy nào đăng nhập cùng Apple ID cũng thấy. Hai máy học lệch nhau thì lấy phần nhiều hơn, không xoá của nhau.")
        }
    }

    private static let timeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        return formatter
    }()
}

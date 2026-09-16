//
//  FriendsView.swift
//  Bạn bè kiểu Duolingo: theo dõi nhau, bảng xếp hạng số câu nói trong tuần, gợi ý kết bạn.
//  Dữ liệu dùng chung với trang ban-be.php của website (api/social.php).
//

import PhotosUI
import SwiftUI

let socialRed = Color(red: 0.86, green: 0.17, blue: 0.16)

struct FriendsView: View {
    @ObservedObject private var web = WebAccountStore.shared

    var body: some View {
        NavigationStack {
            Group {
                if web.isSignedIn {
                    FriendsHomeView()
                } else {
                    SocialSignInCard(
                        icon: "person.2.fill",
                        title: "Học cùng bạn bè",
                        message: "Cần tài khoản để theo dõi bạn bè, xem ai nói nhiều câu nhất tuần và giữ chuỗi ngày cùng nhau."
                    )
                    .navigationTitle("Bạn bè")
                }
            }
            .homeBackButton()
        }
    }
}

// MARK: - Dữ liệu

@MainActor
final class FriendsModel: ObservableObject {
    @Published var payload = FriendsPayload.empty
    @Published var results: [SocialUser] = []
    @Published var loaded = false
    @Published var searching = false
    @Published var errorMessage: String?
    /// Bảng vàng: top 3 các tuần đã chốt (mới nhất trước).
    @Published var awardWeeks: [AwardWeek] = []
    @Published var awardsLoaded = false

    func loadAwards() async {
        if let weeks = try? await SocialAPI.awards(weeks: 8) {
            awardWeeks = weeks
        }
        awardsLoaded = true
    }

    func load() async {
        do {
            payload = try await SocialAPI.friends()
            loaded = true
        } catch is CancellationError {
        } catch {
            // Lần tải đầu hỏng thì báo; tự làm mới lỗi thì im lặng.
            if !loaded { errorMessage = error.localizedDescription }
        }
    }

    func search(_ query: String) async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else {
            results = []
            return
        }
        searching = true
        defer { searching = false }
        do {
            let users = try await SocialAPI.search(q)
            if !Task.isCancelled { results = users }
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Theo dõi / bỏ theo dõi: đổi ngay trên màn hình, lỗi thì trả lại như cũ.
    /// Trả về hồ sơ mới của máy chủ, nil nếu lỗi.
    @discardableResult
    func toggleFollow(_ user: SocialUser) async -> SocialUser? {
        let follow = !user.following
        let before = (payload, results)
        apply(id: user.id) { $0.following = follow }
        do {
            let updated: SocialUser
            if follow {
                updated = try await SocialAPI.follow(userId: user.id)
            } else {
                updated = try await SocialAPI.unfollow(userId: user.id)
            }
            apply(id: user.id) {
                $0.following = updated.following
                $0.followsMe = updated.followsMe
            }
            await load()
            return updated
        } catch {
            (payload, results) = before
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func apply(id: Int, _ change: (inout SocialUser) -> Void) {
        func update(_ list: inout [SocialUser]) {
            for index in list.indices where list[index].id == id { change(&list[index]) }
        }
        update(&payload.following)
        update(&payload.followers)
        update(&payload.suggestions)
        update(&payload.leaderboard)
        update(&results)
    }
}

// MARK: - Màn chính

private struct FriendsHomeView: View {
    enum Tab: String {
        case feed, friends
    }

    @StateObject private var model = FriendsModel()
    @StateObject private var feed = FeedModel(source: .feed)
    @State private var query = ""
    @State private var showFollowers = false
    @State private var tab: Tab = .feed

    private var isSearching: Bool { query.trimmingCharacters(in: .whitespaces).count >= 2 }

    var body: some View {
        content
        .navigationTitle("Bạn bè")
        .toolbar {
            if let me = model.payload.me {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(value: me) {
                        HStack(spacing: 6) {
                            SocialAvatar(url: me.avatarURL, initial: me.initial, size: 26)
                            Text("Tường của tôi")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .accessibilityLabel("Tường của tôi")
                }
            }
        }
        .navigationDestination(for: SocialUser.self) { user in
            SocialProfileView(user: user, model: model)
        }
        .roomDestinations()
        .searchable(text: $query, prompt: "Tìm theo tên hoặc @username")
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        // Gõ xong 300ms mới tìm, để không gọi máy chủ theo từng chữ.
        .task(id: query) {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await model.search(query)
        }
        .refreshable {
            if tab == .feed && !isSearching {
                await feed.load()
            }
            await model.load()
            await model.loadAwards()
        }
        // Tải lần đầu rồi tự làm mới mỗi 30 giây khi màn hình đang mở.
        .task {
            await model.load()
            await model.loadAwards()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { break }
                await model.load()
            }
        }
        .alert("Có lỗi", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        if isSearching || tab == .friends {
            List {
                if isSearching {
                    searchSection
                } else {
                    Section {
                        tabPicker
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                    }
                    listSection
                    GoldBoardSection(weeks: model.awardWeeks, loaded: model.awardsLoaded)
                    leaderboardSection
                    suggestionsSection
                }
            }
            .listStyle(.insetGrouped)
            .overlay {
                if !model.loaded && model.errorMessage == nil && !isSearching {
                    ProgressView("Đang tải…")
                }
            }
        } else {
            feedScroll
        }
    }

    private var tabPicker: some View {
        Picker("", selection: $tab) {
            Text("Bảng tin").tag(Tab.feed)
            Text("Bạn bè").tag(Tab.friends)
        }
        .pickerStyle(.segmented)
    }

    // MARK: Bảng tin

    private var feedScroll: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                tabPicker
                    .padding(.top, 8)
                FeedComposerCard(me: model.payload.me) { post in
                    feed.insert(post)
                }
                Picker("", selection: $feed.explore) {
                    Text("Mọi người").tag(true)
                    Text("Đang theo dõi").tag(false)
                }
                .pickerStyle(.segmented)
                FeedPostsList(feed: feed, emptyText: feed.explore
                              ? "Chưa ai đăng bài. Hãy là người đầu tiên!"
                              : "Chưa có bài nào từ bạn và những người bạn theo dõi. Xem Mọi người hoặc đăng bài đầu tiên nhé!")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .task {
            if !feed.loaded { await feed.load() }
        }
        .onChange(of: feed.explore) { _ in
            feed.loaded = false
            feed.posts = []
            feed.hasMore = false
            Task { await feed.load() }
        }
        .onDisappear { FeedAudioPlayer.shared.stop() }
        .alert("Có lỗi", isPresented: Binding(get: { feed.errorMessage != nil }, set: { if !$0 { feed.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(feed.errorMessage ?? "")
        }
    }

    // MARK: Tìm kiếm

    @ViewBuilder
    private var searchSection: some View {
        Section {
            if model.results.isEmpty {
                HStack {
                    if model.searching { ProgressView() }
                    Text(model.searching ? "Đang tìm…" : "Không tìm thấy ai.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(model.results) { user in
                    userRow(user)
                }
            }
        } header: {
            Text("Kết quả tìm kiếm")
        }
    }

    // MARK: Đang theo dõi / Người theo dõi

    private var listSection: some View {
        Section {
            Picker("", selection: $showFollowers) {
                Text("Đang theo dõi (\(model.payload.following.count))").tag(false)
                Text("Người theo dõi (\(model.payload.followers.count))").tag(true)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            let users = showFollowers ? model.payload.followers : model.payload.following
            if users.isEmpty, model.loaded {
                Text(showFollowers
                     ? "Chưa có ai theo dõi bạn. Luyện nói đều đặn để lọt vào gợi ý của người khác nhé!"
                     : "Bạn chưa theo dõi ai. Tìm bạn bè ở ô tìm kiếm hoặc xem gợi ý bên dưới.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(users) { user in
                    userRow(user)
                }
            }
        }
    }

    // MARK: Bảng xếp hạng tuần

    @ViewBuilder
    private var leaderboardSection: some View {
        if !model.payload.leaderboard.isEmpty {
            Section {
                ForEach(Array(model.payload.leaderboard.enumerated()), id: \.element.id) { index, user in
                    NavigationLink(value: user) {
                        leaderboardRow(rank: index + 1, user: user)
                    }
                    .listRowBackground(user.isMe ? socialRed.opacity(0.1) : Color(.secondarySystemGroupedBackground))
                }
            } header: {
                Text("Bảng xếp hạng tuần")
            } footer: {
                Text("Số câu tiếng Trung đã nói trong tuần này (từ thứ Hai), gồm bạn và những người bạn theo dõi.")
            }
        }
    }

    private func leaderboardRow(rank: Int, user: SocialUser) -> some View {
        HStack(spacing: 12) {
            Group {
                switch rank {
                case 1: Text("🥇")
                case 2: Text("🥈")
                case 3: Text("🥉")
                default: Text("\(rank)").foregroundStyle(.secondary)
                }
            }
            .font(rank <= 3 ? .title3 : .subheadline.weight(.semibold))
            .frame(width: 30)

            SocialAvatar(url: user.avatarURL, initial: user.initial, size: 36, online: user.online,
                         ring: Color(.secondarySystemGroupedBackground))
            Text(user.isMe ? "Bạn" : user.name)
                .font(.subheadline.weight(user.isMe ? .bold : .semibold))
                .lineLimit(1)
            MedalChips(medals: user.medals)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(user.weekSentences) câu")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(user.isMe ? socialRed : .primary)
                if user.streak > 0 {
                    Text("🔥 \(user.streak)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: Gợi ý

    @ViewBuilder
    private var suggestionsSection: some View {
        if !model.payload.suggestions.isEmpty {
            Section {
                ForEach(model.payload.suggestions) { user in
                    userRow(user)
                }
            } header: {
                Text("Gợi ý kết bạn")
            } footer: {
                Text("Những người học chăm chỉ trong 7 ngày qua.")
            }
        }
    }

    private func userRow(_ user: SocialUser) -> some View {
        NavigationLink(value: user) {
            SocialUserRow(user: user) {
                Task { await model.toggleFollow(user) }
            }
        }
    }
}

// MARK: - Dòng người dùng

struct SocialUserRow: View {
    let user: SocialUser
    let onFollow: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            SocialAvatar(url: user.avatarURL, initial: user.initial, size: 44, online: user.online,
                         ring: Color(.secondarySystemGroupedBackground))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(user.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    MedalChips(medals: user.medals)
                }
                if let handle = user.handle {
                    Text(handle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(statsLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if !user.isMe {
                FollowButton(user: user, action: onFollow)
            }
        }
        .padding(.vertical, 2)
    }

    private var statsLine: String {
        let week = "\(user.weekSentences) câu tuần này"
        let line = user.streak > 0 ? "🔥 \(user.streak) · \(week)" : week
        return user.online && !user.isMe ? "Đang online · " + line : line
    }
}

/// Nút viên: đỏ đặc "Theo dõi", viền "Đang theo dõi", "Theo dõi lại" khi người đó đã theo dõi mình.
struct FollowButton: View {
    let user: SocialUser
    var large = false
    let action: () -> Void

    private var title: String {
        if user.following { return "Đang theo dõi" }
        return user.followsMe ? "Theo dõi lại" : "Theo dõi"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if user.following {
                    Image(systemName: "checkmark")
                        .font(.system(size: large ? 13 : 10, weight: .bold))
                }
                Text(title)
                    .lineLimit(1)
            }
            .font((large ? Font.subheadline : .caption).weight(.semibold))
            .foregroundStyle(user.following ? socialRed : .white)
            .padding(.horizontal, large ? 22 : 12)
            .padding(.vertical, large ? 11 : 7)
            .frame(maxWidth: large ? .infinity : nil)
            .background {
                if user.following {
                    Capsule().strokeBorder(socialRed, lineWidth: 1.5)
                } else {
                    Capsule().fill(socialRed)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.borderless)
        .animation(.easeInOut(duration: 0.15), value: user.following)
        .accessibilityLabel(title)
    }
}

/// Màu xanh chuẩn cho trạng thái đang online.
let onlineGreen = Color(red: 0.2, green: 0.72, blue: 0.35)

struct OnlineDot: View {
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(onlineGreen)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Ảnh đại diện; không có ảnh thì là vòng tròn đỏ với chữ cái đầu tên.
/// `online`: chấm xanh có viền màu nền ở góc dưới phải.
struct SocialAvatar: View {
    let url: URL?
    let initial: String
    var size: CGFloat = 40
    var online: Bool = false
    /// Màu viền quanh chấm online (trùng màu nền phía sau).
    var ring: Color = Color(.systemBackground)

    private var dotSize: CGFloat { max(8, size * 0.28) }
    private var ringWidth: CGFloat { max(1.5, dotSize * 0.18) }

    var body: some View {
        ZStack {
            placeholder
            if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(alignment: .bottomTrailing) {
            if online {
                Circle()
                    .fill(ring)
                    .frame(width: dotSize, height: dotSize)
                    .overlay(OnlineDot(size: dotSize - ringWidth * 2))
                    .offset(x: size >= 60 ? -size * 0.04 : 1, y: size >= 60 ? -size * 0.04 : 1)
            }
        }
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Circle()
            .fill(LinearGradient(colors: AppTab.friends.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
                Text(initial.isEmpty ? "?" : initial)
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            )
    }
}

// MARK: - Hồ sơ (tường kiểu Duolingo)

struct SocialProfileView: View {
    /// Có khi mở từ màn Bạn bè (để cập nhật danh sách khi theo dõi); mở từ phòng chat thì nil.
    var model: FriendsModel?
    @State private var user: SocialUser
    @State private var busy = false
    @State private var loaded = false
    @State private var errorMessage: String?
    @StateObject private var postsFeed: FeedModel

    /// Có khi là tường của chính mình ở mục Hồ sơ: hiện nút "Đăng xuất" (giống web).
    var onSignOut: (() -> Void)?
    @State private var confirmSignOut = false
    @State private var editingProfile = false
    @State private var selectedWord: SelectedWord?
    @State private var tab: WallTab = WallTab.last
    /// Dữ liệu tiến bộ đã tải: đổi tab chỉ chạy lại hoạt ảnh, không tải lại.
    @State private var progressCache: LearningProgress?
    /// Mở lại tình huống từ "Tình huống gần đây" (tường của mình).
    @State private var openingTopicID: Int?
    @State private var openScenario: Scenario?
    @State private var showConversation = false
    @State private var topicMissing = false

    init(user: SocialUser, model: FriendsModel? = nil, onSignOut: (() -> Void)? = nil) {
        _user = State(initialValue: user)
        _postsFeed = StateObject(wrappedValue: FeedModel(source: .user(user.id)))
        self.model = model
        self.onSignOut = onSignOut
    }

    private let card = RoundedRectangle(cornerRadius: 18, style: .continuous)

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                header
                // Mở từ phòng chat thì chưa biết có phải mình không: đợi tải hồ sơ xong mới hiện nút.
                if !user.isMe, loaded || user.followersCount != nil {
                    FollowButton(user: user, large: true) {
                        Task { await toggle() }
                    }
                    .disabled(busy)
                    .padding(.horizontal, 40)
                }
                if user.isMe || onSignOut != nil {
                    HStack(spacing: 10) {
                        Button {
                            editingProfile = true
                        } label: {
                            Label("Sửa hồ sơ", systemImage: "pencil")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(Capsule().fill(Color(.secondarySystemGroupedBackground)))
                        }
                        .buttonStyle(.plain)
                        if onSignOut != nil {
                            Button {
                                confirmSignOut = true
                            } label: {
                                Label("Đăng xuất", systemImage: "rectangle.portrait.and.arrow.right")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(socialRed)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .background(Capsule().fill(socialRed.opacity(0.1)))
                            }
                            .buttonStyle(.plain)
                            .confirmationDialog("Đăng xuất khỏi tài khoản?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                                Button("Đăng xuất", role: .destructive) { onSignOut?() }
                                Button("Huỷ", role: .cancel) {}
                            } message: {
                                Text("Bạn sẽ cần đăng nhập lại để dùng Bạn bè, Phòng chat và đồng bộ với website.")
                            }
                        }
                    }
                }
                wallTabBar
                Group {
                    switch tab {
                    case .wall:
                        wallTabContent
                    case .skills:
                        skillsTabContent
                    case .study:
                        studyTabContent
                    }
                }
                .id(tab)
                .transition(.opacity)
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .wordPopup($selectedWord)
        .navigationDestination(isPresented: $showConversation) {
            if let openScenario {
                ConversationView(scenario: openScenario)
            }
        }
        .alert("Tình huống này không còn nữa", isPresented: $topicMissing) {
            Button("OK", role: .cancel) {}
        }
        .sheet(isPresented: $editingProfile) {
            EditProfileSheet(user: user) { updated in
                user.applyProfile(from: updated)
                if let model { Task { await model.load() } }
            }
        }
        .navigationTitle(user.isMe ? "Tường của tôi" : user.name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            async let posts: Void = postsFeed.load()
            await reload()
            await posts
            // Kéo làm mới ở tab Kỹ năng thì tải lại cả biểu đồ tiến bộ.
            if tab == .skills, let fresh = try? await ProgressAPI.progress(userId: user.id) {
                progressCache = fresh
            }
        }
        .task {
            async let posts: Void = postsFeed.loaded ? () : postsFeed.load()
            await reload()
            await posts
        }
        .onChange(of: postsFeed.errorMessage) { message in
            guard let message else { return }
            errorMessage = message
            postsFeed.errorMessage = nil
        }
        .alert("Có lỗi", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Tab Tường / Kỹ năng

    enum WallTab: Hashable {
        case wall, skills, study

        /// Tab chọn gần nhất (nhớ trong lúc app đang mở).
        static var last: WallTab = .wall
    }

    @Namespace private var tabUnderline

    private var wallTabBar: some View {
        HStack(spacing: 0) {
            tabButton(.wall, title: user.isMe ? "📝 Tường của bạn" : "📝 Tường")
            tabButton(.skills, title: "📊 Kỹ năng")
            tabButton(.study, title: "📚 Học tập")
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(.separator)).frame(height: 0.5)
        }
        .accessibilityElement(children: .contain)
    }

    private func tabButton(_ value: WallTab, title: String) -> some View {
        let selected = tab == value
        return Button {
            guard tab != value else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { tab = value }
            WallTab.last = value
        } label: {
            VStack(spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(selected ? .bold : .semibold))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                ZStack {
                    Capsule().fill(Color.clear).frame(height: 3)
                    if selected {
                        Capsule()
                            .fill(socialRed)
                            .frame(height: 3)
                            .matchedGeometryEffect(id: "underline", in: tabUnderline)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    /// Tường: chỉ bài đăng (ô soạn bài trên tường của mình + danh sách bài).
    @ViewBuilder
    private var wallTabContent: some View {
        // Lazy: bài đăng tải thêm khi cuộn tới cuối.
        LazyVStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Bài đăng")
                if user.isMe {
                    FeedComposerCard(me: user) { post in
                        postsFeed.insert(post)
                    }
                }
            }
            FeedPostsList(feed: postsFeed, emptyText: user.isMe ? "Bạn chưa đăng bài nào." : "\(user.name) chưa đăng bài nào.")
        }
    }

    /// Kỹ năng: thống kê, huân chương tuần, tiến bộ.
    @ViewBuilder
    private var skillsTabContent: some View {
        VStack(spacing: 18) {
            if !loaded {
                ProgressView().padding(.top, 8)
            }
            statsGrid
            WallMedalsCard(medals: user.medals, awards: user.awards)
            WallProgressSection(userID: user.id, isMe: user.isMe, name: user.name, progress: $progressCache) { word in
                selectedWord = SelectedWord(word: word)
            }
        }
    }

    /// Học tập: lịch luyện tập 5 tuần, thành tích, tình huống gần đây, phòng chat đã tạo.
    @ViewBuilder
    private var studyTabContent: some View {
        VStack(spacing: 18) {
            if !loaded {
                ProgressView().padding(.top, 8)
            }
            if !user.calendar.isEmpty { calendarCard }
            if !user.badges.isEmpty { badgesCard }
            if !user.recentTopics.isEmpty { topicsCard }
            if !user.rooms.isEmpty { roomsCard }
            if loaded, user.calendar.isEmpty, user.badges.isEmpty, user.recentTopics.isEmpty, user.rooms.isEmpty {
                VStack(spacing: 6) {
                    Text("📚").font(.largeTitle)
                    Text(user.isMe ? "Bạn chưa luyện tình huống nào hay tạo phòng chat." : "\(user.name) chưa luyện tình huống nào hay tạo phòng chat.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            }
        }
    }

    // MARK: Đầu trang

    private var header: some View {
        VStack(spacing: 8) {
            SocialAvatar(url: user.avatarURL, initial: user.initial, size: 104, online: user.online,
                         ring: Color(.systemGroupedBackground))
                .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
            Text(user.name)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            if let handle = user.handle {
                Text(handle).font(.subheadline).foregroundStyle(.secondary)
            }
            if let bio = user.bio?.trimmingCharacters(in: .whitespacesAndNewlines), !bio.isEmpty {
                Text(bio)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
            }
            HStack(spacing: 6) {
                if let joined = SocialFormat.joined(user.joinedAt) {
                    Label(joined, systemImage: "calendar")
                }
                if let presence = SocialFormat.presence(online: user.online, lastSeenAt: user.lastSeenAt) {
                    if SocialFormat.joined(user.joinedAt) != nil { Text("·") }
                    HStack(spacing: 4) {
                        if user.online { OnlineDot(size: 7) }
                        Text(presence)
                    }
                    .foregroundStyle(user.online ? onlineGreen : .secondary)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            if user.followsMe && !user.isMe {
                Text("Đang theo dõi bạn")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color(.tertiarySystemFill)))
            }

            HStack(spacing: 0) {
                countColumn(user.followersCount, "người theo dõi")
                Divider().frame(height: 30)
                countColumn(user.followingCount, "đang theo dõi")
                Divider().frame(height: 30)
                countColumn(user.weekSentences, "câu tuần này")
            }
            .padding(.vertical, 10)
            .background(card.fill(Color(.secondarySystemGroupedBackground)))
            .padding(.top, 6)
        }
        .padding(.top, 12)
    }

    private func countColumn(_ value: Int?, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value.map(String.init) ?? "–")
                .font(.headline)
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: Thống kê

    private var statsGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Thống kê")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                stat("🔥", "\(user.streak)", "chuỗi hiện tại")
                stat("🏅", user.bestStreak.map(String.init) ?? "–", "chuỗi dài nhất")
                stat("💬", "\(user.totalSentences)", "tổng câu")
                stat("📅", user.activeDays.map(String.init) ?? "–", "ngày đã học")
                stat("🎯", user.accuracy.map(Self.percent) ?? "–", "độ chính xác")
                stat("⚡", user.avgCpm.map(String.init) ?? "–", "chữ/phút")
            }
        }
    }

    private static func percent(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value))%" : String(format: "%.1f%%", value)
    }

    private func stat(_ emoji: String, _ value: String, _ label: String) -> some View {
        HStack(spacing: 10) {
            Text(emoji).font(.title2)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(card.fill(Color(.secondarySystemGroupedBackground)))
        .accessibilityElement(children: .combine)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Lịch 5 tuần

    private static let weekdays = ["T2", "T3", "T4", "T5", "T6", "T7", "CN"]

    private var calendarCard: some View {
        let today = SocialFormat.dayParser.string(from: Date())
        // Máy chủ trả từ thứ Hai; thêm ô trống cho những ngày chưa tới trong tuần này.
        let days: [WallDay?] = user.calendar.map { Optional($0) }
            + Array(repeating: nil, count: (7 - user.calendar.count % 7) % 7)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        return VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Lịch luyện tập")
            VStack(spacing: 6) {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(Self.weekdays, id: \.self) { day in
                        Text(day)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                        calendarCell(day, isToday: day?.day == today)
                    }
                }
                HStack(spacing: 4) {
                    Spacer()
                    Text("Ít").font(.caption2).foregroundStyle(.secondary)
                    ForEach([0, 1, 5, 15, 30], id: \.self) { n in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Self.heat(n))
                            .frame(width: 12, height: 12)
                    }
                    Text("Nhiều").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
            .padding(12)
            .background(card.fill(Color(.secondarySystemGroupedBackground)))
        }
    }

    @ViewBuilder
    private func calendarCell(_ day: WallDay?, isToday: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        if let day {
            shape
                .fill(Self.heat(day.sentences))
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    Text(String(day.day.suffix(2)).replacingOccurrences(of: "^0", with: "", options: .regularExpression))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(day.sentences >= 5 ? .white : .secondary)
                }
                .overlay(shape.strokeBorder(isToday ? socialRed : .clear, lineWidth: 2))
                .accessibilityLabel("Ngày \(day.day): \(day.sentences) câu")
        } else {
            shape
                .strokeBorder(Color(.tertiarySystemFill), style: StrokeStyle(lineWidth: 1, dash: [3]))
                .aspectRatio(1, contentMode: .fit)
                .accessibilityHidden(true)
        }
    }

    private static func heat(_ sentences: Int) -> Color {
        switch sentences {
        case ..<1: return Color(.tertiarySystemFill)
        case 1..<5: return socialRed.opacity(0.25)
        case 5..<15: return socialRed.opacity(0.5)
        case 15..<30: return socialRed.opacity(0.75)
        default: return socialRed
        }
    }

    // MARK: Thành tích

    private var badgesCard: some View {
        let done = user.badges.filter(\.done).count
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("Thành tích")
                Text("\(done)/\(user.badges.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(user.badges) { badge in
                    badgeCell(badge)
                }
            }
        }
    }

    private func badgeCell(_ badge: WallBadge) -> some View {
        VStack(spacing: 6) {
            Text(badge.emoji)
                .font(.system(size: 34))
                .grayscale(badge.done ? 0 : 1)
                .opacity(badge.done ? 1 : 0.45)
            Text(badge.title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(badge.done ? socialRed : .secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(badge.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if badge.done {
                Label("Đã đạt", systemImage: "checkmark.seal.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(socialRed)
            } else {
                VStack(spacing: 2) {
                    ProgressView(value: Double(min(badge.progress, badge.target)), total: Double(badge.target))
                        .tint(.gray)
                    Text("\(badge.progress)/\(badge.target)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 160)
        .background(card.fill(badge.done ? socialRed.opacity(0.1) : Color(.secondarySystemGroupedBackground)))
        .overlay(card.strokeBorder(badge.done ? socialRed.opacity(0.35) : .clear, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    // MARK: Tình huống gần đây

    private var topicsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("Tình huống gần đây")
                if let completed = user.topicsCompleted, let count = user.topicsCount {
                    Text("\(completed)/\(count) hoàn thành")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            VStack(spacing: 0) {
                ForEach(Array(user.recentTopics.enumerated()), id: \.offset) { index, topic in
                    if index > 0 { Divider().padding(.leading, 52) }
                    // Tường của mình: chạm để mở lại bài hội thoại đó.
                    if user.isMe, let id = topic.id {
                        Button {
                            Task { await openTopic(id) }
                        } label: {
                            topicRow(topic, tappable: true, loading: openingTopicID == id)
                        }
                        .buttonStyle(TopicRowStyle())
                        .disabled(openingTopicID != nil)
                        .accessibilityHint("Mở lại tình huống này")
                    } else {
                        topicRow(topic, tappable: false, loading: false)
                    }
                }
            }
            .padding(.horizontal, 12)
            .background(card.fill(Color(.secondarySystemGroupedBackground)))
        }
    }

    private func topicRow(_ topic: WallTopic, tappable: Bool, loading: Bool) -> some View {
        HStack(spacing: 12) {
            Text(topic.emoji)
                .font(.title3)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(socialRed.opacity(0.1)))
            VStack(alignment: .leading, spacing: 5) {
                Text(topic.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    ProgressView(value: Double(min(topic.userTurns, topic.target)), total: Double(topic.target))
                        .tint(topic.userTurns >= topic.target ? onlineGreen : socialRed)
                    Text("\(min(topic.userTurns, topic.target))/\(topic.target)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if tappable {
                Group {
                    if loading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 18)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// Tìm hội thoại trên website theo id rồi mở màn hội thoại AI.
    private func openTopic(_ id: Int) async {
        openingTopicID = id
        defer { openingTopicID = nil }
        do {
            let conversations = try await WebConversationAPI.state().conversations
            if let conversation = conversations.first(where: { $0.id == id }) {
                openScenario = conversation.scenario
                showConversation = true
            } else {
                topicMissing = true
            }
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Phòng chat đã tạo

    private var roomsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Phòng chat đã tạo")
            VStack(spacing: 0) {
                ForEach(Array(user.rooms.enumerated()), id: \.element.id) { index, room in
                    if index > 0 { Divider().padding(.leading, 52) }
                    NavigationLink(value: room) {
                        HStack(spacing: 12) {
                            Text(room.emoji)
                                .font(.title3)
                                .frame(width: 40, height: 40)
                                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(socialRed.opacity(0.1)))
                            Text(room.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer(minLength: 6)
                            Text("👑").font(.caption)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .background(card.fill(Color(.secondarySystemGroupedBackground)))
        }
    }

    // MARK: Dữ liệu

    private func reload() async {
        do {
            user = try await SocialAPI.profile(id: user.id)
        } catch is CancellationError {
        } catch {
            if !loaded { errorMessage = error.localizedDescription }
        }
        loaded = true
    }

    private func toggle() async {
        busy = true
        defer { busy = false }
        let before = user
        let follow = !user.following
        user.following = follow
        if let count = user.followersCount { user.followersCount = max(0, count + (follow ? 1 : -1)) }
        let ok: Bool
        if let model {
            ok = await model.toggleFollow(before) != nil
        } else {
            do {
                if follow {
                    _ = try await SocialAPI.follow(userId: before.id)
                } else {
                    _ = try await SocialAPI.unfollow(userId: before.id)
                }
                ok = true
            } catch {
                errorMessage = error.localizedDescription
                ok = false
            }
        }
        if ok {
            await reload()
        } else {
            user = before
        }
    }
}

// MARK: - Thẻ mời đăng nhập (dùng chung cho Bạn bè và Phòng chat)

struct SocialSignInCard: View {
    let icon: String
    let title: String
    let message: String

    @ObservedObject private var web = WebAccountStore.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 76, height: 76)
                    .background(Circle().fill(LinearGradient(colors: AppTab.friends.colors, startPoint: .top, endPoint: .bottom)))
                VStack(spacing: 6) {
                    Text(title).font(.title3.weight(.bold))
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                VStack(spacing: 12) {
                    PasswordLoginForm()
                    GoogleSignInButton()
                    if let error = web.errorMessage {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }
                .padding(.top, 4)
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
            .padding(16)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}

/// Dòng bấm được trong thẻ: sáng nền nhẹ khi nhấn.
private struct TopicRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.tertiarySystemFill).opacity(configuration.isPressed ? 1 : 0))
                    .padding(.horizontal, -8)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Sửa hồ sơ

/// Sheet sửa tên, tên đăng nhập, giới thiệu và ảnh đại diện của chính mình.
struct EditProfileSheet: View {
    /// Báo hồ sơ mới (sau khi đổi ảnh hoặc bấm Lưu) để tường cập nhật ngay.
    let onUpdate: (SocialUser) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var user: SocialUser
    @State private var name: String
    @State private var username: String
    @State private var bio: String
    @State private var saving = false
    @State private var saveError: String?

    @State private var choosingAvatar = false
    @State private var pickingPhoto = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var uploading = false
    @State private var uploadProgress: Double = 0
    @State private var avatarError: String?

    private static let bioLimit = 160

    init(user: SocialUser, onUpdate: @escaping (SocialUser) -> Void) {
        self.onUpdate = onUpdate
        _user = State(initialValue: user)
        _name = State(initialValue: user.name)
        _username = State(initialValue: user.username ?? "")
        _bio = State(initialValue: user.bio ?? "")
    }

    // MARK: Kiểm tra (trùng quy tắc máy chủ)

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedUsername: String { username.trimmingCharacters(in: .whitespaces) }
    private var trimmedBio: String { bio.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var nameError: String? {
        (2...50).contains(trimmedName.count) ? nil : "Tên hiển thị cần từ 2 đến 50 ký tự."
    }

    private var usernameError: String? {
        let value = trimmedUsername
        if value.isEmpty { return nil }
        if !(3...32).contains(value.count) { return "Tên đăng nhập cần từ 3 đến 32 ký tự." }
        if value.range(of: "^[a-z0-9][a-z0-9_.]{2,31}$", options: .regularExpression) == nil {
            return "Chỉ dùng chữ thường không dấu, số, dấu chấm hoặc gạch dưới, bắt đầu bằng chữ hoặc số."
        }
        return nil
    }

    private var bioError: String? {
        bio.count > Self.bioLimit ? "Giới thiệu tối đa \(Self.bioLimit) ký tự." : nil
    }

    private var isValid: Bool { nameError == nil && usernameError == nil && bioError == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    avatarHeader
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }

                Section {
                    TextField("Tên của bạn", text: $name)
                        .textContentType(.name)
                        .submitLabel(.done)
                } header: {
                    Text("Tên hiển thị")
                } footer: {
                    if let nameError { validation(nameError) }
                }

                Section {
                    HStack(spacing: 2) {
                        Text("@").foregroundStyle(.secondary)
                        TextField("ten_dang_nhap", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.asciiCapable)
                            .textContentType(.username)
                    }
                } header: {
                    Text("Tên đăng nhập")
                } footer: {
                    if let usernameError {
                        validation(usernameError)
                    } else {
                        Text("Chữ thường không dấu, số, dấu chấm hoặc gạch dưới")
                    }
                }

                Section {
                    TextEditor(text: $bio)
                        .frame(minHeight: 90)
                } header: {
                    Text("Giới thiệu")
                } footer: {
                    HStack(alignment: .top) {
                        if let bioError { validation(bioError) }
                        Spacer(minLength: 8)
                        Text("\(bio.count)/\(Self.bioLimit)")
                            .monospacedDigit()
                            .foregroundStyle(bio.count > Self.bioLimit ? Color.red : Color.secondary)
                    }
                }

                if let saveError {
                    Section {
                        Label(saveError, systemImage: "exclamationmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Sửa hồ sơ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }
                        .disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("Lưu") { Task { await save() } }
                            .fontWeight(.semibold)
                            .disabled(!isValid || uploading)
                    }
                }
            }
            .onChange(of: username) { value in
                let lowered = value.lowercased().replacingOccurrences(of: " ", with: "")
                if lowered != value { username = lowered }
            }
            .interactiveDismissDisabled(saving || uploading)
            .confirmationDialog("Ảnh đại diện", isPresented: $choosingAvatar, titleVisibility: .visible) {
                Button("Chọn từ thư viện") { pickingPhoto = true }
                if CameraPicker.isAvailable {
                    Button("Chụp ảnh") { showCamera = true }
                }
                if user.avatarURL != nil {
                    Button("Xoá ảnh", role: .destructive) { Task { await removeAvatar() } }
                }
                Button("Huỷ", role: .cancel) {}
            }
            .photosPicker(isPresented: $pickingPhoto, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { item in
                guard let item else { return }
                photoItem = nil
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                        avatarError = "Không đọc được ảnh này."
                        return
                    }
                    await uploadAvatar(image)
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    Task { await uploadAvatar(image) }
                }
                .ignoresSafeArea()
            }
        }
    }

    private func validation(_ text: String) -> some View {
        Text(text).foregroundStyle(.red)
    }

    // MARK: Ảnh đại diện

    private var avatarHeader: some View {
        VStack(spacing: 10) {
            Button {
                avatarError = nil
                choosingAvatar = true
            } label: {
                SocialAvatar(url: user.avatarURL, initial: String(trimmedName.prefix(1)).uppercased(), size: 110,
                             ring: Color(.systemGroupedBackground))
                    .overlay {
                        if uploading {
                            ZStack {
                                Circle().fill(Color.black.opacity(0.45))
                                VStack(spacing: 4) {
                                    ProgressView().tint(.white)
                                    if uploadProgress > 0 {
                                        Text("\(Int(uploadProgress * 100))%")
                                            .font(.caption2.weight(.semibold).monospacedDigit())
                                            .foregroundStyle(.white)
                                    }
                                }
                            }
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(socialRed))
                            .overlay(Circle().stroke(Color(.systemGroupedBackground), lineWidth: 3))
                    }
            }
            .buttonStyle(.plain)
            .disabled(uploading || saving)
            .accessibilityLabel("Đổi ảnh đại diện")

            if let avatarError {
                Text(avatarError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            } else {
                Text(uploading ? "Đang tải ảnh lên…" : "Chạm để đổi ảnh")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func uploadAvatar(_ image: UIImage) async {
        guard let jpeg = SocialImageCompressor.jpeg(from: image, maxSide: 1024, quality: 0.85) else {
            avatarError = "Không đọc được ảnh này."
            return
        }
        guard jpeg.count <= 8 * 1024 * 1024 else {
            avatarError = "Ảnh quá lớn (tối đa 8MB)."
            return
        }
        avatarError = nil
        uploadProgress = 0
        uploading = true
        defer { uploading = false }
        do {
            let updated = try await SocialAPI.uploadAvatar(jpeg: jpeg) { value in
                uploadProgress = value
            }
            applyAvatar(updated)
        } catch is CancellationError {
        } catch {
            avatarError = error.localizedDescription
        }
    }

    private func removeAvatar() async {
        avatarError = nil
        uploadProgress = 0
        uploading = true
        defer { uploading = false }
        do {
            applyAvatar(try await SocialAPI.removeAvatar())
        } catch is CancellationError {
        } catch {
            avatarError = error.localizedDescription
        }
    }

    /// Ảnh đã lưu trên máy chủ: đổi ngay trên tường (không đụng tên / giới thiệu đang sửa dở).
    private func applyAvatar(_ updated: SocialUser) {
        user.avatar = updated.avatar
        onUpdate(user)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: Lưu

    private func save() async {
        guard isValid else { return }
        saveError = nil
        saving = true
        defer { saving = false }
        do {
            let updated = try await SocialAPI.updateProfile(name: trimmedName, username: trimmedUsername, bio: trimmedBio)
            user.applyProfile(from: updated)
            if updated.bio == nil { user.bio = trimmedBio }
            onUpdate(user)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch is CancellationError {
        } catch {
            saveError = error.localizedDescription
        }
    }
}

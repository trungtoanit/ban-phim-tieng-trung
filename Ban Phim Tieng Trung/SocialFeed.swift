//
//  SocialFeed.swift
//  Bảng tin kiểu Facebook/Duolingo (status, ảnh, nhạc, chia sẻ phòng đang live, thích, bình luận)
//  và các thành phần ảnh dùng chung với phòng chat (nén ảnh, chụp ảnh, xem ảnh toàn màn hình).
//  Dữ liệu từ api/social.php (app/feed.php) của website.
//

import AVFoundation
import Combine
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Ảnh

enum SocialImageCompressor {
    /// Thu nhỏ cạnh dài về tối đa `maxSide` px rồi nén JPEG.
    static func jpeg(from image: UIImage, maxSide: CGFloat = 1600, quality: CGFloat = 0.8) -> Data? {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, maxSide / longest)
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }

    static func jpeg(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return jpeg(from: image)
    }
}

/// Máy ảnh của hệ thống (chụp ảnh gửi đi).
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

/// Ảnh từ máy chủ, giữ đúng tỉ lệ ngay cả khi đang tải.
struct SocialImageView: View {
    let image: SocialImage
    var maxWidth: CGFloat = 260
    var maxHeight: CGFloat = 320
    var cornerRadius: CGFloat = 16

    var body: some View {
        let size = fittedSize
        AsyncImage(url: image.imageURL) { phase in
            if let loaded = phase.image {
                loaded.resizable().scaledToFill()
            } else if phase.error != nil {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .frame(width: size.width, height: size.height)
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityLabel("Ảnh")
    }

    private var fittedSize: CGSize {
        let ratio = image.aspectRatio
        var width = maxWidth
        var height = width / ratio
        if height > maxHeight {
            height = maxHeight
            width = height * ratio
        }
        return CGSize(width: width, height: height)
    }
}

/// Xem ảnh toàn màn hình: chụm để phóng to, kéo để di chuyển, chạm đúp để phóng / thu.
struct ZoomableImageViewer: View {
    let url: URL?
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in scale = max(1, min(5, lastScale * value)) }
                                .onEnded { _ in
                                    lastScale = scale
                                    if scale <= 1 { resetPosition() }
                                }
                                .simultaneously(with: DragGesture()
                                    .onChanged { value in
                                        guard scale > 1 else { return }
                                        offset = CGSize(width: lastOffset.width + value.translation.width,
                                                        height: lastOffset.height + value.translation.height)
                                    }
                                    .onEnded { value in
                                        if scale > 1 {
                                            lastOffset = offset
                                        } else if value.translation.height > 120 {
                                            dismiss()
                                        }
                                    })
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if scale > 1 {
                                    scale = 1
                                    lastScale = 1
                                    resetPosition()
                                } else {
                                    scale = 2.5
                                    lastScale = 2.5
                                }
                            }
                        }
                } else if phase.error != nil {
                    Text("Không tải được ảnh").foregroundStyle(.white)
                } else {
                    ProgressView().tint(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.white.opacity(0.2)))
            }
            .padding(16)
            .accessibilityLabel("Đóng")
        }
        .statusBarHidden()
    }

    private func resetPosition() {
        offset = .zero
        lastOffset = .zero
    }
}

// MARK: - Phát nhạc

/// Một trình phát dùng chung cho cả bảng tin: bật bài khác thì bài cũ dừng.
@MainActor
final class FeedAudioPlayer: ObservableObject {
    static let shared = FeedAudioPlayer()

    @Published private(set) var currentURL: URL?
    @Published private(set) var isPlaying = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var duration: Double = 0

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    func toggle(_ url: URL) {
        if currentURL == url, let player {
            if isPlaying {
                player.pause()
                isPlaying = false
            } else {
                activateSession()
                player.play()
                isPlaying = true
            }
            return
        }
        stop()
        NaturalSpeaker.all.forEach { $0.stop() }
        activateSession()
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player
        currentURL = url
        progress = 0
        duration = 0
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self, let item = self.player?.currentItem else { return }
                let total = item.duration.seconds
                if total.isFinite, total > 0 {
                    self.duration = total
                    self.progress = min(1, time.seconds / total)
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.isPlaying = false
                self?.progress = 1
                self?.player?.seek(to: .zero)
            }
        }
        player.play()
        isPlaying = true
    }

    func seek(_ url: URL, to fraction: Double) {
        guard currentURL == url, let player, duration > 0 else { return }
        progress = fraction
        player.seek(to: CMTime(seconds: fraction * duration, preferredTimescale: 600))
    }

    func stop() {
        player?.pause()
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil
        player = nil
        currentURL = nil
        isPlaying = false
        progress = 0
        duration = 0
    }

    private func activateSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }
}

// MARK: - Dữ liệu bảng tin

@MainActor
final class FeedModel: ObservableObject {
    enum Source: Equatable {
        case feed
        case user(Int)
    }

    @Published var posts: [FeedPost] = []
    @Published var hasMore = false
    @Published var loaded = false
    @Published var loadingMore = false
    @Published var errorMessage: String?
    /// Bảng tin: false = Đang theo dõi, true = Khám phá.
    @Published var explore = false

    let source: Source

    init(source: Source) {
        self.source = source
    }

    private func page(before: Int) async throws -> SocialAPI.FeedPage {
        switch source {
        case .feed: return try await SocialAPI.feed(all: explore, before: before)
        case .user(let id): return try await SocialAPI.posts(userId: id, before: before)
        }
    }

    func load() async {
        do {
            let result = try await page(before: 0)
            posts = result.posts
            hasMore = result.hasMore
            loaded = true
        } catch is CancellationError {
        } catch {
            if !loaded { errorMessage = error.localizedDescription }
            loaded = true
        }
    }

    func loadMore() async {
        guard hasMore, !loadingMore, let last = posts.last else { return }
        loadingMore = true
        defer { loadingMore = false }
        do {
            let result = try await page(before: last.id)
            let known = Set(posts.map(\.id))
            posts.append(contentsOf: result.posts.filter { !known.contains($0.id) })
            hasMore = result.hasMore
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func insert(_ post: FeedPost) {
        posts.removeAll { $0.id == post.id }
        posts.insert(post, at: 0)
    }

    func toggleLike(_ post: FeedPost) async {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        let like = !posts[index].liked
        posts[index].liked = like
        posts[index].likeCount = max(0, posts[index].likeCount + (like ? 1 : -1))
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        do {
            let result = try await SocialAPI.like(postId: post.id, like)
            if let i = posts.firstIndex(where: { $0.id == post.id }) {
                posts[i].likeCount = result.count
                posts[i].liked = result.liked
            }
        } catch {
            if let i = posts.firstIndex(where: { $0.id == post.id }) {
                posts[i].liked = !like
                posts[i].likeCount = max(0, posts[i].likeCount + (like ? -1 : 1))
            }
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ post: FeedPost) async {
        let before = posts
        posts.removeAll { $0.id == post.id }
        do {
            try await SocialAPI.deletePost(id: post.id)
        } catch {
            posts = before
            errorMessage = error.localizedDescription
        }
    }

    /// Bình luận vừa thay đổi trong sheet: cập nhật số đếm + 2 bình luận mới nhất trên thẻ.
    func updateComments(postId: Int, comments: [PostComment]) {
        guard let index = posts.firstIndex(where: { $0.id == postId }) else { return }
        posts[index].commentCount = comments.count
        posts[index].comments = Array(comments.suffix(2))
    }
}

// MARK: - Danh sách bài (dùng trong ScrollView)

/// Các thẻ bài + tải thêm khi cuộn tới cuối. Đặt trong LazyVStack.
struct FeedPostsList: View {
    @ObservedObject var feed: FeedModel
    var emptyText = "Chưa có bài đăng nào."

    var body: some View {
        if !feed.loaded {
            ProgressView().padding(.vertical, 24)
        } else if feed.posts.isEmpty {
            VStack(spacing: 6) {
                Text("📝").font(.largeTitle)
                Text(emptyText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        } else {
            ForEach(feed.posts) { post in
                PostCard(post: post, feed: feed)
                    .onAppear {
                        if post.id == feed.posts.last?.id {
                            Task { await feed.loadMore() }
                        }
                    }
            }
            if feed.loadingMore {
                ProgressView().padding(.vertical, 12)
            }
        }
    }
}

/// Ô "Bạn đang nghĩ gì?" mở trình soạn bài.
struct FeedComposerCard: View {
    let me: SocialUser?
    let onPosted: (FeedPost) -> Void

    @State private var composing = false

    var body: some View {
        HStack(spacing: 10) {
            SocialAvatar(url: me?.avatarURL, initial: me?.initial ?? "", size: 40)
            Button {
                composing = true
            } label: {
                Text("Bạn đang nghĩ gì?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color(.tertiarySystemFill)))
            }
            .buttonStyle(.plain)
            Button {
                composing = true
            } label: {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 20))
                    .foregroundStyle(onlineGreen)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Đăng ảnh")
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .sheet(isPresented: $composing) {
            PostComposerSheet(me: me, onPosted: onPosted)
        }
    }
}

// MARK: - Thẻ bài đăng

struct PostCard: View {
    let post: FeedPost
    @ObservedObject var feed: FeedModel

    @ObservedObject private var player = FeedAudioPlayer.shared
    @AppStorage(SharedSettings.showHanVietKey, store: SharedSettings.store) private var showHanViet = false
    @State private var showComments = false
    @State private var confirmDelete = false
    @State private var viewing: SocialImage?

    private let card = RoundedRectangle(cornerRadius: 18, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if !post.text.isEmpty { postText }
            if let image = post.image {
                Button {
                    viewing = image
                } label: {
                    GeometryReader { geo in
                        SocialImageView(image: image, maxWidth: geo.size.width, maxHeight: 420, cornerRadius: 14)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(height: imageHeight(image))
                }
                .buttonStyle(.plain)
            }
            if let audio = post.audio, let url = URL(string: audio.url) { audioCard(audio, url: url) }
            if let link = post.link, let url = URL(string: link.url) { linkCard(link, url: url) }
            if let room = post.room { roomCard(room) }
            actions
            if !post.comments.isEmpty { commentPreview }
        }
        .padding(14)
        .background(card.fill(Color(.secondarySystemGroupedBackground)))
        .sheet(isPresented: $showComments) {
            PostCommentsSheet(post: post) { comments in
                feed.updateComments(postId: post.id, comments: comments)
            }
        }
        .fullScreenCover(item: $viewing) { image in
            ZoomableImageViewer(url: image.imageURL)
        }
        .confirmationDialog("Xoá bài đăng này?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Xoá bài", role: .destructive) { Task { await feed.delete(post) } }
            Button("Huỷ", role: .cancel) {}
        }
    }

    /// Chiều cao ảnh theo tỉ lệ, ước lượng theo bề ngang màn hình (tối đa 420).
    private func imageHeight(_ image: SocialImage) -> CGFloat {
        let width = min(UIScreen.main.bounds.width, 640) - 60
        return min(420, width / image.aspectRatio)
    }

    private var header: some View {
        HStack(spacing: 10) {
            NavigationLink(value: post.user.socialUser) {
                HStack(spacing: 10) {
                    SocialAvatar(url: post.user.avatarURL, initial: post.user.initial, size: 42, online: post.user.online,
                                 ring: Color(.secondarySystemGroupedBackground))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(post.user.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            Text(SocialFormat.ago(post.createdAt))
                            if let label = kindLabel {
                                Text("·")
                                Text(label)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer(minLength: 6)
            if post.mine {
                Menu {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Xoá bài đăng", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 30)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Tuỳ chọn bài đăng")
            }
        }
    }

    private var kindLabel: String? {
        switch post.kind {
        case "music": return "🎵 chia sẻ nhạc"
        case "room": return "💬 chia sẻ phòng chat"
        case "image": return "📷 đăng ảnh"
        default: return nil
        }
    }

    @ViewBuilder
    private var postText: some View {
        if ChineseText.containsHan(post.text), post.text.count <= 200, !post.text.contains("\n") {
            RubyText(words: ChineseText.words(for: post.text), hanziSize: 18, pinyinColor: .blue, showHanViet: showHanViet)
        } else {
            Text(post.text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    // MARK: Nhạc

    private func audioCard(_ audio: FeedPost.Audio, url: URL) -> some View {
        let current = player.currentURL == url
        let playing = current && player.isPlaying
        return HStack(spacing: 12) {
            Button {
                player.toggle(url)
            } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(socialRed))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playing ? "Tạm dừng" : "Phát nhạc")
            VStack(alignment: .leading, spacing: 6) {
                Text("🎵 \(audio.name?.isEmpty == false ? audio.name! : "Bản nhạc")")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                ProgressView(value: current ? player.progress : 0)
                    .tint(socialRed)
                if current, player.duration > 0 {
                    Text("\(Self.clock(player.progress * player.duration)) / \(Self.clock(player.duration))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(socialRed.opacity(0.08)))
    }

    private static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.isFinite ? seconds : 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: Link nhạc

    private func linkCard(_ link: FeedPost.Link, url: URL) -> some View {
        let style = Self.provider(link.provider)
        return Link(destination: url) {
            HStack(spacing: 12) {
                Image(systemName: style.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(style.color))
                VStack(alignment: .leading, spacing: 2) {
                    Text(style.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(url.host ?? link.url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.tertiarySystemFill)))
        }
        .buttonStyle(.plain)
    }

    static func provider(_ key: String?) -> (name: String, icon: String, color: Color) {
        switch key {
        case "youtube": return ("YouTube", "play.rectangle.fill", Color(red: 0.95, green: 0, blue: 0))
        case "spotify": return ("Spotify", "music.note", Color(red: 0.11, green: 0.73, blue: 0.33))
        case "soundcloud": return ("SoundCloud", "cloud.fill", Color(red: 1, green: 0.33, blue: 0))
        case "zingmp3": return ("Zing MP3", "music.quarternote.3", Color(red: 0.55, green: 0.2, blue: 0.8))
        case "nhaccuatui": return ("NhacCuaTui", "headphones", Color(red: 0.1, green: 0.5, blue: 0.95))
        case "applemusic": return ("Apple Music", "music.note", Color(red: 0.98, green: 0.24, blue: 0.4))
        default: return ("Nghe nhạc", "link", Color.gray)
        }
    }

    // MARK: Phòng chat

    private func roomCard(_ room: ChatRoom) -> some View {
        HStack(spacing: 12) {
            Text(room.emoji)
                .font(.title2)
                .frame(width: 48, height: 48)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(socialRed.opacity(0.1)))
            VStack(alignment: .leading, spacing: 3) {
                Text(room.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if room.onlineCount > 0 {
                    HStack(spacing: 4) {
                        Text("🔴 LIVE")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(socialRed)
                        Text("·").foregroundStyle(.secondary)
                        OnlineDot(size: 7)
                        Text("\(room.onlineCount) đang online")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(onlineGreen)
                    }
                } else {
                    Text("👥 \(room.memberCount) thành viên")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            NavigationLink(value: WallRoom(id: room.id, name: room.name, emoji: room.emoji)) {
                Text("Vào phòng")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(socialRed))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(socialRed.opacity(0.3), lineWidth: 1))
    }

    // MARK: Thích / bình luận

    private var actions: some View {
        HStack(spacing: 18) {
            Button {
                Task { await feed.toggleLike(post) }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: post.liked ? "heart.fill" : "heart")
                        .foregroundStyle(post.liked ? socialRed : .secondary)
                        .scaleEffect(post.liked ? 1.1 : 1)
                    Text(post.likeCount > 0 ? "\(post.likeCount)" : "Thích")
                        .foregroundStyle(post.liked ? socialRed : .secondary)
                }
                .font(.subheadline.weight(.semibold))
                .animation(.spring(response: 0.25, dampingFraction: 0.5), value: post.liked)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(post.liked ? "Bỏ thích, \(post.likeCount) lượt thích" : "Thích, \(post.likeCount) lượt thích")

            Button {
                showComments = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "bubble.right")
                    Text(post.commentCount > 0 ? "\(post.commentCount)" : "Bình luận")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(post.commentCount) bình luận")
            Spacer()
        }
        .padding(.top, 2)
    }

    private var commentPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            if post.commentCount > post.comments.count {
                Button("Xem tất cả \(post.commentCount) bình luận") { showComments = true }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
            }
            ForEach(post.comments) { comment in
                (Text(comment.user.name).fontWeight(.semibold) + Text("  ") + Text(comment.text))
                    .font(.caption)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { showComments = true }
    }
}

// MARK: - Bình luận

struct PostCommentsSheet: View {
    let post: FeedPost
    let onChange: ([PostComment]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var comments: [PostComment] = []
    @State private var loaded = false
    @State private var draft = ""
    @State private var sending = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    if loaded, comments.isEmpty {
                        Text("Chưa có bình luận nào. Hãy là người đầu tiên!")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(comments) { comment in
                        row(comment)
                            .id(comment.id)
                            .swipeActions {
                                if comment.mine || post.mine {
                                    Button(role: .destructive) {
                                        Task { await delete(comment) }
                                    } label: {
                                        Label("Xoá", systemImage: "trash")
                                    }
                                }
                            }
                            .contextMenu {
                                Button {
                                    UIPasteboard.general.string = comment.text
                                } label: {
                                    Label("Sao chép", systemImage: "doc.on.doc")
                                }
                                if comment.mine || post.mine {
                                    Button(role: .destructive) {
                                        Task { await delete(comment) }
                                    } label: {
                                        Label("Xoá bình luận", systemImage: "trash")
                                    }
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .overlay {
                    if !loaded { ProgressView() }
                }
                .onChange(of: comments.last?.id) { id in
                    guard let id else { return }
                    withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .navigationTitle("Bình luận")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { dismiss() }
                }
            }
            .task { await load() }
            .alert("Có lỗi", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .tint(socialRed)
        .presentationDetents([.medium, .large])
    }

    private func row(_ comment: PostComment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            SocialAvatar(url: comment.user.avatarURL, initial: comment.user.initial, size: 34, online: comment.user.online)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(comment.user.name)
                        .font(.caption.weight(.semibold))
                    if comment.user.id == post.user.id {
                        Text("Tác giả")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(socialRed)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(socialRed.opacity(0.12)))
                    }
                    Text(SocialFormat.ago(comment.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(comment.text)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    private var composer: some View {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return HStack(alignment: .bottom, spacing: 8) {
            TextField("Viết bình luận…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .focused($focused)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.secondarySystemBackground)))
            Button {
                Task { await send() }
            } label: {
                Group {
                    if sending {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "arrow.up").font(.system(size: 17, weight: .bold))
                    }
                }
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Circle().fill(trimmed.isEmpty ? Color(.systemGray3) : socialRed))
            }
            .buttonStyle(.plain)
            .disabled(trimmed.isEmpty || sending || trimmed.count > 1000)
            .accessibilityLabel("Gửi bình luận")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func load() async {
        do {
            comments = try await SocialAPI.comments(postId: post.id)
            onChange(comments)
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
        loaded = true
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sending = true
        defer { sending = false }
        do {
            let comment = try await SocialAPI.comment(postId: post.id, text: text)
            comments.append(comment)
            draft = ""
            onChange(comments)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ comment: PostComment) async {
        let before = comments
        comments.removeAll { $0.id == comment.id }
        do {
            try await SocialAPI.deleteComment(id: comment.id)
            onChange(comments)
        } catch {
            comments = before
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Soạn bài

struct PostComposerSheet: View {
    let me: SocialUser?
    let onPosted: (FeedPost) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var previewImage: UIImage?
    @State private var showCamera = false
    @State private var audio: SocialAPI.UploadFile?
    @State private var importingAudio = false
    @State private var musicURL = ""
    @State private var showMusicLink = false
    @State private var room: ChatRoom?
    @State private var pickingRoom = false
    @State private var posting = false
    @State private var progress: Double = 0
    @State private var errorMessage: String?
    @FocusState private var textFocused: Bool

    private static let maxAudioBytes = 12 * 1024 * 1024
    private static let musicHosts = ["youtube.com", "youtu.be", "spotify.com", "soundcloud.com", "zingmp3.vn", "nhaccuatui.com", "music.apple.com"]

    private var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedLink: String { musicURL.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var linkError: String? {
        guard !trimmedLink.isEmpty else { return nil }
        guard let url = URL(string: trimmedLink), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host?.lowercased() else {
            return "Link cần bắt đầu bằng https://"
        }
        guard Self.musicHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) else {
            return "Hỗ trợ YouTube, Spotify, SoundCloud, Zing MP3, NhacCuaTui, Apple Music."
        }
        return nil
    }

    private var canPost: Bool {
        guard !posting, linkError == nil, text.count <= 2000 else { return false }
        return !trimmedText.isEmpty || imageData != nil || audio != nil || !trimmedLink.isEmpty || room != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        SocialAvatar(url: me?.avatarURL, initial: me?.initial ?? "", size: 40)
                        Text(me?.name ?? "Bạn")
                            .font(.subheadline.weight(.semibold))
                    }

                    ZStack(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("Bạn đang nghĩ gì? Viết bằng tiếng Trung để luyện nhé 加油！")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                        }
                        TextEditor(text: $text)
                            .focused($textFocused)
                            .frame(minHeight: 110)
                            .scrollContentBackground(.hidden)
                    }
                    .font(.body)
                    if text.count > 1800 {
                        Text("\(text.count)/2000")
                            .font(.caption2)
                            .foregroundStyle(text.count > 2000 ? .red : .secondary)
                    }

                    attachments

                    if posting {
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView(value: progress).tint(socialRed)
                            Text(progress < 1 ? "Đang tải lên… \(Int(progress * 100))%" : "Đang đăng…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let errorMessage {
                        Text(errorMessage).font(.footnote).foregroundStyle(.red)
                    }

                    addButtons
                }
                .padding(16)
            }
            .navigationTitle("Tạo bài đăng")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }
                        .disabled(posting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Đăng") { Task { await post() } }
                        .fontWeight(.bold)
                        .disabled(!canPost)
                }
            }
            .onAppear { textFocused = true }
            .onChange(of: photoItem) { item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        setImage(image)
                    } else {
                        errorMessage = "Không đọc được ảnh này."
                    }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { setImage($0) }.ignoresSafeArea()
            }
            .fileImporter(isPresented: $importingAudio, allowedContentTypes: Self.audioTypes) { result in
                handleAudio(result)
            }
            .sheet(isPresented: $pickingRoom) {
                LiveRoomPicker { room = $0 }
            }
        }
        .tint(socialRed)
        .interactiveDismissDisabled(posting)
    }

    private static var audioTypes: [UTType] {
        [UTType.mp3, UTType.mpeg4Audio, UTType.wav, UTType(filenameExtension: "aac"), UTType(filenameExtension: "m4a"), UTType.audio]
            .compactMap { $0 }
    }

    // MARK: Đính kèm

    @ViewBuilder
    private var attachments: some View {
        if let previewImage {
            ZStack(alignment: .topTrailing) {
                Image(uiImage: previewImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                removeButton {
                    self.previewImage = nil
                    imageData = nil
                    photoItem = nil
                }
            }
        }
        if let audio {
            attachmentRow(icon: "music.note", color: socialRed, title: audio.filename,
                          subtitle: ByteCountFormatter.string(fromByteCount: Int64(audio.data.count), countStyle: .file)) {
                self.audio = nil
            }
        }
        if showMusicLink || !musicURL.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "link").foregroundStyle(.secondary)
                    TextField("Dán link YouTube / Spotify / SoundCloud / Zing MP3…", text: $musicURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        musicURL = ""
                        showMusicLink = false
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.tertiarySystemFill)))
                if let linkError {
                    Text(linkError).font(.caption).foregroundStyle(.red)
                } else if !trimmedLink.isEmpty {
                    let host = URL(string: trimmedLink)?.host?.lowercased() ?? ""
                    let key = ["youtube": "youtu", "spotify": "spotify", "soundcloud": "soundcloud", "zingmp3": "zingmp3",
                               "nhaccuatui": "nhaccuatui", "applemusic": "music.apple"].first { host.contains($0.value) }?.key
                    Text("✓ \(PostCard.provider(key).name)").font(.caption).foregroundStyle(onlineGreen)
                }
            }
        }
        if let room {
            attachmentRow(icon: nil, emoji: room.emoji, color: socialRed, title: room.name,
                          subtitle: room.onlineCount > 0 ? "🔴 LIVE · 🟢 \(room.onlineCount) đang online" : "👥 \(room.memberCount) thành viên") {
                self.room = nil
            }
        }
    }

    private func removeButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.black.opacity(0.6)))
        }
        .buttonStyle(.plain)
        .padding(8)
        .accessibilityLabel("Bỏ")
    }

    private func attachmentRow(icon: String?, emoji: String? = nil, color: Color, title: String, subtitle: String,
                               onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Group {
                if let emoji {
                    Text(emoji).font(.title3)
                } else if let icon {
                    Image(systemName: icon).foregroundStyle(color)
                }
            }
            .frame(width: 40, height: 40)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(color.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Bỏ")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.tertiarySystemFill)))
    }

    private var addButtons: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Thêm vào bài đăng")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)
            PhotosPicker(selection: $photoItem, matching: .images) {
                addRow("photo.on.rectangle.angled", onlineGreen, "Ảnh từ thư viện")
            }
            .buttonStyle(.plain)
            if CameraPicker.isAvailable {
                Divider()
                Button { showCamera = true } label: { addRow("camera.fill", .blue, "Chụp ảnh") }
                    .buttonStyle(.plain)
            }
            Divider()
            Button { importingAudio = true } label: { addRow("music.note", socialRed, "File nhạc (MP3, M4A, AAC, WAV · ≤ 12 MB)") }
                .buttonStyle(.plain)
                .disabled(!trimmedLink.isEmpty)
            Divider()
            Button { showMusicLink = true } label: { addRow("link", .purple, "Link nhạc (YouTube, Spotify, Zing MP3…)") }
                .buttonStyle(.plain)
                .disabled(audio != nil)
            Divider()
            Button { pickingRoom = true } label: { addRow("dot.radiowaves.left.and.right", .orange, "Chia sẻ phòng đang live") }
                .buttonStyle(.plain)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func addRow(_ icon: String, _ color: Color, _ title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 26)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    // MARK: Xử lý

    private func setImage(_ image: UIImage) {
        guard let data = SocialImageCompressor.jpeg(from: image) else {
            errorMessage = "Không đọc được ảnh này."
            return
        }
        previewImage = image
        imageData = data
    }

    private func handleAudio(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            errorMessage = "Không đọc được file nhạc."
            return
        }
        guard data.count <= Self.maxAudioBytes else {
            errorMessage = "File nhạc quá lớn (tối đa 12 MB)."
            return
        }
        let ext = url.pathExtension.lowercased()
        let mime: String
        switch ext {
        case "mp3": mime = "audio/mpeg"
        case "m4a": mime = "audio/mp4"
        case "aac": mime = "audio/aac"
        case "wav": mime = "audio/wav"
        case "ogg": mime = "audio/ogg"
        default:
            errorMessage = "Chỉ nhận file nhạc MP3, M4A, AAC, WAV."
            return
        }
        errorMessage = nil
        musicURL = ""
        showMusicLink = false
        audio = SocialAPI.UploadFile(field: "audio", filename: url.lastPathComponent, mimeType: mime, data: data)
    }

    private func post() async {
        guard canPost else { return }
        posting = true
        progress = 0
        errorMessage = nil
        defer { posting = false }
        do {
            let post = try await SocialAPI.createPost(text: trimmedText, image: imageData, audio: audio,
                                                      musicURL: trimmedLink, roomId: room?.id) { value in
                progress = value
            }
            onPosted(post)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Chọn phòng đang live (hoặc đã tham gia) để chia sẻ.
struct LiveRoomPicker: View {
    let onPick: (ChatRoom) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var rooms: [ChatRoom] = []
    @State private var loaded = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                } else if loaded, rooms.isEmpty {
                    Text("Chưa có phòng nào đang live. Hãy tham gia hoặc tạo phòng chat trước nhé.")
                        .foregroundStyle(.secondary)
                }
                ForEach(rooms) { room in
                    Button {
                        onPick(room)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Text(room.emoji)
                                .font(.title3)
                                .frame(width: 42, height: 42)
                                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(socialRed.opacity(0.1)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(room.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text("👥 \(room.memberCount) thành viên")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if room.onlineCount > 0 {
                                HStack(spacing: 4) {
                                    OnlineDot(size: 8)
                                    Text("\(room.onlineCount)")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(onlineGreen)
                                }
                            }
                        }
                    }
                }
            }
            .overlay { if !loaded { ProgressView() } }
            .navigationTitle("Phòng đang live")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Huỷ") { dismiss() } }
            }
            .task {
                do {
                    rooms = try await SocialAPI.liveRooms().sorted { $0.onlineCount > $1.onlineCount }
                } catch {
                    errorMessage = error.localizedDescription
                }
                loaded = true
            }
        }
        .tint(socialRed)
        .presentationDetents([.medium, .large])
    }
}

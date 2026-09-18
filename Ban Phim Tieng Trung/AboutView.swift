//
//  AboutView.swift
//  Giới thiệu tác giả: ảnh, tên tiếng Trung, mục tiêu phát triển và thông tin sản phẩm.
//

import SwiftUI

private let accentRed = Color(red: 0.86, green: 0.17, blue: 0.16)

struct AboutView: View {
    /// Ảnh tác giả trong Assets; chưa có thì hiện chữ viết tắt.
    private static let photo = UIImage(named: "AuthorPhoto")

    @State private var appeared = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    hero
                    chineseName
                    aboutCard
                    goalCard
                    infoCard
                    quoteCard
                    footer
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Giới thiệu")
            .navigationBarTitleDisplayMode(.inline)
            .homeBackButton()
            .onAppear {
                withAnimation(.easeOut(duration: 0.45)) { appeared = true }
            }
        }
    }

    // MARK: - Ảnh và tên

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let photo = Self.photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(colors: [Color(red: 0.55, green: 0.08, blue: 0.1), Color(red: 0.12, green: 0.07, blue: 0.2)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                        .overlay {
                            Text("NT")
                                .font(.system(size: 72, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white.opacity(0.9))
                                .offset(y: -24)
                        }
                }
            }
            .frame(height: 280)
            .frame(maxWidth: .infinity)
            .clipped()

            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 4) {
                Text("关于作者 · GIỚI THIỆU TÁC GIẢ")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.8))
                Text("NGUYỄN TRUNG TOÁN")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("Nhà phát triển phần mềm")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(18)
        }
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    private var chineseName: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("中文名")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("阮中算")
                    .font(.system(size: 36, weight: .bold))
                Text("Ruǎn Zhōng Suàn")
                    .font(.headline)
                    .foregroundStyle(accentRed)
            }
            Spacer()
            speakButton("阮中算")
        }
        .padding(16)
        .background(card)
    }

    // MARK: - Nội dung

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Về tác giả", icon: "person.fill")
            (Text("Nguyễn Trung Toán là người phát triển phần mềm với mong muốn tạo ra một công cụ học tiếng Trung ")
                + Text("đơn giản, trực quan và dễ sử dụng cho người Việt Nam").bold()
                + Text("."))
                .fixedSize(horizontal: false, vertical: true)
            Text("Phần mềm được xây dựng tập trung vào việc giúp người học ghi nhớ từ vựng, luyện phát âm, học Pinyin, nhận biết chữ Hán và từng bước nâng cao khả năng giao tiếp tiếng Trung trong thực tế.")
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.body)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(card)
    }

    private var goalCard: some View {
        VStack(spacing: 12) {
            sectionTitle("Mục tiêu phát triển", icon: "target")
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                goalChip("HỌC DỄ HƠN", "易学", "Yì xué")
                goalChip("NHỚ LÂU HƠN", "易记", "Yì jì")
                goalChip("GIAO TIẾP\nTỰ TIN HƠN", "敢开口", "Gǎn kāikǒu")
            }
            Button {
                NaturalSpeaker.chinese.speak("易学，易记，敢开口。", preferOpenAI: true)
            } label: {
                Label("Nghe: 易学 · 易记 · 敢开口", systemImage: "speaker.wave.2.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accentRed)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(card)
    }

    private func goalChip(_ vi: String, _ zh: String, _ py: String) -> some View {
        VStack(spacing: 4) {
            Text(zh)
                .font(.system(size: 22, weight: .bold))
            Text(py)
                .font(.caption.weight(.semibold))
                .foregroundStyle(accentRed)
            Text(vi)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 96)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(accentRed.opacity(0.08)))
    }

    private var infoCard: some View {
        VStack(spacing: 0) {
            sectionTitle("Thông tin", icon: "info.circle.fill")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)
            infoRow("Tác giả", "Nguyễn Trung Toán")
            Divider()
            infoRow("Vai trò", "Founder & Developer")
            Divider()
            infoRow("Sản phẩm", "Phần mềm học tiếng Trung")
            Divider()
            infoRow("Quốc gia", "Việt Nam 🇻🇳")
        }
        .padding(16)
        .background(card)
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.vertical, 10)
    }

    private var quoteCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "quote.opening")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.7))
            Text("“Mỗi ngày học một chút, mỗi ngày tiến bộ một chút.”")
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
            Text("每天学一点，每天进步一点。")
                .font(.system(size: 20, weight: .semibold))
            Text("Měitiān xué yìdiǎn, měitiān jìnbù yìdiǎn.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
            Button {
                NaturalSpeaker.chinese.speak("每天学一点，每天进步一点。", preferOpenAI: true)
            } label: {
                Label("Nghe câu này", systemImage: "speaker.wave.2.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(.white.opacity(0.2)))
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 1, green: 0.42, blue: 0.36), Color(red: 0.72, green: 0.1, blue: 0.14)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text("© 2026 Nguyễn Trung Toán. All rights reserved.")
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                Text("Phiên bản \(version)")
            }
            Text("Từ điển tách từ & pinyin: CC-CEDICT (CC BY-SA 4.0), jieba (MIT)")
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 4)
    }

    // MARK: - Tiện ích

    private var card: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground))
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .foregroundStyle(accentRed)
    }

    private func speakButton(_ text: String) -> some View {
        Button {
            NaturalSpeaker.chinese.speak(text, preferOpenAI: true)
        } label: {
            Image(systemName: "speaker.wave.2.fill")
                .font(.title3)
                .foregroundStyle(accentRed)
                .frame(width: 50, height: 50)
                .background(Circle().fill(accentRed.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Nghe \(text)")
    }
}

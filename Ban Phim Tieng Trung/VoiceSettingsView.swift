//
//  VoiceSettingsView.swift
//  Ban Phim Tieng Trung
//

import AVFoundation
import SwiftUI

struct VoiceSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showChinese = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Ngôn ngữ", selection: $showChinese) {
                        Text("Tiếng Việt").tag(false)
                        Text("Tiếng Trung").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                SpeakerSettings(speaker: showChinese ? .chinese : .vietnamese)
                    .id(showChinese)
            }
            .navigationTitle("Giọng đọc")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { dismiss() }
                }
            }
            .onDisappear {
                NaturalSpeaker.all.forEach { $0.stop() }
            }
        }
    }
}

private struct SpeakerSettings: View {
    let speaker: NaturalSpeaker
    @AppStorage private var voiceID: String
    @AppStorage private var speed: Double
    @AppStorage private var pitch: Double

    init(speaker: NaturalSpeaker) {
        self.speaker = speaker
        _voiceID = AppStorage(wrappedValue: NaturalSpeaker.automaticID, speaker.voiceKey)
        _speed = AppStorage(wrappedValue: speaker.language.defaultSpeed, speaker.speedKey)
        _pitch = AppStorage(wrappedValue: NaturalSpeaker.defaultPitch, speaker.pitchKey)
    }

    private var usesGoogle: Bool {
        speaker.resolvedID(for: voiceID) == NaturalSpeaker.googleID
    }

    var body: some View {
        Section {
            voiceRow(
                id: NaturalSpeaker.automaticID,
                title: "Tự động (khuyên dùng)",
                subtitle: "Đang dùng: \(speaker.displayName(for: speaker.resolvedID(for: NaturalSpeaker.automaticID)))"
            )
            if NaturalSpeaker.hasOpenAIVoice() {
                voiceRow(id: NaturalSpeaker.openAIID, title: "OpenAI", subtitle: "Tự nhiên nhất, dùng khoá OpenAI (có tính phí nhỏ)")
            }
            voiceRow(id: NaturalSpeaker.googleID, title: "Google", subtitle: "Tự nhiên, cần kết nối mạng")
            ForEach(speaker.installedVoices, id: \.identifier) { voice in
                voiceRow(
                    id: voice.identifier,
                    title: voice.name,
                    subtitle: "Giọng của máy · \(NaturalSpeaker.qualityLabel(voice))"
                )
            }
        } header: {
            Text("Giọng đọc \(speaker.language.title.lowercased())")
        } footer: {
            Text("Muốn giọng của máy hay hơn, không cần mạng: mở Cài đặt → Trợ năng → Nội dung được đọc → Giọng nói → \(speaker.language.settingsLanguageName), tải giọng “Nâng cao” hoặc “Cao cấp”, rồi quay lại đây.")
        }

        Section("Cách đọc") {
            VStack(alignment: .leading) {
                Text("Tốc độ")
                HStack {
                    Image(systemName: "tortoise")
                    Slider(value: $speed, in: 0.6...1.2, step: 0.05)
                    Image(systemName: "hare")
                }
                .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading) {
                Text("Cao độ giọng")
                HStack {
                    Text("Trầm").font(.caption)
                    Slider(value: $pitch, in: 0.8...1.2, step: 0.05)
                    Text("Cao").font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            .disabled(usesGoogle)
            .opacity(usesGoogle ? 0.4 : 1)

            Button {
                speaker.speak(speaker.language.sample)
            } label: {
                Label("Nghe thử", systemImage: "play.circle.fill")
            }
            Button("Khôi phục mặc định") {
                voiceID = NaturalSpeaker.automaticID
                speed = speaker.language.defaultSpeed
                pitch = NaturalSpeaker.defaultPitch
            }
        }
    }

    private func voiceRow(id: String, title: String, subtitle: String) -> some View {
        Button {
            voiceID = id
            speaker.speak(speaker.language.sample)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if voiceID == id {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
        }
    }
}

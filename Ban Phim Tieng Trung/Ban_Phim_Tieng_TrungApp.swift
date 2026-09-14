//
//  Ban_Phim_Tieng_TrungApp.swift
//  Ban Phim Tieng Trung
//
//  Created by MAC on 14/09/2026.
//

import SwiftUI

@main
struct Ban_Phim_Tieng_TrungApp: App {
    @State private var openedFromKeyboard = false
    @State private var tab: AppTab = .practice

    init() {
        NaturalSpeaker.hasOpenAIVoice = { OpenAISettings.hasAPIKey }
        NaturalSpeaker.openAISpeech = { text, languageCode in
            try await OpenAIClient.speech(text: text, languageCode: languageCode)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(tab: $tab, openedFromKeyboard: openedFromKeyboard)
                .onOpenURL { url in
                    guard url.scheme == AppGroup.urlScheme else { return }
                    openedFromKeyboard = true
                    tab = .keyboard
                    VoiceEngine.shared.activate()
                }
        }
    }
}

//
//  AskAIDemoApp.swift
//  AskAIDemo
//
//  Created on iOS 18+ for iPhone 17 Pro Max demo
//  让 Siri 调用自定义大模型的最小可运行 Demo
//

import SwiftUI
import AppIntents

@main
struct AskAIDemoApp: App {
    var body: some Scene {
        WindowGroup {
            VoiceChatView()   // 改为全屏语音对话界面
        }
    }
}

//
//  VoiceChatView.swift
//  AskAIDemo
//
//  全屏语音对话 UI(大按钮 + 实时 ASR + 状态指示)
//  Action Button 触发后进入这个界面,按大圆按钮说话
//

import SwiftUI

struct VoiceChatView: View {
    @StateObject private var voice = VoiceController()
    @State private var showSettings = false
    @State private var showChat = false
    @State private var config: AppLLMConfig = AppLLMConfigStore.shared.load()

    var body: some View {
        ZStack {
            backgroundGradient
            VStack(spacing: 24) {
                statusBadge
                Spacer()
                bigMicButton
                transcriptBubble
                Spacer()
                if !voice.lastAnswer.isEmpty {
                    answerCard
                }
                bottomBar
            }
            .padding()
        }
        .preferredColorScheme(.dark)
        .onAppear { Task { await voice.requestPermission() } }
        .sheet(isPresented: $showSettings) {
            SettingsView(config: $config) {
                AppLLMConfigStore.shared.save(config)
            }
        }
        .sheet(isPresented: $showChat) {
            ContentView()
        }
    }

    // MARK: - 背景

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color(red: 0.05, green: 0.1, blue: 0.3),
                     Color(red: 0.1, green: 0.05, blue: 0.2)],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - 状态条

    private var statusBadge: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
                .shadow(color: statusColor.opacity(0.8), radius: 6)
            Text(voice.status.rawValue)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            let displayModel = config.mode == .local
                ? URL(fileURLWithPath: config.local.modelDirectory).lastPathComponent
                : config.remote.model
            if !displayModel.isEmpty {
                Text(displayModel)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    // MARK: - 大麦克风按钮

    private var bigMicButton: some View {
        Button {
            voice.toggleRecording()
        } label: {
            ZStack {
                Circle()
                    .fill(voice.status == .listening ? Color.red : Color.blue)
                    .frame(width: 180, height: 180)
                    .shadow(color: statusColor.opacity(0.6), radius: 30)
                if voice.status == .listening {
                    Circle()
                        .stroke(Color.red.opacity(0.5), lineWidth: 4)
                        .frame(width: 230, height: 230)
                        .scaleEffect(1.4)
                        .opacity(0.4)
                        .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                                   value: voice.status)
                }
                Image(systemName: voice.status == .listening ? "stop.fill" : "mic.fill")
                    .font(.system(size: 72, weight: .light))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .disabled(voice.status == .thinking || voice.status == .speaking)
        .accessibilityLabel(voice.status == .listening ? "停止录音" : "开始录音")
    }

    // MARK: - 实时文字

    @ViewBuilder
    private var transcriptBubble: some View {
        let text = voice.partialText.isEmpty ? voice.transcript : voice.partialText
        if !text.isEmpty {
            Text(text)
                .font(.title3)
                .foregroundStyle(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(0.12))
                .cornerRadius(16)
                .transition(.opacity)
        } else {
            VStack(spacing: 6) {
                Text("点击下方按钮开始说话")
                    .foregroundStyle(.white.opacity(0.5))
                    .font(.subheadline)
                Text("或对 Siri 说“嘿 Siri,问 AI xxx”")
                    .foregroundStyle(.white.opacity(0.35))
                    .font(.caption)
            }
        }
    }

    // MARK: - 答案卡

    private var answerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("AI 回答")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                if voice.status == .speaking {
                    Button {
                        voice.stopSpeaking()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .foregroundStyle(.red.opacity(0.8))
                    }
                }
            }
            Text(voice.lastAnswer)
                .font(.body)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
    }

    // MARK: - 底部工具栏

    private var bottomBar: some View {
        HStack(spacing: 32) {
            Button {
                voice.newSession()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "plus.bubble").font(.title2)
                    Text("新会话").font(.caption2)
                }
            }
            Spacer()
            Button {
                showChat = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "bubble.left.and.bubble.right").font(.title2)
                    Text("文字").font(.caption2)
                }
            }
            Spacer()
            Button {
                showSettings = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "gear").font(.title2)
                    Text("设置").font(.caption2)
                }
            }
        }
        .foregroundStyle(.white.opacity(0.75))
    }

    private var statusColor: Color {
        switch voice.status {
        case .idle:      return .gray
        case .listening: return .red
        case .thinking:  return .orange
        case .speaking:  return .green
        }
    }
}

#Preview {
    VoiceChatView()
}

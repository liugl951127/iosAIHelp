//
//  VoiceController.swift
//  AskAIDemo
//
//  全本地语音对话控制器
//  ASR(SFSpeechRecognizer) -> 统一 LLM 客户端(远程/本地 MLX) -> TTS(AVSpeechSynthesizer)
//

import Foundation
import Speech
import AVFoundation
import Combine

@MainActor
final class VoiceController: NSObject, ObservableObject {

    enum Status: String {
        case idle = "待机"
        case listening = "聆听中..."
        case thinking = "思考中..."
        case speaking = "AI 回答中..."
    }

    @Published var status: Status = .idle
    @Published var transcript: String = ""
    @Published var lastAnswer: String = ""
    @Published var hasPermission: Bool = false
    @Published var partialText: String = ""

    /// 当前模式下的 LLM 信息(给 UI 显示)
    @Published var llmInfo: String = ""

    private let recognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private let synthesizer = AVSpeechSynthesizer()
    private var llm: UnifiedLLMClient?
    private let store = ConversationStore.shared
    private var sessionId: String = UUID().uuidString
    private let config: AppLLMConfig

    init(config: AppLLMConfig = AppLLMConfigStore.shared.load()) {
        self.config = config
        self.llm = UnifiedLLMClient(config: config)
        super.init()
        recognizer?.delegate = self
        synthesizer.delegate = self
        refreshLLMInfo()
    }

    func reload(config: AppLLMConfig) {
        self.llm = UnifiedLLMClient(config: config)
        refreshLLMInfo()
    }

    private func refreshLLMInfo() {
        switch config.mode {
        case .remote:
            llmInfo = "☁️ \(config.remote.model)"
        case .local:
            let dir = URL(fileURLWithPath: config.local.modelDirectory).lastPathComponent
            llmInfo = "📱 \(dir) (本机)"
        }
    }

    // MARK: - 权限

    func requestPermission() async {
        let speechAuth: Bool = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        let micAuth: Bool = await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
        hasPermission = speechAuth && micAuth
    }

    // MARK: - 录音控制

    func toggleRecording() {
        if status == .listening {
            stopRecording()
        } else {
            Task { await startRecording() }
        }
    }

    private func startRecording() async {
        guard hasPermission else {
            await requestPermission()
            guard hasPermission else { return }
        }

        recognitionTask?.cancel()
        recognitionTask = nil
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.reset()
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(iOS 16, *) {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement,
                                    options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("音频会话配置失败: \(error)")
            return
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            print("音频引擎启动失败: \(error)")
            return
        }

        status = .listening
        transcript = ""
        partialText = ""

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            if let result = result {
                let text = result.bestTranscription.formattedString
                Task { @MainActor in
                    self.partialText = text
                }
            }
            if error != nil || (result?.isFinal ?? false) {
                Task { @MainActor in
                    await self.finishRecording()
                }
            }
        }
    }

    private func stopRecording() {
        recognitionRequest?.endAudio()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
    }

    private func finishRecording() async {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest = nil
        recognitionTask = nil

        let userText = partialText.trimmingCharacters(in: .whitespacesAndNewlines)
        transcript = userText

        guard !userText.isEmpty else {
            status = .idle
            return
        }

        await ask(text: userText)
    }

    // MARK: - 调 LLM + TTS

    private func ask(text: String) async {
        status = .thinking

        // 重新加载配置(用户可能刚改过 mode)
        let cfg = AppLLMConfigStore.shared.load()
        if llm == nil {
            llm = UnifiedLLMClient(config: cfg)
        }

        store.append(sessionId: sessionId, message: ChatMessage(role: "user", content: text))
        let history = store.find(id: sessionId)?.messages ?? []

        guard let client = llm else {
            speak("LLM 客户端未初始化")
            return
        }

        do {
            let answer = try await client.chat(messages: history)
            store.append(sessionId: sessionId, message: ChatMessage(role: "assistant", content: answer))
            lastAnswer = answer
            speak(answer)
        } catch {
            let err = "抱歉,出错了:\(error.localizedDescription)"
            lastAnswer = err
            speak(err)
        }
    }

    private func speak(_ text: String) {
        status = .speaking
        let cleaned = text
            .replacingOccurrences(of: "```", with: "")
            .replacingOccurrences(of: "\n", with: ",")
        let utterance = AVSpeechUtterance(string: cleaned)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        utterance.postUtteranceDelay = 0.3
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(utterance)
    }

    @objc private func speechDidFinish() {
        // 保留作为 Notification 兼容(暂时未用)
        Task { @MainActor in
            if self.status == .speaking {
                self.status = .idle
            }
        }
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        status = .idle
    }

    func newSession() {
        sessionId = UUID().uuidString
        store.loadOrCreate(id: sessionId)
        transcript = ""
        partialText = ""
        lastAnswer = ""
        status = .idle
    }
}

extension VoiceController: SFSpeechRecognizerDelegate {
    nonisolated func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        Task { @MainActor in
            if !available { self.status = .idle }
        }
    }
}

extension VoiceController: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if self.status == .speaking {
                self.status = .idle
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if self.status == .speaking {
                self.status = .idle
            }
        }
    }
}

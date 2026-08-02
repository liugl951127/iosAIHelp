//
//  LLMClient.swift
//  AskAIDemo
//
//  统一 LLM 客户端 - 支持两种模式:
//    1. Remote 模式:HTTP 调 OpenAI 兼容 API
//    2. Local  模式:用 MLX Swift 跑本地模型
//

import Foundation

struct ChatMessage: Codable, Equatable {
    let role: String
    let content: String
}

struct ChatRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool = false
    let temperature: Double = 0.7
}

struct ChatResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            let role: String
            let content: String
        }
        let message: Message
        let finish_reason: String?
    }
    let choices: [Choice]
    let usage: Usage?

    struct Usage: Codable {
        let prompt_tokens: Int?
        let completion_tokens: Int?
        let total_tokens: Int?
    }
}

struct LLMError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// 模式
enum LLMMode: String, Codable, CaseIterable, Identifiable {
    case remote = "云端 API"
    case local  = "本机推理 (MLX)"
    var id: String { rawValue }
}

/// 顶层配置(决定用哪个模式)
struct AppLLMConfig: Codable, Equatable {
    var mode: LLMMode = .remote
    var remote: LLMConfig = .default
    var local: LocalLLMConfig = LocalLLMConfig(modelDirectory: LocalLLMConfig.defaultModelDirectory)
    var systemPrompt: String = LLMConfig.default.systemPrompt

    static let `default` = AppLLMConfig()
}

class AppLLMConfigStore {
    static let shared = AppLLMConfigStore()
    private let key = "askai.app.config.v2"

    func load() -> AppLLMConfig {
        if let data = UserDefaults.standard.data(forKey: key),
           let cfg = try? JSONDecoder().decode(AppLLMConfig.self, from: data) {
            return cfg
        }
        return .default
    }

    func save(_ config: AppLLMConfig) {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: key)
        }
        // 同步保存到子存储,保持兼容
        LLMConfigStore.shared.save(config.remote)
        LocalLLMConfigStore.shared.save(config.local)
    }
}

/// 统一 LLM 客户端 - 内部根据 mode 选远端还是本地
actor UnifiedLLMClient {
    let config: AppLLMConfig
    private let remote: RemoteLLMClient
    private let local: LocalLLMClient

    init(config: AppLLMConfig) {
        self.config = config
        self.remote = RemoteLLMClient(config: config.remote)
        self.local = LocalLLMClient(config: config.local)
    }

    func chat(messages: [ChatMessage]) async throws -> String {
        var msgs = messages
        // 注入 system prompt
        if !config.systemPrompt.isEmpty,
           !msgs.contains(where: { $0.role == "system" }) {
            msgs.insert(ChatMessage(role: "system", content: config.systemPrompt), at: 0)
        }

        switch config.mode {
        case .remote:
            return try await remote.chat(messages: msgs)
        case .local:
            return try await local.chat(messages: msgs)
        }
    }
}

/// 远端 API 客户端
actor RemoteLLMClient {
    let config: LLMConfig

    init(config: LLMConfig) {
        self.config = config
    }

    func chat(messages: [ChatMessage]) async throws -> String {
        guard let url = config.url else {
            throw LLMError(message: "endpoint URL 非法: \(config.endpoint)")
        }
        guard !config.apiKey.isEmpty || config.endpoint.contains("localhost") || config.endpoint.contains("127.0.0.1") || config.endpoint.contains("192.168") || config.endpoint.contains("11434") else {
            throw LLMError(message: "API key 为空")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30

        let body = ChatRequest(model: config.model, messages: messages)
        req.httpBody = try JSONEncoder().encode(body)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw LLMError(message: "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0): \(body.prefix(200))")
            }
            let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
            return decoded.choices.first?.message.content ?? ""
        } catch let err as LLMError {
            throw err
        } catch {
            throw LLMError(message: "网络错误: \(error.localizedDescription)")
        }
    }
}

/// 本地 MLX 客户端(包装 LocalLLMEngine)
/// 不强制 MainActor,这样 UnifiedLLMClient(actor)可以在 init 里同步构造
/// 内部 await LocalLLMEngine(它是 @MainActor)时 Swift 自动切到 main actor
final class LocalLLMClient: @unchecked Sendable {
    let engine: LocalLLMEngine

    init(config: LocalLLMConfig) {
        self.engine = LocalLLMEngine(config: config)
    }

    func chat(messages: [ChatMessage]) async throws -> String {
        await engine.ensureLoaded()
        var collected = ""
        try await engine.generate(messages: messages) { token in
            collected += token
        }
        return collected
    }
}

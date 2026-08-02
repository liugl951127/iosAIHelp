//
//  LLMConfig.swift
//  AskAIDemo
//
//  大模型配置(从 UserDefaults 读,支持运行时修改)
//

import Foundation

struct LLMConfig: Codable, Equatable {
    var endpoint: String
    var apiKey: String
    var model: String
    var systemPrompt: String

    static let `default` = LLMConfig(
        endpoint: "https://api.deepseek.com/v1/chat/completions",
        apiKey: "",
        model: "deepseek-chat",
        systemPrompt: "你是一个简洁的中文助手,回答控制在 60 字以内,口语化,适合 Siri 朗读。不要使用 Markdown。"
    )

    // 预设了几个常见模型(可在 UI 里一键切换)
    static let presets: [(name: String, endpoint: String, model: String)] = [
        ("Ollama 全本地(Mac)", "http://192.168.1.100:11434/v1/chat/completions",       "qwen2.5:7b"),
        ("Ollama 本机",         "http://127.0.0.1:11434/v1/chat/completions",            "qwen2.5:7b"),
        ("DeepSeek",            "https://api.deepseek.com/v1/chat/completions",          "deepseek-chat"),
        ("通义千问",            "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions", "qwen-plus"),
        ("月之暗面",            "https://api.moonshot.cn/v1/chat/completions",            "moonshot-v1-8k"),
        ("OpenAI",              "https://api.openai.com/v1/chat/completions",             "gpt-4o-mini")
    ]

    // OpenAI 兼容 chat/completions 通用
    var url: URL? { URL(string: endpoint) }
}

// UserDefaults 持久化
class LLMConfigStore {
    static let shared = LLMConfigStore()
    private let key = "askai.config"

    func load() -> LLMConfig {
        guard let data = UserDefaults.standard.data(forKey: key),
              let cfg = try? JSONDecoder().decode(LLMConfig.self, from: data)
        else { return .default }
        return cfg
    }

    func save(_ config: LLMConfig) {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

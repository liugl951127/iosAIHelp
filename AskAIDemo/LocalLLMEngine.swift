//
//  LocalLLMEngine.swift
//  AskAIDemo
//
//  iPhone 本机大模型推理(Apple MLX Swift)
//  支持 4-bit 量化的 Qwen2.5 / Llama3 / DeepSeek 等 MLX 格式模型
//

import Foundation
import MLX
import MLXLLM
import MLXLMCommon

/// 引擎状态
enum LocalEngineState: Equatable {
    case unloaded
    case loading(progress: Double)
    case ready
    case generating
    case error(String)
}

/// 引擎配置
struct LocalLLMConfig: Codable, Equatable {
    /// 模型目录(绝对路径),需要从 HuggingFace 下载到本机
    var modelDirectory: String

    /// 温度
    var temperature: Double = 0.7

    /// 最大生成长度
    var maxTokens: Int = 512

    /// 推荐模型预设
    static let presets: [(name: String, hfId: String, sizeGB: Double)] = [
        ("Qwen2.5-7B-Instruct-4bit", "mlx-community/Qwen2.5-7B-Instruct-4bit", 4.5),
        ("Qwen2.5-3B-Instruct-4bit", "mlx-community/Qwen2.5-3B-Instruct-4bit", 2.0),
        ("Llama-3.1-8B-Instruct-4bit", "mlx-community/Llama-3.1-8B-Instruct-4bit", 4.5),
        ("DeepSeek-V2-Lite-Chat-4bit", "mlx-community/DeepSeek-V2-Lite-Chat-4bit", 5.5)
    ]

    /// 找到 App Documents/Models 下的模型目录
    static var defaultModelDirectory: String {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("Models").path
    }
}

/// 持久化
class LocalLLMConfigStore {
    static let shared = LocalLLMConfigStore()
    private let key = "askai.local.config"

    func load() -> LocalLLMConfig {
        if let data = UserDefaults.standard.data(forKey: key),
           let cfg = try? JSONDecoder().decode(LocalLLMConfig.self, from: data) {
            return cfg
        }
        return LocalLLMConfig(modelDirectory: LocalLLMConfig.defaultModelDirectory)
    }

    func save(_ config: LocalLLMConfig) {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

/// 本地大模型推理引擎
@MainActor
final class LocalLLMEngine: ObservableObject {

    @Published private(set) var state: LocalEngineState = .unloaded
    @Published private(set) var modelInfo: String = ""

    private var modelContainer: ModelContainer?
    private var chatSession: ChatSession?
    private let config: LocalLLMConfig

    init(config: LocalLLMConfig = LocalLLMConfigStore.shared.load()) {
        self.config = config
    }

    /// 加载模型
    func loadModel() async {
        state = .loading(progress: 0.0)
        modelInfo = "正在加载模型..."

        do {
            // 1. 校验模型目录
            let modelURL = URL(fileURLWithPath: config.modelDirectory)
            let files = try FileManager.default.contentsOfDirectory(at: modelURL, includingPropertiesForKeys: nil)
            let hasConfig = files.contains { $0.lastPathComponent == "config.json" }
            let hasTokenizer = files.contains { $0.lastPathComponent.contains("tokenizer") }
            let hasWeights = files.contains { $0.lastPathComponent.contains(".safetensors") }

            guard hasConfig, hasTokenizer, hasWeights else {
                state = .error("模型目录缺少必要文件。需要 config.json、tokenizer.*、*.safetensors")
                return
            }

            // 2. 构造配置
            let modelDirName = modelURL.lastPathComponent
            let modelConfig = ModelConfiguration(
                directory: modelURL,
                modelType: nil
            )

            // 3. 加载
            modelInfo = "正在加载 \(modelDirName)..."
            let container = try await LLMModelFactory.shared.loadContainer(
                configuration: modelConfig,
                progressHandler: { [weak self] progress in
                    Task { @MainActor in
                        self?.state = .loading(progress: progress.fractionCompleted)
                        self?.modelInfo = "加载中: \(Int(progress.fractionCompleted * 100))%"
                    }
                }
            )

            self.modelContainer = container
            self.chatSession = ChatSession(container)
            self.modelInfo = "✓ \(modelDirName) 就绪"
            self.state = .ready
        } catch {
            self.state = .error("加载失败: \(error.localizedDescription)")
            self.modelInfo = "✗ \(error.localizedDescription)"
        }
    }

    /// 卸载模型释放内存
    func unload() {
        chatSession = nil
        modelContainer = nil
        state = .unloaded
        modelInfo = ""
        // 释放 MLX 显存
        MLX.Memory.clearCache()
    }

    /// 生成(流式)
    /// - Parameters:
    ///   - messages: 完整对话历史
    ///   - onToken: 每个 token 的回调
    func generate(messages: [ChatMessage], onToken: @escaping (String) -> Void) async throws {
        guard let session = chatSession else {
            throw NSError(domain: "LocalLLM", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "模型未加载"])
        }
        state = .generating

        // 构造 chat template 格式的 prompt
        let prompt = formatChatPrompt(messages: messages)

        // 流式生成
        do {
            let stream = session.stream(
                prompt: prompt,
                temperature: Float(config.temperature),
                maxTokens: config.maxTokens
            )
            for try await token in stream {
                onToken(token)
            }
            state = .ready
        } catch {
            state = .error("生成失败: \(error.localizedDescription)")
            throw error
        }
    }

    /// 把 messages 拼成 Qwen2.5 chat template
    /// Qwen 格式: <|im_start|>system\n...\n<|im_end|>\n<|im_start|>user\n...\n<|im_end|>\n<|im_start|>assistant\n
    private func formatChatPrompt(messages: [ChatMessage]) -> String {
        var out = ""
        for msg in messages {
            out += "<|im_start|>\(msg.role)\n\(msg.content)<|im_end|>\n"
        }
        out += "<|im_start|>assistant\n"
        return out
    }

    // MARK: - 模型目录管理

    /// 列出 Models 目录下的子目录
    static func listLocalModels() -> [URL] {
        let dir = URL(fileURLWithPath: LocalLLMConfig.defaultModelDirectory)
        guard FileManager.default.fileExists(atPath: dir.path) else { return [] }
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
            )
            return contents.filter { url in
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                return isDir.boolValue && (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            }
        } catch {
            return []
        }
    }

    /// 确保 Models 目录存在
    static func ensureModelsDirectory() throws -> URL {
        let dir = URL(fileURLWithPath: LocalLLMConfig.defaultModelDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 计算目录大小(GB)
    static func directorySize(at url: URL) -> Double {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let attrs = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey])
            total += Int64(attrs?.totalFileAllocatedSize ?? 0)
        }
        return Double(total) / 1024 / 1024 / 1024
    }
}

//
//  ContentView.swift
//  AskAIDemo
//
//  文字版聊天界面(补充 VoiceChatView)
//

import SwiftUI

struct ContentView: View {
    @State private var config: AppLLMConfig = AppLLMConfigStore.shared.load()
    @State private var showSettings = false
    @State private var sessions: [ConversationStore.Session] = ConversationStore.shared.list()
    @State private var currentSessionId: String = UUID().uuidString
    @State private var input: String = ""
    @State private var loading = false
    @State private var llm: UnifiedLLMClient?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                chatHeader
                Divider()
                messageList
                Divider()
                inputBar
            }
            .navigationTitle("问 AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("新建会话") { startNewSession() }
                        if !sessions.isEmpty {
                            Divider()
                            ForEach(sessions) { s in
                                Button {
                                    currentSessionId = s.id
                                } label: { Label(s.title, systemImage: "bubble.left") }
                            }
                            Divider()
                            Button("清空所有会话", role: .destructive) {
                                ConversationStore.shared.clearAll(); refresh()
                            }
                        }
                    } label: { Image(systemName: "bubble.left.and.bubble.right") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gear") }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(config: $config) {
                    AppLLMConfigStore.shared.save(config)
                    llm = UnifiedLLMClient(config: config)
                }
            }
            .onAppear {
                refresh()
                llm = UnifiedLLMClient(config: config)
            }
        }
    }

    private var chatHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(currentModeDescription)
                    .font(.headline)
                Text(loading ? "推理中..." : "✓ 就绪")
                    .font(.caption)
                    .foregroundStyle(loading ? .orange : .green)
            }
            Spacer()
            if loading { ProgressView() }
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
    }

    private var currentModeDescription: String {
        switch config.mode {
        case .remote:
            return config.remote.model.isEmpty ? "未配置云端" : "☁️ \(config.remote.model)"
        case .local:
            return "📱 本机 MLX"
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    let msgs = ConversationStore.shared.find(id: currentSessionId)?.messages ?? []
                    if msgs.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 40)).foregroundStyle(.tertiary)
                            Text("开始对话").foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity).padding(.top, 80)
                    } else {
                        ForEach(Array(msgs.enumerated()), id: \.offset) { idx, msg in
                            MessageBubble(role: msg.role, content: msg.content).id(idx)
                        }
                    }
                }
                .padding()
            }
            .onChange(of: currentSessionId) { _, _ in
                proxy.scrollTo(0, anchor: .top)
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("输入问题", text: $input, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
            Button { Task { await send() } } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title)
            }
            .disabled(loading || input.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding()
    }

    private func send() async {
        let q = input.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        input = ""
        ConversationStore.shared.append(sessionId: currentSessionId,
                                        message: ChatMessage(role: "user", content: q))
        refresh()
        loading = true
        defer { loading = false }
        let cfg = AppLLMConfigStore.shared.load()
        let client = UnifiedLLMClient(config: cfg)
        let history = ConversationStore.shared.find(id: currentSessionId)?.messages ?? []
        do {
            let ans = try await client.chat(messages: history)
            ConversationStore.shared.append(sessionId: currentSessionId,
                                            message: ChatMessage(role: "assistant", content: ans))
        } catch {
            ConversationStore.shared.append(sessionId: currentSessionId,
                                            message: ChatMessage(role: "assistant",
                                                                 content: "❌ \(error.localizedDescription)"))
        }
        refresh()
    }

    private func startNewSession() {
        currentSessionId = UUID().uuidString
        ConversationStore.shared.loadOrCreate(id: currentSessionId)
        refresh()
    }

    private func refresh() {
        sessions = ConversationStore.shared.list()
    }
}

struct MessageBubble: View {
    let role: String
    let content: String
    var isUser: Bool { role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            Text(content)
                .padding(12)
                .background(isUser ? Color.blue : Color(.systemGray5))
                .foregroundStyle(isUser ? .white : .primary)
                .cornerRadius(16)
            if !isUser { Spacer(minLength: 40) }
        }
    }
}

// MARK: - 设置页

struct SettingsView: View {
    @Binding var config: AppLLMConfig
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("运行模式") {
                    Picker("模式", selection: $config.mode) {
                        ForEach(LLMMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if config.mode == .local {
                        NavigationLink {
                            LocalModelView(config: $config.local) {
                                AppLLMConfigStore.shared.save(config)
                            }
                        } label: {
                            HStack {
                                Text("本机模型管理")
                                Spacer()
                                Text(URL(fileURLWithPath: config.local.modelDirectory).lastPathComponent)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    } else {
                        remoteSection
                    }
                }

                Section("System Prompt") {
                    TextEditor(text: $config.systemPrompt)
                        .frame(minHeight: 80)
                }

                Section {
                    Button { onSave(); dismiss() } label: {
                        Text("保存").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private var remoteSection: some View {
        Group {
            Section("预设(云端)") {
                ForEach(LLMConfig.presets, id: \.name) { p in
                    Button {
                        config.remote.endpoint = p.endpoint
                        config.remote.model = p.model
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(p.name).foregroundStyle(.primary)
                                Text(p.model).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if config.remote.model == p.model {
                                Image(systemName: "checkmark").foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }
            Section("Endpoint") {
                TextField("https://...", text: $config.remote.endpoint)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
            }
            Section("API Key") {
                SecureField("sk-...", text: $config.remote.apiKey)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            Section("Model") {
                TextField("model-name", text: $config.remote.model)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
        }
    }
}

// MARK: - 本机模型管理

struct LocalModelView: View {
    @Binding var config: LocalLLMConfig
    let onChange: () -> Void
    @State private var models: [(name: String, size: Double)] = []
    @StateObject private var engine = LocalLLMEngine()

    var body: some View {
        Form {
            Section {
                Text("iPhone 本机运行大模型,数据不离开手机,断网也能用")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("模型加载") {
                HStack {
                    Text("状态")
                    Spacer()
                    Text(engine.modelInfo)
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                if case .loading(let p) = engine.state {
                    ProgressView(value: p)
                }
                Button {
                    Task { await engine.loadModel() }
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("加载本机模型")
                    }
                }
                .disabled({
                    if case .loading = engine.state { return true }
                    if case .generating = engine.state { return true }
                    return false
                }())
                if engine.state == .ready {
                    Button(role: .destructive) {
                        engine.unload()
                    } label: {
                        HStack {
                            Image(systemName: "xmark.circle")
                            Text("卸载模型释放内存")
                        }
                    }
                }
            }

            Section("模型目录") {
                HStack {
                    Text(URL(fileURLWithPath: config.modelDirectory).lastPathComponent)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(String(format: "%.1f GB", LocalLLMEngine.directorySize(at: URL(fileURLWithPath: config.modelDirectory))))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("已下载模型") {
                if models.isEmpty {
                    Text("Models 目录为空").foregroundStyle(.secondary)
                } else {
                    ForEach(models, id: \.name) { m in
                        HStack {
                            Image(systemName: "cube.box.fill").foregroundStyle(.blue)
                            VStack(alignment: .leading) {
                                Text(m.name).font(.subheadline)
                                Text(String(format: "%.2f GB", m.size)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if m.name == URL(fileURLWithPath: config.modelDirectory).lastPathComponent {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        }
                    }
                }
            }

            Section("如何下载模型?") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. 在 Mac 上用 huggingface-cli 下载:")
                        .font(.caption.bold())
                    Text("pip install -U huggingface_hub")
                        .font(.caption.monospaced())
                    Text("huggingface-cli download mlx-community/Qwen2.5-7B-Instruct-4bit --local-dir ~/Models/Qwen2.5-7B")
                        .font(.caption.monospaced())
                    Text("2. 在 Mac Finder 把整个目录拖到 iPhone 的「问 AI」App 里(从 Files App 进入)")
                        .font(.caption)
                    Text("3. 回到这里选择已下载的模型")
                        .font(.caption)
                }
            }

            Section {
                Button {
                    onChange()
                    refresh()
                } label: {
                    HStack { Image(systemName: "arrow.clockwise"); Text("刷新列表") }
                }
            }
        }
        .navigationTitle("本机模型")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refresh() }
    }

    private func refresh() {
        _ = try? LocalLLMEngine.ensureModelsDirectory()
        let urls = LocalLLMEngine.listLocalModels()
        models = urls.map { url in
            (name: url.lastPathComponent, size: LocalLLMEngine.directorySize(at: url))
        }
    }
}

#Preview { ContentView() }

//
//  AskAIIntent.swift
//  AskAIDemo
//
//  暴露给 Siri 的 App Intent
//  触发: "嘿 Siri, 问 AI xxx"
//        "嘿 Siri, 用问AI xxx"
//

import AppIntents
import Foundation

struct AskAIIntent: AppIntent {
    static var title: LocalizedStringResource = "问 AI"
    static var description = IntentDescription("向自定义大模型提问,Siri 会朗读答案。")

    @Parameter(
        title: "问题"
    )
    var question: QuestionEntity

    @Parameter(
        title: "会话 ID",
        description: "用于多轮对话,留空则新会话"
    )
    var sessionId: String?

    // 让 Siri / Shortcuts 知道如何展示这个 Action
    static var parameterSummary: some ParameterSummary {
        Summary("问 \(\.$question)") {
            \.$sessionId
        }
    }

    // 不打开 App,后台直接跑(Siri 场景必需)
    static var openAppWhenRun: Bool = false

    // 性能提示:Siri 触发时,系统会更激进地调度
    static var isDiscoverable: Bool = true

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        // 1) 加载配置
        let config = AppLLMConfigStore.shared.load()
        let client = UnifiedLLMClient(config: config)

        // 2) 加载/创建会话
        let sid: String
        if let s = sessionId, !s.isEmpty {
            sid = s
        } else {
            sid = UUID().uuidString
        }
        var session = ConversationStore.shared.loadOrCreate(id: sid)

        // 3) 追加用户消息
        let userMsg = ChatMessage(role: "user", content: question.text)
        session.messages.append(userMsg)

        // 4) 调 LLM
        let answer: String
        do {
            answer = try await client.chat(messages: session.messages)
        } catch {
            return .result(
                value: sid,
                dialog: IntentDialog("抱歉,AI 出错了:\(error.localizedDescription)")
            )
        }

        // 5) 追加 AI 回复 + 保存会话
        session.messages.append(ChatMessage(role: "assistant", content: answer))
        ConversationStore.shared.save(session)

        // 6) 返回:朗读答案 + 把 sessionId 给 Shortcuts(下次继续)
        return .result(
            value: sid,
            dialog: IntentDialog(stringLiteral: answer)
        )
    }
}

// 注册到 App Shortcuts,让 Siri 在系统层发现
struct AskAIShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskAIIntent(),
            phrases: [
                "问 AI ${applicationName} \(\.$question)",
                "用 ${applicationName} 问 \(\.$question)",
                "Hey ${applicationName} ask \(\.$question)"
            ],
            shortTitle: "问 AI",
            systemImageName: "brain.head.profile"
        )
    }
}

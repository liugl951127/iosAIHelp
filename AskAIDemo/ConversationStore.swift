//
//  ConversationStore.swift
//  AskAIDemo
//
//  多轮对话会话存储(UserDefaults)
//  生产环境建议换 App Group + 文件 / SwiftData / Core Data
//

import Foundation

final class ConversationStore {
    static let shared = ConversationStore()

    private let key = "askai.sessions.v1"
    private let maxHistory = 10   // 每个会话最多保留 N 轮

    struct Session: Codable, Identifiable, Equatable {
        var id: String
        var title: String
        var messages: [ChatMessage]
        var updatedAt: Date

        var lastUserMessage: String? {
            messages.last(where: { $0.role == "user" })?.content
        }
    }

    // 加载/创建会话
    func loadOrCreate(id: String) -> Session {
        if let s = find(id: id) { return s }
        let s = Session(id: id, title: "新会话", messages: [], updatedAt: Date())
        save(s)
        return s
    }

    func find(id: String) -> Session? {
        return all()[id]
    }

    func all() -> [String: Session] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let map = try? JSONDecoder().decode([String: Session].self, from: data)
        else { return [:] }
        return map
    }

    func list() -> [Session] {
        return all().values.sorted(by: { $0.updatedAt > $1.updatedAt })
    }

    func save(_ session: Session) {
        var map = all()
        map[session.id] = session
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func append(sessionId: String, message: ChatMessage) -> Session {
        var s = loadOrCreate(id: sessionId)
        s.messages.append(message)
        // 截断过长历史
        if s.messages.count > maxHistory * 2 {
            s.messages = Array(s.messages.suffix(maxHistory * 2))
        }
        s.updatedAt = Date()
        if s.title == "新会话" && message.role == "user" {
            s.title = String(message.content.prefix(20))
        }
        save(s)
        return s
    }

    func delete(id: String) {
        var map = all()
        map.removeValue(forKey: id)
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func clearAll() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

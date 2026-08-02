//
//  QuestionEntity.swift
//  AskAIDemo
//
//  AppEntity 包装(让 Siri AppShortcut phrases 能用 String question)
//

import AppIntents
import Foundation

/// 把用户问题包成 AppEntity
/// iOS 18 AppIntents 强制要求:AppShortcut phrase 里 \($xxx) 捕获的参数
/// 必须是 AppEntity / AppEnum,不允许 String
struct QuestionEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "问题")
    }
    static var defaultQuery = QuestionQuery()

    /// 用问题文本本身做 id(Siri 通常传完整文本)
    var id: String { text }

    /// 问题内容
    let text: String

    init(text: String) {
        self.text = text
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(text)")
    }
}

/// EntityQuery:让 Siri 能从 id 找到 entity
struct QuestionQuery: EntityQuery {
    func entities(for identifiers: [QuestionEntity.ID]) async throws -> [QuestionEntity] {
        identifiers.map { QuestionEntity(text: $0) }
    }

    /// Siri 提取到的"问题"在这里转成 entity
    func suggestedEntities() async throws -> [QuestionEntity] {
        []  // 动态提取,Siri 实时转 ASR 后回填
    }
}

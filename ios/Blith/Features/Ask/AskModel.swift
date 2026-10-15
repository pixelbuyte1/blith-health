import BlithCore
import Foundation
import Observation

@MainActor
@Observable
final class AskModel {
    var messages: [ChatMessage] = []
    var draft = ""
    var isResponding = false
    var progress: String?
    /// Set when the user sends before deciding on AI sharing; the view shows the consent sheet.
    var pendingQuestion: String?
    /// The model the person picked with the composer toggle for this chat; nil means automatic.
    var pickedModel: AskModelChoice?
    /// What the person tagged with @ for the next question.
    var tags: [AskTag] = []

    /// From the @ panel: adds a tag, never removes one that's already there.
    func addTag(_ tag: AskTag) {
        guard !tags.contains(tag), tags.count < AskTag.limit else { return }
        tags.append(tag)
    }

    func toggleTag(_ tag: AskTag) {
        if let i = tags.firstIndex(of: tag) {
            tags.remove(at: i)
        } else if tags.count < AskTag.limit {
            tags.append(tag)
        }
    }

    /// Automatic: Quick for the first answers of a chat, then Deep for the follow-ups.
    var currentModel: AskModelChoice {
        if let pickedModel { return pickedModel }
        let aiAnswers = messages.filter { $0.role == .assistant && !$0.isLocal && !$0.isError }.count
        return aiAnswers < AskModelChoice.quickAnswers ? .quick : .deep
    }

    func clear() {
        messages = []
        draft = ""
        pendingQuestion = nil
        pickedModel = nil
        tags = []
    }

    /// Chooses the engine: the AI model when the user allowed sharing and a key exists,
    /// otherwise the on-device assistant. AI failures fall back on-device and say so.
    func send(_ text: String, app: AppModel) async {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isResponding, let snapshot = app.snapshot else { return }
        if AppConfig.aiConfigured && Persistence.aiConsent == nil && SafetyScreen.check(question) == nil {
            pendingQuestion = question
            return
        }
        draft = ""
        let tagged = tags
        tags = []
        app.recordQuestion()
        let history = messages
        messages.append(ChatMessage(role: .user, text: question, tags: tagged.isEmpty ? nil : tagged.map(\.label)))
        // The engines see the tags as one extra line after the question.
        let prompt = tagged.isEmpty ? question : question + "\n\nTagged: " + tagged.map(\.context).joined(separator: "; ")
        isResponding = true
        progress = "Thinking"
        defer {
            isResponding = false
            progress = nil
        }
        let tools = HealthAssistantTools(snapshot: snapshot)
        let useAI = AppConfig.aiConfigured && Persistence.aiConsent == true
        let onProgress: @Sendable (String) -> Void = { p in Task { @MainActor in self.progress = p } }
        do {
            if useAI, let key = AppConfig.openRouterKey {
                let choice = currentModel
                let engine = LLMAssistant(client: OpenRouterClient(apiKey: key, model: choice.modelID), tools: tools)
                var reply = try await engine.respond(to: prompt, history: history, progress: onProgress)
                reply.modelName = choice.name
                messages.append(reply)
            } else {
                messages.append(try await LocalAssistant(tools: tools).respond(to: question, history: history, progress: onProgress))
            }
        } catch {
            var local = (try? await LocalAssistant(tools: tools).respond(to: question, history: history, progress: onProgress))
                ?? ChatMessage(role: .assistant, text: "Something went wrong answering that.", isError: true)
            local.text = "I couldn't reach the AI service, so here's what I can tell from your data on this iPhone:\n\n" + local.text
            messages.append(local)
        }
    }

    /// Records the choice and clears `pendingQuestion` synchronously (which closes the sheet),
    /// then answers the question that was waiting.
    func resolveConsent(_ allowed: Bool, app: AppModel) {
        Persistence.aiConsent = allowed
        guard let q = pendingQuestion else { return }
        pendingQuestion = nil
        Task { await send(q, app: app) }
    }

    /// Used by CI screenshots: answers questions with the on-device engine.
    func runScript(_ questions: [String], snapshot: HealthSnapshot) async {
        let tools = HealthAssistantTools(snapshot: snapshot)
        for q in questions {
            messages.append(ChatMessage(role: .user, text: q))
            if let reply = try? await LocalAssistant(tools: tools).respond(to: q, history: messages, progress: { _ in }) {
                messages.append(reply)
            }
        }
    }
}

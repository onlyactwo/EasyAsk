import AppKit
import Foundation

struct ChatMessage: Identifiable, Codable {
    var id = UUID()
    var role: String
    var text: String
    var reasoning = ""
    var hadImage = false
    var createdAt = Date()
}

struct Conversation: Identifiable, Codable {
    var id = UUID()
    var title: String
    var updatedAt = Date()
    var messages: [ChatMessage] = []
}

@MainActor
final class ChatStore: ObservableObject {
    @Published private(set) var conversations: [Conversation] = []
    @Published var selectedID: UUID?
    @Published var draft = ""
    @Published var attachedImage: Data?
    @Published var isGenerating = false
    @Published var errorMessage: String?
    @Published var showSettings = false
    @Published var thinkingEnabled = false
    @Published var reasoningEffort = "high"

    private let client = DeepSeekClient()
    private let storageURL: URL
    private var requestTask: Task<Void, Never>?
    private var activeRequestID: UUID?

    init(storageURL overrideURL: URL? = nil) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let defaultURL = appSupport.appendingPathComponent("EasyAsk/history.json")
        storageURL = overrideURL ?? defaultURL
        let directory = storageURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: storageURL),
           let saved = try? JSONDecoder().decode([Conversation].self, from: data) {
            conversations = saved.sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    var selectedConversation: Conversation? {
        conversations.first { $0.id == selectedID }
    }

    func newConversation() {
        stop()
        selectedID = nil
        draft = ""
        attachedImage = nil
        errorMessage = nil
        showSettings = false
    }

    func select(_ id: UUID) {
        stop()
        selectedID = id
        draft = ""
        attachedImage = nil
        errorMessage = nil
        showSettings = false
    }

    func delete(_ id: UUID) {
        if selectedID == id { stop(); selectedID = nil }
        conversations.removeAll { $0.id == id }
        save()
    }

    func attachPastedImage(_ image: NSImage) {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            errorMessage = "无法读取粘贴的图片。"
            return
        }
        guard png.count <= 30 * 1024 * 1024 else {
            errorMessage = "图片过大，请粘贴小于 30 MiB 的图片。"
            return
        }
        attachedImage = png
        errorMessage = nil
    }

    func stop() {
        requestTask?.cancel()
        requestTask = nil
        activeRequestID = nil
        isGenerating = false
        save()
    }

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isGenerating, !text.isEmpty || attachedImage != nil else { return }
        let apiKey: String
        do {
            guard let savedKey = try KeychainStore.load(), !savedKey.isEmpty else {
                errorMessage = KeychainStore.hasLegacyItem
                    ? "旧版 API Key 无法读取，请在设置中重新输入并保存一次。"
                    : DeepSeekError.missingKey.localizedDescription
                showSettings = true
                return
            }
            apiKey = savedKey
        } catch {
            errorMessage = "无法读取 API Key：\(error.localizedDescription)"
            showSettings = true
            return
        }

        let conversationID: UUID
        if let selectedID, conversations.contains(where: { $0.id == selectedID }) {
            conversationID = selectedID
        } else {
            let chat = Conversation(title: String(text.prefix(32)).isEmpty ? "图片提问" : String(text.prefix(32)))
            conversationID = chat.id
            conversations.insert(chat, at: 0)
            selectedID = chat.id
        }

        let image = attachedImage
        let userMessage = ChatMessage(role: "user", text: text, hadImage: image != nil)
        append(userMessage, to: conversationID)
        let assistantMessage = ChatMessage(role: "assistant", text: "")
        append(assistantMessage, to: conversationID)

        draft = ""
        attachedImage = nil
        errorMessage = nil
        isGenerating = true
        save()

        let messages = apiMessages(for: conversationID, excluding: assistantMessage.id, currentImage: image, currentMessageID: userMessage.id)
        let useThinking = thinkingEnabled
        let effort = reasoningEffort
        let requestID = UUID()
        activeRequestID = requestID
        requestTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await client.stream(messages: messages, apiKey: apiKey, thinkingEnabled: useThinking, reasoningEffort: effort) { [weak self] delta in
                    self?.apply(delta, to: assistantMessage.id, in: conversationID)
                }
            } catch is CancellationError {
                // Keep any partial response already received.
            } catch {
                if self.selectedID == conversationID { self.errorMessage = error.localizedDescription }
                if self.message(assistantMessage.id, in: conversationID)?.text.isEmpty == true {
                    self.removeMessage(assistantMessage.id, from: conversationID)
                }
            }
            if self.activeRequestID == requestID {
                self.isGenerating = false
                self.requestTask = nil
                self.activeRequestID = nil
            }
            self.save()
        }
    }

    private func apiMessages(for id: UUID, excluding excludedID: UUID, currentImage: Data?, currentMessageID: UUID) -> [DeepSeekMessage] {
        guard let chat = conversations.first(where: { $0.id == id }) else { return [] }
        return chat.messages.filter { $0.id != excludedID }.map { message in
            DeepSeekMessage(
                role: message.role,
                text: message.text,
                images: message.id == currentMessageID ? currentImage.map { [$0] } ?? [] : []
            )
        }
    }

    private func message(_ messageID: UUID, in conversationID: UUID) -> ChatMessage? {
        conversations.first(where: { $0.id == conversationID })?.messages.first { $0.id == messageID }
    }

    private func append(_ message: ChatMessage, to id: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].messages.append(message)
        conversations[index].updatedAt = Date()
    }

    private func removeMessage(_ messageID: UUID, from id: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].messages.removeAll { $0.id == messageID }
    }

    private func apply(_ delta: DeepSeekDelta, to messageID: UUID, in id: UUID) {
        guard let conversationIndex = conversations.firstIndex(where: { $0.id == id }),
              let messageIndex = conversations[conversationIndex].messages.firstIndex(where: { $0.id == messageID }) else { return }
        switch delta {
        case .reasoning(let text): conversations[conversationIndex].messages[messageIndex].reasoning += text
        case .answer(let text): conversations[conversationIndex].messages[messageIndex].text += text
        }
        conversations[conversationIndex].updatedAt = Date()
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(conversations)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            errorMessage = "保存聊天记录失败：\(error.localizedDescription)"
        }
    }
}

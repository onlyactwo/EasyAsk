import Foundation

@main
enum Smoke {
    @MainActor
    static func main() async throws {
        let reasoning = #"data: {"choices":[{"delta":{"reasoning_content":"思考中","content":null}}]}"#
        let answer = #"data: {"choices":[{"delta":{"reasoning_content":null,"content":"答案"}}]}"#
        precondition(DeepSeekStreamParser.parse(reasoning) == [.reasoning("思考中")])
        precondition(DeepSeekStreamParser.parse(answer) == [.answer("答案")])
        precondition(DeepSeekStreamParser.parse("data: [DONE]").isEmpty)
        precondition(DeepSeekStreamParser.parse("data: broken").isEmpty)

        let markdown = """
        # 标题

        **加粗**和[链接](https://example.com)

        - 第一项
        2. 第二项

        > 引用

        ```swift
        print("hello")
        ```

        | 名称 | 值 |
        | --- | --- |
        | A | 1 |
        """
        precondition(MarkdownBlocks.parse(markdown) == [
            .heading(level: 1, text: "标题"),
            .paragraph("**加粗**和[链接](https://example.com)"),
            .listItem(marker: "•", indent: 0, text: "第一项"),
            .listItem(marker: "2.", indent: 0, text: "第二项"),
            .quote("引用"),
            .code(language: "swift", text: "print(\"hello\")"),
            .table(headers: ["名称", "值"], rows: [["A", "1"]])
        ])

        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("easyask-smoke-\(UUID().uuidString)")
            .appendingPathComponent("history.json")
        let conversation = Conversation(title: "测试", messages: [ChatMessage(role: "user", text: "你好")])
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode([conversation]).write(to: file)
        await MainActor.run {
            let store = ChatStore(storageURL: file)
            precondition(store.conversations.count == 1)
            store.delete(conversation.id)
            precondition(store.conversations.isEmpty)
        }
        let saved = try JSONDecoder().decode([Conversation].self, from: Data(contentsOf: file))
        precondition(saved.isEmpty)
        try FileManager.default.removeItem(at: file.deletingLastPathComponent())

        guard let endpointString = ProcessInfo.processInfo.environment["EASYASK_TEST_URL"],
              let endpoint = URL(string: endpointString) else { fatalError("Missing mock URL") }
        let client = DeepSeekClient(endpoint: endpoint)
        var deltas: [DeepSeekDelta] = []
        try await client.stream(
            messages: [DeepSeekMessage(role: "user", text: "你好", images: [])],
            apiKey: "smoke-key", thinkingEnabled: false, reasoningEffort: "high"
        ) { deltas.append($0) }
        precondition(deltas == [.answer("好")])

        deltas = []
        try await client.stream(
            messages: [DeepSeekMessage(role: "user", text: "看图", images: [Data([1, 2, 3])])],
            apiKey: "smoke-key", thinkingEnabled: true, reasoningEffort: "high"
        ) { deltas.append($0) }
        precondition(deltas == [.reasoning("想"), .answer("好")])
        print("Smoke tests passed")
    }
}

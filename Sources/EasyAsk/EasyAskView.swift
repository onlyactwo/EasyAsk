import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum EasyAskPalette {
    static let ink = Color(red: 0.247, green: 0.176, blue: 0.125)
    static let muted = Color(red: 0.573, green: 0.490, blue: 0.404)
    static let accent = Color(red: 0.902, green: 0.541, blue: 0.192)
    static let accentSoft = Color(red: 1, green: 0.886, blue: 0.702)
    static let reasoning = Color(red: 0.38, green: 0.42, blue: 0.84)
    static let reasoningSoft = Color(red: 0.93, green: 0.93, blue: 1)
    static let paper = Color(red: 1, green: 0.992, blue: 0.973)
    static let line = Color(red: 0.922, green: 0.867, blue: 0.784)
    static let userBubble = Color(red: 1, green: 0.941, blue: 0.855)
}

@MainActor private enum EasyAskAssets {
    static let sideMascot: NSImage? = {
        guard let url = Bundle.main.url(forResource: "mascot-side-peek", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()
}

struct EasyAskView: View {
    @ObservedObject var store: ChatStore
    @StateObject private var reportExport = ReportExport()
    @AppStorage("followStreamingOutput") private var followStreamingOutput = false
    let onDismiss: () -> Void
    let onRestart: () -> Void
    @FocusState private var inputFocused: Bool
    @State private var userIsScrolling = false
    @State private var followAfterUserScroll = true
    @State private var isNearChatBottom = true
    @State private var hoveredHistoryID: UUID?
    @State private var showingThinkingOptions = false
    private let chatBottomID = "chat-bottom"

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            EasyAskPalette.line.frame(width: 1)
            if store.showSettings {
                SettingsView(store: store, exportInProgress: reportExport.isExporting, onRestart: onRestart)
            }
            else { chatPane }
        }
        .frame(minWidth: 660, minHeight: 440)
        .background(EasyAskPalette.paper)
        .preferredColorScheme(.light)
        .onReceive(NotificationCenter.default.publisher(for: .easyAskPanelShown)) { _ in
            if !store.showSettings { inputFocused = true }
        }
        .onChange(of: store.showSettings) { _, isShowing in
            if isShowing { showingThinkingOptions = false }
            if !isShowing { inputFocused = true }
        }
        .onChange(of: store.isGenerating) { _, isGenerating in
            if isGenerating { showingThinkingOptions = false }
        }
        .onChange(of: store.selectedID) { _, _ in
            showingThinkingOptions = false
            userIsScrolling = false
            followAfterUserScroll = true
            isNearChatBottom = true
            reportExport.dismissNotice()
        }
        .onExitCommand { onDismiss() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text("Easy").foregroundStyle(EasyAskPalette.ink)
                Text("Ask").foregroundStyle(EasyAskPalette.accent)
                Image(systemName: "sparkle")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(EasyAskPalette.accent)
                    .padding(.leading, 3)
            }
            .font(.system(size: 21, weight: .heavy, design: .rounded))
            .padding(.leading, 8)
            .padding(.top, 27)

            Button {
                store.newConversation()
                inputFocused = true
            } label: {
                Label("新建聊天", systemImage: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .foregroundStyle(EasyAskPalette.ink)
                    .background(EasyAskPalette.accentSoft, in: RoundedRectangle(cornerRadius: 11))
            }
            .buttonStyle(.plain)
            .padding(.top, 28)
            .padding(.bottom, 29)

            Text("历史")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(EasyAskPalette.muted)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(store.conversations) { chat in
                        HStack(spacing: 4) {
                            Button {
                                store.select(chat.id)
                                inputFocused = true
                            } label: {
                                Label(chat.title, systemImage: "bubble.left")
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Button(role: .destructive) { store.delete(chat.id) } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                                    .frame(width: 18, height: 22)
                            }
                            .buttonStyle(.plain)
                            .opacity(hoveredHistoryID == chat.id ? 1 : 0.35)
                            .help("删除这段聊天")
                        }
                        .foregroundStyle(EasyAskPalette.ink)
                        .padding(.horizontal, 9)
                        .frame(height: 34)
                        .background(
                            store.selectedID == chat.id ? Color.white.opacity(0.72) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 9)
                        )
                        .onHover { hoveredHistoryID = $0 ? chat.id : nil }
                    }
                }
            }
            .scrollIndicators(.hidden)

            Spacer(minLength: 0)
            Button { store.showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 17))
                    .foregroundStyle(EasyAskPalette.muted)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("设置、重启或退出 EasyAsk")
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 17)
        .frame(width: 214)
        .background(
            LinearGradient(
                colors: [Color(red: 1, green: 0.961, blue: 0.898), Color(red: 0.984, green: 0.914, blue: 0.784)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .overlay(alignment: .bottomTrailing) {
            if let mascot = EasyAskAssets.sideMascot {
                Image(nsImage: mascot)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 175)
                    .offset(x: 24, y: 14)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .zIndex(1)
    }

    private var chatPane: some View {
        VStack(spacing: 0) {
            if let chat = store.selectedConversation {
                HStack {
                    Text(chat.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(EasyAskPalette.ink)
                        .lineLimit(1)
                    Spacer()
                    if reportExport.isExporting && reportExport.noticeConversationID == chat.id {
                        ProgressView()
                            .controlSize(.small)
                    }
                    if reportExport.noticeConversationID == chat.id,
                       let status = reportExport.statusMessage {
                        Text(status)
                            .font(.system(size: 11))
                            .foregroundStyle(EasyAskPalette.muted)
                            .lineLimit(1)
                    }
                    if reportExport.noticeConversationID == chat.id,
                       let url = reportExport.lastFeishuURL, !reportExport.isExporting {
                        Button("打开") { NSWorkspace.shared.open(url) }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(EasyAskPalette.accent)
                            .help("打开刚创建的飞书文档")
                    }
                    Menu {
                        Button("飞书在线文档") {
                            reportExport.export(chat, to: .feishu)
                        }
                        Button("Markdown…") {
                            chooseMarkdownLocation(for: chat)
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(EasyAskPalette.ink)
                            .frame(width: 28, height: 28)
                            .accessibilityLabel("导出聊天")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(store.isGenerating || reportExport.isExporting)
                    .help("把这段完整聊天整理成文档并导出")
                    if store.isGenerating {
                        Button("停止") { store.stop() }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(EasyAskPalette.accent)
                    }
                }
                .padding(.horizontal, 27)
                .frame(height: 64)
                EasyAskPalette.line.frame(height: 1)
                messageScroll
            } else {
                emptyState
            }

            if let error = store.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 27)
                    .padding(.bottom, 6)
            }
            if let selectedID = store.selectedID,
               reportExport.noticeConversationID == selectedID,
               let error = reportExport.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 27)
                    .padding(.bottom, 6)
            }
            composer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EasyAskPalette.paper)
    }

    private var emptyState: some View {
        ZStack {
            Circle()
                .stroke(EasyAskPalette.accent.opacity(0.07), lineWidth: 27)
                .frame(width: 280, height: 280)
                .offset(x: 245, y: -125)
            HStack(alignment: .top, spacing: 5) {
                Text("想问什么？")
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .foregroundStyle(EasyAskPalette.ink)
                Image(systemName: "sparkle")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(EasyAskPalette.accent)
                    .offset(y: -8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var messageScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if let chat = store.selectedConversation {
                        ForEach(chat.messages) { message in
                            MessageView(message: message)
                                .id(message.id)
                        }
                    }
                    Color.clear.frame(height: 1).id(chatBottomID)
                }
                .padding(.horizontal, 27)
                .padding(.vertical, 22)
            }
            .defaultScrollAnchor(
                followStreamingOutput && followAfterUserScroll ? .bottom : nil,
                for: .sizeChanges
            )
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.visibleRect.maxY >= geometry.contentSize.height - 30
            } action: { _, isNearBottom in
                isNearChatBottom = isNearBottom
                if userIsScrolling { followAfterUserScroll = isNearBottom }
            }
            .onScrollPhaseChange { _, phase, context in
                let isNearBottom = context.geometry.visibleRect.maxY >=
                    context.geometry.contentSize.height - 30
                if phase == .interacting || phase == .decelerating {
                    userIsScrolling = true
                    followAfterUserScroll = isNearBottom
                } else if phase == .idle, userIsScrolling {
                    userIsScrolling = false
                    followAfterUserScroll = isNearBottom
                }
            }
            .onChange(of: store.selectedConversation?.messages.last?.id) { _, _ in
                followAfterUserScroll = true
                proxy.scrollTo(chatBottomID, anchor: .bottom)
            }
            .onChange(of: followStreamingOutput) { _, enabled in
                if enabled {
                    followAfterUserScroll = true
                    proxy.scrollTo(chatBottomID, anchor: .bottom)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if store.selectedConversation != nil && !isNearChatBottom &&
                    !(followStreamingOutput && followAfterUserScroll) {
                    Button {
                        followAfterUserScroll = true
                        proxy.scrollTo(chatBottomID, anchor: .bottom)
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(EasyAskPalette.ink)
                            .frame(width: 32, height: 32)
                            .background(Color.white, in: Circle())
                            .overlay(Circle().stroke(EasyAskPalette.line))
                    }
                    .buttonStyle(.plain)
                    .help("回到聊天底部")
                    .padding(.trailing, 25)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 7) {
            if store.attachedImage != nil {
                HStack {
                    Label("已添加图片（不会保存）", systemImage: "photo")
                        .font(.system(size: 11))
                        .foregroundStyle(EasyAskPalette.muted)
                    Button { store.attachedImage = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 9) {
                    Button { pasteImage() } label: {
                        Image(systemName: "photo")
                            .font(.system(size: 17))
                            .foregroundStyle(EasyAskPalette.muted)
                            .frame(width: 24, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help("从剪贴板粘贴图片")

                    TextField("问点什么…", text: $store.draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...4)
                        .font(.system(size: 13))
                        .foregroundStyle(EasyAskPalette.ink)
                        .focused($inputFocused)
                        .onSubmit { store.send() }
                        .disabled(store.isGenerating)

                    Button {
                        showingThinkingOptions.toggle()
                    } label: {
                        HStack(spacing: 5) {
                            Text("思考模式")
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(store.thinkingEnabled ? EasyAskPalette.reasoning : EasyAskPalette.muted)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(store.thinkingEnabled ? EasyAskPalette.reasoningSoft : Color.black.opacity(0.045), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .popover(isPresented: $showingThinkingOptions, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                        thinkingOptions
                    }

                    Button { store.send() } label: {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(EasyAskPalette.accent, in: RoundedRectangle(cornerRadius: 11))
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isGenerating || (store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && store.attachedImage == nil))
                    .help("发送")
                }
            }
            .padding(9)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(EasyAskPalette.line))
            .shadow(color: EasyAskPalette.ink.opacity(0.05), radius: 10, y: 3)
        }
        .padding(.horizontal, 24)
        .padding(.top, 9)
        .padding(.bottom, 18)
    }

    private var thinkingOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("启用思考", isOn: $store.thinkingEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 13, weight: .medium))

            HStack {
                Text("推理强度")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text(ReasoningEffortSlider.label(for: store.reasoningEffort))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(store.thinkingEnabled ? EasyAskPalette.reasoning : EasyAskPalette.muted)
            }
            ReasoningEffortSlider(selection: $store.reasoningEffort)
                .frame(height: 30)
                .disabled(!store.thinkingEnabled)
                .opacity(store.thinkingEnabled ? 1 : 0.5)
        }
        .foregroundStyle(EasyAskPalette.ink)
        .padding(14)
        .frame(width: 264)
        .background(EasyAskPalette.paper)
    }

    private func pasteImage() {
        if let image = NSImage(pasteboard: .general) { store.attachPastedImage(image) }
        else { store.errorMessage = "剪贴板里没有图片。" }
    }

    private func chooseMarkdownLocation(for chat: Conversation) {
        let panel = NSSavePanel()
        panel.title = "保存 Markdown 文档"
        panel.prompt = "生成并保存"
        panel.nameFieldStringValue = "\(safeFileName(chat.title)).md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md", conformingTo: .plainText) ?? .plainText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            reportExport.export(chat, to: .markdown(url))
        }
    }

    private func safeFileName(_ title: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\")
        let cleaned = title.components(separatedBy: forbidden).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "EasyAsk 整理" : String(cleaned.prefix(50))
    }
}

private struct ReasoningEffortSlider: View {
    @Binding var selection: String

    private static let levels = ["low", "high", "max"]
    private static let labels = ["低", "高", "最高"]
    private let thumbSize: CGFloat = 30
    private let accent = EasyAskPalette.reasoning

    private var selectedIndex: Int {
        Self.levels.firstIndex(of: selection) ?? 1
    }

    static func label(for selection: String) -> String {
        labels[levels.firstIndex(of: selection) ?? 1]
    }

    var body: some View {
        GeometryReader { geometry in
                let travel = geometry.size.width - thumbSize
                let thumbX = thumbSize / 2 + travel * CGFloat(selectedIndex) / CGFloat(Self.levels.count - 1)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(red: 0.91, green: 0.91, blue: 0.92))
                        .overlay(Capsule().stroke(Color.black.opacity(0.08)))

                    Capsule()
                        .fill(accent)
                        .frame(width: thumbX)

                    HStack {
                        ForEach(Self.levels.indices, id: \.self) { index in
                            Circle()
                                .fill(index < selectedIndex ? Color.white.opacity(0.7) : Color.gray.opacity(0.55))
                                .frame(width: 6, height: 6)
                            if index < Self.levels.count - 1 { Spacer() }
                        }
                    }
                    .padding(.horizontal, thumbSize / 2 - 3)

                    Circle()
                        .fill(.white)
                        .frame(width: thumbSize, height: thumbSize)
                        .shadow(color: .black.opacity(0.16), radius: 3, y: 1)
                        .offset(x: thumbX - thumbSize / 2)
                }
                .contentShape(Capsule())
                .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                    let fraction = (gesture.location.x - thumbSize / 2) / max(travel, 1)
                    let index = Int((fraction * CGFloat(Self.levels.count - 1)).rounded())
                    selection = Self.levels[min(max(index, 0), Self.levels.count - 1)]
                })
                .animation(.easeOut(duration: 0.14), value: selection)
        }
        .frame(height: thumbSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("推理强度")
        .accessibilityValue(Self.labels[selectedIndex])
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                selection = Self.levels[min(selectedIndex + 1, Self.levels.count - 1)]
            case .decrement:
                selection = Self.levels[max(selectedIndex - 1, 0)]
            @unknown default:
                break
            }
        }
    }
}

private struct MessageView: View {
    let message: ChatMessage
    @State private var reasoningExpanded = false
    @State private var copied = false

    var body: some View {
        Group {
            if message.role == "user" {
                HStack {
                    Spacer(minLength: 48)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(message.text)
                            .textSelection(.enabled)
                            .font(.system(size: 13))
                        if message.hadImage {
                            Label("已发送图片（未保存）", systemImage: "photo")
                                .font(.system(size: 10))
                                .foregroundStyle(EasyAskPalette.muted)
                        }
                    }
                    .foregroundStyle(EasyAskPalette.ink)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 11)
                    .background(EasyAskPalette.userBubble, in: RoundedRectangle(cornerRadius: 14))
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(EasyAskPalette.accent)
                        .frame(width: 28, height: 28)
                        .background(EasyAskPalette.accentSoft.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 8) {
                        Text("EasyAsk")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(EasyAskPalette.accent)
                        if !message.reasoning.isEmpty {
                            DisclosureGroup("思考过程", isExpanded: $reasoningExpanded) {
                                MarkdownView(source: message.reasoning)
                                    .font(.caption)
                                    .foregroundStyle(EasyAskPalette.muted)
                                    .padding(.top, 4)
                            }
                            .font(.caption)
                        }
                        if !message.text.isEmpty {
                            MarkdownView(source: message.text)
                                .font(.system(size: 13))
                                .foregroundStyle(EasyAskPalette.ink)
                            Button {
                                let pasteboard = NSPasteboard.general
                                pasteboard.clearContents()
                                copied = pasteboard.setString(message.text, forType: .string)
                            } label: {
                                Label(copied ? "已复制" : "复制回复",
                                      systemImage: copied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 11))
                                    .foregroundStyle(EasyAskPalette.muted)
                            }
                            .buttonStyle(.plain)
                            .help("复制这条回复的正文")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .onChange(of: message.text) { _, _ in copied = false }
    }
}

private struct SettingsView: View {
    @ObservedObject var store: ChatStore
    let exportInProgress: Bool
    let onRestart: () -> Void
    @AppStorage("followStreamingOutput") private var followStreamingOutput = false
    @State private var apiKey = ""
    @State private var shortcutLabel = "未设置"
    @State private var statusMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { store.showSettings = false } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 20, height: 28)
                }
                .buttonStyle(.plain)
                Text("设置")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(EasyAskPalette.ink)
            .padding(.horizontal, 27)
            .frame(height: 64)
            EasyAskPalette.line.frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let error = store.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        Text("API Key")
                            .font(.system(size: 13, weight: .semibold))
                        HStack(spacing: 9) {
                            SecureField("输入 API Key", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                            Button("粘贴") { pasteAPIKey() }
                                .buttonStyle(.plain)
                                .foregroundStyle(EasyAskPalette.accent)
                            Button("保存") {
                                let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !key.isEmpty else {
                                    statusMessage = "请先输入 API Key"
                                    return
                                }
                                do {
                                    try KeychainStore.save(key)
                                    guard try KeychainStore.load() == key else {
                                        statusMessage = "保存后校验失败，请重试"
                                        return
                                    }
                                    store.errorMessage = nil
                                    statusMessage = "密钥已保存"
                                } catch {
                                    statusMessage = "保存失败：\(error.localizedDescription)"
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(EasyAskPalette.accent)
                        }
                        .font(.system(size: 12))
                    }

                    EasyAskPalette.line.frame(height: 1)
                    Toggle("回答自动跟随", isOn: $followStreamingOutput)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .font(.system(size: 13, weight: .medium))
                        .help("手动上滚暂停跟随，回到底部后恢复")

                    EasyAskPalette.line.frame(height: 1)
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text("全局快捷键")
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Text(shortcutLabel)
                                .font(.system(size: 11))
                                .foregroundStyle(EasyAskPalette.muted)
                        }
                        HStack(spacing: 12) {
                            ShortcutRecorder { shortcut in
                                if HotkeyManager.shared.set(shortcut) {
                                    shortcutLabel = shortcut.label
                                    statusMessage = "快捷键已设置"
                                } else {
                                    statusMessage = "该快捷键不可用，请换一个。"
                                }
                            }
                            .frame(width: 240, height: 30)
                            Button("清除") {
                                _ = HotkeyManager.shared.set(nil)
                                shortcutLabel = "未设置"
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundStyle(EasyAskPalette.muted)
                        }
                    }

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(EasyAskPalette.muted)
                    }

                    EasyAskPalette.line.frame(height: 1)
                    HStack(spacing: 20) {
                        Button("重启 EasyAsk", action: onRestart)
                            .disabled(store.isGenerating || exportInProgress)
                            .help(store.isGenerating || exportInProgress ? "请等待当前操作完成" : "未发送的输入不会保留")
                        Button("退出 EasyAsk") { NSApp.terminate(nil) }
                            .help("彻底结束 EasyAsk")
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(EasyAskPalette.muted)
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(EasyAskPalette.paper)
        .onAppear {
            do {
                apiKey = try KeychainStore.load() ?? ""
                if apiKey.isEmpty && KeychainStore.hasLegacyItem {
                    statusMessage = "旧版密钥无法读取，请重新粘贴并保存一次"
                }
            } catch {
                apiKey = ""
                statusMessage = "无法读取 API Key：\(error.localizedDescription)"
            }
            shortcutLabel = HotkeyManager.shared.shortcut?.label ?? "未设置"
        }
    }

    private func pasteAPIKey() {
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusMessage = "剪贴板里没有可粘贴的文字"
            return
        }
        apiKey = text.trimmingCharacters(in: .whitespacesAndNewlines)
        statusMessage = "已粘贴，请点击“保存”"
    }
}

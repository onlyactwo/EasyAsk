import AppKit
import Carbon
import SwiftUI

struct Shortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let label: String

    static func from(_ event: NSEvent) -> Shortcut? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        var label = ""
        if flags.contains(.control) { modifiers |= UInt32(controlKey); label += "⌃" }
        if flags.contains(.option) { modifiers |= UInt32(optionKey); label += "⌥" }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey); label += "⇧" }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey); label += "⌘" }
        guard modifiers != 0 else { return nil }
        let key = event.keyCode == 49 ? "Space" : (event.charactersIgnoringModifiers ?? "").uppercased()
        guard !key.isEmpty else { return nil }
        return Shortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers, label: label + key)
    }
}

@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()
    var onHotkey: (() -> Void)?
    private var hotkey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private(set) var shortcut: Shortcut?

    private init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotkeyManager.shared.onHotkey?() }
            return noErr
        }, 1, &type, nil, &eventHandler)
        if let data = UserDefaults.standard.data(forKey: "shortcut"),
           let saved = try? JSONDecoder().decode(Shortcut.self, from: data) {
            _ = set(saved)
        }
    }

    @discardableResult
    func set(_ value: Shortcut?) -> Bool {
        if let hotkey { UnregisterEventHotKey(hotkey); self.hotkey = nil }
        guard let value else {
            shortcut = nil
            UserDefaults.standard.removeObject(forKey: "shortcut")
            return true
        }
        let id = EventHotKeyID(signature: 0x4541534B, id: 1)
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(value.keyCode, value.modifiers, id, GetApplicationEventTarget(), 0, &reference)
        guard status == noErr else { return false }
        hotkey = reference
        shortcut = value
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: "shortcut")
        return true
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    let onRecord: (Shortcut) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderView {
        let view = ShortcutRecorderView()
        view.onRecord = onRecord
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderView, context: Context) {
        nsView.onRecord = onRecord
    }
}

final class ShortcutRecorderView: NSView {
    var onRecord: ((Shortcut) -> Void)?
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("录制全局快捷键")
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { window?.makeFirstResponder(nil); return }
        if let shortcut = Shortcut.from(event) {
            onRecord?(shortcut)
            window?.makeFirstResponder(nil)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
        let text = window?.firstResponder === self ? "请按下快捷键（Esc 取消）" : "点击后录制快捷键"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: 10, y: (bounds.height - size.height) / 2), withAttributes: attributes)
    }
}

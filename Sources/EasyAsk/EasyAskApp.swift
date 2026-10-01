import AppKit
import SwiftUI

extension Notification.Name {
    static let easyAskPanelShown = Notification.Name("EasyAskPanelShown")
}

@main
enum EasyAskApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = EasyAskDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        let mainMenu = NSMenu()
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        app.mainMenu = mainMenu
        app.run()
    }
}

@MainActor
final class EasyAskDelegate: NSObject, NSApplicationDelegate {
    let store = ChatStore()
    private var popover: NSPopover!
    private var statusItem: NSStatusItem!
    private var pasteMonitor: Any?
    private var isRestarting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "com.easyask.local.main"
        statusItem.button?.image = EasyAskStatusIcon.make()
        statusItem.button?.toolTip = "EasyAsk"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)

        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 780, height: 540)
        popover.contentViewController = NSHostingController(
            rootView: EasyAskView(
                store: store,
                onDismiss: { [weak self] in self?.popover.performClose(nil) },
                onRestart: { [weak self] in self?.restart() }
            )
        )

        HotkeyManager.shared.onHotkey = { [weak self] in self?.togglePopover() }
        pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.popover.isShown,
                  self.popover.contentViewController?.view.window?.isKeyWindow == true,
                  !self.store.showSettings,
                  event.modifierFlags.contains(.command), event.keyCode == 9,
                  let image = NSImage(pasteboard: .general) else { return event }
            self.store.attachPastedImage(image)
            return nil
        }
        // Let the system place the new status item before anchoring the first popover.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.showPopover() }
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        guard !popover.isShown else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NotificationCenter.default.post(name: .easyAskPanelShown, object: nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover()
        return true
    }

    func applicationDidResignActive(_ notification: Notification) {
        popover?.performClose(nil)
    }

    private func restart() {
        guard !isRestarting, !store.isGenerating else { return }
        let appURL = Bundle.main.bundleURL
        guard appURL.pathExtension == "app" else {
            store.errorMessage = "无法确定 EasyAsk.app 的位置。"
            return
        }
        isRestarting = true
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.allowsRunningApplicationSubstitution = false
        configuration.activates = true
        Task { @MainActor in
            do {
                let replacement = try await NSWorkspace.shared.openApplication(
                    at: appURL, configuration: configuration
                )
                guard replacement.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
                    throw NSError(domain: "EasyAsk", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "系统仍打开了当前进程。"
                    ])
                }
                NSApp.terminate(nil)
            } catch {
                isRestarting = false
                store.errorMessage = "重启失败：\(error.localizedDescription)"
            }
        }
    }
}

private enum EasyAskStatusIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let head = NSBezierPath(roundedRect: NSRect(x: 2.5, y: 2.5, width: 15, height: 13),
                                    xRadius: 6.5, yRadius: 6.5)
            head.lineWidth = 1.5
            head.stroke()

            let cap = NSBezierPath(ovalIn: NSRect(x: 7.7, y: 15.0, width: 4.6, height: 2.5))
            cap.fill()
            let stem = NSBezierPath()
            stem.move(to: NSPoint(x: 10, y: 17.2))
            stem.line(to: NSPoint(x: 10.4, y: 18.5))
            stem.lineWidth = 1.2
            stem.stroke()

            NSBezierPath(ovalIn: NSRect(x: 6.1, y: 10.0, width: 1.5, height: 1.5)).fill()
            NSBezierPath(ovalIn: NSRect(x: 12.4, y: 10.0, width: 1.5, height: 1.5)).fill()
            let smile = NSBezierPath()
            smile.move(to: NSPoint(x: 6.5, y: 7.0))
            smile.curve(to: NSPoint(x: 13.5, y: 7.0),
                        controlPoint1: NSPoint(x: 8, y: 3.4),
                        controlPoint2: NSPoint(x: 12, y: 3.4))
            smile.lineWidth = 1.4
            smile.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}

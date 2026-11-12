import AppKit
import SwiftUI

// A physical I key shortcut works even when the active layout produces Cyrillic Ш.
enum InfoShortcut {
    static func matches(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        keyCode == 34 && modifiers.intersection([.command, .shift, .option, .control]) == .command
    }
}

struct InfoShortcutBridge: NSViewRepresentable {
    let model: TransferModel
    func makeNSView(context: Context) -> InfoShortcutView {
        let view = InfoShortcutView(); view.model = model; return view
    }
    func updateNSView(_ view: InfoShortcutView, context: Context) { view.model = model }
    static func dismantleNSView(_ view: InfoShortcutView, coordinator: ()) { view.stopMonitoring() }
}

final class InfoShortcutView: NSView {
    weak var model: TransferModel?
    private var monitor: Any?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated {
                guard let self, let window = self.window,
                      event.window === window, window.isKeyWindow,
                      window.attachedSheet == nil, NSApp.modalWindow == nil,
                      InfoShortcut.matches(keyCode: event.keyCode, modifiers: event.modifierFlags),
                      let model = self.model, model.canExplore, model.previewURL == nil,
                      model.fileInfo == nil, model.selectedPhoneIDs.count == 1 else { return false }
                // Keep editor shortcuts (e.g. italics) available while a text field has focus.
                if let editor = window.firstResponder as? NSTextView, editor.isEditable { return false }
                if !event.isARepeat { model.showInfo() }
                return true
            }
            return handled ? nil : event
        }
    }
    func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

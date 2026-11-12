import AppKit
import Foundation

@MainActor final class TransferModel {
    var canExplore = true
    var previewURL: URL?
    var fileInfo: String?
    var selectedPhoneIDs: Set<UInt32> = [1]
    func showInfo() {}
}
@main struct InterfaceChecks {
    @MainActor static func main() {
        for characters in ["i", "ш"] {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                timestamp: 0, windowNumber: 0, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 34)!
            precondition(InfoShortcut.matches(keyCode: event.keyCode, modifiers: event.modifierFlags))
        }
        for modifiers: NSEvent.ModifierFlags in [[], .control, [.command, .shift], [.command, .option], [.command, .control]] {
            precondition(!InfoShortcut.matches(keyCode: 34, modifiers: modifiers))
        }
        precondition(!InfoShortcut.matches(keyCode: 35, modifiers: .command))
        precondition(InfoShortcut.matches(keyCode: 34, modifiers: [.command, .capsLock]))
        let credits = AppAbout.credits()
        let range = (credits.string as NSString).range(of: "github.com/poltoraska")
        precondition(range.location != NSNotFound)
        precondition(credits.attribute(.link, at: range.location, effectiveRange: nil) as? URL == URL(string: "https://github.com/poltoraska"))
        precondition(credits.string.contains("libmtp") && credits.string.contains("libusb"))
        print("English/Cyrillic key events, modifier exclusions and clickable author URL: OK")
    }
}

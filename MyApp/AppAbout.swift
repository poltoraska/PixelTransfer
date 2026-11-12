import AppKit

@MainActor
enum AppAbout {
    static let authorURL = URL(string: "https://github.com/poltoraska")!
    static func credits() -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.paragraphSpacing = 8
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        let description = String(localized: "Передача файлов и управление содержимым Google Pixel по USB.")
        let author = String(localized: "Автор: poltoraska")
        let libraries = String(localized: "Использует libmtp и libusb (LGPL 2.1).")
        let result = NSMutableAttributedString(string: description + "\n\n" + author + "\n", attributes: attributes)
        var linkAttributes = attributes
        linkAttributes[.link] = authorURL
        linkAttributes[.foregroundColor] = NSColor.linkColor
        linkAttributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        result.append(NSAttributedString(string: "github.com/poltoraska", attributes: linkAttributes))
        result.append(NSAttributedString(string: "\n\n" + libraries, attributes: attributes))
        return result
    }
    static func show() {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "PixelTransfer", .credits: credits()])
    }
}

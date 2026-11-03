import UIKit
import UniformTypeIdentifiers

/// Copies text without Universal Clipboard, so locations and logs stay off the user's other devices.
enum Clipboard {
    static func copy(_ text: String, expiresAfter seconds: TimeInterval? = nil) {
        var options: [UIPasteboard.OptionsKey: Any] = [.localOnly: true]
        if let seconds { options[.expirationDate] = Date().addingTimeInterval(seconds) }
        UIPasteboard.general.setItems([[UTType.plainText.identifier: text]], options: options)
    }
}

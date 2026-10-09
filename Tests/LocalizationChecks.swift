import Foundation

let application = CommandLine.arguments[1]
func localization(_ language: String) -> Bundle {
    guard let bundle = Bundle(path: application + "/Contents/Resources/" + language + ".lproj") else {
        fatalError("Missing localization: \(language)")
    }
    return bundle
}
let english = localization("en")
let russian = localization("ru")
precondition(String(localized: "Музыка", bundle: english) == "Music")
precondition(String(localized: "Музыка", bundle: russian) == "Музыка")
precondition(String(localized: "Копировать на телефон", bundle: english) == "Copy to phone")
precondition(String(localized: "Подключите телефон заново.", bundle: english) == "Reconnect the phone.")
let name = "Исполнитель/Album 🎵"
precondition(String(localized: "Убрать \(name) из очереди", bundle: english) == "Remove \(name) from the queue")
for (count, ru, en) in [(0, "0 объектов", "0 items"), (1, "1 объект", "1 item"), (2, "2 объекта", "2 items"), (5, "5 объектов", "5 items"), (11, "11 объектов", "11 items"), (21, "21 объект", "21 items")] {
    precondition(String(localized: "\(count) объектов", bundle: english, locale: Locale(identifier: "en")) == en)
    precondition(String(localized: "\(count) объектов", bundle: russian, locale: Locale(identifier: "ru")) == ru)
}
let position = 2, total = 3, destination = "/Music"
precondition(String(localized: "\(position) из \(total): \(name) → \(destination)", bundle: english) == "2 of 3: \(name) → /Music")
print("Compiled Russian/English strings, native errors, filename interpolation and plurals: OK")

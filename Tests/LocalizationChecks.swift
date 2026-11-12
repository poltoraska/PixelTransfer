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
precondition(String(localized: "Копировать на Mac…", bundle: english) == "Copy to Mac…")
precondition(String(localized: "Копировать на Mac…", bundle: russian) == "Копировать на Mac…")
precondition(String(localized: "Не удалось сохранить файл на Mac. Проверьте папку назначения и совпадения имён.", bundle: english) == "Could not save the file on the Mac. Check the destination folder and name conflicts.")
precondition(String(localized: "Быстрый доступ", bundle: english) == "Quick Access")
precondition(String(localized: "Быстрый доступ", bundle: russian) == "Быстрый доступ")
precondition(String(localized: "Камера", bundle: english) == "Camera")
precondition(String(localized: "Камера", bundle: russian) == "Камера")
precondition(String(localized: "Изображения", bundle: english) == "Pictures")
precondition(String(localized: "Изображения", bundle: russian) == "Изображения")
precondition(String(localized: "С Mac на Pixel…", bundle: english) == "Mac to Pixel…")
precondition(String(localized: "С Mac на Pixel…", bundle: russian) == "С Mac на Pixel…")
precondition(String(localized: "С Pixel на Mac…", bundle: english) == "Pixel to Mac…")
precondition(String(localized: "С Pixel на Mac…", bundle: russian) == "С Pixel на Mac…")
precondition(String(localized: "Показать в Finder", bundle: english) == "Show in Finder")
precondition(String(localized: "Показать в Finder", bundle: russian) == "Показать в Finder")
precondition(String(localized: "Скрыть результат", bundle: english) == "Dismiss result")
precondition(String(localized: "Скрыть результат", bundle: russian) == "Скрыть результат")
precondition(String(localized: "Отменить", bundle: english) == "Cancel")
precondition(String(localized: "Отменить", bundle: russian) == "Отменить")
precondition(String(localized: "Быстрый просмотр", bundle: english) == "Quick Look")
precondition(String(localized: "Свойства", bundle: english) == "Get Info")
precondition(String(localized: "Переместить сюда", bundle: english) == "Move Here")
precondition(String(localized: "Удалить с Pixel без возможности восстановления?", bundle: english) == "Permanently delete from Pixel?")
precondition(String(localized: "Новая папка…", bundle: english) == "New Folder…")
precondition(String(localized: "О PixelTransfer", bundle: english) == "About PixelTransfer")
precondition(String(localized: "Автор: poltoraska", bundle: english) == "Author: poltoraska")
precondition(String(localized: "Передача файлов и управление содержимым Google Pixel по USB.", bundle: english) == "Transfer files and manage content on Google Pixel over USB.")
let name = "Исполнитель/Album 🎵"
precondition(String(localized: "Убрать \(name) из очереди", bundle: english) == "Remove \(name) from the queue")
for (count, ru, en) in [(0, "0 объектов", "0 items"), (1, "1 объект", "1 item"), (2, "2 объекта", "2 items"), (5, "5 объектов", "5 items"), (11, "11 объектов", "11 items"), (21, "21 объект", "21 items")] {
    precondition(String(localized: "\(count) объектов", bundle: english, locale: Locale(identifier: "en")) == en)
    precondition(String(localized: "\(count) объектов", bundle: russian, locale: Locale(identifier: "ru")) == ru)
}
let position = 2, total = 3, destination = "/Music"
precondition(String(localized: "\(position) из \(total): \(name) → \(destination)", bundle: english) == "2 of 3: \(name) → /Music")
let copiedCount = 24, skippedCount = 2
precondition(String(localized: "Скопировано файлов: \(copiedCount). Пропущено: \(skippedCount).", bundle: english) == "Files copied: 24. Skipped: 2.")
precondition(String(localized: "Скопировано файлов: \(copiedCount). Пропущено: \(skippedCount).", bundle: russian) == "Скопировано файлов: 24. Пропущено: 2.")
print("Compiled Russian/English strings, native errors, filename interpolation and plurals: OK")

# PixelTransfer

[Русский](#russian) · [English](#english)

<a id="russian"></a>

## Русский

Mac ↔ Android по USB

Локальный прототип для Apple Silicon и macOS 27. Работает через MTP без USB-отладки и приложения на Android.

### Запуск

Откройте `PixelTransfer.xcodeproj` в этой папке. Проект, цель сборки, схема и готовое приложение называются `PixelTransfer`. Выберите My Mac и нажмите Run (⌘R).

1. Закройте OpenMTP и другие приложения, использующие телефон.
2. Подключите Pixel кабелем с поддержкой передачи данных, разблокируйте телефон и выберите USB → «Передача файлов».
3. Нажмите «Подключить Pixel». В боковой панели выберите папку в разделе «Быстрый доступ» или корень хранилища; вложенные папки открываются двойным щелчком или клавишей Return.
4. Нажмите «С Mac на Pixel…», выберите файлы или папки и подтвердите копирование. Передача начнётся сразу в открытую папку телефона.
5. Можно также перетащить файлы из Finder. Они попадут в очередь; проверьте путь назначения внизу окна и нажмите «Копировать на телефон».

Например, при выборе папки `Исполнитель` и папки назначения `Music` на телефоне получится `Music/Исполнитель/Альбом/треки`. Верхняя выбранная папка и вся вложенность сохраняются; пустые папки тоже создаются.

Можно отправлять несколько файлов и папок. Перед копированием дерево папки обходится в фоне, рассчитывается размер и формируется план. Существующие папки объединяются, совпадающие имена файлов пропускаются: существующие файлы не заменяются. Если вместо нужной папки на телефоне уже есть файл с таким именем, передача останавливается с понятной ошибкой. Символические ссылки и специальные файлы не копируются; служебные `.DS_Store` и `._*` исключаются. Это предотвращает циклы и выход за пределы выбранного каталога. После передачи проверяется размер нового файла по метаданным MTP; это не проверка контрольной суммы. При ошибке соединения приложение закрывает сессию и предлагает подключиться заново. При отмене текущий созданный объект удаляется по возможности; если кабель отключён, неполный файл может остаться на телефоне.

### Копирование с Android на Mac

Выделите один или несколько файлов и папок в таблице телефона (⌘ для отдельных объектов, ⇧ для диапазона). Нажмите «С Pixel на Mac…» в панели инструментов, «Копировать на Mac…» в контекстном меню либо ⇧⌘S. Выберите папку назначения в системном диалоге и нажмите «Копировать сюда». Копирование начнётся сразу. Внизу окна доступны имя файла, прогресс и отмена. После передачи отображаются количество скопированных и пропущенных файлов, «Подробности» и «Показать в Finder». Последняя выбранная папка на Mac запоминается между запусками и подставляется в диалог; доступ подтверждается при каждом выборе. Ожидающие отправки файлы с Mac остаются в очереди и отправляются отдельно.

Верхняя выбранная папка, вложенность и пустые папки сохраняются. Папки объединяются, существующие обычные файлы пропускаются без проверки содержимого. Конфликт с папкой, ссылкой или специальным объектом останавливает копирование. Ссылки внутри папки назначения не используются. Передача идёт во временный файл в папке назначения: после проверки размера он получает итоговое имя без замены существующего объекта. При отмене или ошибке незавершённый файл удаляется; уже готовые файлы и папки сохраняются. Размер проверяется по метаданным MTP, контрольная сумма не вычисляется. Исходные файлы на телефоне сохраняются.

Пока нет продолжения прерванного файла и интеграции с Finder. При отмене или ошибке уже скопированные файлы и папки остаются в папке назначения. Можно повторно добавить исходную папку: недостающие файлы скопируются, существующие будут пропущены. Очередь хранится только во время работы приложения. Если файл пропущен или операция завершилась ошибкой, удалите строку из очереди и добавьте файл заново для отправки либо снова выделите его в таблице телефона для скачивания.

### Проводник Pixel

Пробел открывает Quick Look для одного выбранного файла; двойной щелчок по файлу делает то же самое. Для папки пробел открывает свойства. ⌘I (физическая клавиша I/Ш в английской и русской раскладках) — свойства одного объекта: имя, путь, тип, размер файла, дата изменения (если предоставлена Pixel), хранилище и его доступность для записи. Размер папок не рассчитывается автоматически.

Для предпросмотра файл целиком скачивается во временную папку Mac, с прогрессом и отменой. После закрытия предпросмотра временная копия удаляется. Форматы определяются системным Quick Look; приложение не редактирует оригинал на Pixel.

Контекстное меню таблицы и меню «Передача» содержат переименование, перемещение и удаление. ⇧⌘N создаёт папку в текущем каталоге; ⌘Delete запрашивает удаление выделенных объектов. Удаление требует подтверждения, выполняется без корзины и без Undo, папки удаляются со всем содержимым. Перемещение предлагает папки выбранного хранилища Pixel. Совпадения имён и перенос папки в саму себя запрещены. Операции зависят от поддержки MTP устройством; при ошибке уже выполненные изменения сохраняются. Автоматического отката и переноса между хранилищами нет.

Проверки без телефона: `./scripts/check-explorer.sh`.

### Интерфейс

Окно использует стандартные компоненты SwiftUI: системную боковую панель, панель инструментов, таблицу и скрываемый инспектор очереди. Liquid Glass применяется к навигации и управляющим элементам: системной панели инструментов, строке пути и кнопкам. Таблица файлов сохраняет обычный фон для читаемости. Цвета и материалы адаптируются к системной светлой/тёмной теме.

Раздел «Быстрый доступ» показывает только существующие папки выбранного хранилища: «Музыка» (`Music`), «Загрузки» (`Download`), «Камера» (`DCIM`), «Изображения» (`Pictures`) и «Документы» (`Documents`). Список обновляется при подключении, переходе между папками и обновлении папки. Если подходящих папок нет, раздел скрывается; пункт «Хранилище» остаётся доступен. Папки автоматически не создаются. «Камера» открывает `DCIM`, а не всю галерею телефона.

Поиск фильтрует имена только в текущей папке. Щелчок по заголовку таблицы меняет сортировку; кнопки в строке пути возвращают к родительским папкам. Скрытые файлы включаются в меню «…». В версии 1.1 очередь скрыта по умолчанию и не открывается при добавлении файлов. Кнопка справа в панели инструментов и «Подробности» открывают список передач; выбранная видимость запоминается. Подробности результата раскрываются у каждой завершённой передачи.

Сочетания клавиш: ⌘O — выбрать файлы на Mac и начать копирование, ⌘K — подключить/отключить телефон, ⌘R — обновить папку, ⌘↑ — на папку выше, ⌘Return — копировать на телефон, ⇧⌘S — копировать выделенное на Mac. Навигация отключена во время передачи.

Рекомендации Apple: [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass), [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars).

### О приложении

В PixelTransfer → «О PixelTransfer» доступны версия, описание, автор poltoraska и кликабельная [ссылка на профиль GitHub](https://github.com/poltoraska). Описание и подписи доступны на русском и английском. Проверки сочетания клавиш и ссылки без запуска интерфейса: `./scripts/check-interface.sh`.

### Языки

Приложение поддерживает русский и английский языки. macOS выбирает язык по системным предпочтениям. Тексты интерфейса, меню, подсказки, статусы и сообщения об ошибках приложения находятся в `MyApp/Localizable.xcstrings`. Имена файлов, папок, устройств и пути сохраняются. Счётчики используют правила множественного числа выбранного языка.

Чтобы проверить английский в Xcode: Product → Scheme → Edit Scheme… → Run → Options → App Language → English. Для возврата к настройкам macOS выберите System Language. После смены языка перезапустите приложение.

### Сборка в Терминале

```sh
xcodebuild -project 'PixelTransfer.xcodeproj' -scheme PixelTransfer \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build build
open .build/Build/Products/Debug/PixelTransfer.app
```

### DMG с установкой перетаскиванием

В папке проекта выполните:

```sh
./scripts/create-dmg.sh
```

Скрипт собирает Release для Apple Silicon и создаёт `dist/PixelTransfer-1.1-arm64.dmg` (номер берётся из версии приложения). Внутри — PixelTransfer и ссылка «Программы» на `/Applications`; установка выполняется перетаскиванием приложения на эту папку. Фон берётся из `PixelTransferBackground.png` в корне проекта и содержит обычное и Retina-представления. Положение значков и размер окна задаются в `scripts/dmg-settings.py`.

Для сборки нужны Xcode и Python 3. При первом запуске dmgbuild 1.6.7 устанавливается из PyPI в изолированное окружение `.build/dmg-tools`; в приложение Python и dmgbuild не входят. Finder не используется для автоматической настройки или проверки окна. Перед выдачей DMG скрипт проверяет контрольные суммы образа, подпись приложения, исполняемый файл, ссылку «Программы», фон и позиции значков. Визуальную проверку окна пользователь выполняет самостоятельно.

Для упаковки заранее подписанного приложения можно передать путь:

```sh
./scripts/create-dmg.sh /path/to/PixelTransfer.app
```

Этот режим сохраняет подпись приложения и не пересобирает его. Текущий образ содержит локальную ad-hoc сборку. Для распространения на другие Mac необходимы Developer ID, корректная подпись вложенных библиотек, notarization и stapling по [документации Apple](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution). Скрипт сам не выполняет публикацию, Developer ID-подпись или notarization.

### Устройство кода

- `MyApp/ContentView.swift`: интерфейс, выбор файлов и drag-and-drop.
- `MyApp/TransferModel.swift`: очередь, прогресс, отмена, последовательный фоновый доступ к телефону.
- `MyApp/UploadPlan.swift`: обход вложенных папок, исключение ссылок и служебных файлов, план копирования.
- `MyApp/DownloadPlan.swift`: план чтения дерева телефона и безопасный обход папки назначения на Mac.
- `MyApp/Localizable.xcstrings`: русские и английские переводы.
- `MyApp/Native/MTPBridge.m`: адаптер libmtp, просмотр и создание папок, отправка, получение файлов и проверка размера.
- `MyApp/Libraries.bundle`: заменяемые динамические библиотеки libmtp 1.1.23 и libusb 1.0.30 (arm64). Библиотеки входят в приложение; Homebrew при запуске не требуется.

App Sandbox включён. Приложение имеет доступ к USB и чтению и записи в файлы и папки, выбранные пользователем. Сборка локальная, с ad-hoc подписью; для распространения потребуются Developer ID, корректная подпись вложенных библиотек и notarization.

### Сторонние библиотеки

libmtp: https://github.com/libmtp/libmtp (версия 1.1.23, LGPL 2.1).
libusb: https://github.com/libusb/libusb (версия 1.0.30, LGPL 2.1).
Лицензии находятся в `ThirdParty/` и внутри `Libraries.bundle/`.
Сами библиотеки не изменены; пути зависимости libusb изменены на `@loader_path` для автономной загрузки. Для восстановления библиотек из Homebrew предусмотрен `scripts/vendor-libraries.sh`.

Перед публичным распространением приложите соответствующий исходный код сторонних библиотек и выполните требования LGPL; текущая версия предназначена для локальной разработки.

### Проверки

Результаты USB-проверок находятся в `Tests/RESULTS.md`. Для проверки планирования отправки папок без телефона:

```sh
swiftc MyApp/UploadPlan.swift Tests/UploadPlanTests.swift -o /tmp/pixel_plan_tests
/tmp/pixel_plan_tests
```

Проверки скачивания без телефона и без запуска интерфейса (вложенные и пустые папки, конфликты, ссылки, отмена, обрыв, проверка размера и очистка временных файлов) используют подменную MTP-библиотеку:

```sh
./scripts/check-download.sh
```

Для проверки локализации собранного Debug-приложения без интерфейса:

```sh
swift Tests/LocalizationChecks.swift .build/Build/Products/Debug/PixelTransfer.app
```

### Проверочные папки

`TestFiles/` и `TestFolders/` — временные материалы USB-проверок. Их можно удалить: сборка приложения и DMG их не используют. Эти папки исключены из Git. Примеры ручного чтения обратно из `Tests/RESULTS.md` ссылаются на эти файлы; после удаления для повтора этих примеров материалы потребуется создать заново. `Tests/` содержит проверки регрессий и результаты; её лучше оставить, хотя для запуска приложения она не требуется. `scripts/` нужны для сборки DMG и подготовки библиотек, `ThirdParty/` — для лицензий зависимостей. `.build/` и `dist/` создаются автоматически и могут быть удалены и собраны заново.

### Публикация в GitHub через Xcode

1. Откройте `PixelTransfer.xcodeproj` из этой папки.
2. Выберите Integrate → New Git Repository… и создайте репозиторий в корне проекта, рядом с `.xcodeproj` и README.
3. Если Xcode уже создал `Initial Commit` и изменений нет, дополнительный коммит не нужен. Если есть новые изменения, выберите Integrate → Commit…, проверьте список файлов и сохраните их коммитом. `.gitignore` исключает сборки, персональные настройки Xcode, DMG и временные материалы проверок. Общую схему, ресурсы приложения, вложенные библиотеки и лицензии нужно сохранить в репозитории.
4. В Xcode → Settings… → Source Control нажмите Add Account, выберите GitHub и выполните показанные шаги входа. Раздел Apple Accounts предназначен для учётных записей Apple.
5. В Source Control navigator откройте вкладку Repositories, раскройте PixelTransfer, нажмите правой кнопкой на Remotes и выберите New “PixelTransfer” Remote…. Выберите GitHub, имя `PixelTransfer` и доступ Public или Private, затем Create.
6. Xcode создаст удалённый репозиторий и отправит коммиты. Если остались неотправленные изменения, выполните Integrate → Push…. Проверьте наличие файлов на GitHub.

Если пустой репозиторий уже создан на GitHub, используйте Add Existing Remote… с его адресом. При создании репозитория на GitHub не добавляйте отдельный README: он уже есть в проекте. Токены доступа вводятся только при входе в Xcode, в файлы проекта их добавлять не нужно.

Документация Apple: [Настройка Git](https://developer.apple.com/documentation/xcode/configuring-your-xcode-project-to-use-source-control), [Создание удалённого репозитория](https://help.apple.com/xcode/mac/current/en.lproj/dev2547b9dbe.html).

<a id="english"></a>

## English

PixelTransfer is a local prototype for Apple Silicon and macOS 27. It copies files from Mac to Android over USB using MTP. USB debugging and an Android companion app are not required.

### Getting started

Open `PixelTransfer.xcodeproj`. The project, target, scheme, and built application are all named `PixelTransfer`. Select My Mac and click Run (⌘R).

1. Close OpenMTP and other apps that access the phone.
2. Connect your Pixel with a data-capable USB cable, unlock it, and select USB → File transfer.
3. Click Connect Pixel. Choose Music, Downloads, or Storage in the sidebar. Open subfolders with a double-click or Return.
4. Click “Mac to Pixel…”, select files or folders, and confirm. Copying starts immediately into the current phone folder.
5. You can also drag files from Finder to queue them. Check the destination at the bottom of the window and click “Copy to phone”.

For example, selecting an `Artist` folder and the phone's `Music` directory produces `Music/Artist/Album/tracks`. The selected top-level folder, all subfolders, and empty folders are preserved.

You can send several files and folders together. The app scans each folder in the background, calculates its size, and prepares an upload plan. Existing folders are merged. Files with matching names are skipped rather than overwritten. If a file on the phone has the name of a folder that needs to be created, the transfer stops with an error. Symbolic links and special files are excluded, as are Finder metadata files `.DS_Store` and `._*`. This avoids cycles and access outside the selected folder. After each upload, the app verifies the new file's size using MTP metadata; this is not a checksum verification. Connection errors close the session and require reconnecting. Cancelling attempts to delete the current incomplete object; if the cable is disconnected, a partial file may remain on the phone.

### Copying from Android to Mac

Select one or more files and folders in the phone table (⌘ for individual items, ⇧ for a range). Click “Pixel to Mac…” in the toolbar, “Copy to Mac…” in the context menu, or press ⇧⌘S. Choose a destination in the system folder picker and click “Copy here”. Copying starts immediately. The file name, progress, and cancellation appear at the bottom of the window. The result includes copied/skipped counts, Details, and Show in Finder. The last Mac destination is remembered across launches and offered in the folder picker; access is confirmed with each selection. Pending uploads from the Mac stay queued and are sent separately.

The selected top-level folder, subfolders, and empty folders are preserved. Existing folders are merged; existing regular files are skipped without comparing their contents. Conflicts with directories, links, or special items stop the transfer. Links inside the destination folder are never followed. Each download goes into a temporary file in its destination directory. After its size is verified, it receives the final name without replacing any existing object. Cancellation and errors remove the incomplete file; completed files and folders remain. Size is checked against MTP metadata, not a checksum. Original files remain on the phone.

Resuming interrupted files and Finder integration are not implemented. Files and folders already copied remain in the destination after cancellation or an error. Add the source folder again to copy missing files while skipping existing ones. The queue is kept only while the app is running. To retry a skipped or failed item, remove it from the queue and add it again for upload, or select it again in the phone table for download.

### Pixel file browser

Space opens Quick Look for one selected file; double-clicking a file does the same. For a folder, Space opens Get Info. ⌘I (the physical I/Ш key in English and Russian layouts) shows one item's name, path, type, file size, modification date (when provided by Pixel), storage, and storage write access. Folder sizes are not calculated automatically.

Preview downloads the whole file to a temporary Mac folder, with progress and cancellation. Closing the preview removes the temporary copy. Supported formats depend on system Quick Look; the original on Pixel is not edited.

The table context menu and Transfer menu provide Rename, Move, and Delete. ⇧⌘N creates a folder in the current directory; ⌘Delete requests deletion of selected items. Deletion requires confirmation, has no Trash or Undo, and includes all contents of selected folders. Move lets you select a folder in the current Pixel storage. Name collisions and moving a folder inside itself are blocked. Operations depend on device MTP support; completed changes are kept if an error occurs. Automatic rollback and moves between storages are not provided.

Checks without a phone: `./scripts/check-explorer.sh`.

### Interface

The window uses standard SwiftUI components: a system sidebar, toolbar, file table, and a collapsible transfer inspector. Liquid Glass is used for navigation and controls, including the system toolbar, path bar, and buttons. The file table retains a plain background for readability. Colors and materials follow the system's light or dark appearance.

Quick Access shows only folders present in the selected storage: Music (`Music`), Downloads (`Download`), Camera (`DCIM`), Pictures (`Pictures`), and Documents (`Documents`). The list refreshes on connection, folder navigation, and folder refresh. If none of these folders exist, the section is hidden; Storage remains available. Folders are not created automatically. Camera opens `DCIM`, rather than the entire phone gallery.

Search filters names only in the current folder. Click a column heading to sort the table, or a path component to return to an enclosing folder. The More menu controls hidden files. In version 1.1 the queue is hidden by default and stays hidden when files are added. The rightmost toolbar button or Details opens the transfer list; your visibility preference is remembered. Expand Details on a completed item to see its result.

Keyboard shortcuts: ⌘O selects Mac files and starts copying, ⌘K connects or disconnects the phone, ⌘R refreshes the folder, ⌘↑ opens the enclosing folder, and ⌘Return starts copying to the phone, and ⇧⌘S copies selected phone items to the Mac. Navigation is disabled during a transfer.

Apple guidance: [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass), [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars).

### About

PixelTransfer → About PixelTransfer shows the version, description, author poltoraska, and a clickable [GitHub profile link](https://github.com/poltoraska). Descriptions and labels are available in Russian and English. Run shortcut and link checks without opening the interface: `./scripts/check-interface.sh`.

### Languages

The app supports Russian and English. macOS selects the app language from your language preferences. All app-owned labels, menus, tooltips, statuses, and errors are stored in `MyApp/Localizable.xcstrings`. File names, folder names, device names, and paths are preserved. Item counts use the plural rules of each language.

To try English from Xcode: Product → Scheme → Edit Scheme… → Run → Options → App Language → English. Select System Language to return to your macOS preferences. Restart the app after changing its language.

### Building in Terminal

```sh
xcodebuild -project 'PixelTransfer.xcodeproj' -scheme PixelTransfer \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build build
open .build/Build/Products/Debug/PixelTransfer.app
```

### Creating a drag-to-install DMG

Run this from the project directory:

```sh
./scripts/create-dmg.sh
```

The script builds Release for Apple Silicon and creates `dist/PixelTransfer-1.1-arm64.dmg`, using the app's current version number. The image contains PixelTransfer and a shortcut named «Программы» pointing to `/Applications`. Drag the app onto that folder to install it. The background comes from `PixelTransferBackground.png` in the project root and includes standard and Retina representations. Icon positions and window size are configured in `scripts/dmg-settings.py`.

Xcode and Python 3 are required to build the image. On the first run, dmgbuild 1.6.7 is installed from PyPI into the isolated `.build/dmg-tools` environment. Python and dmgbuild are not shipped inside the application. Finder is not used to configure or verify the window. Before producing the DMG, the script verifies the image checksums, app signature, executable, Applications shortcut, background, and icon positions. Visual inspection is left to the user.

To package an app that has already been signed, pass its path:

```sh
./scripts/create-dmg.sh /path/to/PixelTransfer.app
```

This preserves the app's signature and does not rebuild it. The current image contains a local ad-hoc build. Distribution to other Macs requires Developer ID, correct signing of embedded libraries, notarization, and stapling as described in [Apple's documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution). The script does not publish the app or perform Developer ID signing or notarization.

### Code layout

- `MyApp/ContentView.swift`: interface, file selection, and drag-and-drop.
- `MyApp/TransferModel.swift`: queue, progress, cancellation, and serial background access to the phone.
- `MyApp/UploadPlan.swift`: folder traversal, link and metadata exclusions, and the upload plan.
- `MyApp/DownloadPlan.swift`: remote folder planning and safe traversal of the selected Mac destination.
- `MyApp/Localizable.xcstrings`: Russian and English translations.
- `MyApp/Native/MTPBridge.m`: libmtp adapter for browsing, folder creation, uploading, and size verification.
- `MyApp/Libraries.bundle`: replaceable arm64 libraries, libmtp 1.1.23 and libusb 1.0.30. They are bundled with the app; Homebrew is not required at runtime.

App Sandbox is enabled. The app has USB access and read/write access to files and folders selected by the user. Local builds use ad-hoc signing; distribution requires Developer ID, correctly signed embedded libraries, and notarization.

### Third-party libraries

libmtp: https://github.com/libmtp/libmtp (1.1.23, LGPL 2.1).
libusb: https://github.com/libusb/libusb (1.0.30, LGPL 2.1).
Licenses are stored in `ThirdParty/` and inside `Libraries.bundle/`.
The libraries themselves are unmodified; the libusb dependency path uses `@loader_path` for self-contained loading. `scripts/vendor-libraries.sh` restores them from Homebrew.

Before public distribution, provide the corresponding source code for the third-party libraries and comply with LGPL requirements. This version is intended for local development.

### Checks and optional folders

USB verification results are recorded in `Tests/RESULTS.md`. To check upload planning without a phone:

```sh
swiftc MyApp/UploadPlan.swift Tests/UploadPlanTests.swift -o /tmp/pixel_plan_tests
/tmp/pixel_plan_tests
```

Download regression checks run without a phone or app UI, using a mock MTP library. They cover nested and empty folders, conflicts, links, cancellation, disconnects, size verification, and temporary file cleanup:

```sh
./scripts/check-download.sh
```

To check the compiled Debug app's translations without opening its interface:

```sh
swift Tests/LocalizationChecks.swift .build/Build/Products/Debug/PixelTransfer.app
```

`TestFiles/` and `TestFolders/` contain disposable USB test fixtures. You may delete them; neither the app build nor DMG creation uses them. They are ignored by Git. Manual USB readback examples in `Tests/RESULTS.md` reference those fixtures and require recreating them if deleted. `Tests/` contains regression checks and notes; keeping it is recommended, though the app does not need it to run. Keep `scripts/` for DMG creation and library maintenance, and `ThirdParty/` for dependency licenses. `.build/` and `dist/` are generated and may be removed and rebuilt.

### Publishing from Xcode to GitHub

1. Open `PixelTransfer.xcodeproj` from this directory.
2. Choose Integrate → New Git Repository… and create the repository in the project root, alongside the `.xcodeproj` and README.
3. If Xcode has already created `Initial Commit` and there are no changes, another commit is unnecessary. If there are new changes, use Integrate → Commit…, review the files, and commit them. The `.gitignore` excludes build output, user-specific Xcode state, DMGs, and disposable test fixtures. Keep the shared scheme, app resources, bundled libraries, and third-party licenses.
4. In Xcode → Settings… → Source Control, click Add Account, select GitHub, and complete the sign-in steps shown by Xcode. Apple Accounts is for Apple accounts.
5. In the Source Control navigator, open Repositories, expand PixelTransfer, Control-click Remotes, and choose New “PixelTransfer” Remote…. Select GitHub, enter `PixelTransfer`, choose Public or Private, and click Create.
6. Xcode creates the remote and sends the commits. If anything remains to push, use Integrate → Push…. Check the repository on GitHub to confirm that the files are present.

If GitHub already has an empty repository, use Add Existing Remote… with its URL instead of creating another remote. Keep the GitHub repository empty initially: this project already has a README. GitHub access tokens are entered only in Xcode's sign-in flow, not in project files.

Apple documentation: [Source control setup](https://developer.apple.com/documentation/xcode/configuring-your-xcode-project-to-use-source-control), [Create a remote repository](https://help.apple.com/xcode/mac/current/en.lproj/dev2547b9dbe.html).

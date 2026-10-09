# PixelTransfer

[Русский](#russian) · [English](#english)

<a id="russian"></a>

## Русский

Mac → Android по USB

Локальный прототип для Apple Silicon и macOS 27. Работает через MTP без USB-отладки и приложения на Android.

### Запуск

Откройте `PixelTransfer.xcodeproj` в этой папке. Проект, цель сборки, схема и готовое приложение называются `PixelTransfer`. Выберите My Mac и нажмите Run (⌘R).

1. Закройте OpenMTP и другие приложения, использующие телефон.
2. Подключите Pixel кабелем с поддержкой передачи данных, разблокируйте телефон и выберите USB → «Передача файлов».
3. Нажмите «Подключить Pixel». В боковой панели выберите «Музыка», «Загрузки» или корень хранилища; вложенные папки открываются двойным щелчком или клавишей Return.
4. Добавьте файлы или папки кнопкой «+» в панели инструментов, кнопкой «Выбрать на Mac…» в очереди либо перетащите их из Finder.
5. Проверьте папку назначения внизу очереди справа и нажмите «Копировать на телефон».

Например, при выборе папки `Исполнитель` и папки назначения `Music` на телефоне получится `Music/Исполнитель/Альбом/треки`. Верхняя выбранная папка и вся вложенность сохраняются; пустые папки тоже создаются.

Можно отправлять несколько файлов и папок. Перед копированием дерево папки обходится в фоне, рассчитывается размер и формируется план. Существующие папки объединяются, совпадающие имена файлов пропускаются: существующие файлы не заменяются. Если вместо нужной папки на телефоне уже есть файл с таким именем, передача останавливается с понятной ошибкой. Символические ссылки и специальные файлы не копируются; служебные `.DS_Store` и `._*` исключаются. Это предотвращает циклы и выход за пределы выбранного каталога. После передачи проверяется размер нового файла по метаданным MTP; это не проверка контрольной суммы. При ошибке соединения приложение закрывает сессию и предлагает подключиться заново. При отмене текущий созданный объект удаляется по возможности; если кабель отключён, неполный файл может остаться на телефоне.

Пока нет передачи с телефона на Mac, продолжения прерванного файла и интеграции с Finder. При отмене или ошибке уже скопированные файлы и папки остаются на телефоне. Можно повторно добавить исходную папку: недостающие файлы скопируются, существующие будут пропущены. Очередь хранится только во время работы приложения. Если файл пропущен или операция завершилась ошибкой, удалите строку из очереди и добавьте файл заново для повтора.

### Интерфейс

Окно использует стандартные компоненты SwiftUI: системную боковую панель, панель инструментов, таблицу и скрываемый инспектор очереди. Liquid Glass применяется к навигации и управляющим элементам: системной панели инструментов, строке пути и кнопкам. Таблица файлов сохраняет обычный фон для читаемости. Цвета и материалы адаптируются к системной светлой/тёмной теме.

Поиск фильтрует имена только в текущей папке. Щелчок по заголовку таблицы меняет сортировку; кнопки в строке пути возвращают к родительским папкам. Скрытые файлы включаются в меню «…». Очередь можно скрыть кнопкой справа в панели инструментов; добавление новых файлов открывает её автоматически. Подробности результата раскрываются у каждой завершённой передачи.

Сочетания клавиш: ⌘O — добавить файлы и папки, ⌘K — подключить/отключить телефон, ⌘R — обновить папку, ⌘↑ — на папку выше, ⌘Return — копировать. Навигация отключена во время передачи.

Рекомендации Apple: [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass), [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars).

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

Скрипт собирает Release для Apple Silicon и создаёт `dist/PixelTransfer-1.0-arm64.dmg` (номер берётся из версии приложения). Внутри — PixelTransfer и ссылка «Программы» на `/Applications`; установка выполняется перетаскиванием приложения на эту папку. Фон берётся из `PixelTransferBackground.png` в корне проекта и содержит обычное и Retina-представления. Положение значков и размер окна задаются в `scripts/dmg-settings.py`.

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
- `MyApp/Localizable.xcstrings`: русские и английские переводы.
- `MyApp/Native/MTPBridge.m`: адаптер libmtp, просмотр и создание папок, отправка и проверка размера.
- `MyApp/Libraries.bundle`: заменяемые динамические библиотеки libmtp 1.1.23 и libusb 1.0.30 (arm64). Библиотеки входят в приложение; Homebrew при запуске не требуется.

App Sandbox включён. Приложение имеет доступ к USB и чтению файлов, выбранных пользователем. Сборка локальная, с ad-hoc подписью; для распространения потребуются Developer ID, корректная подпись вложенных библиотек и notarization.

### Сторонние библиотеки

libmtp: https://github.com/libmtp/libmtp (версия 1.1.23, LGPL 2.1).
libusb: https://github.com/libusb/libusb (версия 1.0.30, LGPL 2.1).
Лицензии находятся в `ThirdParty/` и внутри `Libraries.bundle/`.
Сами библиотеки не изменены; пути зависимости libusb изменены на `@loader_path` для автономной загрузки. Для восстановления библиотек из Homebrew предусмотрен `scripts/vendor-libraries.sh`.

Перед публичным распространением приложите соответствующий исходный код сторонних библиотек и выполните требования LGPL; текущая версия предназначена для локальной разработки.

### Проверки

Результаты USB-проверок находятся в `Tests/RESULTS.md`. Для проверки планирования папок без телефона:

```sh
swiftc MyApp/UploadPlan.swift Tests/UploadPlanTests.swift -o /tmp/pixel_plan_tests
/tmp/pixel_plan_tests
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
3. Выберите Integrate → Commit…, проверьте список файлов и сделайте первый коммит, например `Initial PixelTransfer version`. `.gitignore` исключает сборки, персональные настройки Xcode, DMG и временные материалы проверок. Общую схему, ресурсы приложения, вложенные библиотеки и лицензии нужно сохранить в репозитории.
4. В Xcode → Settings… → Accounts добавьте GitHub (+ → GitHub) и выполните показанные шаги входа.
5. В Source Control navigator нажмите правой кнопкой на репозиторий PixelTransfer и выберите Create PixelTransfer Remote…. Выберите GitHub, имя `PixelTransfer` и доступ Public или Private, затем Create.
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
4. Add files or folders using the + toolbar button, Choose on Mac… in the queue, or drag them from Finder.
5. Check the destination folder at the bottom of the queue and click Copy to phone.

For example, selecting an `Artist` folder and the phone's `Music` directory produces `Music/Artist/Album/tracks`. The selected top-level folder, all subfolders, and empty folders are preserved.

You can send several files and folders together. The app scans each folder in the background, calculates its size, and prepares an upload plan. Existing folders are merged. Files with matching names are skipped rather than overwritten. If a file on the phone has the name of a folder that needs to be created, the transfer stops with an error. Symbolic links and special files are excluded, as are Finder metadata files `.DS_Store` and `._*`. This avoids cycles and access outside the selected folder. After each upload, the app verifies the new file's size using MTP metadata; this is not a checksum verification. Connection errors close the session and require reconnecting. Cancelling attempts to delete the current incomplete object; if the cable is disconnected, a partial file may remain on the phone.

Transfers from Android to Mac, resuming an interrupted file, and Finder integration are not implemented. Files and folders already copied remain on the phone after cancellation or an error. Add the source folder again to copy missing files while skipping existing ones. The queue is kept only while the app is running. To retry a skipped or failed item, remove it from the queue and add it again.

### Interface

The window uses standard SwiftUI components: a system sidebar, toolbar, file table, and a collapsible transfer inspector. Liquid Glass is used for navigation and controls, including the system toolbar, path bar, and buttons. The file table retains a plain background for readability. Colors and materials follow the system's light or dark appearance.

Search filters names only in the current folder. Click a column heading to sort the table, or a path component to return to an enclosing folder. The More menu controls hidden files. The toolbar button on the right hides the queue; adding new files opens it automatically. Expand Details on a completed item to see its result.

Keyboard shortcuts: ⌘O adds files and folders, ⌘K connects or disconnects the phone, ⌘R refreshes the folder, ⌘↑ opens the enclosing folder, and ⌘Return starts copying. Navigation is disabled during a transfer.

Apple guidance: [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass), [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars).

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

The script builds Release for Apple Silicon and creates `dist/PixelTransfer-1.0-arm64.dmg`, using the app's current version number. The image contains PixelTransfer and a shortcut named «Программы» pointing to `/Applications`. Drag the app onto that folder to install it. The background comes from `PixelTransferBackground.png` in the project root and includes standard and Retina representations. Icon positions and window size are configured in `scripts/dmg-settings.py`.

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
- `MyApp/Localizable.xcstrings`: Russian and English translations.
- `MyApp/Native/MTPBridge.m`: libmtp adapter for browsing, folder creation, uploading, and size verification.
- `MyApp/Libraries.bundle`: replaceable arm64 libraries, libmtp 1.1.23 and libusb 1.0.30. They are bundled with the app; Homebrew is not required at runtime.

App Sandbox is enabled. The app has USB access and read-only access to files selected by the user. Local builds use ad-hoc signing; distribution requires Developer ID, correctly signed embedded libraries, and notarization.

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

To check the compiled Debug app's translations without opening its interface:

```sh
swift Tests/LocalizationChecks.swift .build/Build/Products/Debug/PixelTransfer.app
```

`TestFiles/` and `TestFolders/` contain disposable USB test fixtures. You may delete them; neither the app build nor DMG creation uses them. They are ignored by Git. Manual USB readback examples in `Tests/RESULTS.md` reference those fixtures and require recreating them if deleted. `Tests/` contains regression checks and notes; keeping it is recommended, though the app does not need it to run. Keep `scripts/` for DMG creation and library maintenance, and `ThirdParty/` for dependency licenses. `.build/` and `dist/` are generated and may be removed and rebuilt.

### Publishing from Xcode to GitHub

1. Open `PixelTransfer.xcodeproj` from this directory.
2. Choose Integrate → New Git Repository… and create the repository in the project root, alongside the `.xcodeproj` and README.
3. Choose Integrate → Commit…, review the files, and create an initial commit such as `Initial PixelTransfer version`. The `.gitignore` excludes build output, user-specific Xcode state, DMGs, and disposable test fixtures. Keep the shared scheme, app resources, bundled libraries, and third-party licenses.
4. In Xcode → Settings… → Accounts, add your GitHub account (+ → GitHub) and complete the sign-in steps shown by Xcode.
5. In the Source Control navigator, Control-click the PixelTransfer repository and choose Create PixelTransfer Remote…. Select GitHub, enter `PixelTransfer`, choose Public or Private, and click Create.
6. Xcode creates the remote and sends the commits. If anything remains to push, use Integrate → Push…. Check the repository on GitHub to confirm that the files are present.

If GitHub already has an empty repository, use Add Existing Remote… with its URL instead of creating another remote. Keep the GitHub repository empty initially: this project already has a README. GitHub access tokens are entered only in Xcode's sign-in flow, not in project files.

Apple documentation: [Source control setup](https://developer.apple.com/documentation/xcode/configuring-your-xcode-project-to-use-source-control), [Create a remote repository](https://help.apple.com/xcode/mac/current/en.lproj/dev2547b9dbe.html).

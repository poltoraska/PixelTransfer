import SwiftUI
import QuickLook
import UniformTypeIdentifiers

private struct PhoneLocation: Identifiable {
    let id: String
    let title: String
    let symbol: String
    static let quickAccess = [
        PhoneLocation(id: "Music", title: String(localized: "Музыка"), symbol: "music.note"),
        PhoneLocation(id: "Download", title: String(localized: "Загрузки"), symbol: "arrow.down.circle"),
        PhoneLocation(id: "DCIM", title: String(localized: "Камера"), symbol: "camera"),
        PhoneLocation(id: "Pictures", title: String(localized: "Изображения"), symbol: "photo"),
        PhoneLocation(id: "Documents", title: String(localized: "Документы"), symbol: "doc")
    ]
}
private extension PhoneEntry {
    var kind: String {
        if folder { return String(localized: "Папка") }
        let type = UTType(filenameExtension: (name as NSString).pathExtension)
        if type?.conforms(to: .audio) == true { return String(localized: "Аудиофайл") }
        if type?.conforms(to: .image) == true { return String(localized: "Изображение") }
        if type?.conforms(to: .movie) == true { return String(localized: "Видео") }
        return String(localized: "Файл")
    }
    var symbol: String {
        if folder { return "folder.fill" }
        let type = UTType(filenameExtension: (name as NSString).pathExtension)
        if type?.conforms(to: .audio) == true { return "music.note" }
        if type?.conforms(to: .image) == true { return "photo" }
        if type?.conforms(to: .movie) == true { return "film" }
        return "doc"
    }
}

struct ContentView: View {
    @StateObject private var model = TransferModel()
    @AppStorage("showTransferQueueV11") private var showQueue = false
    @AppStorage("showHiddenPhoneFiles") private var showHidden = false
    @State private var dropTarget = false
    @State private var search = ""
    @State private var sidebarSelection: String?
    @State private var sortOrder = [KeyPathComparator(\PhoneEntry.name)]

    private var folderTitle: String { model.folders.last?.name ?? String(localized: "Хранилище") }
    private var currentSidebarLocation: String? {
        guard model.connected else { return nil }
        guard let name = model.folders.first?.name else { return "storage" }
        return quickAccessLocations.contains { $0.id == name } ? name : nil
    }
    private var quickAccessLocations: [PhoneLocation] {
        PhoneLocation.quickAccess.filter { model.rootFolderNames.contains($0.id) }
    }
    private var visibleEntries: [PhoneEntry] {
        model.entries.filter {
            (showHidden || !$0.name.hasPrefix(".")) && (search.isEmpty || $0.name.localizedStandardContains(search))
        }.sorted(using: sortOrder)
    }
    private var selectedFolder: PhoneEntry? {
        guard model.selectedPhoneIDs.count == 1 else { return nil }
        return model.entries.first { model.selectedPhoneIDs.contains($0.id) && $0.folder }
    }
    private var objectCount: String { String(localized: "\(visibleEntries.count) объектов") }
    private var canCopy: Bool { model.connected && model.writable && !model.isBusy && !model.isChoosingDestination && model.pending > 0 }
    private func size(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .file)
    }

    var body: some View {
        NavigationSplitView {
            WindowColumn { sidebar }
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            WindowColumn { browser }
                .navigationTitle(model.connected ? folderTitle : "PixelTransfer")
                .navigationSubtitle(model.connected ? "\(model.deviceName ?? "Android") · \(objectCount)" : String(localized: "Файлы между Mac и Android"))
                .searchable(text: $search, placement: .toolbar, prompt: String(localized: "Поиск в папке"))
                .toolbar { windowToolbar }
        }
        .navigationSplitViewStyle(.balanced)
        .inspector(isPresented: $showQueue) {
            WindowColumn { queuePane }
                .inspectorColumnWidth(min: 300, ideal: 330, max: 440)
        }
        .quickLookPreview($model.previewURL)
        .onChange(of: model.previewURL) { _, url in if url == nil { model.closePreview() } }
        .sheet(item: $model.fileInfo) { info in ExplorerInfoView(info: info) }
        .sheet(isPresented: $model.movePresented, onDismiss: model.closeMove) { MoveDestinationView(model: model) }
        .background(InfoShortcutBridge(model: model).frame(width: 0, height: 0))
        .focusedSceneValue(\.transferModel, model)
        .frame(minWidth: 920, minHeight: 590)
        .onChange(of: search) { _, _ in model.selectedPhoneIDs = [] }
        .onChange(of: model.destination) { _, _ in search = ""; model.selectedPhoneIDs = [] }
        .onChange(of: model.storageID) { _, _ in search = ""; model.selectedPhoneIDs = [] }
        .onDrop(of: [.fileURL], isTargeted: $dropTarget, perform: acceptDrop)
        .overlay {
            if dropTarget && !model.isBusy {
                RoundedRectangle(cornerRadius: 16).strokeBorder(.tint, style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
                    .padding(8).allowsHitTesting(false)
            }
        }
        .alert(String(localized: "Не удалось выполнить операцию"), isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button(String(localized: "Понятно")) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "smartphone").font(.system(size: 27, weight: .light)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.deviceName ?? "Pixel").font(.headline)
                    HStack(spacing: 5) {
                        Circle().fill(model.connected ? Color.green : Color.secondary.opacity(0.5)).frame(width: 5, height: 5)
                        Text(model.connected ? String(localized: "Подключён по USB") : String(localized: "Не подключён")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, 18).padding(.vertical, 20)
            // Selection belongs to the view so the highlight follows the click immediately.
            // Synchronize with the actual folder after navigation finishes (including errors).
            List(selection: $sidebarSelection) {
                Section(String(localized: "Телефон")) {
                    Label(String(localized: "Хранилище"), systemImage: "internaldrive").tag("storage")
                }
                if !quickAccessLocations.isEmpty {
                    Section(String(localized: "Быстрый доступ")) {
                        ForEach(quickAccessLocations) { location in
                            Label(location.title, systemImage: location.symbol).tag(location.id)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .disabled(!model.connected || model.isTransferring || model.isChoosingDestination)
            // Block extra clicks during folder reads without dimming the selected row.
            .allowsHitTesting(!model.isBusy)
            .onChange(of: sidebarSelection) { _, location in
                guard let location, location != currentSidebarLocation else { return }
                guard !model.isBusy, !model.isChoosingDestination else {
                    sidebarSelection = currentSidebarLocation
                    return
                }
                model.browseShortcut(named: location == "storage" ? nil : location)
            }
            .onChange(of: currentSidebarLocation, initial: true) { _, location in
                sidebarSelection = location
            }
            .onChange(of: model.isBusy) { _, busy in
                if !busy { sidebarSelection = currentSidebarLocation }
            }
            if model.connected {
                VStack(alignment: .leading, spacing: 7) {
                    if model.storages.count > 1 {
                        Picker(String(localized: "Хранилище"), selection: Binding(get: { model.storageID }, set: { storage in
                            guard storage != model.storageID else { return }
                            Task { @MainActor in
                                guard storage != model.storageID else { return }
                                model.browse([], storage: storage)
                            }
                        })) {
                            ForEach(model.storages) { Text($0.name).tag($0.id) }
                        }.labelsHidden().disabled(model.isBusy)
                    }
                    if let storage = model.storages.first(where: { $0.id == model.storageID }) {
                        Label(String(localized: "\(size(storage.freeBytes)) свободно"), systemImage: "internaldrive")
                            .font(.caption).foregroundStyle(.secondary)
                            .help(String(localized: "Свободное место при подключении"))
                        if !storage.writable { Text(String(localized: "Только чтение")).font(.caption).foregroundStyle(.secondary) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            }
        }
    }

    private var browser: some View {
        Group {
            if !model.connected {
                ContentUnavailableView {
                    Label(String(localized: "Подключите телефон"), systemImage: "cable.connector")
                } description: {
                    Text(String(localized: "Подключите Pixel по USB, разблокируйте его\nи выберите «Передача файлов» в настройках USB."))
                } actions: {
                    Button(String(localized: "Подключить Pixel"), action: model.connect)
                        .buttonStyle(.glassProminent).controlSize(.large).disabled(model.isBusy)
                }
            } else if visibleEntries.isEmpty {
                if search.isEmpty {
                    ContentUnavailableView(String(localized: "Папка пуста"), systemImage: "folder", description: Text(String(localized: "Нажмите «С Mac на Pixel…», чтобы скопировать файлы в эту папку.")))
                } else {
                    ContentUnavailableView.search(text: search)
                }
            } else {
                fileTable
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .safeAreaInset(edge: .top, spacing: 0) {
            if model.connected { pathBar.padding(.horizontal, 18).padding(.vertical, 12) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { statusBar }
    }

    private var fileTable: some View {
        Table(visibleEntries, selection: $model.selectedPhoneIDs, sortOrder: $sortOrder) {
            TableColumn(String(localized: "Имя"), value: \.name) { entry in
                HStack(spacing: 9) {
                    Image(systemName: entry.symbol)
                        .foregroundStyle(entry.folder ? Color.accentColor : Color.secondary)
                        .frame(width: 18)
                    Text(entry.name).lineLimit(1).truncationMode(.middle)
                }.padding(.vertical, 3)
            }.width(min: 170, ideal: 260)
            TableColumn(String(localized: "Тип"), value: \.kind) { entry in
                Text(entry.kind).foregroundStyle(.secondary)
            }.width(min: 65, ideal: 85, max: 110)
            TableColumn(String(localized: "Размер"), value: \.size) { entry in
                Text(entry.folder ? "—" : size(entry.size)).foregroundStyle(.secondary).monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }.width(min: 65, ideal: 80, max: 100)
        }
        .contextMenu(forSelectionType: UInt32.self) { ids in
            if ids.count == 1, let entry = model.entries.first(where: { ids.contains($0.id) && $0.folder }) {
                Button(String(localized: "Открыть папку")) { model.open(entry) }.disabled(model.isBusy)
            }
            if ids.count == 1 {
                Button(String(localized: "Быстрый просмотр")) { model.preview(ids: ids) }.disabled(!model.canExplore)
                Button(String(localized: "Свойства")) { model.showInfo(ids: ids) }.disabled(!model.canExplore)
                Button(String(localized: "Переименовать…")) { model.requestRename(ids: ids) }.disabled(!model.canEdit)
            }
            if !ids.isEmpty {
                Button(String(localized: "Переместить…")) { model.beginMove(ids: ids) }.disabled(!model.canEdit)
                Button(String(localized: "Удалить…"), role: .destructive) { model.requestDelete(ids: ids) }.disabled(!model.canEdit)
                Divider()
                Button(String(localized: "Копировать на Mac…")) { model.pickDownloadDestination(ids: ids) }
                    .disabled(model.isBusy || model.isChoosingDestination || !model.connected)
            }
        } primaryAction: { ids in
            guard ids.count == 1, let entry = model.entries.first(where: { ids.contains($0.id) }) else { return }
            if entry.folder { model.open(entry) } else { model.preview(ids: ids) }
        }
        .onKeyPress(keys: [.space], phases: .down) { press in
            guard press.modifiers.isEmpty, model.selectedPhoneIDs.count == 1, model.canExplore else { return .ignored }
            model.preview(); return .handled
        }
        .onKeyPress(keys: [.return], phases: .down) { press in
            guard press.modifiers.isEmpty, let folder = selectedFolder, !model.isBusy else { return .ignored }
            model.open(folder); return .handled
        }
    }

    private var pathBar: some View {
        GlassEffectContainer {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    Image(systemName: "smartphone").foregroundStyle(.secondary)
                    Button(String(localized: "Хранилище")) { model.browse([]) }
                    ForEach(Array(model.folders.enumerated()), id: \.element.id) { index, folder in
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        Button(folder.name) { model.browse(Array(model.folders.prefix(index + 1))) }
                            .fontWeight(index == model.folders.count - 1 ? .medium : .regular)
                    }
                }
                .buttonStyle(.plain).font(.callout)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .disabled(model.isBusy)
            }
            .scrollIndicators(.hidden)
            .fixedSize(horizontal: false, vertical: true)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
        }
        .accessibilityLabel(String(localized: "Путь на телефоне"))
    }

    private var statusBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.isTransferring {
                HStack(spacing: 12) {
                    Image(systemName: model.downloadDestination == nil ? "smartphone" : "laptopcomputer")
                        .foregroundStyle(.secondary)
                    Text(model.currentTransferPath).lineLimit(1).truncationMode(.middle)
                        .help(model.status)
                    Spacer(minLength: 0)
                    Text(model.progress, format: .percent.precision(.fractionLength(0))).monospacedDigit()
                    Button(String(localized: "Отменить"), action: model.cancel).buttonStyle(.glass)
                }
                ProgressView(value: model.progress).progressViewStyle(.linear)
            } else if let result = model.transferResult {
                HStack(alignment: .center, spacing: 12) {
                    Text(result).lineLimit(2).textSelection(.enabled).help(result)
                    Spacer(minLength: 0)
                    if model.resultDestination != nil {
                        Button(String(localized: "Показать в Finder"), action: model.revealDownload)
                    }
                    Button(String(localized: "Подробности")) { showQueue = true }
                    Button { model.transferResult = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless).help(String(localized: "Скрыть результат"))
                        .accessibilityLabel(String(localized: "Скрыть результат"))
                }.buttonStyle(.glass)
            }
            if !model.isTransferring && model.pending > 0 {
                HStack(spacing: 12) {
                    Text(String(localized: "Ожидают отправки: \(model.pending)"))
                    Text(model.connected ? model.destination : String(localized: "Подключите телефон"))
                        .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                    Button(String(localized: "Копировать на телефон"), action: model.startTransfer)
                        .buttonStyle(.glassProminent).disabled(!canCopy)
                    Button(String(localized: "Подробности")) { showQueue = true }.buttonStyle(.glass)
                }
            }
            if !model.isTransferring && model.transferResult == nil {
                HStack(spacing: 8) {
                    if model.isBusy { ProgressView().controlSize(.mini) }
                    Text(model.status).foregroundStyle(.secondary).lineLimit(1).help(model.status)
                    Spacer(minLength: 0)
                    if !model.selectedPhoneIDs.isEmpty {
                        Text(String(localized: "Выбрано: \(model.selectedPhoneIDs.count)")).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .font(.caption).padding(.horizontal, 18).padding(.vertical, 10)
        .background(.bar)
    }

    @ToolbarContentBuilder
    private var windowToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { model.browse(Array(model.folders.dropLast())) } label: {
                Label(String(localized: "На папку выше"), systemImage: "chevron.left")
            }.disabled(!model.connected || model.folders.isEmpty || model.isBusy)
                .keyboardShortcut(.upArrow, modifiers: .command).help(String(localized: "На папку выше (⌘↑)"))
            Button { model.browse(model.folders) } label: { Label(String(localized: "Обновить"), systemImage: "arrow.clockwise") }
                .disabled(!model.connected || model.isBusy).help(String(localized: "Обновить папку (⌘R)"))
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { model.pickDownloadDestination() } label: {
                Label(String(localized: "С Pixel на Mac…"), systemImage: "arrow.down.to.line")
            }.labelStyle(.titleAndIcon).disabled(!model.canDownload).help(String(localized: "Скопировать выделенные файлы и папки на Mac (⇧⌘S)"))
            Button(action: model.pickFiles) {
                Label(String(localized: "С Mac на Pixel…"), systemImage: "arrow.up.to.line")
            }.labelStyle(.titleAndIcon)
                .disabled(!model.connected || !model.writable || model.isBusy || model.isChoosingDestination)
                .help(String(localized: "Выбрать на Mac и скопировать в текущую папку телефона (⌘O)"))
            Menu {
                Toggle(String(localized: "Показывать скрытые файлы"), isOn: $showHidden)
                    .keyboardShortcut(".", modifiers: [.command, .shift])
                Divider()
                Button(String(localized: "Новая папка…"), action: model.requestNewFolder).disabled(!model.canEdit)
                if model.connected { Button(String(localized: "Отключить телефон"), action: model.disconnect).disabled(model.isBusy) }
                else { Button(String(localized: "Подключить телефон"), action: model.connect).disabled(model.isBusy) }
            } label: { Label(String(localized: "Дополнительно"), systemImage: "ellipsis") }
            Button { showQueue.toggle() } label: { Label(String(localized: "Очередь передачи"), systemImage: "sidebar.trailing") }
                .help(showQueue ? String(localized: "Скрыть очередь передачи") : String(localized: "Показать очередь передачи"))
        }
    }

    private var queuePane: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Очередь передачи")).font(.headline)
                    Text(model.pending == 0 ? String(localized: "Mac ↔ Android") : String(localized: "Ожидают отправки: \(model.pending)"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: model.clearCompleted) { Image(systemName: "checkmark.circle") }
                    .buttonStyle(.borderless)
                    .disabled(model.isBusy || !model.uploads.contains(where: { $0.state != .waiting }))
                    .help(String(localized: "Убрать завершённые из очереди")).accessibilityLabel(String(localized: "Очистить завершённые"))
            }.padding(18)
            if model.uploads.isEmpty {
                VStack(spacing: 14) {
                    Spacer(minLength: 12)
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 38, weight: .light)).foregroundStyle(.secondary)
                    Text(String(localized: "Добавьте файлы")).font(.title3.weight(.semibold))
                    Text(String(localized: "Перетащите сюда файл или папку. Вложенные папки сохранятся."))
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(String(localized: "Чтобы скопировать с телефона, выделите объекты в таблице и нажмите «С Pixel на Mac…»."))
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(String(localized: "Выбрать на Mac…"), action: model.pickFiles)
                        .buttonStyle(.glass).disabled(model.isBusy)
                    Spacer(minLength: 12)
                }
                .padding(.horizontal, 24).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.uploads) { item in uploadRow(item) }
                    .listStyle(.inset).scrollContentBackground(.hidden)
            }
            queueFooter
        }
    }

    private func uploadRow(_ item: UploadItem) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: item.folder ? "folder.fill" : "doc")
                .font(.title3).foregroundStyle(item.folder ? Color.accentColor : Color.secondary)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                Text(item.remote?.name ?? item.url.lastPathComponent).fontWeight(.medium).lineLimit(2).truncationMode(.middle)
                Label(item.remote == nil ? String(localized: "На телефон") : String(localized: "На Mac"),
                      systemImage: item.remote == nil ? "smartphone" : "laptopcomputer")
                    .font(.caption).foregroundStyle(.secondary)
                if item.remote != nil { Text(item.url.deletingLastPathComponent().path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(item.url.path) }
                HStack(spacing: 5) {
                    if item.state == .sending { ProgressView().controlSize(.mini) }
                    else { Image(systemName: stateSymbol(item.state)) }
                    Text(item.state.title)
                    if !item.folder || item.state != .waiting { Text("· \(size(item.size))").foregroundStyle(.secondary) }
                }.font(.caption).foregroundStyle(stateColor(item.state))
                if !item.detail.isEmpty {
                    DisclosureGroup(String(localized: "Подробности")) {
                        Text(item.detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }.font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Button { model.remove(item.id) } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless).foregroundStyle(.secondary).disabled(model.isBusy)
                .help(String(localized: "Убрать из очереди")).accessibilityLabel(String(localized: "Убрать \(item.url.lastPathComponent) из очереди"))
        }.padding(.vertical, 8)
    }

    private var queueFooter: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()
            HStack(spacing: 10) {
                Image(systemName: "folder").font(.title3).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Папка назначения")).font(.caption).foregroundStyle(.secondary)
                    Text(model.queueDestination)
                        .font(.callout).lineLimit(1).truncationMode(.middle).help(model.queueDestination)
                }
                Spacer(minLength: 0)
            }
            if model.isTransferring {
                VStack(spacing: 8) {
                    HStack {
                        Text(String(localized: "Копирование")).font(.callout)
                        Spacer()
                        Text(model.progress, format: .percent.precision(.fractionLength(0)))
                            .font(.callout).monospacedDigit().foregroundStyle(.secondary)
                    }
                    ProgressView(value: model.progress).progressViewStyle(.linear)
                    Button(String(localized: "Отменить передачу"), action: model.cancel).buttonStyle(.glass)
                        .frame(maxWidth: .infinity)
                }
            } else if model.pending == 0 {
                Button { model.pickDownloadDestination() } label: {
                    Label(String(localized: "Копировать на Mac…"), systemImage: "arrow.down.to.line")
                        .frame(maxWidth: .infinity)
                }.buttonStyle(.glassProminent).controlSize(.large).disabled(!model.canDownload)
            } else {
                Button(action: model.startTransfer) {
                    Label(String(localized: "Копировать на телефон"), systemImage: "arrow.down.to.line")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent).controlSize(.large).disabled(!canCopy)
                .help(String(localized: "Копировать выбранные файлы и папки (⌘↩)"))
            }
            Text(String(localized: "Папки объединяются. Существующие файлы пропускаются."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(.horizontal, 18).padding(.bottom, 20)
    }

    private func stateSymbol(_ state: UploadState) -> String {
        switch state {
        case .waiting: "clock"
        case .sending: "arrow.triangle.2.circlepath"
        case .done: "checkmark.circle.fill"
        case .skipped: "arrow.right.circle"
        case .failed: "exclamationmark.circle.fill"
        case .cancelled: "stop.circle"
        }
    }
    private func stateColor(_ state: UploadState) -> Color {
        switch state {
        case .done: .green
        case .failed: .red
        case .cancelled: .orange
        default: .secondary
        }
    }
    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !model.isBusy else { return false }
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in model.addFiles([url]) }
            }
        }
        return true
    }
}

// Constrain each column to the available window size so empty states cannot
// push fixed controls outside the toolbar safe area or below the window.
private struct WindowColumn<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        GeometryReader { geometry in
            content
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

struct TransferModelFocusKey: FocusedValueKey { typealias Value = TransferModel }
extension FocusedValues {
    var transferModel: TransferModel? {
        get { self[TransferModelFocusKey.self] }
        set { self[TransferModelFocusKey.self] = newValue }
    }
}
struct TransferCommands: Commands {
    @FocusedValue(\.transferModel) private var model
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(String(localized: "О PixelTransfer"), action: AppAbout.show)
        }
        CommandGroup(replacing: .newItem) {
            Button(String(localized: "С Mac на Pixel…")) { model?.pickFiles() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(model?.connected != true || model?.writable != true || model?.isBusy == true || model?.isChoosingDestination == true)
        }
        CommandMenu(String(localized: "Передача")) {
            Button(model?.connected == true ? String(localized: "Отключить телефон") : String(localized: "Подключить телефон")) {
                if model?.connected == true { model?.disconnect() } else { model?.connect() }
            }.keyboardShortcut("k", modifiers: .command).disabled(model == nil || model?.isBusy == true)
            Button(String(localized: "Копировать на телефон")) { model?.startTransfer() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model?.connected != true || model?.writable != true || model?.isBusy == true || model?.pending == 0)
            Button(String(localized: "С Pixel на Mac…")) { model?.pickDownloadDestination() }
                .keyboardShortcut("s", modifiers: [.command, .shift]).disabled(model?.canDownload != true)
            Button(String(localized: "Отменить передачу")) { model?.cancel() }.disabled(model?.isTransferring != true)
            Divider()
            Button(String(localized: "Быстрый просмотр")) { model?.preview() }
                .disabled(model?.canExplore != true || model?.selectedPhoneIDs.count != 1)
            Button(String(localized: "Свойства")) { model?.showInfo() }
                .keyboardShortcut("i", modifiers: .command).disabled(model?.canExplore != true || model?.selectedPhoneIDs.count != 1)
            Button(String(localized: "Новая папка…")) { model?.requestNewFolder() }
                .keyboardShortcut("n", modifiers: [.command, .shift]).disabled(model?.canEdit != true)
            Button(String(localized: "Переименовать…")) { model?.requestRename() }
                .disabled(model?.canEdit != true || model?.selectedPhoneIDs.count != 1)
            Button(String(localized: "Переместить…")) { model?.beginMove() }
                .disabled(model?.canEdit != true || model?.selectedPhoneIDs.isEmpty != false)
            Button(String(localized: "Удалить…")) { model?.requestDelete() }
                .keyboardShortcut(.delete, modifiers: .command).disabled(model?.canEdit != true || model?.selectedPhoneIDs.isEmpty != false)
            Divider()
            Button(String(localized: "Обновить папку")) { if let model { model.browse(model.folders) } }
                .keyboardShortcut("r", modifiers: .command).disabled(model?.connected != true || model?.isBusy == true)
        }
        SidebarCommands()
        InspectorCommands()
    }
}
#Preview("Светлая тема") { ContentView().frame(width: 1160, height: 720) }
#Preview("Тёмная тема") { ContentView().preferredColorScheme(.dark).frame(width: 1160, height: 720) }

import SwiftUI
import UniformTypeIdentifiers

private struct PhoneLocation: Identifiable {
    let id: String
    let title: String
    let symbol: String
    static let favorites = [
        PhoneLocation(id: "Music", title: String(localized: "Музыка"), symbol: "music.note"),
        PhoneLocation(id: "Download", title: String(localized: "Загрузки"), symbol: "arrow.down.circle"),
        PhoneLocation(id: "DCIM", title: String(localized: "Фото"), symbol: "photo"),
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
    @AppStorage("showTransferQueue") private var showQueue = true
    @AppStorage("showHiddenPhoneFiles") private var showHidden = false
    @State private var dropTarget = false
    @State private var search = ""
    @State private var selectedEntries: Set<UInt32> = []
    @State private var sortOrder = [KeyPathComparator(\PhoneEntry.name)]

    private var folderTitle: String { model.folders.last?.name ?? String(localized: "Хранилище") }
    private var sidebarSelection: String? {
        guard model.connected else { return nil }
        return model.folders.first?.name ?? "storage"
    }
    private var visibleEntries: [PhoneEntry] {
        model.entries.filter {
            (showHidden || !$0.name.hasPrefix(".")) && (search.isEmpty || $0.name.localizedStandardContains(search))
        }.sorted(using: sortOrder)
    }
    private var selectedFolder: PhoneEntry? {
        guard selectedEntries.count == 1 else { return nil }
        return model.entries.first { selectedEntries.contains($0.id) && $0.folder }
    }
    private var objectCount: String { String(localized: "\(visibleEntries.count) объектов") }
    private var canCopy: Bool { model.connected && model.writable && !model.isBusy && model.pending > 0 }
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
                .navigationSubtitle(model.connected ? "\(model.deviceName ?? "Android") · \(objectCount)" : String(localized: "Файлы с Mac на Android"))
                .searchable(text: $search, placement: .toolbar, prompt: String(localized: "Поиск в папке"))
                .toolbar { windowToolbar }
        }
        .navigationSplitViewStyle(.balanced)
        .inspector(isPresented: $showQueue) {
            WindowColumn { queuePane }
                .inspectorColumnWidth(min: 300, ideal: 330, max: 440)
        }
        .focusedSceneValue(\.transferModel, model)
        .frame(minWidth: 920, minHeight: 590)
        .onChange(of: model.destination) { _, _ in search = ""; selectedEntries = [] }
        .onChange(of: model.storageID) { _, _ in search = ""; selectedEntries = [] }
        .onChange(of: model.uploads.count) { old, new in if new > old { showQueue = true } }
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
            List(selection: Binding(get: { sidebarSelection }, set: { value in
                guard let value else { return }
                model.browseShortcut(named: value == "storage" ? nil : value)
            })) {
                Section(String(localized: "Телефон")) {
                    Label(String(localized: "Хранилище"), systemImage: "internaldrive").tag("storage")
                }
                Section(String(localized: "Избранное")) {
                    ForEach(PhoneLocation.favorites) { location in
                        Label(location.title, systemImage: location.symbol).tag(location.id)
                    }
                }
            }
            .listStyle(.sidebar)
            .disabled(!model.connected || model.isBusy)
            if model.connected {
                VStack(alignment: .leading, spacing: 7) {
                    if model.storages.count > 1 {
                        Picker(String(localized: "Хранилище"), selection: Binding(get: { model.storageID }, set: { model.browse([], storage: $0) })) {
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
                    ContentUnavailableView(String(localized: "Папка пуста"), systemImage: "folder", description: Text(String(localized: "Добавьте файлы или папки в очередь справа,\nчтобы скопировать их сюда.")))
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
        Table(visibleEntries, selection: $selectedEntries, sortOrder: $sortOrder) {
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
        } primaryAction: { ids in
            guard ids.count == 1, let entry = model.entries.first(where: { ids.contains($0.id) }) else { return }
            model.open(entry)
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
        HStack(spacing: 8) {
            if model.isBusy { ProgressView().controlSize(.mini) }
            Text(model.status).font(.caption).foregroundStyle(.secondary).lineLimit(1).help(model.status)
            Spacer(minLength: 0)
            if !selectedEntries.isEmpty { Text(String(localized: "Выбрано: \(selectedEntries.count)")).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
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
            Button(action: model.pickFiles) { Label(String(localized: "Добавить"), systemImage: "plus") }
                .disabled(model.isBusy).help(String(localized: "Добавить файлы и папки (⌘O)"))
            Menu {
                Toggle(String(localized: "Показывать скрытые файлы"), isOn: $showHidden)
                    .keyboardShortcut(".", modifiers: [.command, .shift])
                Divider()
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
                    Text(model.pending == 0 ? String(localized: "С Mac на телефон") : String(localized: "Ожидают отправки: \(model.pending)"))
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
                Text(item.url.lastPathComponent).fontWeight(.medium).lineLimit(2).truncationMode(.middle)
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
                    Text(model.connected ? model.destination : String(localized: "Подключите телефон"))
                        .font(.callout).lineLimit(1).truncationMode(.middle).help(model.destination)
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
        showQueue = true
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
        CommandGroup(replacing: .newItem) {
            Button(String(localized: "Добавить файлы и папки…")) { model?.pickFiles() }
                .keyboardShortcut("o", modifiers: .command).disabled(model == nil || model?.isBusy == true)
        }
        CommandMenu(String(localized: "Передача")) {
            Button(model?.connected == true ? String(localized: "Отключить телефон") : String(localized: "Подключить телефон")) {
                if model?.connected == true { model?.disconnect() } else { model?.connect() }
            }.keyboardShortcut("k", modifiers: .command).disabled(model == nil || model?.isBusy == true)
            Button(String(localized: "Копировать на телефон")) { model?.startTransfer() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model?.connected != true || model?.writable != true || model?.isBusy == true || model?.pending == 0)
            Button(String(localized: "Отменить передачу")) { model?.cancel() }.disabled(model?.isTransferring != true)
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

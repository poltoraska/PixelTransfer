import Foundation
import AppKit
import Combine

struct PhoneStorage: Identifiable, Sendable {
    let id: UInt32
    let name: String
    let freeBytes: UInt64
    let writable: Bool
}
struct PhoneFolder: Identifiable, Sendable {
    let id: UInt32
    let name: String
}
enum UploadState: String {
    case waiting, sending, done, skipped, failed, cancelled
    var title: String {
        switch self {
        case .waiting: return String(localized: "Ожидает")
        case .sending: return String(localized: "Копируется")
        case .done: return String(localized: "Готово")
        case .skipped: return String(localized: "Пропущен")
        case .failed: return String(localized: "Ошибка")
        case .cancelled: return String(localized: "Отменён")
        }
    }
}

struct UploadItem: Identifiable {
    let id = UUID()
    let url: URL
    var size: UInt64
    let folder: Bool
    var remote: PhoneEntry? = nil
    var state: UploadState = .waiting
    var detail: String = ""
}

final class TransferControl: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    func reset() { lock.lock(); stopped = false; lock.unlock() }
    func cancel() { lock.lock(); stopped = true; lock.unlock() }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
}

// One queue owns the MTP session: libmtp calls must never overlap.
final class PhoneEngine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "PixelTransfer.MTP", qos: .userInitiated)
    private let session = PTSession()
    let control = TransferControl()
    private func perform<T: Sendable>(_ operation: @escaping @Sendable (PTSession) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do { continuation.resume(returning: try operation(session)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
    func connect() async throws -> (String, [PhoneStorage]) {
        try await perform { session in
            do {
                try session.connect()
                let storages = try session.storages().map {
                    PhoneStorage(id: $0.identifier, name: $0.name, freeBytes: $0.freeBytes, writable: $0.writable)
                }
                return (session.deviceName, storages)
            } catch { session.disconnect(); throw error }
        }
    }
    func disconnect() async {
        _ = try? await perform { session in session.disconnect() }
    }
    func contents(storage: UInt32, parent: UInt32) async throws -> [PhoneEntry] {
        try await perform { session in
            try session.contents(ofStorage: storage, parent: parent).map {
                PhoneEntry(id: $0.identifier, name: $0.name, size: $0.size, folder: $0.folder, modifiedAt: $0.modifiedSeconds > 0 ? Date(timeIntervalSince1970: Double($0.modifiedSeconds)) : nil)
            }.sorted {
                if $0.folder != $1.folder { return $0.folder }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }
    }
    private static func native(_ entry: PhoneEntry) -> PTEntry {
        let value = PTEntry(); value.identifier = entry.id; value.name = entry.name
        value.size = entry.size; value.folder = entry.folder; return value
    }
    func metadata(_ entry: PhoneEntry, storage: UInt32, parent: UInt32) async throws -> PhoneEntry {
        try await perform { session in
            let value = try session.metadata(for: Self.native(entry), storage: storage, parent: parent)
            return PhoneEntry(id: value.identifier, name: value.name, size: value.size, folder: value.folder,
                              modifiedAt: value.modifiedSeconds > 0 ? Date(timeIntervalSince1970: Double(value.modifiedSeconds)) : nil)
        }
    }
    func createFolder(_ name: String, storage: UInt32, parent: UInt32) async throws {
        try await perform { session in
            try LocalDownloadDirectory.validate(name)
            guard !(try session.contents(ofStorage: storage, parent: parent)).contains(where: { $0.name == name }) else {
                throw NSError(domain: "PixelTransfer.Explorer", code: 1, userInfo: [NSLocalizedDescriptionKey: String(localized: "Объект с таким именем уже существует.")])
            }
            _ = try session.ensureFolder(name, storage: storage, parent: parent)
        }
    }
    func rename(_ entry: PhoneEntry, name: String, storage: UInt32, parent: UInt32) async throws {
        try await perform { session in
            try LocalDownloadDirectory.validate(name)
            try session.renameEntry(Self.native(entry), storage: storage, parent: parent, name: name)
        }
    }
    func move(_ entries: [PhoneEntry], storage: UInt32, parent: UInt32, target: UInt32) async throws {
        try await perform { session in
            // Validate the full selection and all name conflicts before moving the first object.
            let existing = try session.contents(ofStorage: storage, parent: target)
            for entry in entries {
                _ = try session.metadata(for: Self.native(entry), storage: storage, parent: parent)
                if target != parent && existing.contains(where: { $0.name == entry.name }) {
                    throw NSError(domain: "PixelTransfer.Explorer", code: 2, userInfo: [NSLocalizedDescriptionKey: String(localized: "В папке назначения уже есть объект с таким именем. Замена не выполнялась.")])
                }
            }
            for entry in entries { try session.move(Self.native(entry), storage: storage, parent: parent, destination: target) }
        }
    }
    func delete(_ entries: [PhoneEntry], storage: UInt32, parent: UInt32) async throws {
        try await perform { session in
            var work: [(PhoneEntry, UInt32)] = []
            // Prepare all trees before deleting anything, then delete children before their folders.
            for entry in entries {
                let plan = try DownloadPlan.make(root: entry, cancelled: { false }) { id in
                    try session.contents(ofStorage: storage, parent: id).map { PhoneEntry(id: $0.identifier, name: $0.name, size: $0.size, folder: $0.folder) }
                }
                var parents: [[String]: UInt32] = [[]: parent]
                for node in plan.nodes {
                    work.append((node.entry, parents[Array(node.components.dropLast())]!))
                    if node.entry.folder { parents[node.components] = node.entry.id }
                }
            }
            for (entry, folder) in work { _ = try session.metadata(for: Self.native(entry), storage: storage, parent: folder) }
            for (entry, folder) in work.reversed() { try session.delete(Self.native(entry), storage: storage, parent: folder) }
        }
    }
    func downloadTree(entry: PhoneEntry, storage: UInt32, destination: URL,
                      progress: @escaping @Sendable (UploadUpdate) -> Void) async throws -> UploadSummary {
        let control = control
        return try await perform { session in
            let plan = try DownloadPlan.make(root: entry, cancelled: { control.cancelled }) { parent in
                try session.contents(ofStorage: storage, parent: parent).map {
                    PhoneEntry(id: $0.identifier, name: $0.name, size: $0.size, folder: $0.folder, modifiedAt: $0.modifiedSeconds > 0 ? Date(timeIntervalSince1970: Double($0.modifiedSeconds)) : nil)
                }
            }
            let root = try LocalDownloadDirectory(url: destination)
            var summary = UploadSummary(totalBytes: plan.totalBytes)
            var processed = 0.0
            var lastUpdate = Date.distantPast
            func report(_ fraction: Double, _ path: String) {
                progress(UploadUpdate(fraction: min(1, fraction), path: path, totalBytes: plan.totalBytes, summary: summary))
            }
            report(0, entry.name)
            for node in plan.nodes {
                if control.cancelled { throw CocoaError(.userCancelled) }
                do {
                    let parent = try root.parent(for: Array(node.components.dropLast()))
                    if node.entry.folder {
                        _ = try parent.folder(node.entry.name)
                        summary.folders += 1
                    } else {
                        do {
                            try session.downloadFile(node.entry.id, storage: storage, size: node.entry.size,
                                                     directoryFD: parent.descriptor, name: node.entry.name) { received, total in
                                if control.cancelled { return false }
                                if Date().timeIntervalSince(lastUpdate) >= 0.1 || received == total {
                                    lastUpdate = Date()
                                    let fraction = total == 0 ? 0 : min(1, Double(received) / Double(total))
                                    report((processed + node.weight * fraction) / plan.totalWeight, node.relativePath)
                                }
                                return true
                            }
                            summary.copiedFiles += 1
                        } catch {
                            let failure = error as NSError
                            if failure.domain == "PixelTransfer.MTP", failure.code == 8, !control.cancelled {
                                summary.skippedFiles += 1
                            } else { throw error }
                        }
                    }
                } catch {
                    throw NSError(domain: (error as NSError).domain, code: (error as NSError).code,
                                  userInfo: [NSLocalizedDescriptionKey: "\(node.relativePath): \(error.localizedDescription)\n\(summary.detail)"])
                }
                processed += node.weight
                report(processed / plan.totalWeight, node.relativePath)
            }
            return summary
        }
    }

    func uploadTree(url: URL, storage: UInt32, parent: UInt32,
                    progress: @escaping @Sendable (UploadUpdate) -> Void) async throws -> UploadSummary {
        let control = control
        return try await perform { session in
            // The selected root grants access to its descendants for the entire traversal and transfer.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let plan = try UploadPlan.make(root: url, cancelled: { control.cancelled })
            var summary = UploadSummary(totalBytes: plan.totalBytes, excludedItems: plan.excludedItems)
            var folderIDs: [[String]: UInt32] = [ []: parent ]
            var processedWeight = 0.0
            var lastUpdate = Date.distantPast
            func report(_ fraction: Double, _ path: String) {
                progress(UploadUpdate(fraction: min(1, fraction), path: path, totalBytes: plan.totalBytes, summary: summary))
            }
            report(0, url.lastPathComponent)
            for node in plan.nodes {
                if control.cancelled { throw CocoaError(.userCancelled) }
                guard let destination = folderIDs[Array(node.components.dropLast())] else {
                    throw NSError(domain: "PixelTransfer.Plan", code: 3, userInfo: [NSLocalizedDescriptionKey: String(localized: "Не найдена папка назначения для \(node.relativePath).")])
                }
                do {
                    if node.folder {
                        let identifier = try session.ensureFolder(node.url.lastPathComponent, storage: storage, parent: destination)
                        folderIDs[node.components] = identifier.uint32Value
                        summary.folders += 1
                    } else {
                        do {
                            try session.uploadFile(node.url, storage: storage, parent: destination) { sent, total in
                                if control.cancelled { return false }
                                if Date().timeIntervalSince(lastUpdate) >= 0.1 || sent == total {
                                    lastUpdate = Date()
                                    let fraction = total == 0 ? 0 : min(1, Double(sent) / Double(total))
                                    report((processedWeight + node.weight * fraction) / plan.totalWeight, node.relativePath)
                                }
                                return true
                            }
                            summary.copiedFiles += 1
                        } catch {
                            let error = error as NSError
                            if error.domain == "PixelTransfer.MTP", error.code == 8, !control.cancelled {
                                summary.skippedFiles += 1
                            } else { throw error }
                        }
                    }
                } catch {
                    report(processedWeight / plan.totalWeight, node.relativePath)
                    let error = error as NSError
                    throw NSError(domain: error.domain, code: error.code, userInfo: [NSLocalizedDescriptionKey:
                        "\(node.relativePath): \(error.localizedDescription)\n\(summary.detail)"])
                }
                processedWeight += node.weight
                report(processedWeight / plan.totalWeight, node.relativePath)
            }
            return summary
        }
    }

}

@MainActor
final class TransferModel: ObservableObject {
    @Published var deviceName: String?
    @Published var storages: [PhoneStorage] = []
    @Published var storageID: UInt32 = 0
    @Published private(set) var rootFolderNames: Set<String> = []
    @Published var folders: [PhoneFolder] = []
    @Published var entries: [PhoneEntry] = [] { didSet { selectedPhoneIDs = [] } }
    @Published var uploads: [UploadItem] = []
    @Published var selectedPhoneIDs: Set<UInt32> = []
    @Published var downloadDestination: URL?
    @Published var isChoosingDestination = false
    @Published var isBusy = false
    @Published var isTransferring = false
    @Published var progress: Double = 0
    @Published var currentTransferPath = ""
    @Published var transferResult: String?
    @Published private(set) var resultDestination: URL?
    @Published var status = String(localized: "Подключите Pixel по USB и выберите на телефоне «Передача файлов».")
    @Published var previewURL: URL?
    @Published var fileInfo: ExplorerInfo?
    @Published var movePresented = false
    @Published var movePath: [PhoneFolder] = []
    @Published var moveEntries: [PhoneEntry] = []
    private var previewDirectory: URL?
    private var moveSelection: [PhoneEntry] = []
    @Published var errorMessage: String?
    private let engine = PhoneEngine()
    private var lastDownloadIDs: Set<UUID> = []
    private var connectionID = UUID()
    private var batchID = UUID()
    static let root = UInt32.max
    var parentID: UInt32 { folders.last?.id ?? Self.root }
    var writable: Bool { storages.first { $0.id == storageID }?.writable ?? false }
    var pending: Int { uploads.filter { $0.remote == nil && $0.state == .waiting }.count }
    var destination: String { "/" + folders.map(\.name).joined(separator: "/") }
    var queueDestination: String {
        if let downloadDestination, isTransferring || pending == 0 { return downloadDestination.path }
        return connected ? destination : String(localized: "Подключите телефон")
    }
    var canDownload: Bool { connected && !isBusy && !isChoosingDestination && entries.contains { selectedPhoneIDs.contains($0.id) } }
    var connected: Bool { deviceName != nil }

    func connect() {
        guard !isBusy, !isChoosingDestination else { return }
        isBusy = true; status = String(localized: "Подключение к телефону…")
        Task {
            defer { isBusy = false }
            do {
                let (name, available) = try await engine.connect()
                guard let storage = available.first(where: \.writable) ?? available.first else {
                    throw NSError(domain: "PixelTransfer", code: 1, userInfo: [NSLocalizedDescriptionKey: String(localized: "Хранилище телефона недоступно.")])
                }
                deviceName = name; storages = available; storageID = storage.id; folders = []
                entries = try await engine.contents(storage: storageID, parent: Self.root)
                updateRootFolders(entries)
                status = String(localized: "Телефон подключён. Откройте папку назначения.")
            } catch { await lostConnection(error) }
        }
    }
    func disconnect() {
        guard !isBusy, !isChoosingDestination else { return }
        isBusy = true
        Task {
            await engine.disconnect()
            clearPhone(); isBusy = false; status = String(localized: "Телефон отключён от приложения.")
        }
    }
    func browse(_ newFolders: [PhoneFolder], storage: UInt32? = nil) {
        guard connected, !isBusy, !isChoosingDestination else { return }
        let newStorage = storage ?? storageID
        let newParent = newFolders.last?.id ?? Self.root
        isBusy = true; status = String(localized: "Чтение папки…")
        Task {
            defer { isBusy = false }
            do {
                // Refresh quick access for the selected storage, also inside nested folders.
                let rootEntries = try await engine.contents(storage: newStorage, parent: Self.root)
                let children = newParent == Self.root ? rootEntries
                    : try await engine.contents(storage: newStorage, parent: newParent)
                storageID = newStorage; folders = newFolders; entries = children
                updateRootFolders(rootEntries)
                status = children.isEmpty ? String(localized: "Папка пуста.") : String(localized: "Объектов в папке: \(children.count).")
            } catch { await lostConnection(error) }
        }
    }
    func open(_ entry: PhoneEntry) {
        guard entry.folder else { return }
        browse(folders + [PhoneFolder(id: entry.id, name: entry.name)])
    }
    func browseShortcut(named name: String?) {
        guard connected, !isBusy, !isChoosingDestination else { return }
        guard let name else { browse([]); return }
        isBusy = true; status = String(localized: "Открытие папки…")
        Task {
            defer { isBusy = false }
            do {
                let rootEntries = try await engine.contents(storage: storageID, parent: Self.root)
                updateRootFolders(rootEntries)
                guard let folder = rootEntries.first(where: { $0.folder && $0.name == name }) else {
                    errorMessage = String(localized: "На телефоне нет папки «\(name)». Выберите другую папку в хранилище.")
                    status = String(localized: "Папка не найдена.")
                    return
                }
                let children = try await engine.contents(storage: storageID, parent: folder.id)
                folders = [PhoneFolder(id: folder.id, name: folder.name)]; entries = children
                status = children.isEmpty ? String(localized: "Папка пуста.") : String(localized: "Объектов в папке: \(children.count).")
            } catch { await lostConnection(error) }
        }
    }
    func pickFiles() {
        guard connected, writable, !isBusy, !isChoosingDestination else { return }
        let storage = storageID, parent = parentID, connection = connectionID
        let panel = NSOpenPanel()
        panel.title = String(localized: "Выберите файлы и папки для копирования на телефон")
        panel.prompt = String(localized: "Копировать на телефон")
        panel.canChooseFiles = true; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        isChoosingDestination = true
        panel.begin { [weak self] response in
            Task { @MainActor in
                guard let self else { return }
                self.isChoosingDestination = false
                guard response == .OK, self.connected, !self.isBusy,
                      self.storageID == storage, self.parentID == parent, self.connectionID == connection else { return }
                self.addFiles(panel.urls)
                let selectedURLs = Set(panel.urls)
                let ids = Set(self.uploads.filter { $0.remote == nil && selectedURLs.contains($0.url) && $0.state == .waiting }.map(\.id))
                self.startUpload(ids: ids)
            }
        }
    }
    func addFiles(_ urls: [URL]) {
        guard !isBusy, !isChoosingDestination else { return }
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard url.isFileURL, !uploads.contains(where: { $0.url == url && $0.state == .waiting }) else { continue }
            do {
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                guard values.isSymbolicLink != true, values.isRegularFile == true || values.isDirectory == true else {
                    errorMessage = String(localized: "Выберите обычный файл или папку. Символические ссылки не копируются.")
                    continue
                }
                uploads.append(UploadItem(url: url, size: values.isDirectory == true ? 0 : UInt64(max(0, values.fileSize ?? 0)), folder: values.isDirectory == true))
            } catch { errorMessage = String(localized: "Не удалось прочитать файл \(url.lastPathComponent): \(error.localizedDescription)") }
        }
    }
    func remove(_ id: UUID) {
        guard !isBusy, !isChoosingDestination else { return }
        uploads.removeAll { $0.id == id }
    }
    func clearCompleted() {
        guard !isBusy, !isChoosingDestination else { return }
        uploads.removeAll { $0.state != .waiting }
    }
    func startTransfer() { startUpload(ids: nil) }

    private func startUpload(ids: Set<UUID>?) {
        guard connected, writable, !isBusy, !isChoosingDestination, pending > 0 else { return }
        let batch = uploads.filter { $0.remote == nil && $0.state == .waiting && (ids?.contains($0.id) ?? true) }
        guard !batch.isEmpty else { return }
        downloadDestination = nil
        lastDownloadIDs = []
        resultDestination = nil; transferResult = nil; currentTransferPath = ""
        let storage = storageID, parent = parentID, folderPath = destination
        let token = UUID(); batchID = token
        engine.control.reset()
        isBusy = true; isTransferring = true; progress = 0
        Task {
            defer {
                transferResult = status
                currentTransferPath = ""
                isBusy = false; isTransferring = false; batchID = UUID()
            }
            var completed = 0, skipped = 0, excluded = 0
            for (position, item) in batch.enumerated() {
                if engine.control.cancelled {
                    markRemaining(batch, state: .cancelled, detail: String(localized: "Передача отменена."))
                    break
                }
                update(item.id, state: .sending)
                currentTransferPath = item.url.lastPathComponent
                status = String(localized: "Подготовка: \(item.url.lastPathComponent)…")
                do {
                    let summary = try await engine.uploadTree(url: item.url, storage: storage, parent: parent) { update in
                        Task { @MainActor in
                            guard self.batchID == token, self.isTransferring,
                                  self.uploads.first(where: { $0.id == item.id })?.state == .sending else { return }
                            self.currentTransferPath = update.path
                            self.progress = max(self.progress, (Double(position) + update.fraction) / Double(batch.count))
                            self.status = String(localized: "\(position + 1) из \(batch.count): \(update.path) → \(folderPath)")
                            if let index = self.uploads.firstIndex(where: { $0.id == item.id }) {
                                self.uploads[index].size = update.totalBytes
                                self.uploads[index].detail = update.summary.detail
                            }
                        }
                    }
                    if let index = uploads.firstIndex(where: { $0.id == item.id }) { uploads[index].size = summary.totalBytes }
                    let state: UploadState = !item.folder && summary.skippedFiles > 0 ? .skipped : .done
                    update(item.id, state: state, detail: summary.detail)
                    completed += summary.copiedFiles; skipped += summary.skippedFiles; excluded += summary.excludedItems
                } catch {
                    if engine.control.cancelled {
                        update(item.id, state: .cancelled, detail: String(localized: "Передача отменена. Уже скопированные файлы и папки сохранены. При отключённом кабеле проверьте, не остался ли неполный файл."))
                        markRemaining(batch, state: .cancelled, detail: String(localized: "Передача отменена."))
                        await engine.disconnect(); clearPhone()
                        break
                    } else {
                        update(item.id, state: .failed, detail: error.localizedDescription)
                        // Unsent roots stay queued. Re-adding a partial folder merges and skips existing files.
                        await lostConnection(error)
                        status = String(localized: "Передача остановлена. Уже скопированные файлы и папки сохранены.")
                        return
                    }
                }
                progress = Double(position + 1) / Double(batch.count)
            }
            if engine.control.cancelled {
                status = String(localized: "Передача отменена. Уже скопированные файлы и папки сохранены.")
            } else {
                status = String(localized: "Скопировано файлов: \(completed). Пропущено: \(skipped).")
                if excluded > 0 { status += String(localized: " Исключено ссылок и служебных объектов: \(excluded).") }
                if connected {
                    do {
                        entries = try await engine.contents(storage: storage, parent: parent)
                        if parent == Self.root { updateRootFolders(entries) }
                    }
                    catch { await lostConnection(error) }
                }
            }
        }
    }

    func pickDownloadDestination(ids: Set<UInt32>? = nil) {
        guard connected, !isBusy, !isChoosingDestination else { return }
        let selection = ids ?? selectedPhoneIDs
        let selected = entries.filter { selection.contains($0.id) }
        guard !selected.isEmpty else { return }
        let storage = storageID, connection = connectionID
        let panel = NSOpenPanel()
        panel.title = String(localized: "Выберите папку для копирования с телефона")
        panel.prompt = String(localized: "Копировать сюда")
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.canCreateDirectories = true; panel.allowsMultipleSelection = false
        if let path = UserDefaults.standard.string(forKey: "lastMacDestination") {
            panel.directoryURL = URL(fileURLWithPath: path, isDirectory: true)
        }
        isChoosingDestination = true
        panel.begin { [weak self] response in
            Task { @MainActor in
                guard let self else { return }
                self.isChoosingDestination = false
                guard response == .OK, let destination = panel.url,
                      self.connected, !self.isBusy, self.storageID == storage, self.connectionID == connection else { return }
                UserDefaults.standard.set(destination.path, forKey: "lastMacDestination")
                self.startDownload(selected, storage: storage, destination: destination)
            }
        }
    }

    private func startDownload(_ selected: [PhoneEntry], storage: UInt32, destination: URL) {
        let batch = selected.map {
            UploadItem(url: destination.appendingPathComponent($0.name), size: $0.size, folder: $0.folder, remote: $0)
        }
        uploads.append(contentsOf: batch)
        lastDownloadIDs = Set(batch.map(\.id))
        downloadDestination = destination
        resultDestination = destination; transferResult = nil; currentTransferPath = ""
        let token = UUID(); batchID = token
        engine.control.reset()
        isBusy = true; isTransferring = true; progress = 0
        // Keep sandbox access for the entire asynchronous batch.
        let scoped = destination.startAccessingSecurityScopedResource()
        Task {
            defer {
                if scoped { destination.stopAccessingSecurityScopedResource() }
                transferResult = status
                currentTransferPath = ""
                isBusy = false; isTransferring = false; batchID = UUID()
            }
            var copied = 0, skipped = 0
            for (position, item) in batch.enumerated() {
                if engine.control.cancelled {
                    markRemaining(batch, state: .cancelled, detail: String(localized: "Передача отменена."))
                    break
                }
                guard let entry = item.remote else { continue }
                update(item.id, state: .sending)
                currentTransferPath = entry.name
                status = String(localized: "Подготовка: \(entry.name)…")
                do {
                    let summary = try await engine.downloadTree(entry: entry, storage: storage, destination: destination) { update in
                        Task { @MainActor in
                            guard self.batchID == token, self.isTransferring,
                                  let index = self.uploads.firstIndex(where: { $0.id == item.id }),
                                  self.uploads[index].state == .sending else { return }
                            self.currentTransferPath = update.path
                            self.progress = max(self.progress, (Double(position) + update.fraction) / Double(batch.count))
                            self.status = String(localized: "\(position + 1) из \(batch.count): \(update.path) → \(destination.path)")
                            self.uploads[index].size = update.totalBytes
                            self.uploads[index].detail = update.summary.detail
                        }
                    }
                    if let index = uploads.firstIndex(where: { $0.id == item.id }) { uploads[index].size = summary.totalBytes }
                    update(item.id, state: !item.folder && summary.skippedFiles > 0 ? .skipped : .done, detail: summary.detail)
                    copied += summary.copiedFiles; skipped += summary.skippedFiles
                } catch {
                    let cancelled = engine.control.cancelled
                    update(item.id, state: cancelled ? .cancelled : .failed, detail: error.localizedDescription)
                    markRemaining(batch, state: .cancelled, detail: String(localized: "Передача остановлена. Уже скопированные файлы и папки сохранены."))
                    // Local destination errors should not disconnect an otherwise healthy phone.
                    if (error as NSError).domain == "PixelTransfer.MTP" || cancelled {
                        await engine.disconnect(); clearPhone()
                    }
                    status = cancelled ? String(localized: "Передача отменена. Уже скопированные файлы и папки сохранены.")
                        : String(localized: "Передача остановлена. Уже скопированные файлы и папки сохранены.")
                    if !cancelled { errorMessage = error.localizedDescription }
                    return
                }
                progress = Double(position + 1) / Double(batch.count)
            }
            status = engine.control.cancelled ? String(localized: "Передача отменена. Уже скопированные файлы и папки сохранены.")
                : String(localized: "Скопировано файлов: \(copied). Пропущено: \(skipped).")
        }
    }

    func revealDownload() {
        guard let resultDestination else { return }
        let files = uploads.filter { lastDownloadIDs.contains($0.id) && ($0.state == .done || $0.state == .skipped) }.map(\.url)
        if files.isEmpty { NSWorkspace.shared.open(resultDestination) }
        else { NSWorkspace.shared.activateFileViewerSelecting(files) }
    }

    func cancel() {
        engine.control.cancel()
        status = String(localized: "Отмена передачи…")
    }
    private func update(_ id: UUID, state: UploadState, detail: String = "") {
        guard let index = uploads.firstIndex(where: { $0.id == id }) else { return }
        uploads[index].state = state; uploads[index].detail = detail
    }
    private func markRemaining(_ batch: [UploadItem], state: UploadState, detail: String) {
        for item in batch where uploads.first(where: { $0.id == item.id })?.state == .waiting {
            update(item.id, state: state, detail: detail)
        }
    }
    private func updateRootFolders(_ entries: [PhoneEntry]) {
        rootFolderNames = Set(entries.filter(\.folder).map(\.name))
    }
    private func clearPhone() {
        rootFolderNames = []
        connectionID = UUID()
        deviceName = nil; storages = []; storageID = 0; folders = []; entries = []
    }
    private func lostConnection(_ error: Error) async {
        await engine.disconnect()
        clearPhone(); errorMessage = error.localizedDescription
        status = String(localized: "Не удалось выполнить операцию. Проверьте подключение и подключите телефон заново.")
    }
}


struct ExplorerInfo: Identifiable {
    let id = UUID()
    let entry: PhoneEntry
    let path: String
    let storage: String
    let writable: Bool
}

extension TransferModel {
    var explorerSelection: [PhoneEntry] { entries.filter { selectedPhoneIDs.contains($0.id) } }
    var canExplore: Bool { connected && !isBusy && !isChoosingDestination }
    var canEdit: Bool { canExplore && writable }

    private func explorerAlert(_ alert: NSAlert, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        isChoosingDestination = true
        let callback: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            Task { @MainActor in
                self?.isChoosingDestination = false
                completion(response)
            }
        }
        if let window = NSApp.keyWindow { alert.beginSheetModal(for: window, completionHandler: callback) }
        else { callback(alert.runModal()) }
    }
    func requestNewFolder() {
        guard canEdit else { return }
        let alert = NSAlert(); alert.messageText = String(localized: "Новая папка")
        let field = NSTextField(string: String(localized: "Новая папка")); field.frame.size = NSSize(width: 320, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Создать")); alert.addButton(withTitle: String(localized: "Отменить"))
        explorerAlert(alert) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            let name = field.stringValue
            self.runExplorer { engine, storage, parent in try await engine.createFolder(name, storage: storage, parent: parent) }
        }
    }
    func requestRename(ids: Set<UInt32>? = nil) {
        guard canEdit else { return }
        let selected = entries.filter { (ids ?? selectedPhoneIDs).contains($0.id) }
        guard selected.count == 1, let entry = selected.first else { return }
        let alert = NSAlert(); alert.messageText = String(localized: "Переименовать")
        let field = NSTextField(string: entry.name); field.frame.size = NSSize(width: 320, height: 24); alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Сохранить")); alert.addButton(withTitle: String(localized: "Отменить"))
        explorerAlert(alert) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            let name = field.stringValue
            self.runExplorer { engine, storage, parent in try await engine.rename(entry, name: name, storage: storage, parent: parent) }
        }
    }
    func requestDelete(ids: Set<UInt32>? = nil) {
        guard canEdit else { return }
        let selected = entries.filter { (ids ?? selectedPhoneIDs).contains($0.id) }
        guard !selected.isEmpty else { return }
        let alert = NSAlert(); alert.alertStyle = .warning
        alert.messageText = String(localized: "Удалить с Pixel без возможности восстановления?")
        alert.informativeText = selected.map(\.name).joined(separator: "\n") + "\n\n" + String(localized: "Папки удаляются со всем содержимым. Корзины и отмены удаления нет.")
        alert.addButton(withTitle: String(localized: "Отменить")); alert.addButton(withTitle: String(localized: "Удалить"))
        explorerAlert(alert) { [weak self] response in
            guard response == .alertSecondButtonReturn, let self else { return }
            self.runExplorer { engine, storage, parent in try await engine.delete(selected, storage: storage, parent: parent) }
        }
    }
    private func runExplorer(_ operation: @escaping (PhoneEngine, UInt32, UInt32) async throws -> Void) {
        guard canEdit else { return }
        let storage = storageID, parent = parentID
        isBusy = true; status = String(localized: "Выполнение операции на Pixel…")
        Task {
            defer { isBusy = false }
            var failure: Error?
            do { try await operation(engine, storage, parent) }
            catch { failure = error }
            do {
                let rootEntries = try await engine.contents(storage: storage, parent: Self.root)
                entries = parent == Self.root ? rootEntries : try await engine.contents(storage: storage, parent: parent)
                updateRootFolders(rootEntries)
            } catch {
                await lostConnection(error)
                if failure == nil { failure = error }
            }
            if let failure {
                errorMessage = failure.localizedDescription
                status = String(localized: "Операция остановлена. Уже выполненные изменения сохранены.")
            } else { status = String(localized: "Операция завершена.") }
        }
    }
    func showInfo(ids: Set<UInt32>? = nil) {
        guard canExplore else { return }
        let selected = entries.filter { (ids ?? selectedPhoneIDs).contains($0.id) }
        guard selected.count == 1, let entry = selected.first else { return }
        let storage = storageID, parent = parentID, path = destination
        let name = storages.first { $0.id == storage }?.name ?? "Pixel"
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let current = try await engine.metadata(entry, storage: storage, parent: parent)
                fileInfo = ExplorerInfo(entry: current, path: path == "/" ? "/" + entry.name : path + "/" + entry.name,
                                        storage: name, writable: writable)
            } catch { errorMessage = error.localizedDescription }
        }
    }
    func preview(ids: Set<UInt32>? = nil) {
        if previewURL != nil { previewURL = nil; return }
        guard canExplore else { return }
        let selected = entries.filter { (ids ?? selectedPhoneIDs).contains($0.id) }
        guard selected.count == 1, let entry = selected.first else { return }
        if entry.folder { showInfo(ids: [entry.id]); return }
        let storage = storageID
        engine.control.reset(); isBusy = true; isTransferring = true; progress = 0
        transferResult = nil; resultDestination = nil; currentTransferPath = entry.name
        status = String(localized: "Загрузка предпросмотра с Pixel…")
        let token = UUID(); batchID = token
        Task {
            defer { isBusy = false; isTransferring = false; currentTransferPath = ""; batchID = UUID() }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PixelPreview-" + UUID().uuidString, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                _ = try await engine.downloadTree(entry: entry, storage: storage, destination: directory) { update in
                    Task { @MainActor in
                        guard self.batchID == token, self.isTransferring else { return }
                        self.progress = update.fraction
                    }
                }
                if engine.control.cancelled { throw CocoaError(.userCancelled) }
                previewDirectory = directory
                previewURL = directory.appendingPathComponent(entry.name)
                status = String(localized: "Предпросмотр готов. Временная копия не изменяет файл на Pixel.")
            } catch {
                try? FileManager.default.removeItem(at: directory)
                if !engine.control.cancelled { errorMessage = error.localizedDescription }
                status = String(localized: "Предпросмотр остановлен.")
                await engine.disconnect(); clearPhone()
            }
        }
    }
    func closePreview() {
        if let previewDirectory { try? FileManager.default.removeItem(at: previewDirectory) }
        previewDirectory = nil
    }
    func beginMove(ids: Set<UInt32>? = nil) {
        guard canEdit else { return }
        moveSelection = entries.filter { (ids ?? selectedPhoneIDs).contains($0.id) }
        guard !moveSelection.isEmpty else { return }
        movePath = []; moveEntries = []; movePresented = true; isChoosingDestination = true
        browseMove([])
    }
    func browseMove(_ path: [PhoneFolder]) {
        guard movePresented, !isBusy else { return }
        let storage = storageID, parent = path.last?.id ?? Self.root
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let children = try await engine.contents(storage: storage, parent: parent)
                guard movePresented else { return }
                movePath = path
                moveEntries = children.filter { child in child.folder && !moveSelection.contains(where: { $0.id == child.id }) }
            } catch { errorMessage = error.localizedDescription }
        }
    }
    func finishMove() {
        guard movePresented, !isBusy else { return }
        let selected = moveSelection, target = movePath.last?.id ?? Self.root
        movePresented = false; isChoosingDestination = false
        runExplorer { engine, storage, parent in try await engine.move(selected, storage: storage, parent: parent, target: target) }
    }
    func closeMove() { movePresented = false; isChoosingDestination = false; moveSelection = [] }
}

import Foundation
import AppKit
import Combine

struct PhoneStorage: Identifiable, Sendable {
    let id: UInt32
    let name: String
    let freeBytes: UInt64
    let writable: Bool
}
struct PhoneEntry: Identifiable, Sendable {
    let id: UInt32
    let name: String
    let size: UInt64
    let folder: Bool
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
                PhoneEntry(id: $0.identifier, name: $0.name, size: $0.size, folder: $0.folder)
            }.sorted {
                if $0.folder != $1.folder { return $0.folder }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
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
    @Published var folders: [PhoneFolder] = []
    @Published var entries: [PhoneEntry] = []
    @Published var uploads: [UploadItem] = []
    @Published var isBusy = false
    @Published var isTransferring = false
    @Published var progress: Double = 0
    @Published var status = String(localized: "Подключите Pixel по USB и выберите на телефоне «Передача файлов».")
    @Published var errorMessage: String?
    private let engine = PhoneEngine()
    private var batchID = UUID()
    static let root = UInt32.max
    var parentID: UInt32 { folders.last?.id ?? Self.root }
    var writable: Bool { storages.first { $0.id == storageID }?.writable ?? false }
    var pending: Int { uploads.filter { $0.state == .waiting }.count }
    var destination: String { "/" + folders.map(\.name).joined(separator: "/") }
    var connected: Bool { deviceName != nil }

    func connect() {
        guard !isBusy else { return }
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
                status = String(localized: "Телефон подключён. Откройте папку назначения.")
            } catch { await lostConnection(error) }
        }
    }
    func disconnect() {
        guard !isBusy else { return }
        isBusy = true
        Task {
            await engine.disconnect()
            clearPhone(); isBusy = false; status = String(localized: "Телефон отключён от приложения.")
        }
    }
    func browse(_ newFolders: [PhoneFolder], storage: UInt32? = nil) {
        guard connected, !isBusy else { return }
        let newStorage = storage ?? storageID
        let newParent = newFolders.last?.id ?? Self.root
        isBusy = true; status = String(localized: "Чтение папки…")
        Task {
            defer { isBusy = false }
            do {
                let children = try await engine.contents(storage: newStorage, parent: newParent)
                storageID = newStorage; folders = newFolders; entries = children
                status = children.isEmpty ? String(localized: "Папка пуста.") : String(localized: "Объектов в папке: \(children.count).")
            } catch { await lostConnection(error) }
        }
    }
    func open(_ entry: PhoneEntry) {
        guard entry.folder else { return }
        browse(folders + [PhoneFolder(id: entry.id, name: entry.name)])
    }
    func browseShortcut(named name: String?) {
        guard connected, !isBusy else { return }
        guard let name else { browse([]); return }
        isBusy = true; status = String(localized: "Открытие папки…")
        Task {
            defer { isBusy = false }
            do {
                let rootEntries = try await engine.contents(storage: storageID, parent: Self.root)
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
        guard !isBusy else { return }
        let panel = NSOpenPanel()
        panel.title = String(localized: "Выберите файлы и папки для копирования на телефон")
        panel.prompt = String(localized: "Добавить")
        panel.canChooseFiles = true; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.begin { [weak self] response in
            Task { @MainActor in
                guard response == .OK, let self else { return }
                self.addFiles(panel.urls)
            }
        }
    }
    func addFiles(_ urls: [URL]) {
        guard !isBusy else { return }
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
        guard !isBusy else { return }
        uploads.removeAll { $0.id == id }
    }
    func clearCompleted() {
        guard !isBusy else { return }
        uploads.removeAll { $0.state != .waiting }
    }
    func startTransfer() {
        guard connected, writable, !isBusy, pending > 0 else { return }
        let batch = uploads.filter { $0.state == .waiting }
        let storage = storageID, parent = parentID, folderPath = destination
        let token = UUID(); batchID = token
        engine.control.reset()
        isBusy = true; isTransferring = true; progress = 0
        Task {
            defer { isBusy = false; isTransferring = false; batchID = UUID() }
            var completed = 0, skipped = 0, excluded = 0
            for (position, item) in batch.enumerated() {
                if engine.control.cancelled {
                    markRemaining(batch, state: .cancelled, detail: String(localized: "Передача отменена."))
                    break
                }
                update(item.id, state: .sending)
                status = String(localized: "Подготовка: \(item.url.lastPathComponent)…")
                do {
                    let summary = try await engine.uploadTree(url: item.url, storage: storage, parent: parent) { update in
                        Task { @MainActor in
                            guard self.batchID == token, self.isTransferring,
                                  self.uploads.first(where: { $0.id == item.id })?.state == .sending else { return }
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
                status = String(localized: "Скопировано файлов: \(completed). Пропущено совпадений: \(skipped).")
                if excluded > 0 { status += String(localized: " Исключено ссылок и служебных объектов: \(excluded).") }
                if connected {
                    do { entries = try await engine.contents(storage: storage, parent: parent) }
                    catch { await lostConnection(error) }
                }
            }
        }
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
    private func clearPhone() {
        deviceName = nil; storages = []; storageID = 0; folders = []; entries = []
    }
    private func lostConnection(_ error: Error) async {
        await engine.disconnect()
        clearPhone(); errorMessage = error.localizedDescription
        status = String(localized: "Не удалось выполнить операцию. Проверьте подключение и подключите телефон заново.")
    }
}

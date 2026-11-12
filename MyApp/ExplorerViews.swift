import SwiftUI
import UniformTypeIdentifiers

struct ExplorerInfoView: View {
    let info: ExplorerInfo
    @Environment(\.dismiss) private var dismiss
    private var kind: String {
        info.entry.folder ? String(localized: "Папка")
            : (UTType(filenameExtension: (info.entry.name as NSString).pathExtension)?.localizedDescription ?? String(localized: "Файл"))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label(String(localized: "Свойства"), systemImage: "info.circle").font(.title2)
            Form {
                LabeledContent(String(localized: "Имя"), value: info.entry.name)
                LabeledContent(String(localized: "Тип"), value: kind)
                LabeledContent(String(localized: "Путь на Pixel"), value: info.path)
                LabeledContent(String(localized: "Хранилище"), value: info.storage)
                if !info.entry.folder {
                    LabeledContent(String(localized: "Размер"), value: ByteCountFormatter.string(fromByteCount: Int64(clamping: info.entry.size), countStyle: .file))
                    LabeledContent(String(localized: "Байт"), value: String(info.entry.size))
                }
                LabeledContent(String(localized: "Изменён"), value: info.entry.modifiedAt?.formatted(date: .abbreviated, time: .standard) ?? String(localized: "Неизвестно"))
                LabeledContent(String(localized: "Доступ к хранилищу"), value: info.writable ? String(localized: "Чтение и запись") : String(localized: "Только чтение"))
            }.textSelection(.enabled)
            if info.entry.folder {
                Text(String(localized: "Размер папки не рассчитывается: он требует чтения всего дерева Pixel."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack { Spacer(); Button(String(localized: "Закрыть")) { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 470)
    }
}

struct MoveDestinationView: View {
    @ObservedObject var model: TransferModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "Переместить на Pixel")).font(.title2)
            HStack {
                Button { model.browseMove(Array(model.movePath.dropLast())) } label: { Image(systemName: "chevron.left") }
                    .disabled(model.isBusy || model.movePath.isEmpty)
                Text("/" + model.movePath.map(\.name).joined(separator: "/")).lineLimit(2)
                Spacer()
                if model.isBusy { ProgressView().controlSize(.small) }
            }
            List(model.moveEntries) { folder in
                Button {
                    model.browseMove(model.movePath + [PhoneFolder(id: folder.id, name: folder.name)])
                } label: { Label(folder.name, systemImage: "folder").frame(maxWidth: .infinity, alignment: .leading) }
                    .buttonStyle(.plain).disabled(model.isBusy)
            }.overlay {
                if model.moveEntries.isEmpty && !model.isBusy { Text(String(localized: "Вложенных папок нет")).foregroundStyle(.secondary) }
            }
            Text(String(localized: "Выберите папку в текущем хранилище. Существующие объекты не заменяются."))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(String(localized: "Отменить"), action: model.closeMove).keyboardShortcut(.cancelAction).disabled(model.isBusy)
                Spacer()
                Button(String(localized: "Переместить сюда"), action: model.finishMove)
                    .keyboardShortcut(.defaultAction).disabled(model.isBusy || (model.movePath.last?.id ?? TransferModel.root) == model.parentID)
            }
        }.padding(24).frame(width: 470, height: 430)
    }
}

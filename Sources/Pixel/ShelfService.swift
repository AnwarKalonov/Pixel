import AppKit
import Foundation
import SwiftUI

public struct ShelfItem: Identifiable, Sendable {
    public let id: UUID
    public let fileURL: URL
    public let filename: String
    public let fileSizeString: String
    public let dateAdded: Date
    public let kind: String

    public init(
        id: UUID = UUID(),
        fileURL: URL,
        filename: String,
        fileSizeString: String,
        dateAdded: Date = Date(),
        kind: String
    ) {
        self.id = id
        self.fileURL = fileURL
        self.filename = filename
        self.fileSizeString = fileSizeString
        self.dateAdded = dateAdded
        self.kind = kind
    }
}

@MainActor
public final class ShelfService: ObservableObject {
    public static let shared = ShelfService()

    @Published public var items: [ShelfItem] = []

    private let fileManager = FileManager.default
    private let shelfDirectory: URL

    public init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.shelfDirectory = appSupport.appendingPathComponent("Pixel/Shelf", isDirectory: true)

        try? fileManager.createDirectory(at: shelfDirectory, withIntermediateDirectories: true)
        loadItemsFromDisk()
    }

    public func loadItemsFromDisk() {
        guard let files = try? fileManager.contentsOfDirectory(at: shelfDirectory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else {
            return
        }

        var loaded: [ShelfItem] = []
        for url in files {
            if url.lastPathComponent.hasPrefix(".") { continue }
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = values?.fileSize ?? 0
            let date = values?.contentModificationDate ?? Date()
            let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
            let ext = url.pathExtension.uppercased()

            loaded.append(
                ShelfItem(
                    fileURL: url,
                    filename: url.lastPathComponent,
                    fileSizeString: sizeStr,
                    dateAdded: date,
                    kind: ext.isEmpty ? "FILE" : ext
                )
            )
        }

        // Sort most recently modified first
        self.items = loaded.sorted { $0.dateAdded > $1.dateAdded }
    }

    public func addFile(from sourceURL: URL) -> ShelfItem? {
        let destination = shelfDirectory.appendingPathComponent(sourceURL.lastPathComponent)

        // If file already exists, remove or overwrite
        if fileManager.fileExists(atPath: destination.path) {
            try? fileManager.removeItem(at: destination)
        }

        do {
            try fileManager.copyItem(at: sourceURL, to: destination)
            let values = try? destination.resourceValues(forKeys: [.fileSizeKey])
            let size = values?.fileSize ?? 0
            let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
            let ext = destination.pathExtension.uppercased()

            let newItem = ShelfItem(
                fileURL: destination,
                filename: destination.lastPathComponent,
                fileSizeString: sizeStr,
                dateAdded: Date(),
                kind: ext.isEmpty ? "FILE" : ext
            )

            self.items.removeAll { $0.filename == newItem.filename }
            self.items.insert(newItem, at: 0)
            return newItem
        } catch {
            return nil
        }
    }

    public func addSnippet(text: String, title: String = "Snippet.txt") -> ShelfItem? {
        let destination = shelfDirectory.appendingPathComponent(title)
        do {
            try text.write(to: destination, atomically: true, encoding: .utf8)
            let newItem = ShelfItem(
                fileURL: destination,
                filename: title,
                fileSizeString: "\(text.count) B",
                dateAdded: Date(),
                kind: "TEXT"
            )
            self.items.removeAll { $0.filename == newItem.filename }
            self.items.insert(newItem, at: 0)
            return newItem
        } catch {
            return nil
        }
    }

    public func removeItem(_ item: ShelfItem) {
        try? fileManager.removeItem(at: item.fileURL)
        items.removeAll { $0.id == item.id }
    }

    public func readFileContent(for item: ShelfItem) -> String {
        if let text = try? String(contentsOf: item.fileURL, encoding: .utf8) {
            return String(text.prefix(4000))
        }
        return "File '\(item.filename)' of type \(item.kind), size \(item.fileSizeString)."
    }

    public func copyToPasteboard(_ item: ShelfItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([item.fileURL as NSURL])
    }

    public func clearAll() {
        for item in items {
            try? fileManager.removeItem(at: item.fileURL)
        }
        items.removeAll()
    }
}

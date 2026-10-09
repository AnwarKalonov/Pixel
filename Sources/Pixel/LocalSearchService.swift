import AppKit
import Foundation

public struct LocalFileMatch: Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let path: String
    public let snippet: String
    public let kind: String
    public let modificationDate: Date

    public init(
        id: UUID = UUID(),
        title: String,
        path: String,
        snippet: String,
        kind: String,
        modificationDate: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.path = path
        self.snippet = snippet
        self.kind = kind
        self.modificationDate = modificationDate
    }
}

@MainActor
public final class LocalSearchService: ObservableObject {
    public static let shared = LocalSearchService()

    @Published public var results: [LocalFileMatch] = []
    @Published public var isSearching: Bool = false
    @Published public var indexedFileCount: Int = 0

    private let fileManager = FileManager.default

    public init() {
        Task {
            await countIndexedFiles()
        }
    }

    public func search(query: String, in directories: [String]) async {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanQuery.isEmpty else {
            self.results = []
            return
        }

        self.isSearching = true
        var matches: [LocalFileMatch] = []

        for dirStr in directories {
            let expandedPath = NSString(string: dirStr).expandingTildeInPath
            let url = URL(fileURLWithPath: expandedPath)
            guard fileManager.fileExists(atPath: url.path) else { continue }

            let enumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )

            var count = 0
            while let fileURL = enumerator?.nextObject() as? URL {
                count += 1
                if count > 2000 { break } // Guard against huge folders

                let filename = fileURL.lastPathComponent
                let lowerName = filename.lowercased()
                let ext = fileURL.pathExtension.lowercased()

                // Check ignored extensions
                if ext == "git" || ext == "tmp" || lowerName.contains("node_modules") {
                    continue
                }

                // Match in filename
                if lowerName.contains(cleanQuery) {
                    let modDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
                    matches.append(
                        LocalFileMatch(
                            title: filename,
                            path: fileURL.path,
                            snippet: "Matched file name in \(fileURL.deletingLastPathComponent().lastPathComponent)",
                            kind: ext.uppercased().isEmpty ? "FILE" : ext.uppercased(),
                            modificationDate: modDate
                        )
                    )
                    if matches.count >= 20 { break }
                    continue
                }

                // If small text file, check content
                if ["txt", "md", "swift", "py", "json", "csv", "js", "html"].contains(ext) {
                    let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                    if fileSize < 200_000, let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                        if let range = content.range(of: cleanQuery, options: .caseInsensitive) {
                            let start = content.index(range.lowerBound, offsetBy: -40, limitedBy: content.startIndex) ?? content.startIndex
                            let end = content.index(range.upperBound, offsetBy: 60, limitedBy: content.endIndex) ?? content.endIndex
                            let snippetText = "…" + content[start..<end].replacingOccurrences(of: "\n", with: " ") + "…"
                            let modDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()

                            matches.append(
                                LocalFileMatch(
                                    title: filename,
                                    path: fileURL.path,
                                    snippet: snippetText,
                                    kind: ext.uppercased(),
                                    modificationDate: modDate
                                )
                            )
                            if matches.count >= 20 { break }
                        }
                    }
                }
            }
            if matches.count >= 20 { break }
        }

        self.results = matches
        self.isSearching = false
    }

    public func countIndexedFiles() async {
        let dirs = PixelSettings.shared.indexedDirectories
        var total = 0
        for dirStr in dirs {
            let path = NSString(string: dirStr).expandingTildeInPath
            if let count = try? fileManager.contentsOfDirectory(atPath: path).count {
                total += count
            }
        }
        self.indexedFileCount = max(total, 120)
    }

    public func openFileInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

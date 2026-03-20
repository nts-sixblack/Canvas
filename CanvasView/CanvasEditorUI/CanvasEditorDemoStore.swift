import Combine
import Foundation
import UIKit

@MainActor
final class CanvasEditorDemoStore: ObservableObject {
    @Published private(set) var templates: [CanvasTemplate] = []
    @Published private(set) var savedDocument: SavedCanvasDocument?

    init() {
        loadTemplates()
        loadSavedDocument()
    }

    func save(result: CanvasEditorResult) {
        let folderURL = storageDirectory()
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
            try result.imageData.write(to: folderURL.appendingPathComponent("last-export.png"), options: .atomic)
            try result.projectData.write(to: folderURL.appendingPathComponent("last-project.json"), options: .atomic)
            loadSavedDocument()
        } catch {
            print("Canvas save error: \(error)")
        }
    }

    func clearSavedDocument() {
        let fileManager = FileManager.default
        let folderURL = storageDirectory()
        try? fileManager.removeItem(at: folderURL.appendingPathComponent("last-export.png"))
        try? fileManager.removeItem(at: folderURL.appendingPathComponent("last-project.json"))
        savedDocument = nil
    }

    private func loadTemplates() {
        let decoder = JSONDecoder()
        let bundleTemplates = (Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: "Templates") ?? [])
            .compactMap { url -> CanvasTemplate? in
                guard let data = try? Data(contentsOf: url) else {
                    return nil
                }
                return try? decoder.decode(CanvasTemplate.self, from: data)
            }
            .sorted(by: { $0.name < $1.name })

        templates = bundleTemplates.isEmpty ? CanvasTemplateFallbacks.all : bundleTemplates
    }

    private func loadSavedDocument() {
        let imageURL = storageDirectory().appendingPathComponent("last-export.png")
        let projectURL = storageDirectory().appendingPathComponent("last-project.json")

        guard let imageData = try? Data(contentsOf: imageURL),
              let projectData = try? Data(contentsOf: projectURL),
              let previewImage = UIImage(data: imageData) else {
            savedDocument = nil
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let project = try? decoder.decode(CanvasProject.self, from: projectData)
        let savedAt = ((try? projectURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate) ?? Date()
        savedDocument = SavedCanvasDocument(
            previewImage: previewImage,
            imageData: imageData,
            projectData: projectData,
            project: project,
            savedAt: savedAt
        )
    }

    private func storageDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CanvasEditorDemo", isDirectory: true)
    }
}

struct SavedCanvasDocument: Identifiable {
    let id = UUID()
    let previewImage: UIImage
    let imageData: Data
    let projectData: Data
    let project: CanvasProject?
    let savedAt: Date
}

private enum CanvasTemplateFallbacks {
    static var all: [CanvasTemplate] {
        [
            CanvasTemplate(
                id: "square-vibes",
                name: "Square Vibes",
                canvasSize: CanvasSize(width: 1080, height: 1080),
                background: .solid(CanvasColor(hex: "132238")),
                nodes: [
                    CanvasNode(
                        kind: .image,
                        name: "Hero",
                        transform: CanvasTransform(position: CanvasPoint(x: 540, y: 520)),
                        size: CanvasSize(width: 760, height: 760),
                        zIndex: 0,
                        source: .remoteURL("https://picsum.photos/seed/canvas-square/900/900")
                    ),
                    CanvasNode(
                        kind: .text,
                        name: "Headline",
                        transform: CanvasTransform(position: CanvasPoint(x: 540, y: 180)),
                        size: CanvasSize(width: 760, height: 180),
                        zIndex: 1,
                        text: "NEW DROP",
                        style: CanvasTextStyle(
                            fontFamily: "Avenir Next",
                            weight: .heavy,
                            fontSize: 76,
                            foregroundColor: .white,
                            alignment: .center,
                            letterSpacing: 2,
                            lineSpacing: 0,
                            shadow: CanvasShadowStyle(color: .black, radius: 20, offsetX: 0, offsetY: 12),
                            outline: CanvasOutlineStyle(color: CanvasColor(hex: "FF6A3D"), width: 8),
                            backgroundFill: nil,
                            opacity: 1
                        )
                    ),
                    CanvasNode(
                        kind: .sticker,
                        name: "Sparkles",
                        transform: CanvasTransform(position: CanvasPoint(x: 875, y: 860), rotation: -0.15, scale: 1),
                        size: CanvasSize(width: 180, height: 180),
                        zIndex: 2,
                        source: .symbol(named: "sparkles"),
                        style: CanvasTextStyle(
                            fontFamily: "Avenir Next",
                            weight: .bold,
                            fontSize: 40,
                            foregroundColor: .sunflower,
                            alignment: .center,
                            opacity: 1
                        )
                    )
                ]
            ),
            CanvasTemplate(
                id: "portrait-story",
                name: "Portrait Story",
                canvasSize: CanvasSize(width: 1080, height: 1920),
                background: .solid(CanvasColor(hex: "190E2C")),
                nodes: [
                    CanvasNode(
                        kind: .image,
                        name: "Mood",
                        transform: CanvasTransform(position: CanvasPoint(x: 540, y: 720)),
                        size: CanvasSize(width: 900, height: 1080),
                        zIndex: 0,
                        source: .remoteURL("https://picsum.photos/seed/canvas-portrait/900/1200")
                    ),
                    CanvasNode(
                        kind: .emoji,
                        name: "Emoji",
                        transform: CanvasTransform(position: CanvasPoint(x: 230, y: 260), rotation: -0.2, scale: 1),
                        size: CanvasSize(width: 220, height: 220),
                        zIndex: 1,
                        text: "🌙",
                        style: .defaultEmoji
                    ),
                    CanvasNode(
                        kind: .text,
                        name: "Story",
                        transform: CanvasTransform(position: CanvasPoint(x: 540, y: 1510)),
                        size: CanvasSize(width: 820, height: 260),
                        zIndex: 2,
                        text: "Tonight feels electric",
                        style: CanvasTextStyle(
                            fontFamily: "Georgia",
                            weight: .bold,
                            fontSize: 68,
                            foregroundColor: .white,
                            alignment: .center,
                            letterSpacing: 0.5,
                            lineSpacing: 10,
                            shadow: CanvasShadowStyle(color: .black, radius: 20, offsetX: 0, offsetY: 10),
                            outline: nil,
                            backgroundFill: CanvasFillStyle(color: CanvasColor(hex: "000000", alpha: 0.5)),
                            opacity: 1
                        )
                    )
                ]
            ),
            CanvasTemplate(
                id: "poster-45",
                name: "Poster 4:5",
                canvasSize: CanvasSize(width: 1080, height: 1350),
                background: .solid(CanvasColor(hex: "0F1A10")),
                nodes: [
                    CanvasNode(
                        kind: .text,
                        name: "Poster",
                        transform: CanvasTransform(position: CanvasPoint(x: 540, y: 210)),
                        size: CanvasSize(width: 860, height: 220),
                        zIndex: 0,
                        text: "Weekend launch",
                        style: CanvasTextStyle(
                            fontFamily: "Helvetica Neue",
                            weight: .heavy,
                            fontSize: 84,
                            foregroundColor: .mint,
                            alignment: .center,
                            letterSpacing: -1,
                            lineSpacing: 2,
                            shadow: nil,
                            outline: nil,
                            backgroundFill: nil,
                            opacity: 1
                        )
                    ),
                    CanvasNode(
                        kind: .sticker,
                        name: "Heart",
                        transform: CanvasTransform(position: CanvasPoint(x: 190, y: 1130), rotation: 0.2, scale: 1),
                        size: CanvasSize(width: 180, height: 180),
                        zIndex: 1,
                        source: .symbol(named: "heart.fill"),
                        style: CanvasTextStyle(
                            fontFamily: "Avenir Next",
                            weight: .bold,
                            fontSize: 40,
                            foregroundColor: .accent,
                            alignment: .center,
                            opacity: 1
                        )
                    ),
                    CanvasNode(
                        kind: .image,
                        name: "Preview",
                        transform: CanvasTransform(position: CanvasPoint(x: 540, y: 790)),
                        size: CanvasSize(width: 820, height: 820),
                        zIndex: 2,
                        source: .remoteURL("https://picsum.photos/seed/canvas-poster/900/900")
                    )
                ]
            )
        ]
    }
}

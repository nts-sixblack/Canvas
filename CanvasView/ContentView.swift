import Combine
import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var demoStore = CanvasEditorDemoStore()
    @State private var activeEditor: ActiveEditorSession?
    @State private var previewDocument: SavedCanvasDocument?

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.09, green: 0.11, blue: 0.16),
                        Color(red: 0.03, green: 0.04, blue: 0.06),
                        Color(red: 0.17, green: 0.08, blue: 0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        heroCard
                        templatesSection
                        if let savedDocument = demoStore.savedDocument {
                            savedSection(savedDocument)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Canvas Lab")
        }
        .sheet(item: $activeEditor) { session in
            CanvasEditorView(
                input: session.input,
                configuration: .demo,
                onCancel: {
                    activeEditor = nil
                },
                onExport: { result, image in
                    let documentID = UUID()
                    let transientDocument = demoStore.makeTransientDocument(
                        id: documentID,
                        result: result,
                        previewImage: image
                    )
                    demoStore.save(documentID: documentID, result: result)
                    activeEditor = nil
                    DispatchQueue.main.async {
                        previewDocument = transientDocument
                    }
                }
            )
        }
        .sheet(item: $previewDocument) { document in
            ResultPreviewSheet(document: document)
        }
        .onReceive(demoStore.$savedDocument.compactMap { $0 }) { document in
            guard previewDocument?.id == document.id else {
                return
            }
            previewDocument = document
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Reusable UIKit-powered canvas editor")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text("Import a JSON template, edit text, emoji, sticker, images, reorder layers, save project JSON, and export PNG.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))
            HStack(spacing: 12) {
                pill("UIKit core")
                pill("SwiftUI host")
                pill("JSON templates")
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1, green: 0.42, blue: 0.24).opacity(0.75),
                            Color(red: 0.25, green: 0.71, blue: 1).opacity(0.5),
                            Color(red: 0.11, green: 0.14, blue: 0.23)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }

    private var templatesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Templates")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            ForEach(demoStore.templates, id: \.id) { template in
                Button {
                    activeEditor = ActiveEditorSession(input: .template(template))
                } label: {
                    TemplateCard(template: template)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func savedSection(_ document: SavedCanvasDocument) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Last Export")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 16) {
                Image(uiImage: document.previewImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                Text(document.savedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))

                HStack(spacing: 12) {
                    Button("Preview") {
                        previewDocument = document
                    }
                    .buttonStyle(ActionButtonStyle(fill: Color.white))

                    Button("Resume Edit") {
                        if let project = document.project {
                            activeEditor = ActiveEditorSession(input: .project(project))
                        }
                    }
                    .buttonStyle(ActionButtonStyle(fill: Color(red: 0.27, green: 0.72, blue: 1)))
                    .disabled(document.project == nil)

                    Button("Clear") {
                        demoStore.clearSavedDocument()
                    }
                    .buttonStyle(ActionButtonStyle(fill: Color(red: 1, green: 0.42, blue: 0.24)))
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
        }
    }

    private func pill(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.white.opacity(0.14)))
    }
}

private struct ActiveEditorSession: Identifiable {
    let id = UUID()
    let input: CanvasEditorInput
}

private struct TemplateCard: View {
    let template: CanvasTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(template.name)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("\(Int(template.canvasSize.width)) x \(Int(template.canvasSize.height))")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                }
                Spacer()
                Text("\(template.nodes.count) layers")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.86))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
            }

            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(backgroundFill)
                Text(template.id.uppercased())
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(height: 120)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }

    private var backgroundFill: LinearGradient {
        LinearGradient(
            colors: [
                Color(canvasColor: template.background.color ?? .accent),
                Color.white.opacity(0.12),
                Color.black.opacity(0.5)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct ActionButtonStyle: ButtonStyle {
    let fill: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(.black)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(fill.opacity(configuration.isPressed ? 0.75 : 1))
            )
    }
}

private struct ResultPreviewSheet: View {
    let document: SavedCanvasDocument
    @State private var sharedResource: SharedResource?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(uiImage: document.previewImage)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                    Text("Export Summary")
                        .font(.system(size: 22, weight: .bold, design: .rounded))

                    VStack(alignment: .leading, spacing: 12) {
                        SummaryRow(title: "Status", value: document.isPersisted ? "Saved" : "Saving in background...")
                        SummaryRow(title: "Canvas", value: formattedCanvasSize)
                        SummaryRow(title: "Layers", value: formattedNodeCount)
                        SummaryRow(title: "PNG Size", value: formatByteCount(document.imageByteCount))
                        SummaryRow(title: "JSON Size", value: formatByteCount(document.projectByteCount))
                        SummaryRow(title: "Inline Images", value: inlineImageStatus)
                        SummaryRow(
                            title: "Saved At",
                            value: document.savedAt.formatted(date: .abbreviated, time: .shortened)
                        )
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.black.opacity(0.06))
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        Button("Open/Share PNG") {
                            guard let imageURL = document.imageURL else {
                                return
                            }
                            sharedResource = SharedResource(name: "PNG Export", url: imageURL)
                        }
                        .buttonStyle(ActionButtonStyle(fill: Color.white))
                        .disabled(document.imageURL == nil)

                        Button("Open/Share JSON") {
                            guard let projectURL = document.projectURL else {
                                return
                            }
                            sharedResource = SharedResource(name: "Project JSON", url: projectURL)
                        }
                        .buttonStyle(ActionButtonStyle(fill: Color(red: 0.27, green: 0.72, blue: 1)))
                        .disabled(document.projectURL == nil)

                        if !document.isPersisted {
                            Text("Files are still being written and indexed. Share actions unlock automatically when save completes.")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Export Preview")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $sharedResource) { resource in
                ActivityView(activityItems: [resource.url])
            }
        }
    }

    private var formattedCanvasSize: String {
        guard let canvasSize = document.canvasSize else {
            return "Preparing summary..."
        }
        return "\(Int(canvasSize.width)) x \(Int(canvasSize.height))"
    }

    private var formattedNodeCount: String {
        guard let nodeCount = document.nodeCount else {
            return "Preparing summary..."
        }
        return "\(nodeCount)"
    }

    private var inlineImageStatus: String {
        guard let containsInlineImages = document.containsInlineImages else {
            return "Preparing summary..."
        }
        return containsInlineImages ? "Yes" : "No"
    }

    private func formatByteCount(_ byteCount: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }
}

private struct SummaryRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)

            Text(value)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SharedResource: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

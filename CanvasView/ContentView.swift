import SwiftUI

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
                    demoStore.save(result: result)
                    previewDocument = demoStore.savedDocument ?? SavedCanvasDocument(
                        previewImage: image,
                        imageData: result.imageData,
                        projectData: result.projectData,
                        project: nil,
                        savedAt: Date()
                    )
                    activeEditor = nil
                }
            )
        }
        .sheet(item: $previewDocument) { document in
            ResultPreviewSheet(document: document)
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(uiImage: document.previewImage)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                    Text("Project JSON")
                        .font(.system(size: 22, weight: .bold, design: .rounded))

                    Text(prettyPrintedJSON)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.black.opacity(0.06))
                        )
                }
                .padding(20)
            }
            .navigationTitle("Export Preview")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var prettyPrintedJSON: String {
        String(data: document.projectData, encoding: .utf8) ?? "Unable to decode JSON"
    }
}

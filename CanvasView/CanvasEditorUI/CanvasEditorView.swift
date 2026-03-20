import SwiftUI
import UIKit

struct CanvasEditorView: UIViewControllerRepresentable {
    let input: CanvasEditorInput
    let configuration: CanvasEditorConfiguration
    let onCancel: () -> Void
    let onExport: (CanvasEditorResult, UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let viewController = CanvasEditorViewController(input: input, configuration: configuration)
        viewController.delegate = context.coordinator
        let navigationController = UINavigationController(rootViewController: viewController)
        navigationController.navigationBar.prefersLargeTitles = false
        navigationController.navigationBar.tintColor = .white
        navigationController.navigationBar.barStyle = .black
        navigationController.navigationBar.titleTextAttributes = [.foregroundColor: UIColor.white]
        navigationController.modalPresentationStyle = .fullScreen
        return navigationController
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    final class Coordinator: NSObject, CanvasEditorViewControllerDelegate {
        private let parent: CanvasEditorView

        init(_ parent: CanvasEditorView) {
            self.parent = parent
        }

        func canvasEditorViewControllerDidCancel(_ viewController: CanvasEditorViewController) {
            parent.onCancel()
        }

        func canvasEditorViewController(
            _ viewController: CanvasEditorViewController,
            didExport result: CanvasEditorResult,
            previewImage: UIImage
        ) {
            parent.onExport(result, previewImage)
        }
    }
}

extension Color {
    init(canvasColor: CanvasColor) {
        self.init(
            red: canvasColor.red,
            green: canvasColor.green,
            blue: canvasColor.blue,
            opacity: canvasColor.alpha
        )
    }
}

// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CanvasEditorCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "CanvasEditorCore",
            targets: ["CanvasEditorCore"]
        )
    ],
    targets: [
        .target(
            name: "CanvasEditorCore",
            path: "CanvasView/CanvasEditorCore"
        ),
        .testTarget(
            name: "CanvasEditorCoreTests",
            dependencies: ["CanvasEditorCore"],
            path: "Tests/CanvasEditorCoreTests"
        )
    ]
)

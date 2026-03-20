import XCTest
@testable import CanvasEditorCore

final class CanvasEditorCoreTests: XCTestCase {
    func testTemplateAndProjectRoundTrip() throws {
        let template = Self.sampleTemplate
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let templateData = try encoder.encode(template)
        let decodedTemplate = try decoder.decode(CanvasTemplate.self, from: templateData)
        XCTAssertEqual(decodedTemplate.id, template.id)
        XCTAssertEqual(decodedTemplate.nodes.count, template.nodes.count)
        XCTAssertEqual(decodedTemplate.canvasSize, template.canvasSize)

        let project = CanvasProject(template: decodedTemplate)
        let projectData = try encoder.encode(project)
        let decodedProject = try decoder.decode(CanvasProject.self, from: projectData)
        XCTAssertEqual(decodedProject.templateID, template.id)
        XCTAssertEqual(decodedProject.nodes.first?.source?.kind, .remoteURL)
    }

    func testStoreSupportsUndoRedoTransformFlow() {
        let store = CanvasEditorStore(template: Self.sampleTemplate, configuration: .demo)
        store.addTextNode(text: "Hello")
        let addedID = store.selectedNodeID
        let originalPosition = store.selectedNode?.transform.position

        store.moveSelectedNode(by: CanvasPoint(x: 40, y: -20))
        XCTAssertNotEqual(store.selectedNode?.transform.position, originalPosition)

        store.undo()
        XCTAssertEqual(store.selectedNode?.transform.position, originalPosition)

        store.undo()
        XCTAssertFalse(store.project.nodes.contains(where: { $0.id == addedID }))

        store.redo()
        XCTAssertTrue(store.project.nodes.contains(where: { $0.id == addedID }))
    }

    func testStoreNormalizesZOrderWhenReordering() {
        let store = CanvasEditorStore(template: Self.sampleTemplate, configuration: .demo)
        let middleNodeID = store.project.sortedNodes[1].id
        store.selectNode(middleNodeID)
        store.bringSelectedNodeToFront()

        let frontNode = store.project.sortedNodes.last
        XCTAssertEqual(frontNode?.id, middleNodeID)
        XCTAssertEqual(store.project.sortedNodes.map(\.zIndex), Array(0..<store.project.nodes.count))

        store.sendSelectedNodeToBack()
        let backNode = store.project.sortedNodes.first
        XCTAssertEqual(backNode?.id, middleNodeID)
        XCTAssertEqual(store.project.sortedNodes.map(\.zIndex), Array(0..<store.project.nodes.count))
    }

    func testTextStyleSerializationPreservesAdvancedFields() throws {
        let style = CanvasTextStyle(
            fontFamily: "Avenir Next",
            weight: .heavy,
            isItalic: true,
            fontSize: 58,
            foregroundColor: .accent,
            alignment: .trailing,
            letterSpacing: 3.5,
            lineSpacing: 11,
            shadow: CanvasShadowStyle(color: .black, radius: 12, offsetX: 2, offsetY: 6),
            outline: CanvasOutlineStyle(color: .white, width: 8),
            backgroundFill: CanvasFillStyle(color: .plum),
            opacity: 0.86
        )

        let data = try JSONEncoder().encode(style)
        let decoded = try JSONDecoder().decode(CanvasTextStyle.self, from: data)

        XCTAssertEqual(decoded, style)
    }

    func testAdjustSelectedTextWidthOnlyChangesWidth() {
        let store = CanvasEditorStore(template: Self.sampleTemplate, configuration: .demo)
        let textNodeID = store.project.sortedNodes[1].id
        store.selectNode(textNodeID)

        let before = store.selectedNode
        store.adjustSelectedTextWidth(by: 120)
        let after = store.selectedNode

        XCTAssertEqual(after?.size.height, before?.size.height)
        XCTAssertNotNil(after)
        XCTAssertNotNil(before)
        XCTAssertEqual(after!.size.width, before!.size.width + 120, accuracy: 0.001)
        XCTAssertGreaterThan(after?.transform.position.x ?? 0, before?.transform.position.x ?? 0)
    }

    func testAddImageNodePreservesIntrinsicAspectRatio() {
        let store = CanvasEditorStore(template: Self.sampleTemplate, configuration: .demo)

        store.addImageNode(
            source: .inlineImage(data: Data([0x00])),
            intrinsicSize: CanvasSize(width: 1600, height: 900)
        )

        guard let imageNode = store.selectedNode else {
            XCTFail("Expected imported image node to be selected")
            return
        }

        XCTAssertEqual(imageNode.kind, .image)
        XCTAssertEqual(imageNode.size.width / imageNode.size.height, 1600.0 / 900.0, accuracy: 0.001)
        XCTAssertLessThanOrEqual(imageNode.size.width, store.project.canvasSize.width * 0.42 + 0.001)
        XCTAssertLessThanOrEqual(imageNode.size.height, store.project.canvasSize.height * 0.42 + 0.001)
    }

    func testViewportMathFitsCanvasWithinBounds() {
        let layout = CanvasViewportMath.fit(
            canvasSize: CGSize(width: 1080, height: 1920),
            in: CGRect(x: 0, y: 0, width: 390, height: 844),
            padding: 20
        )

        XCTAssertEqual(layout.canvasFrame.midX, 195, accuracy: 0.001)
        XCTAssertEqual(layout.canvasFrame.midY, 422, accuracy: 0.001)
        XCTAssertLessThanOrEqual(layout.canvasFrame.width, 350.001)
        XCTAssertLessThanOrEqual(layout.canvasFrame.height, 804.001)
        XCTAssertGreaterThan(layout.scale, 0)
    }

    private static var sampleTemplate: CanvasTemplate {
        CanvasTemplate(
            id: "unit-template",
            name: "Unit Template",
            canvasSize: CanvasSize(width: 1080, height: 1350),
            background: .solid(CanvasColor(hex: "122034")),
            nodes: [
                CanvasNode(
                    kind: .image,
                    name: "Image",
                    transform: CanvasTransform(position: CanvasPoint(x: 540, y: 640)),
                    size: CanvasSize(width: 600, height: 600),
                    zIndex: 0,
                    source: .remoteURL("https://example.com/demo.png")
                ),
                CanvasNode(
                    kind: .text,
                    name: "Text",
                    transform: CanvasTransform(position: CanvasPoint(x: 540, y: 180)),
                    size: CanvasSize(width: 720, height: 180),
                    zIndex: 1,
                    text: "Launch",
                    style: .defaultText
                )
            ]
        )
    }
}

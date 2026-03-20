import AppKit
import Foundation

private struct AssetContents: Decodable {
    struct NamedColor: Decodable {
        struct ColorValue: Decodable {
            struct Components: Decodable {
                let red: String
                let green: String
                let blue: String
                let alpha: String
            }

            let components: Components
        }

        let color: ColorValue
    }

    let colors: [NamedColor]
}

private struct IconPalette {
    let white: NSColor
    let regionFill: NSColor
    let regionStroke: NSColor
    let regionShadow: NSColor
    let guide: NSColor
    let solidEdge: NSColor
    let dottedEdge: NSColor
    let state: NSColor
    let mutation: NSColor
    let effect: NSColor
}

private enum EdgeLineKind {
    case solid
    case dotted
}

private struct GraphNode {
    let id: String
    let column: Int
    let lane: Int
    let color: NSColor
    let predecessorIDs: [String]
    let lineKindByPredecessorID: [String: EdgeLineKind]
}

private enum EdgeSegment {
    case horizontal(lane: Int, startX: CGFloat, endX: CGFloat)
    case sourceCurve(startLane: Int, endLane: Int)
    case targetCurve(startLane: Int, endLane: Int)
    case localCurve(startLane: Int, endLane: Int)
}

private struct EdgePiece {
    let predecessorID: String
    let nodeID: String
    let lineKind: EdgeLineKind
    let segment: EdgeSegment
}

private enum IconLayoutMetrics {
    static let baseWidth: CGFloat = 144
    static let baseHeight: CGFloat = 101
    static let columnCount = 4
    static let columnWidth: CGFloat = baseWidth / CGFloat(columnCount)
    static let nodeRadius: CGFloat = 5
    static let blockerClearance: CGFloat = nodeRadius + 3.2
}

private struct IconGeometry {
    let size: CGFloat
    let canvasPadding: CGFloat
    let scale: CGFloat
    let contentRect: CGRect
    let regionRect: CGRect
    let columnWidth: CGFloat
    let regionCornerRadius: CGFloat
    let guideLineWidth: CGFloat
    let shadowBlur: CGFloat
    let shadowYOffset: CGFloat
    let nodeRadius: CGFloat
    let maxLane = 1

    init(size: CGFloat) {
        self.size = size
        self.canvasPadding = size * 0.03

        self.scale = min(
            (size - canvasPadding * 2) / IconLayoutMetrics.baseWidth,
            (size - canvasPadding * 2) / IconLayoutMetrics.baseHeight
        )

        self.contentRect = CGRect(
            x: (size - IconLayoutMetrics.baseWidth * scale) / 2,
            y: (size - IconLayoutMetrics.baseHeight * scale) / 2,
            width: IconLayoutMetrics.baseWidth * scale,
            height: IconLayoutMetrics.baseHeight * scale
        )

        self.columnWidth = IconLayoutMetrics.columnWidth * scale

        self.regionRect = CGRect(
            x: contentRect.minX,
            y: contentRect.minY + 2 * scale,
            width: CGFloat(IconLayoutMetrics.columnCount) * columnWidth,
            height: 97 * scale
        )

        self.regionCornerRadius = 9 * scale
        self.guideLineWidth = max(1.15 * scale, 0.85)
        self.shadowBlur = 3.5 * scale
        self.shadowYOffset = 1 * scale
        self.nodeRadius = max(6 * scale, 1.4)
    }

    func columnOriginX(_ column: Int) -> CGFloat {
        contentRect.minX + CGFloat(column) * columnWidth
    }

    func centerPoint(column: Int, lane: Int) -> CGPoint {
        CGPoint(
            x: columnOriginX(column) + columnWidth / 2,
            y: laneY(lane)
        )
    }

    func laneY(_ lane: Int) -> CGFloat {
        let displayLane = maxLane - lane
        return contentRect.minY + (41 + CGFloat(displayLane) * 34) * scale
    }
}

private let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
private let assetsURL = rootURL.appendingPathComponent("SessionTraceViewer/Assets.xcassets", isDirectory: true)
private let appIconURL = assetsURL.appendingPathComponent("AppIcon.appiconset", isDirectory: true)

private func loadColor(_ relativeAssetPath: String) throws -> NSColor {
    let contentsURL = assetsURL
        .appendingPathComponent(relativeAssetPath, isDirectory: true)
        .appendingPathComponent("Contents.json", isDirectory: false)
    let data = try Data(contentsOf: contentsURL)
    let contents = try JSONDecoder().decode(AssetContents.self, from: data)
    guard let components = contents.colors.first?.color.components else {
        throw NSError(domain: "RenderAppIcon", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "No color components found for \(relativeAssetPath)."
        ])
    }

    func value(_ string: String) throws -> CGFloat {
        guard let number = Double(string) else {
            throw NSError(domain: "RenderAppIcon", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Invalid component '\(string)' in \(relativeAssetPath)."
            ])
        }
        return CGFloat(number)
    }

    return NSColor(
        srgbRed: try value(components.red),
        green: try value(components.green),
        blue: try value(components.blue),
        alpha: try value(components.alpha)
    )
}

private func loadPalette() throws -> IconPalette {
    .init(
        white: try loadColor("Theme/Base/White.colorset"),
        regionFill: try loadColor("Theme/Surfaces/OverviewRegion.colorset"),
        regionStroke: try loadColor("Theme/Rows/Stroke.colorset"),
        regionShadow: try loadColor("Theme/Shadows/OverviewRegion.colorset"),
        guide: try loadColor("Theme/Overview/Guide.colorset"),
        solidEdge: try loadColor("Theme/Lines/SolidBranch.colorset"),
        dottedEdge: try loadColor("Theme/Lines/DottedBranch.colorset"),
        state: try loadColor("Theme/Semantic/Graph/State.colorset"),
        mutation: try loadColor("Theme/Semantic/Graph/Mutation.colorset"),
        effect: try loadColor("Theme/Semantic/Graph/Effect.colorset")
    )
}

private func drawCircle(
    in context: CGContext,
    center: CGPoint,
    radius: CGFloat,
    color: NSColor
) {
    let rect = CGRect(
        x: center.x - radius,
        y: center.y - radius,
        width: radius * 2,
        height: radius * 2
    )
    context.setFillColor(color.cgColor)
    context.fillEllipse(in: rect)
}

private func strokeGuideLine(in context: CGContext, geometry: IconGeometry, color: NSColor) {
    context.beginPath()
    context.move(to: CGPoint(x: geometry.contentRect.minX, y: geometry.laneY(0)))
    context.addLine(to: CGPoint(x: geometry.contentRect.maxX, y: geometry.laneY(0)))
    context.setStrokeColor(color.cgColor)
    context.setLineWidth(geometry.guideLineWidth)
    context.strokePath()
}

private func splitSegment(
    segment: ClosedRange<CGFloat>,
    removing blockerRange: ClosedRange<CGFloat>
) -> [ClosedRange<CGFloat>] {
    if blockerRange.upperBound <= segment.lowerBound || blockerRange.lowerBound >= segment.upperBound {
        return [segment]
    }

    var result: [ClosedRange<CGFloat>] = []
    if blockerRange.lowerBound > segment.lowerBound {
        result.append(segment.lowerBound...min(blockerRange.lowerBound, segment.upperBound))
    }
    if blockerRange.upperBound < segment.upperBound {
        result.append(max(blockerRange.upperBound, segment.lowerBound)...segment.upperBound)
    }
    return result
}

private func horizontalSegments(
    in baseRange: ClosedRange<CGFloat>,
    hasBlocker: Bool
) -> [ClosedRange<CGFloat>] {
    guard hasBlocker else {
        return [baseRange]
    }

    let blockerLower = max(
        IconLayoutMetrics.columnWidth / 2 - IconLayoutMetrics.blockerClearance,
        0
    )
    let blockerUpper = min(
        IconLayoutMetrics.columnWidth / 2 + IconLayoutMetrics.blockerClearance,
        IconLayoutMetrics.columnWidth
    )
    return splitSegment(segment: baseRange, removing: blockerLower...blockerUpper)
        .filter { $0.upperBound - $0.lowerBound > 0.5 }
}

private func appendHorizontalPieces(
    predecessorID: String,
    nodeID: String,
    column: Int,
    lane: Int,
    baseRange: ClosedRange<CGFloat>,
    excludingNodeIDs: Set<String>,
    lineKind: EdgeLineKind,
    nodesByColumn: [Int: [GraphNode]],
    edgePiecesByColumn: inout [Int: [EdgePiece]]
) {
    let hasBlocker = (nodesByColumn[column] ?? []).contains { node in
        node.lane == lane && !excludingNodeIDs.contains(node.id)
    }

    for segment in horizontalSegments(in: baseRange, hasBlocker: hasBlocker) {
        edgePiecesByColumn[column, default: []].append(
            .init(
                predecessorID: predecessorID,
                nodeID: nodeID,
                lineKind: lineKind,
                segment: .horizontal(
                    lane: lane,
                    startX: segment.lowerBound,
                    endX: segment.upperBound
                )
            )
        )
    }
}

private func buildEdgePieces(nodes: [GraphNode]) -> [Int: [EdgePiece]] {
    let nodesByColumn = Dictionary(grouping: nodes, by: \.column)
    let nodeByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
    let nodeIndexByID = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($1.id, $0) })
    var edgePiecesByColumn: [Int: [EdgePiece]] = [:]

    for node in nodes {
        guard let nodeIndex = nodeIndexByID[node.id] else { continue }
        for predecessorID in node.predecessorIDs {
            guard let predecessor = nodeByID[predecessorID],
                  let predecessorIndex = nodeIndexByID[predecessorID],
                  predecessorIndex < nodeIndex else {
                continue
            }

            let lineKind = node.lineKindByPredecessorID[predecessorID] ?? .solid
            let columnCenterX = IconLayoutMetrics.columnWidth / 2

            if predecessor.column == node.column {
                edgePiecesByColumn[node.column, default: []].append(
                    .init(
                        predecessorID: predecessor.id,
                        nodeID: node.id,
                        lineKind: lineKind,
                        segment: .localCurve(startLane: predecessor.lane, endLane: node.lane)
                    )
                )
                continue
            }

            if predecessor.lane == node.lane {
                appendHorizontalPieces(
                    predecessorID: predecessor.id,
                    nodeID: node.id,
                    column: predecessor.column,
                    lane: predecessor.lane,
                    baseRange: columnCenterX...IconLayoutMetrics.columnWidth,
                    excludingNodeIDs: [predecessor.id],
                    lineKind: lineKind,
                    nodesByColumn: nodesByColumn,
                    edgePiecesByColumn: &edgePiecesByColumn
                )

                if predecessor.column + 1 < node.column {
                    for column in (predecessor.column + 1)..<node.column {
                        appendHorizontalPieces(
                            predecessorID: predecessor.id,
                            nodeID: node.id,
                            column: column,
                            lane: node.lane,
                            baseRange: 0...IconLayoutMetrics.columnWidth,
                            excludingNodeIDs: [],
                            lineKind: lineKind,
                            nodesByColumn: nodesByColumn,
                            edgePiecesByColumn: &edgePiecesByColumn
                        )
                    }
                }

                appendHorizontalPieces(
                    predecessorID: predecessor.id,
                    nodeID: node.id,
                    column: node.column,
                    lane: node.lane,
                    baseRange: 0...columnCenterX,
                    excludingNodeIDs: [node.id],
                    lineKind: lineKind,
                    nodesByColumn: nodesByColumn,
                    edgePiecesByColumn: &edgePiecesByColumn
                )
                continue
            }

            if predecessor.lane < node.lane {
                edgePiecesByColumn[predecessor.column, default: []].append(
                    .init(
                        predecessorID: predecessor.id,
                        nodeID: node.id,
                        lineKind: lineKind,
                        segment: .sourceCurve(startLane: predecessor.lane, endLane: node.lane)
                    )
                )

                if predecessor.column + 1 < node.column {
                    for column in (predecessor.column + 1)..<node.column {
                        appendHorizontalPieces(
                            predecessorID: predecessor.id,
                            nodeID: node.id,
                            column: column,
                            lane: node.lane,
                            baseRange: 0...IconLayoutMetrics.columnWidth,
                            excludingNodeIDs: [],
                            lineKind: lineKind,
                            nodesByColumn: nodesByColumn,
                            edgePiecesByColumn: &edgePiecesByColumn
                        )
                    }
                }

                appendHorizontalPieces(
                    predecessorID: predecessor.id,
                    nodeID: node.id,
                    column: node.column,
                    lane: node.lane,
                    baseRange: 0...columnCenterX,
                    excludingNodeIDs: [node.id],
                    lineKind: lineKind,
                    nodesByColumn: nodesByColumn,
                    edgePiecesByColumn: &edgePiecesByColumn
                )
                continue
            }

            appendHorizontalPieces(
                predecessorID: predecessor.id,
                nodeID: node.id,
                column: predecessor.column,
                lane: predecessor.lane,
                baseRange: columnCenterX...IconLayoutMetrics.columnWidth,
                excludingNodeIDs: [predecessor.id],
                lineKind: lineKind,
                nodesByColumn: nodesByColumn,
                edgePiecesByColumn: &edgePiecesByColumn
            )

            if predecessor.column + 1 < node.column {
                for column in (predecessor.column + 1)..<node.column {
                    appendHorizontalPieces(
                        predecessorID: predecessor.id,
                        nodeID: node.id,
                        column: column,
                        lane: predecessor.lane,
                        baseRange: 0...IconLayoutMetrics.columnWidth,
                        excludingNodeIDs: [],
                        lineKind: lineKind,
                        nodesByColumn: nodesByColumn,
                        edgePiecesByColumn: &edgePiecesByColumn
                    )
                }
            }

            edgePiecesByColumn[node.column, default: []].append(
                .init(
                    predecessorID: predecessor.id,
                    nodeID: node.id,
                    lineKind: lineKind,
                    segment: .targetCurve(startLane: predecessor.lane, endLane: node.lane)
                )
            )
        }
    }

    return edgePiecesByColumn
}

private func strokeStyle(
    for lineKind: EdgeLineKind,
    scale: CGFloat
) -> (lineWidth: CGFloat, dash: [CGFloat]) {
    switch lineKind {
    case .solid:
        return (max(1.3 * scale, 0.95), [])
    case .dotted:
        return (max(1.45 * scale, 1.05), [max(1.5 * scale, 0.85), max(6.6 * scale, 1.9)])
    }
}

private func drawEdgePiece(
    _ piece: EdgePiece,
    in context: CGContext,
    column: Int,
    geometry: IconGeometry,
    color: NSColor
) {
    let originX = geometry.columnOriginX(column)
    let scale = geometry.scale
    let columnWidth = geometry.columnWidth
    let columnCenterX = columnWidth / 2

    context.beginPath()
    switch piece.segment {
    case .horizontal(let lane, let startX, let endX):
        context.move(to: CGPoint(x: originX + startX * scale, y: geometry.laneY(lane)))
        context.addLine(to: CGPoint(x: originX + endX * scale, y: geometry.laneY(lane)))

    case .sourceCurve(let startLane, let endLane):
        let start = CGPoint(x: originX + columnCenterX, y: geometry.laneY(startLane))
        let end = CGPoint(x: originX + columnWidth, y: geometry.laneY(endLane))
        context.move(to: start)
        context.addCurve(
            to: end,
            control1: CGPoint(
                x: originX + columnCenterX + (columnWidth - columnCenterX) * 0.28,
                y: start.y
            ),
            control2: CGPoint(x: originX + columnWidth - 8 * scale, y: end.y)
        )

    case .targetCurve(let startLane, let endLane):
        let start = CGPoint(x: originX, y: geometry.laneY(startLane))
        let end = CGPoint(x: originX + columnCenterX, y: geometry.laneY(endLane))
        context.move(to: start)
        context.addCurve(
            to: end,
            control1: CGPoint(x: originX + 8 * scale, y: start.y),
            control2: CGPoint(x: originX + columnCenterX - columnWidth * 0.22, y: end.y)
        )

    case .localCurve(let startLane, let endLane):
        let start = CGPoint(x: originX + columnCenterX, y: geometry.laneY(startLane))
        let end = CGPoint(x: originX + columnCenterX, y: geometry.laneY(endLane))
        context.move(to: start)
        context.addCurve(
            to: end,
            control1: CGPoint(x: originX + columnWidth * 0.84, y: start.y),
            control2: CGPoint(x: originX + columnWidth * 0.84, y: end.y)
        )
    }

    let style = strokeStyle(for: piece.lineKind, scale: geometry.scale)
    context.setStrokeColor(color.cgColor)
    context.setLineWidth(style.lineWidth)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setLineDash(phase: 0, lengths: style.dash)
    context.strokePath()
    context.setLineDash(phase: 0, lengths: [])
}

private func renderIcon(size: CGFloat, palette: IconPalette) throws -> Data {
    let pixels = Int(size.rounded())
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "RenderAppIcon", code: 3, userInfo: [
            NSLocalizedDescriptionKey: "Unable to create bitmap context."
        ])
    }

    guard let context = NSGraphicsContext(bitmapImageRep: bitmap)?.cgContext else {
        throw NSError(domain: "RenderAppIcon", code: 4, userInfo: [
            NSLocalizedDescriptionKey: "Unable to create graphics context."
        ])
    }

    let geometry = IconGeometry(size: size)
    let nodes: [GraphNode] = [
        .init(
            id: "initial-state",
            column: 0,
            lane: 0,
            color: palette.state,
            predecessorIDs: [],
            lineKindByPredecessorID: [:]
        ),
        .init(
            id: "mutation",
            column: 1,
            lane: 1,
            color: palette.mutation,
            predecessorIDs: ["initial-state"],
            lineKindByPredecessorID: ["initial-state": .solid]
        ),
        .init(
            id: "state-change",
            column: 2,
            lane: 0,
            color: palette.state,
            predecessorIDs: ["mutation"],
            lineKindByPredecessorID: ["mutation": .solid]
        ),
        .init(
            id: "effect",
            column: 3,
            lane: 1,
            color: palette.effect,
            predecessorIDs: ["mutation"],
            lineKindByPredecessorID: ["mutation": .dotted]
        )
    ]
    let edgePiecesByColumn = buildEdgePieces(nodes: nodes)

    context.saveGState()
    context.translateBy(x: 0, y: size)
    context.scaleBy(x: 1, y: -1)
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.interpolationQuality = .high

    context.setFillColor(palette.white.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))

    strokeGuideLine(in: context, geometry: geometry, color: palette.guide)

    for column in 0..<IconLayoutMetrics.columnCount {
        let pieces = edgePiecesByColumn[column] ?? []
        for lineKind in [EdgeLineKind.solid, .dotted] {
            for piece in pieces where piece.lineKind == lineKind {
                let color: NSColor = {
                    switch piece.lineKind {
                    case .solid:
                        return palette.solidEdge
                    case .dotted:
                        return palette.dottedEdge
                    }
                }()
                drawEdgePiece(
                    piece,
                    in: context,
                    column: column,
                    geometry: geometry,
                    color: color
                )
            }
        }
    }

    for node in nodes {
        drawCircle(
            in: context,
            center: geometry.centerPoint(column: node.column, lane: node.lane),
            radius: geometry.nodeRadius,
            color: node.color
        )
    }

    context.restoreGState()

    guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "RenderAppIcon", code: 5, userInfo: [
            NSLocalizedDescriptionKey: "Unable to encode PNG."
        ])
    }
    return pngData
}

private let iconOutputs: [(filename: String, size: CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

private let palette = try loadPalette()

for output in iconOutputs {
    let data = try renderIcon(size: output.size, palette: palette)
    let destinationURL = appIconURL.appendingPathComponent(output.filename, isDirectory: false)
    try data.write(to: destinationURL)
    print("Wrote \(destinationURL.path)")
}

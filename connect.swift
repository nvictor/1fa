//
//  ArrowHead.swift
//  Connect
//
//  Created by Victor Noagbodji on 4/8/25.
//

import SwiftUI

struct ArrowHead: Shape {
    let to: CGPoint
    let from: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let angle = atan2(to.y - from.y, to.x - from.x)
        let tip = to
        let size: CGFloat = 10
        let points = [
            CGPoint(x: tip.x - size * cos(angle - .pi / 6), y: tip.y - size * sin(angle - .pi / 6)),
            tip,
            CGPoint(x: tip.x - size * cos(angle + .pi / 6), y: tip.y - size * sin(angle + .pi / 6))
        ]
        path.move(to: points[0])
        path.addLine(to: points[1])
        path.addLine(to: points[2])
        path.closeSubpath()
        return path
    }
}

//
//  Connector.swift
//  Connect
//
//  Created by Victor Noagbodji on 4/8/25.
//

import SwiftUI

enum NodeSide {
    case top, bottom, left, right
}

struct Connector: Identifiable {
    let id: UUID
    let from: (nodeID: UUID, side: NodeSide)
    let to: (nodeID: UUID, side: NodeSide)
}

//
//  ConnectorView.swift
//  Connect
//
//  Created by Victor Noagbodji on 4/8/25.
//

import SwiftUI

struct ConnectorView: View {
    let from: CGPoint
    let to: CGPoint

    var body: some View {
        Path { path in
            path.move(to: from)
            path.addLine(to: to)
        }
        .stroke(Color.black, lineWidth: 2)
        .overlay(ArrowHead(to: to, from: from).fill(Color.black))
    }
}

//
//  ContentView.swift
//  Connect
//
//  Created by Victor Noagbodji on 4/8/25.
//

import SwiftUI

struct ContentView: View {
    @State private var nodes: [Node] = [
        Node(id: UUID(), position: CGPoint(x: 200, y: 200))
    ]
    @State private var connectors: [Connector] = []
    @State private var selectedNodeID: UUID?

    var body: some View {
        ZStack {
            ForEach(connectors) { connector in
                if let fromNode = node(for: connector.from.nodeID),
                   let toNode = node(for: connector.to.nodeID) {
                    ConnectorView(from: connectionPoint(for: fromNode, side: connector.from.side),
                                  to: connectionPoint(for: toNode, side: connector.to.side))
                }
            }

            ForEach(nodes) { node in
                NodeView(node: node, isSelected: node.id == selectedNodeID)
                    .position(node.position)
                    .onTapGesture {
                        selectedNodeID = node.id
                    }
            }

            KeyCatcherView(onKeyDown: handleKey)
                .frame(width: 0, height: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }

    private func node(for id: UUID) -> Node? {
        nodes.first { $0.id == id }
    }

    private func connectionPoint(for node: Node, side: NodeSide) -> CGPoint {
        let x = node.position.x
        let y = node.position.y
        switch side {
        case .top: return CGPoint(x: x, y: y - node.size.height / 2)
        case .bottom: return CGPoint(x: x, y: y + node.size.height / 2)
        case .left: return CGPoint(x: x - node.size.width / 2, y: y)
        case .right: return CGPoint(x: x + node.size.width / 2, y: y)
        }
    }

    private func handleKey(_ event: NSEvent) {
        guard let selectedID = selectedNodeID,
              let currentNode = node(for: selectedID) else { return }

        let directions: [UInt16: NodeSide] = [
            126: .top,     // up arrow
            125: .bottom,  // down arrow
            123: .left,    // left arrow
            124: .right    // right arrow
        ]

        if let side = directions[event.keyCode] {
            let offset: CGFloat = 150
            var newPosition = currentNode.position
            switch side {
            case .top: newPosition.y -= offset
            case .bottom: newPosition.y += offset
            case .left: newPosition.x -= offset
            case .right: newPosition.x += offset
            }

            let newNode = Node(id: UUID(), position: newPosition)
            nodes.append(newNode)
            connectors.append(Connector(
                id: UUID(),
                from: (currentNode.id, side),
                to: (newNode.id, opposite(side))
            ))
            selectedNodeID = newNode.id
        }
    }

    private func opposite(_ side: NodeSide) -> NodeSide {
        switch side {
        case .top: return .bottom
        case .bottom: return .top
        case .left: return .right
        case .right: return .left
        }
    }
}

#Preview {
    ContentView()
}

//
//  ConnectApp.swift
//  Connect
//
//  Created by Victor Noagbodji on 4/8/25.
//

import SwiftUI

@main
struct ConnectApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

//
//  KeyCatcherView.swift
//  Connect
//
//  Created by Victor Noagbodji on 4/9/25.
//

import SwiftUI

struct KeyCatcherView: NSViewRepresentable {
    var onKeyDown: (NSEvent) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = KeyCatcherNSView()
        view.onKeyDown = onKeyDown
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    class KeyCatcherNSView: NSView {
        var onKeyDown: ((NSEvent) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            onKeyDown?(event)
        }
    }
}

//
//  Node.swift
//  Connect
//
//  Created by Victor Noagbodji on 4/8/25.
//

import SwiftUI

struct Node: Identifiable {
    let id: UUID
    var position: CGPoint
    var size: CGSize = CGSize(width: 100, height: 60)
}

//
//  NodeView.swift
//  Diagram
//
//  Created by Victor Noagbodji on 4/8/25.
//

import SwiftUI

struct NodeView: View {
    let node: Node
    let isSelected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(isSelected ? Color.blue.opacity(0.4) : Color.gray.opacity(0.2))
            .frame(width: node.size.width, height: node.size.height)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black))
    }
}

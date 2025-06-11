//
//  ContentView.swift
//  Moves
//
//  Created by Victor Noagbodji on 5/28/25.
//

import SwiftUI

struct ContentView: View {    
    @State private var preset: Preset? = nil

    @State private var lines: [Line] = [
        Line(
            name: "Untitled",
            segments: [
                Segment(movement: .repeat, length: 4),
                Segment(movement: .repeat, length: 4)
            ])
    ]
    @State private var currentLine: Int = 0
    @State private var selectedSegmentID: UUID? = nil
    @State private var showInspector = false
    
    var body: some View {
        NavigationSplitView {
            Sidebar(preset: $preset)
        } detail: {
            Editor(
                lines: $lines,
                selectedSegmentID: $selectedSegmentID,
                currentLine: $currentLine
            )
        }
        .inspector(isPresented: $showInspector) {
            Inspector(currentLine: $currentLine,
                      lines: $lines,
                      selectedSegmentID: $selectedSegmentID)
        }
        .toolbar {
            ToolbarItem {
                Button {
                    ImageExporter.export(lines: lines)
                } label: {
                    Image(systemName: "photo")
                }
            }
            ToolbarItem {
                Button {
                    showInspector.toggle()
                } label: {
                    Image(systemName: "sidebar.trailing")
                }
            }
        }
        .onChange(of: preset) { _, newPreset in
            guard let p = newPreset else { return }
            if lines.indices.contains(currentLine) {
                lines[currentLine] = Line(name: p.name, segments: p.segments)
            }
        }
    }
}

#Preview {
    ContentView()
}

//
//  Editor.swift
//  Moves
//
//  Created by Victor Noagbodji on 6/3/25.
//

import SwiftUI

struct Editor: View {
    @Binding var lines: [Line]
    @Binding var selectedSegmentID: UUID?
    @Binding var currentLine: Int

    var body: some View {
        VStack(alignment: .leading) {
            ForEach(lines.indices, id: \.self) { index in
                HStack() {
                    Text(lines[index].name)
                        .frame(width: 100, alignment: .leading)
                        .fontWeight(index == currentLine ? .bold : .regular)

                    HStack(spacing: 2) {
                        ForEach(lines[index].segments.indices, id: \.self) { s in
                            SegmentBlock(
                                segment: $lines[index].segments[s],
                                isSelected: selectedSegmentID == lines[index].segments[s].id,
                                isEven: s.isMultiple(of: 2)
                            ) {
                                let id = lines[index].segments[s].id
                                selectedSegmentID = (selectedSegmentID == id) ? nil : id
                            }
                        }
                    }
                }
                .padding()
            }
        }
    }
}

//
//  ImageExporter.swift
//  Moves
//
//  Created by Victor Noagbodji on 6/3/25.
//

import SwiftUI
import AppKit

struct ImageExporter {
    @MainActor
    static func export(lines: [Line], fileName: String = "moves.png") {
        let view = Editor(
            lines: .constant(lines),
            selectedSegmentID: .constant(nil),
            currentLine: .constant(0)
        )
            .padding()
            .fixedSize()
            .preferredColorScheme(.light)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2

        guard
            let nsImage = renderer.nsImage,
            let tiff = nsImage.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
        else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = fileName
        if panel.runModal() == .OK, let url = panel.url {
            try? png.write(to: url)
        }
    }
}

//
//  Inspector.swift
//  Moves
//
//  Created by Victor Noagbodji on 6/3/25.
//

import SwiftUI

struct Inspector: View {
    @Binding var currentLine: Int
    @Binding var lines: [Line]
    @Binding var selectedSegmentID: UUID?

    private var selectedSegmentBinding: Binding<Segment>? {
        guard lines.indices.contains(currentLine) else { return nil }
        for index in lines[currentLine].segments.indices {
            if lines[currentLine].segments[index].id == selectedSegmentID {
                return $lines[currentLine].segments[index]
            }
        }
        return nil
    }

    var body: some View {
        Form {
            Section("Line") {
                Picker("Current", selection: $currentLine) {
                    ForEach(lines.indices, id: \.self) { i in
                        Text(lines[i].name).tag(i)
                    }
                }

                TextField("Name", text: $lines[currentLine].name)

                Button("Add") {
                    lines.append(
                        Line(
                            name: "Line \(lines.count + 1)",
                            segments: [
                                Segment(movement: .repeat, length: 4),
                                Segment(movement: .repeat, length: 4)
                            ])
                    )
                    currentLine = lines.count - 1
                }

                if lines.count > 1 {
                    Button("Delete") {
                        lines.remove(at: currentLine)
                        currentLine = max(0, currentLine - 1)
                    }
                    .tint(.red)
                }
            }

            if let segment = selectedSegmentBinding {
                Section("Segment") {
                    Stepper("Length: \(segment.length.wrappedValue)",
                            value: segment.length, in: 1...16)
                }
            }

            Section("Debug") {
                Button("Reset Presets") {
                    UserDefaults.standard.removeObject(forKey: "MovesPresets")
                }
            }
        }
        .padding()
    }
}

//
//  Line.swift
//  Moves
//
//  Created by Victor Noagbodji on 6/11/25.
//

import Foundation

struct Line: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var segments: [Segment]
}

//
//  Movement.swift
//  Moves
//
//  Created by Victor Noagbodji on 5/28/25.
//

import Foundation
import SwiftUI

enum Movement: String, CaseIterable, Codable {
    case `repeat`, progress,  empty

    func color() -> Color {
        switch self {
        case .repeat: return .blue
        case .progress: return .purple
        case .empty: return .gray.opacity(0.2)
        }
    }
}

//
//  Moves.entitlements
//  Moves
//
//  Created by Victor Noagbodji on 5/28/25.
//

<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.files.user-selected.read-write</key>
	<true/>
</dict>
</plist>

//
//  MovesApp.swift
//  Moves
//
//  Created by Victor Noagbodji on 5/28/25.
//

import SwiftUI

@main
struct MovesApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

//
//  Preset.swift
//  Moves
//
//  Created by Victor Noagbodji on 6/3/25.
//

import SwiftUI

struct Preset: Identifiable, Codable, Hashable, Equatable {
    var id = UUID()
    let name: String
    let segments: [Segment]
}

//
//  PresetManager.swift
//  Moves
//
//  Created by Victor Noagbodji on 6/3/25.
//

import Foundation

class PresetManager {
    static let shared = PresetManager()
    private let defaultsKey = "MovesPresets"
    
    func loadPresets() -> [String: [Preset]] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: [PresetCodable]].self, from: data) else {
            return loadDefaultPresets()
        }

        return decoded.mapValues { $0.map { $0.toPreset() } }
    }

    func savePresets(_ presets: [String: [Preset]]) {
        let codable = presets.mapValues { $0.map { PresetCodable(from: $0) } }
        if let data = try? JSONEncoder().encode(codable) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private func loadDefaultPresets() -> [String: [Preset]] {
        guard let data = PresetManager.defaultPresetJSON.data(using: .utf8),
              let raw = try? JSONDecoder().decode([String: [String: [String]]].self, from: data) else {
            return [:]
        }

        return raw.mapValues { namedPresets in
            namedPresets.map { name, sequence in
                let segments = sequence.map { value -> Segment in
                    let parts = value.split(separator: "/", omittingEmptySubsequences: false)
                    let movement = Movement(rawValue: getMovementType(String(parts[0]))) ?? .empty
                    let length = Int(parts[1]) ?? 1
                    let note = String(parts[2])
                    return Segment(movement: movement, length: length, note: note)
                }
                return Preset(name: name, segments: segments)
            }
            .sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        }
    }
    
    private func getMovementType(_ rawValue: String) -> String {
        switch rawValue {
        case "p":
            return "progress"
        case "r":
            return "repeat"
        default:
            return "empty"
        }
    }

    private struct PresetCodable: Codable {
        var name: String
        var segments: [Segment]

        init(from preset: Preset) {
            self.name = preset.name
            self.segments = preset.segments
        }

        func toPreset() -> Preset {
            Preset(name: name, segments: segments)
        }
    }
    
    private static let defaultPresetJSON = """
    {
      "Intervals": {
        "1. Tension": ["p/1/0", "p/1/1"],
        "2. Doubt": ["p/1/0", "p/1/-1"],
        "3a. Surrender 1": ["p/1/0", "p/1/2"],
        "3b. Surrender 2": ["p/1/0", "p/1/-2"],
        "4a. Sadness": ["p/1/0", "p/1/3"],
        "4b. Call": ["p/1/0", "p/1/-3"],
        "5. Unfinished": ["p/1/0", "p/1/5"],
        "6a. Question": ["p/1/0", "p/1/7"],
        "6b. Agreement": ["p/1/0", "p/1/-7"],
        "7a. Wonder": ["p/1/0", "p/1/9"],
        "7b. Begging": ["p/1/0", "p/1/-9"],
        "8. Insistence": ["p/1/0", "p/1/11"],
        "9. Leap": ["p/1/0", "p/1/12"],
      },
      "Scales": {
        "Major scale": ["p/1/0", "p/1/2", "p/1/4", "p/1/5", "p/1/7", "p/1/9", "p/1/11", "p/1/12"],
        "Natural minor": ["p/1/0", "p/1/2", "p/1/3", "p/1/5", "p/1/7", "p/1/8", "p/1/10", "p/1/12"],
        "Melodic minor": ["p/1/0", "p/1/2", "p/1/3", "p/1/5", "p/1/7", "p/1/9", "p/1/11", "p/1/12"],
        "Harmonic minor": ["p/1/0", "p/1/2", "p/1/3", "p/1/5", "p/1/7", "p/1/8", "p/1/11", "p/1/12"],
        "Pentatonic": ["p/1/0", "p/1/3", "p/1/5", "p/1/7", "p/1/10", "p/1/12"],
        "Major Bebop": ["p/1/0", "p/1/2", "p/1/4", "p/1/5", "p/1/7", "p/1/8", "p/1/9", "p/1/11", "p/1/12"],
        "Minor Bebop": ["p/1/0", "p/1/2", "p/1/3", "p/1/5", "p/1/7", "p/1/8", "p/1/9", "p/1/10", "p/1/12"]
      },
      "Cadences": {
        "Cadence 1": ["p/4/8", "p/4/10", "p/4/12"],
        "Cadence 2": ["p/1/3", "p/1/2", "p/1/0", "p/1/-2", "p/4/0"],
        "Cadence 3": ["p/1/0", "p/1/3", "p/1/0", "p/1/-2", "p/4/0"],
        "Cadence 4": ["p/4/3", "p/4/5", "p/4/0"],
        "Layla": ["e/1/-", "e/1/-", "p/1/0", "p/1/3", "p/1/5", "p/1/8", "p/1/5", "p/1/3", "p/8/5"]
      },
      "Motifs": {
        "Ave Maria": ["p/1/0", "p/1/3", "p/1/7", "p/1/12", "p/1/7", "p/1/3"],
        "Ave Wonder": ["p/1/0", "p/1/3", "p/1/7", "p/1/9", "p/1/7", "p/1/3"],
        "3-step Wave": ["p/1/0", "p/1/3", "p/1/0", "p/1/0", "p/1/3", "p/1/0"],
        "EDM": ["p/1/0", "p/1/3", "p/1/0", "p/1/2", "p/1/0", "p/1/3", "p/1/0", "p/1/2"],
        "Spy clock": ["p/1/0", "p/1/1", "p/1/2", "p/1/1", "p/1/0", "p/1/1", "p/1/2", "p/1/1"],
        "Dies Irae": ["p/1/3", "p/1/2", "p/1/3", "p/1/0", "p/1/2", "p/1/-2", "p/1/0", "p/1/0"],
        "Dies Irae Half": ["p/1/3", "p/1/2", "p/1/3", "p/1/0", "p/1/3", "p/1/2", "p/1/3", "p/1/0"],
        "Requiem for a Dream": ["p/1/3", "p/1/2", "p/1/0", "p/1/-5", "p/1/3", "p/1/2", "p/1/0", "p/1/-5"],
        "Super Fighter": ["p/2/0", "r/1/3", "r/1/5", "p/2/0", "r/1/3", "r/1/5", "p/2/-4", "r/1/2", "r/1/3", "p/2/-4", "r/1/3", "r/1/-2"],
        "Canon": ["p/1/12", "p/1/7", "p/1/9", "p/1/4", "p/1/5", "p/1/0", "p/1/5", "p/1/7"],
        "Suspense 1": ["p/1/0", "p/1/2", "p/1/3", "p/1/2", "p/1/0", "p/1/2", "p/1/3", "p/1/2"],
        "Suspense 2": ["p/1/0", "p/1/2", "p/1/3", "p/1/5", "p/1/0", "p/1/2", "p/1/3", "p/1/5"],
        "Suspense 3": ["p/1/0", "p/1/2", "p/1/3", "p/1/5", "p/1/7", "p/1/5", "p/1/3", "p/1/2"],
        "Suspense 4": ["p/1/0", "p/1/7", "p/1/8", "p/1/7", "p/1/0", "p/1/7", "p/1/8", "p/1/7"],
        "Suspense 5": ["p/1/0", "p/1/3", "p/1/2", "p/1/1", "p/1/0", "p/1/3", "p/1/2", "p/1/1"],
        "Demon Slayer": ["p/1/12", "p/1/7", "p/1/8", "p/1/7", "p/1/12", "p/1/7", "p/1/8", "p/1/7"],
        "Inferno": ["p/1/0", "p/1/2", "p/1/3", "p/1/5", "p/1/7", "p/1/8", "p/1/10", "p/1/12"],
        "SCQJF": ["p/1/0", "p/1/2", "p/1/3", "p/1/7", "p/1/0", "p/1/2", "p/1/3", "p/1/7"],
        "Living on a Prayer": ["r/1/12", "r/1/12", "p/1/7", "p/1/10", "r/1/12", "r/1/12", "p/1/7", "p/1/10"],
        "American Indian": ["p/1/0", "r/1/2", "r/1/2", "r/1/2", "p/1/5", "r/1/2", "r/1/2", "r/1/2"],
        "Disco": ["p/1/0", "p/1/3", "p/6/5", "p/1/5", "p/1/3", "p/6/0"]
      },
      "Progressions": {
        "Ballad 1": ["p/4/12", "p/4/8", "p/4/3", "p/4/10"],
        "Ballad 2": ["p/4/0", "p/4/-4", "p/4/3", "p/4/-2"],
        "Ballad 3a": ["p/4/3", "p/4/0", "p/4/-4", "p/4/-2"],
        "Ballad 3b": ["p/4/0", "p/4/-4", "p/4/3", "p/4/2"],
        "Ballad 4": ["p/4/0", "p/4/5", "p/4/9", "p/4/7"],
        "Blues Walk": ["p/4/12", "p/4/10", "p/4/8", "p/4/7"],
        "Zombie": ["p/4/0", "p/4/10", "p/4/3", "p/4/2"],
        "Teenager in love": ["p/4/12", "p/4/9", "p/4/5", "p/4/7"],
        "Half Canon": ["p/4/5", "p/4/0", "p/4/2", "p/4/-2"]
      }
    }
    """
}

//
//  Segment.swift
//  Moves
//
//  Created by Victor Noagbodji on 5/28/25.
//

import SwiftUI

struct Segment: Identifiable, Codable, Hashable {
    var id = UUID()
    var movement: Movement
    var length: Int
    var note: String? = nil
}

//
//  SegmentBlock.swift
//  Moves
//
//  Created by Victor Noagbodji on 5/28/25.
//

import SwiftUI

struct SegmentBlock: View {
    @Binding var segment: Segment
    var isSelected: Bool
    var isEven: Bool
    let onTap: () -> Void

    var body: some View {
        VStack {
            Text("\(segment.note ?? "")")
                .font(.caption)

            HStack(spacing: 2) {
                ForEach(0..<segment.length, id: \.self) { _ in
                    Rectangle()
                        .foregroundStyle(isEven ? .primary : .secondary)
                        .frame(width: 30, height: 30)
                }
            }
            .foregroundStyle(segment.movement.color())
        }
        .onTapGesture { onTap() }
    }
}

//
//  Sidebar.swift
//  Moves
//
//  Created by Victor Noagbodji on 6/3/25.
//

import SwiftUI

struct Sidebar: View {
    @Binding var preset: Preset?
    @State private var groupedPresets: [String: [Preset]] = [:]

    var body: some View {
        List(selection: $preset) {
            ForEach(groupedPresets.keys.sorted(), id: \.self) { section in
                sectionView(for: section)
            }
        }
        .onAppear {
            groupedPresets = PresetManager.shared.loadPresets()
        }
    }

    @ViewBuilder
    private func sectionView(for section: String) -> some View {
        let presets = groupedPresets[section] ?? []
        Section(header: Text("\(section) (\(presets.count))")) {
            ForEach(presets) { p in
                NavigationLink(value: p) {
                    Text(p.name)
                }
            }
        }
    }
}

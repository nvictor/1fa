//
//  ContentView.swift
//  Parts
//
//  Created by Victor Noagbodji on 5/4/25.
//

import SwiftUI

struct ContentView: View {
    @State private var preset: Preset? = nil

    @State private var segments: [Segment] = [
        Segment(part: .empty, length: 4),
        Segment(part: .empty, length: 4)
    ]

    var effectiveSegments: Binding<[Segment]> {
        Binding(
            get: { preset?.segments ?? segments },
            set: { newValue in
                if preset != nil {
                    preset = Preset(id: preset!.id, name: preset!.name, segments: newValue)
                } else {
                    segments = newValue
                }
            }
        )
    }

    @State private var selectedSegmentID: UUID? = nil
    @State private var showInspector = false

    var body: some View {
        NavigationSplitView {
            Sidebar(preset: $preset)
        } detail: {
            if preset != nil {
                Editor(
                    segments: effectiveSegments,
                    selectedSegmentID: $selectedSegmentID
                )
            } else {
                Text("Select a preset")
            }
        }
        .inspector(isPresented: $showInspector) {
            Inspector(segment: Binding(
                get: {
                    effectiveSegments.wrappedValue.first { $0.id == selectedSegmentID }
                },
                set: { newSegment in
                    guard let newSegment, let id = selectedSegmentID else { return }
                    if let index = effectiveSegments.wrappedValue.firstIndex(where: { $0.id == id }) {
                        effectiveSegments.wrappedValue[index] = newSegment
                    }
                }
            ))
        }
        .toolbar {
            ToolbarItem {
                Button {
                    ImageExporter.export(segments: effectiveSegments.wrappedValue)
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
    }
}

#Preview {
    ContentView()
}

//
//  Editor.swift
//  Parts
//
//  Created by Victor Noagbodji on 6/2/25.
//

import SwiftUI

struct Editor: View {
    @Binding var segments: [Segment]
    @Binding var selectedSegmentID: UUID?

    private func groupedSegments() -> [[Int]] {
        var rows: [[Int]] = []
        var currentRow: [Int] = []
        var currentLength = 0

        for index in segments.indices {
            let length = segments[index].length

            if currentLength + length > 16 {
                rows.append(currentRow)
                currentRow = []
                currentLength = 0
            }

            currentRow.append(index)
            currentLength += length
        }

        if !currentRow.isEmpty {
            rows.append(currentRow)
        }

        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(groupedSegments(), id: \.self) { rowIndices in
                HStack(spacing: 2) {
                    ForEach(rowIndices, id: \.self) { index in
                        SegmentBlock(
                            segment: $segments[index],
                            isSelected: selectedSegmentID == segments[index].id,
                            isEven: index.isMultiple(of: 2),
                            onTap: {
                                let id = segments[index].id
                                selectedSegmentID = (selectedSegmentID == id) ? nil : id
                            }
                        )
                    }
                }
            }
        }
        .padding()
    }
}

//
//  ImageExporter.swift
//  Parts
//
//  Created by Victor Noagbodji on 6/8/25.
//

import SwiftUI
import AppKit

struct ImageExporter {
    @MainActor
    static func export(segments: [Segment], fileName: String = "parts.png") {
        let view = Editor(segments: .constant(segments), selectedSegmentID: .constant(nil))
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
//  Parts
//
//  Created by Victor Noagbodji on 6/2/25.
//

import SwiftUI

struct Inspector: View {
    @Binding var segment: Segment?

    var body: some View {
        Form {
            if let segment = segment {
                Section("Settings") {
                    Picker("Part", selection: Binding(
                        get: { segment.part },
                        set: { newValue in
                            self.segment?.part = newValue
                        })
                    ) {
                        ForEach(Part.allCases, id: \.self) { part in
                            Text(part.rawValue.capitalized).tag(part)
                        }
                    }

                    Picker("Bars", selection: Binding(
                        get: { self.segment?.length ?? 1 },
                        set: { newValue in
                            self.segment?.length = newValue
                        })
                    ) {
                        ForEach(1...16, id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                }
            } else {
                Text("No segment selected.")
            }

            Section("Debug") {
                Button("Reset Presets") {
                    UserDefaults.standard.removeObject(forKey: "PartsPresets")
                }
            }
        }
        .padding()
    }
}

//
//  Part.swift
//  Parts
//
//  Created by Victor Noagbodji on 5/4/25.
//

import SwiftUI

enum Part: String, CaseIterable, Codable {
    case intro, verse, chorus, bridge, outro, refrain, build, coda, tag, empty

    func color() -> Color {
        switch self {
        case .intro: return .purple
        case .verse: return .cyan
        case .chorus: return .pink
        case .bridge: return .orange
        case .outro: return .purple
        case .refrain: return .green
        case .build: return .blue
        case .coda: return .yellow
        case .tag: return .brown
        case .empty: return .gray.opacity(0.2)
        }
    }
}

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
//  PartsApp.swift
//  Parts
//
//  Created by Victor Noagbodji on 5/4/25.
//

import SwiftUI

@main
struct PartsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

//
//  Preset.swift
//  Parts
//
//  Created by Victor Noagbodji on 6/2/25.
//

import SwiftUI

struct Preset: Identifiable, Codable, Hashable {
    var id = UUID()
    let name: String
    let segments: [Segment]
}

//
//  PresetManager.swift
//  Parts
//
//  Created by Victor Noagbodji on 6/2/25.
//

import Foundation

class PresetManager {
    static let shared = PresetManager()
    private let defaultsKey = "PartsPresets"
    
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
                    let parts = value.split(separator: "/")
                    let part = Part(rawValue: String(parts[0])) ?? .empty
                    let bars = Int(parts[1]) ?? 4
                    return Segment(part: part, length: bars)
                }
                return Preset(name: name, segments: segments)
            }
            .sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
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
      "Songs": {
        "AAA": ["intro/4", "verse/8", "verse/8", "verse/8", "outro/4"],
        "AABA": ["intro/4", "verse/8", "verse/8", "bridge/8", "verse/8", "outro/4"],
        "ABABCB short": ["intro/4", "verse/8", "chorus/8", "verse/8", "chorus/8", "bridge/4", "chorus/8", "outro/4"],
        "ABABCB long": ["intro/8", "verse/16", "chorus/16", "verse/16", "chorus/16", "bridge/8", "chorus/16", "outro/4"],
        "12-bar blues": ["intro/4", "verse/4", "verse/2", "verse/1", "verse/1", "verse/2", "outro/4"]
      },
      "Toolbox": {
        "Reset": ["empty/4", "empty/4", "empty/4", "empty/4"]
      }
    }
    """
}

//
//  Segment.swift
//  Parts
//
//  Created by Victor Noagbodji on 5/4/25.
//

import SwiftUI

struct Segment: Identifiable, Codable, Hashable {
    var id = UUID()
    var part: Part
    var length: Int
}

//
//  SegmentBlock.swift
//  Parts
//
//  Created by Victor Noagbodji on 5/4/25.
//

import SwiftUI

struct SegmentBlock: View {
    @Binding var segment: Segment
    var isSelected: Bool
    var isEven: Bool
    var onTap: () -> Void

    var body: some View {
        VStack {
            Text("\(segment.part.rawValue.capitalized)")
                .font(.caption)
                .foregroundStyle(isSelected ? .primary : .secondary)

            HStack(spacing: 2) {
                ForEach(0..<segment.length, id: \.self) { _ in
                    Rectangle()
                        .foregroundStyle(isEven ? .primary : .secondary)
                        .frame(width: 30, height: 30)
                }
            }
            .foregroundStyle(segment.part.color())
        }
        .onTapGesture { onTap() }
    }
}

//
//  Sidebar.swift
//  Parts
//
//  Created by Victor Noagbodji on 6/2/25.
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

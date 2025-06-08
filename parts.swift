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
        Segment(part: .empty, barCount: 4),
        Segment(part: .empty, barCount: 4),
        Segment(part: .empty, barCount: 4),
        Segment(part: .empty, barCount: 4)
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
            Editor(
                segments: effectiveSegments,
                selectedSegmentID: $selectedSegmentID
            )
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

    var body: some View {
        ScrollView(.horizontal) {
            HStack {
                ForEach(segments.indices, id: \.self) { index in
                    SegmentBlock(
                        segment: $segments[index],
                        isSelected: selectedSegmentID == segments[index].id,
                        onSelect: {
                            let id = segments[index].id
                            selectedSegmentID = (selectedSegmentID == id) ? nil : id
                        }
                    )
                }
            }
            .padding()
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

                    Slider(value: Binding(
                        get: { Double(self.segment?.barCount ?? 1) },
                        set: { newValue in
                            self.segment?.barCount = Int(newValue)
                        }
                    ), in: 1...16, step: 1, label: { Text("Bars") })
                }
            } else {
                Text("No segment selected.")
            }

            Section("Debug") {
                Button("Reset Presets") {
                    UserDefaults.standard.removeObject(forKey: "savedPresets")
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

enum Part: String, CaseIterable, Identifiable, Codable {
    case intro, verse, chorus, bridge, outro, refrain, build, coda, tag, empty

    var id: String { rawValue }

    var color: Color {
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

struct Preset: Identifiable, Codable {
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
                    return Segment(part: part, barCount: bars)
                }
                return Preset(name: name, segments: segments)
            }
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

struct Segment: Identifiable, Codable {
    var id = UUID()
    var part: Part
    var barCount: Int
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
    var onSelect: () -> Void

    let barWidth: CGFloat = 20

    var body: some View {
        VStack {
            Rectangle()
                .fill(segment.part.color)
                .frame(width: CGFloat(segment.barCount) * barWidth, height: 6)

            Text("\(segment.part.rawValue.capitalized):\(segment.barCount)")
                .font(.caption)
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
        }
        .onTapGesture { onSelect() }
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
        List {
            ForEach(groupedPresets.keys.sorted(), id: \.self) { section in
                Section(header: Text("\(section) (\(groupedPresets[section]?.count ?? 0))")) {
                    ForEach(groupedPresets[section] ?? []) { currentPreset in
                        Text(currentPreset.name)
                            .onTapGesture {
                                preset = currentPreset
                            }
                    }
                }
            }
        }
        .onAppear {
            groupedPresets = PresetManager.shared.loadPresets()
        }
    }
}

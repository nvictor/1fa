//
//  Beat.swift
//  Grooves
//
//  Created by Victor Noagbodji on 5/31/25.
//

import SwiftUI

enum Beat: CaseIterable {
    case empty, low, high

    func next() -> Beat {
        let all = Beat.allCases
        let idx = all.firstIndex(of: self) ?? 0
        return all[(idx + 1) % all.count]
    }
    
    func hierarchy() -> HierarchicalShapeStyle {
        switch self {
        case .empty: return .tertiary
        case .low: return .secondary
        case .high: return .primary
        }
    }
}

//
//  BeatBlock.swift
//  Grooves
//
//  Created by Victor Noagbodji on 5/31/25.
//

import SwiftUI

struct BeatBlock: View {
    let beat: Beat
    let isCurrent: Bool
    let onTap: () -> Void

    var body: some View {
        Rectangle()
            .foregroundStyle(beat.hierarchy())
            .overlay(
                Rectangle().stroke(isCurrent ? .white : Color.clear, lineWidth: 2)
            )
            .frame(width: 30, height: 30)
            .onTapGesture { onTap() }
    }
}

//
//  ContentView.swift
//  Grooves
//
//  Created by Victor Noagbodji on 5/31/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var playback = PlaybackManager()
    @State private var preset: Preset? = nil
    @State private var showInspector = false

    var body: some View {
        NavigationSplitView {
            Sidebar(preset: $preset)
        } detail: {
            if preset != nil {
                Editor(
                    groove: $playback.groove,
                    isPlaying: $playback.isPlaying,
                    currentBeat: $playback.currentBeat
                )
            } else {
                Text("Select a preset")
            }
        }
        .inspector(isPresented: $showInspector) {
            Inspector(groove: $playback.groove, bpm: $playback.bpm)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    playback.isPlaying ? playback.stop() : playback.start()
                }) {
                    Image(systemName: playback.isPlaying ? "stop.fill" : "play.fill")
                }
            }

            ToolbarItem {
                Button {
                    ImageExporter.export(groove: playback.groove)
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
            if let preset = newPreset {
                playback.groove = preset.beats + Array(repeating: .empty, count: 16 - preset.beats.count)
            }
        }
        .onAppear {
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 49 {
                    playback.isPlaying ? playback.stop() : playback.start()
                    return nil
                }
                return event
            }
        }
    }
}

#Preview {
    ContentView()
}

//
//  Editor.swift
//  Grooves
//
//  Created by Victor Noagbodji on 5/31/25.
//

import SwiftUI

struct Editor: View {
    @Binding var groove: [Beat]
    @Binding var isPlaying: Bool
    @Binding var currentBeat: Int

    var body: some View {
        Text("Beats: \(groove.count)")
            .font(.headline)
    
        HStack(spacing: 2) {
            ForEach(0..<groove.count, id: \.self) { index in
                BeatBlock(
                    beat: groove[index],
                    isCurrent: currentBeat == index && isPlaying,
                    onTap: {
                        groove[index] = groove[index].next()
                    },
                )
            }
        }
        .padding()
        .foregroundStyle(Color.accentColor)
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
//  GroovesApp.swift
//  Grooves
//
//  Created by Victor Noagbodji on 5/31/25.
//

import SwiftUI

@main
struct GroovesApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

//
//  ImageExporter.swift
//  Grooves
//
//  Created by Victor Noagbodji on 6/4/25.
//

import SwiftUI
import AppKit

struct ImageExporter {
    @MainActor
    static func export(groove: [Beat], fileName: String = "groove.png") {
        let view = Editor(
            groove: .constant(groove),
            isPlaying: .constant(false),
            currentBeat: .constant(0)
        )
        .padding()
        .fixedSize()

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
//  Grooves
//
//  Created by Victor Noagbodji on 5/31/25.
//

import SwiftUI

struct Inspector: View {
    @Binding var groove: [Beat]
    @Binding var bpm: Int

    private var bpmFormatter: NumberFormatter {
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.minimum = 40
        fmt.maximum = 300
        return fmt
    }
    
    var body: some View {
        Form {
            Section("Settings") {
                TextField("BPM", value: $bpm, formatter: bpmFormatter)
                    .onChange(of: bpm) { oldValue, newValue in
                        bpm = min(max(newValue, 40), 300)
                    }

                Picker("Beats", selection: Binding(
                    get: { groove.count },
                    set: { newValue in
                        if newValue < groove.count {
                            groove = Array(groove.prefix(newValue))
                        } else {
                            groove += Array(repeating: .empty, count: newValue - groove.count)
                        }
                    }
                )) {
                    ForEach(Array(stride(from: 4, through: 32, by: 4)), id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
            }

            Section("Debug") {
                Button("Reset Presets") {
                    UserDefaults.standard.removeObject(forKey: "GroovesPresets")
                }
            }
        }
        .padding()
    }
}

//
//  PlaybackManager.swift
//  Grooves
//
//  Created by Victor Noagbodji on 6/5/25.
//

import SwiftUI

class PlaybackManager: ObservableObject {
    @Published var isPlaying = false
    @Published var currentBeat = 0
    @Published var bpm: Int = 80
    @Published var groove: [Beat] = Array(repeating: .empty, count: 16)

    private var timer: Timer?
    private let soundService = SoundService()

    func start() {
        isPlaying = true
        currentBeat = 0
        playBeat(at: currentBeat)

        let interval = 60.0 / (Double(bpm) * 4)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            self.currentBeat = (self.currentBeat + 1) % self.groove.count
            self.playBeat(at: self.currentBeat)
        }
    }

    func stop() {
        isPlaying = false
        timer?.invalidate()
        timer = nil
        currentBeat = 0
    }

    private func playBeat(at index: Int) {
        let beat = groove[index]
        if beat == .low || beat == .high {
            soundService.play()
        }
    }
}

//
//  Preset.swift
//  Grooves
//
//  Created by Victor Noagbodji on 5/31/25.
//

import Foundation

struct Preset: Identifiable, Equatable, Hashable {
    let id = UUID()
    let name: String
    let beats: [Beat]
}

//
//  PresetManager.swift
//  Grooves
//
//  Created by Victor Noagbodji on 6/1/25.
//

import Foundation

class PresetManager {
    static let shared = PresetManager()
    private let defaultsKey = "GroovesPresets"

    private init() {}

    func loadPresets() -> [String: [Preset]] {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode([String: [PresetCodable]].self, from: data) {
            return saved.mapValues { codables in
                codables.map { $0.toPreset() }
                        .sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
            }
        } else {
            let defaultPresets = Self.defaultPresetJSON
            let decoded = try! JSONDecoder().decode([String: [String: [Int]]].self, from: defaultPresets.data(using: .utf8)!)
            let converted = decoded.mapValues { group in
                group.map { name, pattern in
                    Preset(name: name, beats: Self.convertToBeats(pattern))
                }
                .sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
            }
            savePresets(converted)
            return converted
        }
    }

    func savePresets(_ presets: [String: [Preset]]) {
        let codable = presets.mapValues { $0.map { PresetCodable(from: $0) } }
        if let data = try? JSONEncoder().encode(codable) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private static func convertToBeats(_ pattern: [Int]) -> [Beat] {
        pattern.flatMap { [Beat.high] + Array(repeating: .empty, count: $0 - 1) }
    }

    private struct PresetCodable: Codable {
        let name: String
        let beats: [Int]

        init(from preset: Preset) {
            self.name = preset.name
            self.beats = Self.convertFromBeats(preset.beats)
        }

        func toPreset() -> Preset {
            Preset(name: name, beats: PresetManager.convertToBeats(beats))
        }

        static func convertFromBeats(_ beats: [Beat]) -> [Int] {
            var result: [Int] = []
            var i = 0
            while i < beats.count {
                if beats[i] == .high {
                    var count = 1
                    i += 1
                    while i < beats.count && beats[i] == .empty {
                        count += 1
                        i += 1
                    }
                    result.append(count)
                } else {
                    i += 1
                }
            }
            return result
        }
    }

    private static let defaultPresetJSON = """
    {
      "American Indians": {
        "Groove 1": [2, 2, 4, 4, 4],
        "Groove 2": [2, 4, 4, 2, 4],
        "Groove 3": [4, 2, 4, 4, 2],
        "Groove 4": [4, 4, 2, 2, 4],
        "Groove 5": [4, 4, 4, 2, 2]
      },
      "Barbara Ann": {
        "Groove 1": [2, 2, 3, 2, 2, 1, 4],
        "Groove 2": [2, 2, 3, 2, 2, 1, 2, 2],
        "Groove 3": [2, 2, 3, 2, 2, 2, 2, 1]
      },
      "Battle": {
        "Groove 1": [1, 5, 1, 5, 1, 3],
        "Groove 2": [2, 2, 2, 3, 3],
        "Groove 3": [3, 3, 2, 2, 2],
        "Groove 4": [3, 3, 3, 3, 2, 2],
        "Groove 5": [4, 5, 3],
        "Groove 6": [5, 4, 3],
        "Groove 7": [6, 6, 2, 2],
        "Groove 8": [6, 6, 4],
        "Call of Duty": [1, 1, 4, 1, 1, 4, 1, 1, 2],
        "Terminator": [1, 2, 2, 1, 2, 2, 2]
      },
      "Funk": {
        "Groove  1": [2, 2, 2, 2, 2, 3, 3],
        "Groove  2": [3, 2, 2, 2, 3, 4],
        "Groove  3": [3, 3, 2, 2, 2, 2, 2],
        "Groove  4": [3, 3, 4, 2, 4],
        "Groove  5": [3, 3, 4, 6],
        "Groove  6": [3, 4, 4, 3, 2],
        "Groove  7": [4, 4, 3, 2, 3],
        "Groove  8": [4, 4, 3, 3, 2],
        "Groove  9": [4, 4, 3, 5],
        "Groove 10": [4, 6, 4, 2],
        "Groove 11": [5, 2, 5, 2, 2],
        "Groove 12": [6, 4, 6],
        "Groove 13": [8, 3, 3, 2]
      },
      "Minims": {
        "My Ego": [1, 1, 2, 4, 1, 1, 2, 4],
        "Your birthday": [2, 2, 4, 2, 2, 4]
      },
      "Rappers": {
        "DMX": [1, 1, 1, 1, 1, 1, 3, 2, 1, 4],
        "Lil Wayne": [1, 1, 1, 2, 1, 5, 2, 1, 2],
        "One T": [2, 2, 2, 2, 1, 1, 6],
        "Tupac": [1, 1, 1, 1, 1, 1, 1, 5, 4]
      },
      "Monkey King": {
        "Groove 1": [1, 1, 1, 1, 1, 1, 2, 1, 1, 2, 1, 1, 2],
        "Groove 2": [1, 1, 2, 1, 1, 2, 1, 1, 1, 1, 1, 1, 2],
        "Kill la Kill": [2, 2, 1, 1, 2, 1, 1, 1, 1, 1, 1, 2]
      },
      "Misc.": {
        "Sadness": [2, 2, 2, 2, 1, 2, 1, 4]
      },
      "Reggae": {
        "Groove 1": [2, 2, 2, 2, 2, 1, 2, 1, 2],
        "Groove 2": [2, 2, 2, 2, 2, 6],
        "Groove 3": [2, 6, 2, 6]
      },
      "Slows": {
        "Groove 1": [1, 1, 1, 3, 3, 3]
      },
      "Strums": {
        "Bluegrass": [4, 6, 2, 2, 2],
        "Boom Chicka": [4, 2, 2, 4, 2, 2],
        "Calypso": [4, 2, 4, 2, 2, 2],
        "Modern 1": [4, 3, 2, 1, 2, 4],
        "Modern 2": [4, 3, 1, 1, 1, 2, 4],
        "Modern 3": [2, 2, 3, 1, 1, 1, 2, 4],
        "Modern 4": [2, 2, 3, 1, 1, 1, 2, 2, 1, 1],
        "Waltz": [4, 4, 2, 6]
      },
      "Toolbox": {
        "Wholes": [16],
        "Minims": [8, 8],
        "Quarters": [4, 4, 4, 4],
        "8ths": [2, 2, 2, 2, 2, 2, 2, 2],
        "8ths dotted": [3, 3, 3, 3],
        "16ths": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
      },
      "Tresillo": {
        "Groove 1": [3, 1, 2, 2, 3, 1, 2, 2],
        "Groove 2": [3, 3, 5, 3, 2],
        "Cinquillo": [2, 1, 2, 1, 2, 2, 1, 2, 1, 2],
        "Zouk": [3, 3, 2, 3, 3, 2]
      }
    }
    """
}

//
//  Sidebar.swift
//  Grooves
//
//  Created by Victor Noagbodji on 5/31/25.
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

//
//  SoundService.swift
//  Grooves
//
//  Created by Victor Noagbodji on 5/31/25.
//

import Foundation
import AudioToolbox

class SoundService {
    private var tinkSoundID: SystemSoundID = 0

    init() {
        let url = URL(fileURLWithPath: "/System/Library/Sounds/Tink.aiff")
        AudioServicesCreateSystemSoundID(url as CFURL, &tinkSoundID)
    }

    deinit {
        AudioServicesDisposeSystemSoundID(tinkSoundID)
    }

    func play() {
        AudioServicesPlaySystemSound(tinkSoundID)
    }
}

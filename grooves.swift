// FILE: AudioEngineManager.swift
//
//  AudioEngineManager.swift
//  Grooves
//
//  Created by Victor Noagbodji on 9/6/25.
//

import Foundation
import AVFoundation

enum Instrument: String, CaseIterable, Identifiable {
    case piano = "Acoustic Grand Piano"
    case woodblock = "Woodblock"
    case taiko = "Taiko Drum"
    case drums = "Drums"

    var id: String { rawValue }

    var program: UInt8 {
        switch self {
        case .piano: return 0
        case .woodblock: return 115
        case .taiko: return 116
        case .drums: return 0 // Percussion bank
        }
    }

    var isPercussion: Bool {
        self == .drums
    }
}

class AudioEngineManager {
    static let shared = AudioEngineManager()

    private let engine = AVAudioEngine()
    private let sampler = AVAudioUnitSampler()

    private init() {
        setupAudioEngine()
    }

    private func setupAudioEngine() {
        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)

        do {
            try engine.start()
        } catch {
            print("❌ Failed to start AVAudioEngine: \(error)")
        }

        loadDefaultInstrument()
    }

    private func loadDefaultInstrument() {
        // Apple provides a built-in General MIDI SoundFont at this path:
        guard let url = Bundle.main.url(forResource: "gs_instruments", withExtension: "dls") ??
                        URL(string: "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls")
        else {
            print("⚠️ Could not find default instrument soundfont")
            return
        }

        do {
            try sampler.loadSoundBankInstrument(
                at: url,
                program: 0,        // Acoustic Grand Piano
                bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                bankLSB: UInt8(kAUSampler_DefaultBankLSB)
            )
        } catch {
            print("⚠️ Failed to load default instrument: \(error)")
        }
    }

    func loadInstrument(_ instrument: Instrument) {
        guard let url = Bundle.main.url(forResource: "gs_instruments", withExtension: "dls") ??
                        URL(string: "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls")
        else { return }

        do {
            try sampler.loadSoundBankInstrument(
                at: url,
                program: instrument.program,
                bankMSB: instrument.isPercussion
                    ? UInt8(kAUSampler_DefaultPercussionBankMSB)
                    : UInt8(kAUSampler_DefaultMelodicBankMSB),
                bankLSB: UInt8(kAUSampler_DefaultBankLSB)
            )
            print("🎹 Loaded instrument: \(instrument.rawValue)")
        } catch {
            print("⚠️ Failed to load instrument \(instrument.rawValue): \(error)")
        }
    }
    
    func play(note: UInt8, velocity: UInt8) {
        sampler.startNote(note, withVelocity: velocity, onChannel: 0)
    }

    func stop(note: UInt8) {
        sampler.stopNote(note, onChannel: 0)
    }
}


// FILE: Beat.swift
//
//  Beat.swift
//  Grooves
//
//  Created by Victor Noagbodji on 5/31/25.
//

import SwiftUI

enum Beat: Equatable, Codable, Hashable {
    case empty
    case low(velocity: Int)
    case high(velocity: Int)
    
    func next() -> Beat {
        switch self {
        case .empty:
            return .low(velocity: 80)
        case .low:
            return .high(velocity: 100)
        case .high:
            return .empty
        }
    }

    var velocity: Int? {
        switch self {
        case .low(let v), .high(let v): return v
        case .empty: return nil
        }
    }

    func hierarchy() -> HierarchicalShapeStyle {
        switch self {
        case .empty: return .tertiary
        case .low: return .secondary
        case .high: return .primary
        }
    }

    func velocityColor(base: Color = .blue) -> Color {
        guard let velocity = self.velocity else {
            return .gray.opacity(0.2)
        }
        let normalized = Double(velocity) / 127.0
        // Brighter color for higher velocities
        return base.opacity(0.4 + 0.6 * normalized)
    }
}


// FILE: BeatBlock.swift
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
        VStack {
            Rectangle()
                .fill(beat.velocityColor(base: .blue))
                .overlay(
                    Rectangle().stroke(isCurrent ? .white : Color.clear, lineWidth: 2)
                )
                .frame(width: 30, height: 30)
                .onTapGesture { onTap() }
            
            Text("\(beat.velocity ?? 0)")
        }
    }
}


// FILE: ContentView.swift
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
            Inspector(playback: playback)
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
                    MIDIExporter.export(groove: playback.groove, bpm: playback.bpm, timeSig: playback.timeSignature)
                } label: {
                    Image(systemName: "music.note.list")
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
                playback.applyVelocities()
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


// FILE: Editor.swift
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


// FILE: Grooves.entitlements
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


// FILE: GroovesApp.swift
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


// FILE: ImageExporter.swift
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


// FILE: Inspector.swift
//
//  Inspector.swift
//  Grooves
//
//  Created by Victor Noagbodji on 5/31/25.
//

import SwiftUI

struct Inspector: View {
    @ObservedObject var playback: PlaybackManager

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
                TextField("BPM", value: $playback.bpm, formatter: bpmFormatter)
                    .onChange(of: playback.bpm) { oldValue, newValue in
                        playback.bpm = min(max(newValue, 40), 300)
                    }

                Picker("Beats", selection: Binding(
                    get: { playback.groove.count },
                    set: { newValue in
                        if newValue < playback.groove.count {
                            playback.groove = Array(playback.groove.prefix(newValue))
                        } else {
                            playback.groove += Array(repeating: .empty, count: newValue - playback.groove.count)
                        }
                    }
                )) {
                    ForEach(Array(stride(from: 4, through: 32, by: 4)), id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
            }

            Section("Instrument") {
                Picker("Sound", selection: $playback.instrument) {
                    ForEach(Instrument.allCases) { instr in
                        Text(instr.rawValue).tag(instr)
                    }
                }
            }

            Section("Velocity") {
                Picker("Style", selection: $playback.grooveStyle) {
                    ForEach(GrooveStyle.allCases) { style in
                        Text(style.rawValue.capitalized).tag(style)
                    }
                }

                Picker("Signature", selection: $playback.timeSignature) {
                    ForEach(TimeSignature.allCases) { ts in
                        Text(ts.rawValue).tag(ts)
                    }
                }

                Picker("Contour", selection: $playback.contour) {
                    ForEach(Contour.allCases) { c in
                        Text(c.rawValue.capitalized).tag(c)
                    }
                }

                HStack {
                    Text("Base Velocity")
                    Slider(value: Binding(
                        get: { Double(playback.baseVelocity) },
                        set: { playback.baseVelocity = Int($0) }
                    ), in: 1...127)
                    Text("\(playback.baseVelocity)")
                        .frame(width: 30, alignment: .leading)
                }

                Button("Regenerate Velocities") {
                    playback.applyVelocities()
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


// FILE: MIDIExporter.swift
//
//  MIDIExporter.swift
//  Grooves
//
//  Created by Victor Noagbodji on 5/31/25.
//

import Foundation
import AudioToolbox
import AppKit

struct MIDIExporter {
    static func export(groove: [Beat], bpm: Int, timeSig: TimeSignature) {
        var seq: MusicSequence?
        guard ok(NewMusicSequence(&seq), "NewMusicSequence"), let sequence = seq else { return }

        var track: MusicTrack?
        guard ok(MusicSequenceNewTrack(sequence, &track), "MusicSequenceNewTrack"),
              let musicTrack = track else { return }

        var tempoTrack: MusicTrack?
        ok(MusicSequenceGetTempoTrack(sequence, &tempoTrack), "MusicSequenceGetTempoTrack")
        if let tempoTrack {
            ok(MusicTrackNewExtendedTempoEvent(tempoTrack, 0.0, Double(bpm)),
               "MusicTrackNewExtendedTempoEvent")
        }

        let barBeats: Double = {
            switch timeSig {
            case .fourFour:  return 4.0
            case .threeFour: return 3.0
            case .sixEight:  return 3.0   // dotted-quarter = 1.5 qn, 2 beats per bar → 3 qn total
            case .nineEight: return 4.5   // 3 dotted-quarters → 4.5 qn total
            }
        }()

        // Each grid step duration (in beats), with a simple gate so notes don’t overlap
        let steps = max(1, groove.count)
        let stepBeats = barBeats / Double(steps)
        let gate: Double = 0.90
        let noteDurBeats = max(0.01, stepBeats * gate)

        // Write notes
        for (i, beat) in groove.enumerated() {
            guard let velocity = beat.velocity else { continue }

            let startBeat = Double(i) * stepBeats
            var msg = MIDINoteMessage(
                channel: 0,
                note: 60,                         // Middle C for now
                velocity: UInt8(clamping: velocity),
                releaseVelocity: 0,
                duration: Float32(noteDurBeats)   // duration in beats
            )
            ok(MusicTrackNewMIDINoteEvent(musicTrack, startBeat, &msg), "MusicTrackNewMIDINoteEvent")
        }

        let panel = NSSavePanel()
        panel.title = "Export MIDI"
        panel.allowedContentTypes = [.midi]
        panel.nameFieldStringValue = "groove.mid"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            // Resolution (ticks per quarter) for the .mid file
            let ppq: Int16 = 480
            let status = MusicSequenceFileCreate(sequence, url as CFURL, .midiType, .eraseFile, ppq)
            if status != noErr {
                print("❌ MusicSequenceFileCreate failed: \(status)")
            } else {
                print("✅ MIDI exported to \(url.path)")
            }
        }
    }

    @discardableResult
    private static func ok(_ status: OSStatus, _ where_: String) -> Bool {
        if status != noErr {
            print("❌ \(where_) failed with status \(status)")
            return false
        }
        return true
    }
}


// FILE: PlaybackManager.swift
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
    @Published var instrument: Instrument = .piano {
        didSet { audioEngine.loadInstrument(instrument) }
    }
    @Published var grooveStyle: GrooveStyle = .rock
    @Published var timeSignature: TimeSignature = .fourFour
    @Published var baseVelocity: Int = 90
    @Published var contour: Contour = .normal

    private var timer: Timer?
    private let soundService = SoundService()
    private let audioEngine = AudioEngineManager.shared

    func start() {
        applyVelocities()

        isPlaying = true
        currentBeat = 0
        playBeat(at: currentBeat)

        let interval = 60.0 / (Double(bpm) * 4)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            self.currentBeat = (self.currentBeat + 1) % self.groove.count
            self.playBeat(at: self.currentBeat)
        }
    }

    func applyVelocities() {
        let velocities = VelocityGenerator.generate(
            groove: groove,
            style: grooveStyle,
            base: baseVelocity,
            timeSig: timeSignature,
            contour: contour
        )
        for i in 0..<groove.count {
            switch groove[i] {
            case .low: groove[i] = .low(velocity: velocities[i])
            case .high: groove[i] = .high(velocity: velocities[i])
            case .empty: break
            }
        }
    }

    func stop() {
        isPlaying = false
        timer?.invalidate()
        timer = nil
        currentBeat = 0
    }

    private func playBeat(at index: Int) {
        playBeatMIDI(at: index)
    }

    private func playBeatSound(at index: Int) {
        let beat = groove[index]
        if let velocity = beat.velocity, velocity > 0 {
            soundService.play()
        }
    }

    private func playBeatMIDI(at index: Int) {
        let beat = groove[index]
        if let velocity = beat.velocity {
            // Pick note (Middle C for now)
            audioEngine.play(note: 60, velocity: UInt8(velocity))
        }
    }
}


// FILE: Preset.swift
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


// FILE: PresetManager.swift
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
        pattern.flatMap { [Beat.high(velocity: 100)] + Array(repeating: .empty, count: $0 - 1) }
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
                if beats[i] == .high(velocity: 100) {
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


// FILE: Sidebar.swift
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


// FILE: SoundService.swift
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


// FILE: VelocityGenerator.swift
//
//  VelocityGenerator.swift
//  Grooves
//
//  Created by Victor Noagbodji on 9/6/25.
//

import Foundation

enum GrooveStyle: String, CaseIterable, Identifiable {
    case rock, funk, jazz, bossa, metal, folk
    var id: String { rawValue }
}

enum TimeSignature: String, CaseIterable, Identifiable {
    case fourFour = "4/4"
    case threeFour = "3/4"
    case sixEight = "6/8"
    case nineEight = "9/8"
    var id: String { rawValue }
}

enum Contour: String, CaseIterable, Identifiable {
    case rising, normal, falling, dip
    var id: String { rawValue }
}

enum AccentStrength { case strong, medium }

struct VelocityGenerator {
    struct StyleRule {
        let accentBoost: Int
        let mediumBoost: Int
        let weakAdjust: Int
        let humanize: Int
    }

    static let rules: [GrooveStyle: StyleRule] = [
        .rock:  StyleRule(accentBoost: 14, mediumBoost: 8, weakAdjust: -6, humanize: 5),
        .funk:  StyleRule(accentBoost: 16, mediumBoost: 10, weakAdjust: -10, humanize: 7),
        .jazz:  StyleRule(accentBoost: 8,  mediumBoost: 4, weakAdjust: -4, humanize: 6),
        .bossa: StyleRule(accentBoost: 10, mediumBoost: 6, weakAdjust: -8, humanize: 5),
        .metal: StyleRule(accentBoost: 6,  mediumBoost: 4, weakAdjust: -3, humanize: 3),
        .folk:  StyleRule(accentBoost: 12, mediumBoost: 6, weakAdjust: -5, humanize: 4),
    ]

    // Accent patterns based on time signature
    static func accentPattern(for sig: TimeSignature, length: Int) -> [Int: AccentStrength] {
        switch sig {
        case .fourFour:
            let step = length / 4
            return [0: .strong, 2*step: .medium]
        case .threeFour:
            _ = length / 3
            return [0: .strong]
        case .sixEight:
            let step = length / 6
            return [0: .strong, 3*step: .medium]
        case .nineEight:
            let step = length / 9
            return [0: .strong, 3*step: .medium, 6*step: .medium]
        }
    }

    // Apply contour shaping
    static func applyContour(_ velocities: [Int], contour: Contour) -> [Int] {
        let n = velocities.count
        guard n > 0 else { return velocities }

        switch contour {
        case .rising:
            return velocities.enumerated().map { i, v in
                let factor = Double(i+1) / Double(n)
                return Int(Double(v) * (0.7 + 0.3 * factor))
            }
        case .falling:
            return velocities.enumerated().map { i, v in
                let factor = 1.0 - Double(i) / Double(n)
                return Int(Double(v) * (0.7 + 0.3 * factor))
            }
        case .normal: // Gaussian peak in the middle
            return velocities.enumerated().map { i, v in
                let x = Double(i - n/2) / Double(n/4)
                let gaussian = exp(-0.5 * x * x) // 0..1
                return Int(Double(v) * (0.7 + 0.3 * gaussian))
            }
        case .dip: // Lower velocities in the middle
            return velocities.enumerated().map { i, v in
                let x = Double(i - n/2) / Double(n/4)
                let gaussian = exp(-0.5 * x * x)
                let dipFactor = 1.0 - 0.3 * gaussian
                return Int(Double(v) * dipFactor)
            }
        }
    }

    static func generate(
        groove: [Beat],
        style: GrooveStyle,
        base: Int,
        timeSig: TimeSignature,
        contour: Contour
    ) -> [Int] {
        guard let rule = rules[style] else { return [] }
        let accents = accentPattern(for: timeSig, length: groove.count)
        var velocities: [Int] = []

        for i in 0..<groove.count {
            let slot = groove[i]
            if case .empty = slot {
                velocities.append(0)
                continue
            }

            var v = base
            if let strength = accents[i] {
                switch strength {
                case .strong: v += rule.accentBoost
                case .medium: v += rule.mediumBoost
                }
            } else {
                switch slot {
                case .low: v += rule.weakAdjust
                case .high: break
                case .empty: break
                }
            }

            // Clamp
            v = max(1, min(127, v))

            // Humanize
            let jitter = Int.random(in: -rule.humanize...rule.humanize)
            v = max(1, min(127, v + jitter))

            velocities.append(v)
        }

        return applyContour(velocities, contour: contour)
    }
}

// FILE: BGLayeredWaves.swift
//
//  BGLayeredWaves.swift
//  Vignette
//
//  Created by Victor Noagbodji on 5/16/25.
//

import SwiftUI

struct BGLayeredWaves: View {
    let count: Int
    let baseColor: Color
    let backgroundColor: Color
    let waves: [WaveProps]

    init() {
        let count = Int.random(in: 2...8)
        let hue = Double.random(in: 0...1)
        let saturation = Double.random(in: 0.5...1)
        let brightness = Double.random(in: 0.7...1)

        let baseColor = Color(hue: hue, saturation: saturation, brightness: brightness)
        let backgroundColor = Color(hue: hue, saturation: saturation * 0.3, brightness: min(brightness * 1.2, 1.0))

        let waves = (0..<count).map { index in
            let saturationStep = saturation * ((Double(index) * 0.1)
            let brightnessStep = brightness * ((Double(index) * 0.1)

            return WaveProps(
                color: Color(hue: hue, saturation: saturationStep, brightness: brightnessStep),
                offset: CGFloat(index * 30),
                control1: CGPoint(
                    x: 0.3 + Double.random(in: -0.1...0.1),
                    y: Double.random(in: -100...100)
                ),
                control2: CGPoint(
                    x: 0.7 + Double.random(in: -0.1...0.1),
                    y: Double.random(in: -100...100)
                )
            )
        }

        self.count = count
        self.baseColor = baseColor
        self.backgroundColor = backgroundColor
        self.waves = waves
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            backgroundColor.ignoresSafeArea()
            ForEach(0..<count, id: \.self) { index in
                Wave(
                    color: waves[index].color,
                    offset: waves[index].offset,
                    control1: waves[index].control1,
                    control2: waves[index].control2
                )
            }
        }
    }
}

struct WaveProps {
    var color: Color
    var offset: CGFloat
    var control1: CGPoint
    var control2: CGPoint
}

struct Wave: View {
    var color: Color
    var offset: CGFloat
    var control1: CGPoint
    var control2: CGPoint

    var body: some View {
        GeometryReader { geo in
            Path { path in
                let width = geo.size.width
                let height = geo.size.height

                path.move(to: CGPoint(x: 0, y: height - offset))
                path.addCurve(
                    to: CGPoint(x: width, y: height - offset),
                    control1: CGPoint(x: width * control1.x, y: height - offset + control1.y),
                    control2: CGPoint(x: width * control2.x, y: height - offset + control2.y))
                path.addLine(to: CGPoint(x: width, y: height))
                path.addLine(to: CGPoint(x: 0, y: height))
                path.closeSubpath()
            }
            .fill(color)
        }
    }
}

#Preview {
    BGLayeredWaves()
}

// FILE: BGLowPoly.swift
//
//  BGLowPoly.swift
//  Vignette
//
//  Created by Victor Noagbodji on 5/16/25.
//

import SwiftUI

struct BGLowPoly: View {
    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let colors = [Color.orange, Color.pink, Color.red, Color.purple]
                let step = 80.0

                for y in stride(from: 0, through: size.height, by: step) {
                    for x in stride(from: 0, through: size.width, by: step) {
                        let points = [
                            CGPoint(x: x, y: y),
                            CGPoint(x: x + step, y: y),
                            CGPoint(x: x, y: y + step)
                        ]
                        var path = Path()
                        path.addLines(points + [points[0]])

                        context.fill(path, with: .color(colors.randomElement()!.opacity(0.6)))
                    }
                }
            }
        }
    }
}

// FILE: BGRandom.swift
//
//  BGRandom.swift
//  Vignette
//
//  Created by Victor Noagbodji on 5/16/25.
//

import SwiftUI

struct BGRandom: View {
    enum BGStyle: CaseIterable {
        case layeredWaves, lowPoly, vanishingRays
    }

    let style: BGStyle

    init(style: BGStyle? = nil) {
        self.style = style ?? BGStyle.allCases.randomElement()!
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                switch style {
                case .layeredWaves:
                    BGLayeredWaves()
                case .lowPoly:
                    BGLowPoly()
                case .vanishingRays:
                    BGVanishingRays()
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

// FILE: BGVanishingRays.swift
//
//  BGVanishingRays.swift
//  Vignette
//
//  Created by Victor Noagbodji on 5/16/25.
//

import SwiftUI

struct BGVanishingRays: View {
    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let rays = 60
                let angleStep = .pi * 2 / Double(rays)
                let radius = max(size.width, size.height) * 2

                for i in 0..<rays {
                    let angle = Double(i) * angleStep
                    let end = CGPoint(x: center.x + cos(angle) * radius,
                                      y: center.y + sin(angle) * radius)

                    var path = Path()
                    path.move(to: center)
                    path.addLine(to: end)

                    context.stroke(path, with: .color(Color.cyan.opacity(0.1)), lineWidth: 3)
                }
            }
            .background(Color.cyan.opacity(0.2))
        }
    }
}

// FILE: ContentView.swift
//
//  ContentView.swift
//  Vignette
//
//  Created by Victor Noagbodji on 5/11/25.
//

import SwiftUI

struct ContentView: View {
    @State private var currentStep = 0
    @State private var style = BGRandom.BGStyle.allCases.randomElement()!
    @State private var setup = "What do you call a fake dad?"
    @State private var punchline = "A faux pa!"
    
    var body: some View {
        VStack {
            ZStack {
                Color.black.ignoresSafeArea()
                switch currentStep {
                case 0:
                    VStack {
                        TextField("Enter setup", text: $setup)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.title)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        TextField("Enter punchline", text: $punchline)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.title)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                    }
                case 1:
                    JokeView(style: style, setup: setup, punchline: punchline)
                default:
                    EmptyView()
                }
            }
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        currentStep -= 1
                    }
                    .padding()
                }
                Spacer()
                if currentStep < 1 {
                    Button("Next") {
                        currentStep += 1
                    }
                    .padding()
                }
                if currentStep == 1 {
                    Button("Random Background") {
                        style = BGRandom.BGStyle.allCases.randomElement()!
                    }
                    .padding()
                    Button("Export as PNG") {
                        let jokeView = JokeView(style: style, setup: setup, punchline: punchline)
                        ImageExporter.export(view: jokeView, size: CGSize(width: 800, height: 450))
                    }
                    .padding()
                }
            }
        }
    }
}

#Preview {
    ContentView()
}

// FILE: ImageExporter.swift
//
//  ImageExporter.swift
//  Vignette
//
//  Created by Victor Noagbodji on 5/13/25.
//

import SwiftUI
import AppKit

struct ImageExporter {
    @MainActor static func export<Content: View>(view: Content, size: CGSize, defaultFileName: String = "joke.png") {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))

        guard let nsImage = renderer.nsImage,
              let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            print("Failed to generate PNG data from view.")
            return
        }

        let savePanel = NSSavePanel()

        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = defaultFileName
        savePanel.canCreateDirectories = true

        if savePanel.runModal() == .OK, let url = savePanel.url {
            do {
                try pngData.write(to: url)
                print("PNG saved to: \(url)")
            } catch {
                print("Failed to save PNG: \(error)")
            }
        }
    }
}

// FILE: Info.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>UIAppFonts</key>
	<array>
		<string>CherryBombOne-Regular.ttf</string>
	</array>
</dict>
</plist>

// FILE: JokeView.swift
//
//  JokeView.swift
//  Vignette
//
//  Created by Victor Noagbodji on 5/11/25.
//

import SwiftUI

struct JokeView: View {
    let style: BGRandom.BGStyle
    let setup: String
    let punchline: String

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                BGRandom(style: style)
                VStack {
                    Text(setup)
                        .font(Font.custom("Cherry Bomb One", size: 48))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .kerning(8)
                        .withStroke()
                        .padding(.top, 30)
                    Spacer()
                    Text(punchline)
                        .font(Font.custom("Cherry Bomb One", size: 48))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .kerning(8)
                        .withStroke()
                        .padding(.bottom, 40)
                }
                .frame(width: 800, height: 450)
                .padding()
            }
            .frame(width: 800, height: 450)
        }
    }
}

// FILE: StrokeModifier.swift
//
//  StrokeModifier.swift
//  Vignette
//
//  Created by Victor Noagbodji on 5/13/25.
//

import SwiftUI

struct StrokeModifier: ViewModifier {
    var size: CGFloat
    var color: Color

    func body(content: Content) -> some View {
        content
            .padding(size)
            .background(
                Canvas { context, cSize in
                    context.addFilter(.alphaThreshold(min: 0.01))
                    context.addFilter(.blur(radius: size))
                    context.drawLayer { layer in
                        if let symbol = context.resolveSymbol(id: "stroke-content") {
                            layer.draw(symbol, at: CGPoint(x: cSize.width / 2, y: cSize.height / 2))
                        }
                    }
                } symbols: {
                    content.tag("stroke-content")
                }
                .foregroundStyle(color)
            )
    }
}

extension View {
    func withStroke(color: Color = .black, width: CGFloat = 2) -> some View {
        self.modifier(StrokeModifier(size: width, color: color))
    }
}

// FILE: Vignette.entitlements
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

// FILE: VignetteApp.swift
//
//  VignetteApp.swift
//  Vignette
//
//  Created by Victor Noagbodji on 5/11/25.
//

import SwiftUI

@main
struct VignetteApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

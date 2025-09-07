// FILE: Attendee.swift
//
//  Attendee.swift
//  Presence
//
//  Created by Victor Noagbodji on 3/9/25.
//

import Foundation

struct Attendee: Identifiable, Codable {
    let id: UUID
    var name: String
    var avatar: String
    var state: Int = 0
}

// FILE: AttendeeViewModel.swift
//
//  AttendeeViewModel.swift
//  Presence
//
//  Created by Victor Noagbodji on 3/9/25.
//

import Foundation

class AttendeeViewModel: ObservableObject {
    @Published var attendees: [Attendee] {
        didSet {
            saveAttendees()
        }
    }

    private let saveKey = "Attendees"

    init() {
        self.attendees = []

        self.attendees = loadAttendees()
        
        if self.attendees.isEmpty {
            self.attendees = [
                Attendee(id: UUID(), name: "Victor", avatar: "👨🏾‍💻"),
                Attendee(id: UUID(), name: "Aisha", avatar: "👩🏾"),
                Attendee(id: UUID(), name: "Alex", avatar: "🧑‍🚀"),
                Attendee(id: UUID(), name: "Sam", avatar: "👨🏻"),
                Attendee(id: UUID(), name: "Emily", avatar: "👩🏼"),
                Attendee(id: UUID(), name: "Daniel", avatar: "👨🏽‍🎓"),
                Attendee(id: UUID(), name: "Sophia", avatar: "👩‍⚕️"),
                Attendee(id: UUID(), name: "Chris", avatar: "👨‍🔧"),
                Attendee(id: UUID(), name: "Olivia", avatar: "👩‍🔬"),
                Attendee(id: UUID(), name: "Ethan", avatar: "👨‍🏫"),
                Attendee(id: UUID(), name: "Ava", avatar: "👩‍🎨"),
                Attendee(id: UUID(), name: "Liam", avatar: "👨‍🚒"),
                Attendee(id: UUID(), name: "Mia", avatar: "👩‍🚀"),
                Attendee(id: UUID(), name: "Noah", avatar: "👨‍⚖️"),
                Attendee(id: UUID(), name: "Ella", avatar: "👩‍🍳")
            ]
        }
    }

    func loadAttendees() -> [Attendee] {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([Attendee].self, from: data) {
            return decoded
        }
        return []
    }

    func saveAttendees() {
        if let encoded = try? JSONEncoder().encode(attendees) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
        }
    }
}

// FILE: AvatarCard.swift
//
//  AvatarCard.swift
//  Presence
//
//  Created by Victor Noagbodji on 3/9/25.
//

import SwiftUI

struct AvatarCard: View {
    let action: () -> Void
    let attendee: Binding<Attendee>?
    let color: Color

    @State private var isRenaming = false
    @State private var isChangingIcon = false
    
    var body: some View {
        VStack {
            if let attendee = attendee {
                Text(attendee.wrappedValue.avatar).font(.system(size: 50))
                Text(attendee.wrappedValue.name).font(.headline)
            } else {
                Text("➕").font(.system(size: 50))
                Text("Add").font(.headline)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10).fill(color)
        )
        .onTapGesture {
            action()
        }
        .contextMenu {
            Button("Rename...") { isRenaming = true }
            Button("Change Icon...") { isChangingIcon = true }
        }
        .sheet(isPresented: $isRenaming) {
            if let attendee = attendee {
                RenameSheet(attendee: attendee)
            }
        }
        .popover(isPresented: $isChangingIcon, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            if let attendee = attendee {
                IconPicker(attendee: attendee)
            }
        }
    }
}

// FILE: ContentView.swift
//
//  ContentView.swift
//  Presence
//
//  Created by Victor Noagbodji on 3/9/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AttendeeViewModel()
    @State private var isEditing = false

    let colors: [Color] = [
        Color.gray.opacity(0.2),
        Color.blue.opacity(0.5),
        Color.red.opacity(0.5)
    ]

    let columns = [GridItem(.adaptive(minimum: 150))]
    
    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 20) {
            ForEach($viewModel.attendees) { $attendee in
                AvatarCard(
                    action: {
                        attendee.state = (attendee.state + 1) % 3
                    },
                    attendee: $attendee,
                    color: colors[attendee.state]
                )
                .modifier(ShakeEffect(isShaking: isEditing))
                .overlay(
                    Group {
                        if isEditing {
                            Image(systemName: "minus.circle.fill")
                                .resizable()
                                .frame(width: 26, height: 26)
                                .offset(x: -40, y: -50)
                                .onTapGesture {
                                    if let index = viewModel.attendees.firstIndex(where: { $0.id == attendee.id }) {
                                        viewModel.attendees.remove(at: index)
                                    }
                                }
                        }
                    }
                )
            }
            AvatarCard(
                action: {
                    viewModel.attendees.append(
                        Attendee(id: UUID(), name: "New", avatar: "👤")
                    )
                },
                attendee: nil,
                color: colors[0]
            )
        }
        .padding()
    }
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                grid
            }
            .navigationTitle("Presence")
            .frame(width: geometry.size.width, height: geometry.size.height)
            .onLongPressGesture {
                isEditing.toggle()
            }
        }
    }
}

#Preview {
    ContentView()
}

// FILE: IconPicker.swift
//
//  IconPicker.swift
//  Presence
//
//  Created by Victor Noagbodji on 3/16/25.
//

import SwiftUI

struct IconPicker: View {
    @Binding var attendee: Attendee

    let columns = Array(repeating: GridItem(.flexible()), count: 3)

    let icons = [
        "👨🏾‍💻", "👩🏾", "🧑‍🚀", "👨🏻", "👩🏼", "👨🏽‍🎓",
        "👩‍⚕️", "👨‍🔧", "👩‍🔬", "👨‍🏫", "👩‍🎨", "👨‍🚒",
        "👩‍🚀", "👨‍⚖️", "👩‍🍳", "👨‍💻", "👩‍💻", "🧑‍🏫",
        "👩‍🏫", "🧑‍⚕️", "👨‍⚕️", "🧑‍🔬", "👨‍🔬", "👨‍🚀",
        "🧑‍🎨", "👨‍🎨", "🧑‍🍳", "👨‍🍳", "🧑‍✈️", "👨‍✈️",
        "👩‍✈️", "🧑‍🔧", "👩‍🔧", "🧑‍🚒", "👩‍🚒", "🧑‍🎤",
        "👨‍🎤", "👩‍🎤", "🧑‍⚖️", "👩‍⚖️", "🧑‍🏭", "👨‍🏭",
        "👩‍🏭", "🧑‍🌾", "👨‍🌾", "👩‍🌾", "🧑‍💼", "👨‍💼",
        "👩‍💼", "🧑‍🎓", "👨‍🎓", "👩‍🎓",
        "🧑‍🎭", "👨‍🎭", "👩‍🎭",
        "🧑‍🚗", "👨‍🚗", "👩‍🚗"
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(icons, id: \.self) { icon in
                    Text(icon)
                        .font(.system(size: 40))
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.2))
                        )
                        .onTapGesture {
                            attendee.avatar = icon
                        }
                }
            }
            .padding()
        }
        .frame(width: 400, height: 250)
    }
}

// FILE: Presence.entitlements
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.files.user-selected.read-only</key>
	<true/>
</dict>
</plist>

// FILE: PresenceApp.swift
//
//  PresenceApp.swift
//  Presence
//
//  Created by Victor Noagbodji on 3/9/25.
//

import SwiftUI

@main
struct PresenceApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// FILE: RenameSheet.swift
//
//  RenameSheet.swift
//  Presence
//
//  Created by Victor Noagbodji on 3/16/25.
//

import SwiftUI

struct RenameSheet: View {
    @Binding var attendee: Attendee
    @State private var newName: String
    @Environment(\.dismiss) private var dismiss

    init(attendee: Binding<Attendee>) {
        self._attendee = attendee
        self._newName = State(initialValue: attendee.wrappedValue.name)
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(attendee.avatar)
                .font(.system(size: 50))
            
            Text("Name").font(.headline)
            TextField("Enter new name", text: $newName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Done") {
                    attendee.name = newName
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .frame(width: 300)
        .padding()
    }
}

// FILE: ShakeEffect.swift
//
//  ShakeEffect.swift
//  Presence
//
//  Created by Victor Noagbodji on 3/10/25.
//

import SwiftUI

struct ShakeEffect: ViewModifier {
    var isShaking: Bool

    func body(content: Content) -> some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { _ in
            content.offset(
                x: isShaking ? CGFloat.random(in: -2...2) : 0,
                y: isShaking ? CGFloat.random(in: -2...2) : 0)
        }
    }
}

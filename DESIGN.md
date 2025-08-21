# 1FA SwiftUI Design Document

## 1. Introduction

This document outlines the design principles and common patterns for creating single-file SwiftUI applications within the `1fa` repository. The goal is to maintain consistency, readability, and maintainability across all applications.

## 2. File Structure

Each application should be contained entirely within a single `.swift` file. The file should be named after the application's primary concept (e.g., `Grooves.swift`, `Parts.swift`).

It is important to note that applications are not developed as a single file from the start. The recommended workflow is to build and test the application in a standard Xcode project with multiple files for better organization. Once development is complete, the code from all source files is assembled into the final, single `.swift` file.

Code within the file should be organized logically by grouping related components. A recommended order is:

1.  Models (Data Structures)
2.  View Models / Managers (State and Logic)
3.  Component Views (Small, reusable UI elements)
4.  Main Views (e.g., `Editor`, `Inspector`, `Sidebar`)
5.  `ContentView` (The root view)
6.  The `App` struct (`@main`)
7.  Utility Structs (e.g., `ImageExporter`)
8.  ViewModifiers or Extensions

## 3. Application Architecture

### 3.1. Entry Point

The application's entry point is a struct conforming to the `App` protocol, marked with the `@main` attribute.

```swift
@main
struct GroovesApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### 3.2. Root View

The main view of the application should be named `ContentView`. This view is responsible for setting up the main layout and initializing the primary state objects.

### 3.3. View Composition

- **Break Down Views:** Decompose complex UIs into smaller, single-purpose `View` structs (e.g., `BeatBlock`, `SegmentBlock`, `AvatarCard`). This improves reusability and readability.
- **Master-Detail Interfaces:** For applications that allow users to select an item from a list to edit, use `NavigationSplitView` with a `Sidebar` and a detail `Editor` view.

## 4. State Management

- **`@State`**: Use for simple, transient view-specific state that is not shared.
- **`@StateObject`**: Use for more complex state or business logic. Create a dedicated `ObservableObject` class (e.g., `PlaybackManager`, `AttendeeViewModel`) to encapsulate this logic. This object is owned and created by the view.
- **`@Binding`**: Use bindings to pass state down to child views, allowing them to read and modify the state owned by a parent view. This is the standard way to connect components like an `Editor` or `Inspector` back to the main `ContentView`.

## 5. Data Modeling

- **Structs for Models:** Define data models as `struct`s.
- **Common Protocols:** Conform models to standard protocols as needed:
  - `Identifiable`: For use in `ForEach` loops and list selections.
  - `Codable`: For persistence to `UserDefaults`.
  - `Hashable` & `Equatable`: For use as `NavigationLink` values and in collections.

```swift
struct Preset: Identifiable, Codable, Hashable {
    var id = UUID()
    let name: String
    let segments: [Segment]
}
```

## 6. Data Persistence

- **UserDefaults:** `UserDefaults` is the standard mechanism for persisting user data.
- **PresetManager:** For applications that use presets, create a singleton `PresetManager` class. This manager is responsible for:
  - Loading default presets from a JSON string.
  - Loading saved presets from `UserDefaults`.
  - Saving presets to `UserDefaults`.
- **Codable Models:** Store data by encoding `Codable` models into JSON `Data` before writing to `UserDefaults`.
- **Debug Reset:** Include a "Reset Presets" button in the `Inspector` view to allow clearing the saved data from `UserDefaults` for debugging.

## 7. Common UI Patterns & Features

### 7.1. Inspector View

For editing the properties of a selected item, use an `Inspector` view.

- It should be presented using the `.inspector(isPresented: ...)` modifier on the main view.
- The `Inspector` receives `@Binding`s to the application's state to allow for direct modification.

### 7.2. Image Exporting

Provide a feature to export the main content view as a PNG image.

- Create a utility struct named `ImageExporter`.
- It should contain a static, `@MainActor` function called `export`.
- Use SwiftUI's `ImageRenderer` to render the view.
- Use `NSSavePanel` to allow the user to choose a file name and location.

```swift
struct ImageExporter {
    @MainActor
    static func export<Content: View>(view: Content, size: CGSize) {
        // 1. Create an ImageRenderer with the view.
        // 2. Get the nsImage from the renderer.
        // 3. Convert to PNG data.
        // 4. Use NSSavePanel to prompt the user for a save location.
        // 5. Write the data to the selected URL.
    }
}
```

### 7.3. Enums for Styling

Use `enum`s to manage a fixed set of states or styles, such as colors for different component types. This centralizes style information and makes it easy to manage.

```swift
enum Part: String, CaseIterable, Codable {
    case intro, verse, chorus, ...

    func color() -> Color {
        switch self {
        case .intro: return .purple
        case .verse: return .cyan
        // ...
        }
    }
}
```

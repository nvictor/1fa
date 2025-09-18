// FILE: ContentView.swift
//
//  ContentView.swift
//  Jiraiya
//
//  Created by Victor Noagbodji on 9/17/25.
//

import SwiftUI

struct ContentView: View {
    let quarters = buildQuarters(from: sampleStories)

    private var navigationTitle: String {
        if let year = quarters.first?.year {
            return "Jiraiya \(year.formatted(.number.grouping(.never)))"
        }
        return "Jiraiya"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) {
                    ForEach(quarters) { quarter in
                        NavigationLink(value: quarter) {
                            QuarterCard(quarter: quarter)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle(navigationTitle)
            .navigationDestination(for: Quarter.self) { quarter in
                QuarterDetailView(quarter: quarter)
            }
            .navigationDestination(for: Epic.self) { epic in
                EpicDetailView(epic: epic)
            }
            .navigationDestination(for: Month.self) { month in
                MonthDetailView(month: month)
            }
        }
    }
}

#Preview {
    ContentView()
}

// FILE: Epic.swift
//
//  Epic.swift
//  Jiraiya
//
//  Created by Victor Noagbodji on 9/17/25.
//

import Foundation

struct Epic: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let description: String
    let stories: [Story]
}

// FILE: EpicCard.swift
//
//  EpicCard.swift
//  Jiraiya
//
//  Created by Victor Noagbodji on 9/17/25.
//

import SwiftUI

struct EpicCard: View {
    let epic: Epic
    
    var body: some View {
        GroupBox {
            HStack {
                Text("Stories: \(epic.stories.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
        } label: {
            Text(epic.title)
                .font(.headline)
        }
    }
}

// FILE: EpicDetailView.swift
//
//  EpicDetailView.swift
//  Jiraiya
//
//  Created by Victor Noagbodji on 9/17/25.
//

import SwiftUI

struct EpicDetailView: View {
    let epic: Epic
    
    private var months: [Month] {
        let cal = Calendar.current
        let storiesByMonth = Dictionary(grouping: epic.stories) { story in
            cal.fiscalMonth(for: story.completedAt)
        }

        return storiesByMonth.map { (date, stories) in
            let year = cal.component(.year, from: date)
            return Month(name: cal.monthName(for: date), stories: stories, date: date, year: year)
        }.sorted { $0.date < $1.date }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(epic.description)
                    .font(.body)
                    .padding(.bottom)
                
                ForEach(months) { month in
                    NavigationLink(value: month) {
                        MonthCard(month: month)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .navigationTitle(epic.title)
    }
}

// FILE: Extensions.swift
//
//  Extensions.swift
//  Jiraiya
//
//  Created by Victor Noagbodji on 9/17/25.
//

import Foundation

extension Calendar {
    /// Fiscal year starts in February on the first Monday
    func fiscalYearStart(for year: Int) -> Date {
        let startComponents = DateComponents(year: year, month: 2, day: 1)
        let febStart = self.date(from: startComponents)!

        let weekday = component(.weekday, from: febStart)
        let offset = (9 - weekday) % 7
        return date(byAdding: .day, value: offset, to: febStart)!
    }

    func fiscalQuarter(for date: Date) -> Int {
        let year = component(.year, from: date)
        let start = fiscalYearStart(for: year)
        guard date >= start else { return 4 } // belongs to previous fiscal year

        let diff = dateComponents([.month], from: start, to: date).month ?? 0
        return (diff / 3) + 1
    }

    func fiscalMonth(for date: Date) -> Date {
        let comps = dateComponents([.year, .month], from: date)
        return self.date(from: comps) ?? date
    }

    func monthName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter.string(from: date)
    }

    func fiscalYear(for date: Date) -> Int {
        let year = component(.year, from: date)
        let startOfFiscalYear = fiscalYearStart(for: year)
        if date < startOfFiscalYear {
            return year - 1
        }
        return year
    }
}

// FILE: Helpers.swift
//
//  Helpers.swift
//  Jiraiya
//
//  Created by Victor Noagbodji on 9/17/25.
//

import SwiftUI

func outcomeColor(for outcome: String) -> Color {
    switch outcome.lowercased() {
    case let s where s.contains("onboarding"): return .blue
    case let s where s.contains("sync"): return .purple
    case let s where s.contains("ux"): return .orange
    default: return .secondary
    }
}

func buildQuarters(from stories: [Story]) -> [Quarter] {
    guard let firstStoryDate = stories.min(by: { $0.completedAt < $1.completedAt })?.completedAt else { return [] }
    let cal = Calendar.current
    let fiscalYear = cal.fiscalYear(for: firstStoryDate)

    // Group stories by epic
    let epicsByTitle = Dictionary(grouping: stories, by: { $0.epicTitle })
    
    let epics = epicsByTitle.map { (title, stories) in
        Epic(title: title, description: "This is a sample description for the \(title) epic.", stories: stories)
    }

    // Group epics by quarter
    var quarterDict: [Int: [Epic]] = [:]
    for epic in epics {
        // Use the latest story in the epic to determine its quarter
        guard let latestDate = epic.stories.map({ $0.completedAt }).max() else { continue }
        let q = cal.fiscalQuarter(for: latestDate)
        quarterDict[q, default: []].append(epic)
    }

    var quarters: [Quarter] = []
    for q in 1...4 {
        let qEpics = quarterDict[q] ?? []
        quarters.append(Quarter(name: "Q\(q)", epics: qEpics, year: fiscalYear))
    }

    return quarters.filter { !$0.epics.isEmpty }
}

// FILE: Jiraiya.entitlements
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>

// FILE: JiraiyaApp.swift
//
//  JiraiyaApp.swift
//  Jiraiya
//
//  Created by Victor Noagbodji on 9/17/25.
//

import SwiftUI

@main
struct JiraiyaApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// FILE: Month.swift
//
//  Month.swift
//  Jiraiya
//
//  Created by Victor Noagbodji on 9/17/25.
//

import Foundation

struct Month: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let stories: [Story]
    let date: Date
    let year: Int
}

// FILE: MonthCard.swift
//
//  MonthCard.swift
//  Jiraiya
//
//  Created by Victor Noagbodji on 9/17/25.
//

import SwiftUI

struct MonthCard: View {
    let month: Month
    
    var body: some View {
        GroupBox {
            HStack {
                Text("Stories: \(month.stories.count)")
                    .font(.caption)
                Spacer()
            }
        } label: {
            Text(month.name)
                .font(.headline)
        }
    }
}

// FILE: MonthDetailView.swift
//
//  MonthDetailView.swift
//  Jiraiya
//
//  Created by Victor Noagbodji on 9/17/25.
//

import SwiftUI

struct MonthDetailView: View {
    let month: Month
    let cal = Calendar.current
    
    var body: some View {
        let range = cal.range(of: .day, in: .month, for: month.date) ?? 1..<1
        let firstWeekday = cal.component(.weekday, from: month.date)
        let storiesByDay = Dictionary(grouping: month.stories) { story in
            cal.component(.day, from: story.completedAt)
        }

        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7)) {
                // Empty slots before first day
                ForEach((0..<(firstWeekday - 1)).map { -$0 - 1 }, id: \.self) { _ in
                    Color.clear.frame(height: 40)
                }
                
                // Days of the month
                ForEach(range, id: \.self) { day in
                    VStack {
                        Text("\(day)")
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                        if let stories = storiesByDay[day] {
                            HStack(spacing: 2) {
                                ForEach(stories) { story in
                                    Circle()
                                        .fill(outcomeColor(for: story.outcome))
                                        .frame(width: 8, height: 8)
                                        .help(story.title)
                                }
                            }
                        }
                    }
                    .frame(height: 40)
                }
            }
            .padding()
            
            VStack {
                ForEach(month.stories) { story in
                    StoryCard(story: story)
                }
            }
            .padding()
        }
        .navigationTitle(month.date.formatted(.dateTime.month(.wide).year()))
    }
}
// FILE: Quarter.swift
//
//  Quarter.swift
//  Jiraiya
//
//  Created by Victor Noagbodji on 9/17/25.
//

import Foundation

struct Quarter: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let epics: [Epic]
    let year: Int
    
    func totalEpics() -> Int {
        epics.count
    }
    
    func totalStories() -> Int {
        epics.reduce(0) { $0 + $1.stories.count }
    }
}

// FILE: QuarterCard.swift
//
//  QuarterCard.swift
//  Jiraiya
//
//  Created by Victor Noagbodji on 9/17/25.
//

import SwiftUI

struct QuarterCard: View {
    let quarter: Quarter
    
    var body: some View {
        GroupBox {
            HStack {
                VStack(alignment: .leading) {
                    Text("Epics: \(quarter.totalEpics())")
                        .font(.caption)
                    Text("Stories: \(quarter.totalStories())")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } label: {
            Text(quarter.name)
                .font(.headline)
        }
    }
}

// FILE: QuarterDetailView.swift
//
//  QuarterDetailView.swift
//  Jiraiya
//
//  Created by Victor Noagbodji on 9/17/25.
//

import SwiftUI

struct QuarterDetailView: View {
    let quarter: Quarter

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible())]) {
                ForEach(quarter.epics) { epic in
                    NavigationLink(value: epic) {
                        EpicCard(epic: epic)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .navigationTitle("\(quarter.name) \(quarter.year.formatted(.number.grouping(.never)))")
    }
}

// FILE: Story.swift
//
//  Story.swift
//  Jiraiya
//
//  Created by Victor Noagbodji on 9/17/25.
//

import Foundation

struct Story: Identifiable, Hashable {
    let id: UUID
    let title: String
    let completedAt: Date
    let outcome: String
    let epicTitle: String
}

let sampleStories: [Story] = [
    // Onboarding Epic
    Story(id: UUID(), title: "Implement login flow", completedAt: Date().addingTimeInterval(-86400 * 5), outcome: "Improved onboarding", epicTitle: "Onboarding Experience"),
    Story(id: UUID(), title: "Create welcome screen", completedAt: Date().addingTimeInterval(-86400 * 10), outcome: "Better UX", epicTitle: "Onboarding Experience"),
    Story(id: UUID(), title: "Add password recovery", completedAt: Date().addingTimeInterval(-86400 * 15), outcome: "Improved onboarding", epicTitle: "Onboarding Experience"),

    // Sync Epic
    Story(id: UUID(), title: "Refactor API client", completedAt: Date().addingTimeInterval(-86400 * 30), outcome: "Faster sync", epicTitle: "Performance & Sync"),
    Story(id: UUID(), title: "Optimize database queries", completedAt: Date().addingTimeInterval(-86400 * 35), outcome: "Faster sync", epicTitle: "Performance & Sync"),
    Story(id: UUID(), title: "Implement background refresh", completedAt: Date().addingTimeInterval(-86400 * 40), outcome: "Better UX", epicTitle: "Performance & Sync"),

    // Dashboard Epic (Previous Quarter)
    Story(id: UUID(), title: "UI polish for dashboard", completedAt: Date().addingTimeInterval(-86400 * 95), outcome: "Better UX", epicTitle: "Dashboard Revamp"),
    Story(id: UUID(), title: "Add new chart type", completedAt: Date().addingTimeInterval(-86400 * 100), outcome: "Better UX", epicTitle: "Dashboard Revamp"),
]

// FILE: StoryCard.swift
//
//  StoryCard.swift
//  Jiraiya
//
//  Created by Victor Noagbodji on 9/17/25.
//

import SwiftUI

struct StoryCard: View {
    let story: Story

    var body: some View {
        GroupBox {
            VStack(alignment: .leading) {
                Text("Completed: \(story.completedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Outcome: \(story.outcome)")
                    .font(.caption)
                    .foregroundColor(outcomeColor(for: story.outcome))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(story.title)
                .font(.headline)
        }
    }
}

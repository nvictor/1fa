// FILE: ColorPalette.swift
//
//  ColorPalette.swift
//  Jiraiya
//
//  Created by Victor Noagbodji on 9/20/25.
//

import Foundation
import SwiftUI

enum PredefinedColor: String, CaseIterable, Identifiable {
    case green
    case orange
    case blue
    case purple
    case red
    case gray
    case yellow
    case cyan
    case indigo

    var id: Self { self }

    var color: Color {
        switch self {
        case .green: return .green
        case .orange: return .orange
        case .blue: return .blue
        case .purple: return .purple
        case .red: return .red
        case .gray: return .gray
        case .yellow: return .yellow
        case .cyan: return .cyan
        case .indigo: return .indigo
        }
    }
}

// FILE: ConsoleView.swift
//
//  ConsoleView.swift
//  Jiraiya
//
//  Created by Victor Noagbodji on 9/18/25.
//

import SwiftUI

struct ConsoleView: View {
    @State private var selection = Set<UUID>()

    var body: some View {
        VStack {
            ConsoleHeaderView(selection: $selection)
            Divider()
            LogView(selection: $selection)
        }
    }
}

// FILE: ContentView.swift
//
//  ContentView.swift
//  Jiraiya
//
//  Created by Victor Noagbodji on 9/17/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var outcomeManager: OutcomeManager
    @State private var stories: [Story] = []
    @State private var showInspector = false
    @State private var path = NavigationPath()

    private var quarters: [Quarter] {
        buildQuarters(from: stories)
    }

    private var navigationTitle: String {
        if let year = quarters.first?.year {
            return year.formatted(.number.grouping(.never))
        }
        return ""
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                if stories.isEmpty {
                    ContentUnavailableView(
                        "No Stories", systemImage: "doc.text.magnifyingglass",
                        description: Text("Connect to JIRA and sync your stories to get started."))
                } else {
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
        .inspector(isPresented: $showInspector) {
            Inspector()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    path = NavigationPath()
                    loadStories()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            ToolbarItem {
                Button {
                    showInspector.toggle()
                } label: {
                    Label("Settings", systemImage: "sidebar.trailing")
                }
            }
        }
        .onAppear(perform: loadStories)
        .onReceive(NotificationCenter.default.publisher(for: .databaseDidReset)) { _ in
            loadStories()
        }
    }

    private func loadStories() {
        do {
            stories = try DatabaseManager.shared.fetchStories()
        } catch {
            print("Failed to load stories from database: \(error)")
            // Consider showing an error to the user
        }
    }
}

#Preview {
    ContentView()
}

// FILE: DatabaseManager.swift
//
//  DatabaseManager.swift
//  Jiraiya
//
//  Created by Victor Noagbodji on 9/18/25.
//

import Foundation
import GRDB

class DatabaseManager {
    static let shared = DatabaseManager()

    var dbQueue: DatabaseQueue

    private init() {
        do {
            let fileManager = FileManager.default
            let dbPath =
                try fileManager
                .url(
                    for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil,
                    create: true
                )
                .appendingPathComponent("jiraiya.sqlite")
                .path

            dbQueue = try DatabaseQueue(path: dbPath)
            try dbQueue.write { db in
                try self.createTables(db)
            }
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
    }

    private func createTables(_ db: Database) throws {
        try db.create(table: "story", ifNotExists: true) { t in
            t.column("id", .text).primaryKey()
            t.column("title", .text).notNull()
            t.column("completedAt", .datetime).notNull()
            t.column("outcome", .text).notNull()
            t.column("epicTitle", .text).notNull()
        }
    }

    func fetchStories() throws -> [Story] {
        try dbQueue.read { db in
            try Story.fetchAll(db)
        }
    }

    func saveStories(_ stories: [Story]) async throws {
        try await dbQueue.write { db in
            for story in stories {
                try story.save(db)
            }
        }
    }

    func clearStories() async throws {
        try await dbQueue.write { db in
            _ = try Story.deleteAll(db)
        }
    }

    /// Replaces all stories in a single transaction (clear + save)
    func replaceStories(_ stories: [Story]) async throws {
        try await dbQueue.write { db in
            _ = try Story.deleteAll(db)
            for story in stories {
                try story.save(db)
            }
        }
    }

    func resetDatabase() async throws {
        try await dbQueue.write { db in
            try db.execute(sql: "DROP TABLE IF EXISTS story")
            try self.createTables(db)
        }
    }
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
    var id: String { title }
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
    @EnvironmentObject private var outcomeManager: OutcomeManager

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(outcomeCounts.keys.sorted(), id: \.self) { key in
                    let count = outcomeCounts[key] ?? 0
                    if count > 0 {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(outcomeManager.color(for: key))
                                .frame(width: 8, height: 8)
                            Text("\(key) \(count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                        .padding(.horizontal, 6)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        } label: {
            Text(epic.title)
                .font(.headline)
        }
    }

    private var outcomeCounts: [String: Int] {
        Dictionary(grouping: epic.stories, by: { $0.outcome }).mapValues { $0.count }
    }
}

// FILE: EpicDescriptionCache.swift
import Foundation

final class EpicDescriptionCache {
    static let shared = EpicDescriptionCache()
    private let key = "epicDescriptions"
    private let defaults = UserDefaults.standard

    private init() {}

    private func loadMap() -> [String: String] {
        guard let data = defaults.data(forKey: key),
            let map = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [:]
        }
        return map
    }

    private func saveMap(_ map: [String: String]) {
        if let data = try? JSONEncoder().encode(map) {
            defaults.set(data, forKey: key)
        }
    }

    func description(for title: String) -> String? {
        loadMap()[title]
    }

    func setDescription(_ description: String, for title: String) {
        var map = loadMap()
        map[title] = description
        saveMap(map)
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
    @EnvironmentObject private var outcomeManager: OutcomeManager
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
        guard date >= start else { return 4 }    // belongs to previous fiscal year

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

extension Notification.Name {
    static let databaseDidReset = Notification.Name("databaseDidReset")
    static let reclassifyProgress = Notification.Name("reclassifyProgress")
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
    guard let firstStoryDate = stories.min(by: { $0.completedAt < $1.completedAt })?.completedAt
    else { return [] }
    let cal = Calendar.current
    let fiscalYear = cal.fiscalYear(for: firstStoryDate)

    // Group stories by epic
    let epicsByTitle = Dictionary(grouping: stories, by: { $0.epicTitle })

    let epics = epicsByTitle.map { (title, stories) in
        let desc: String
        if let cached = EpicDescriptionCache.shared.description(for: title) {
            desc = cached
        } else if let latest = stories.sorted(by: { $0.completedAt > $1.completedAt }).first {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            desc = "Latest activity: \(formatter.string(from: latest.completedAt)) — \(title)"
        } else {
            desc = title
        }
        return Epic(title: title, description: desc, stories: stories)
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

// FILE: Inspector.swift
//
//  Inspector.swift
//  Jiraiya
//
//  Created by Victor Noagbodji on 9/18/25.
//

import SwiftUI

struct Inspector: View {
    @EnvironmentObject private var outcomeManager: OutcomeManager
    @AppStorage("jiraBaseURL") private var jiraBaseURL: String = ""
    @AppStorage("jiraEmail") private var jiraEmail: String = ""
    @AppStorage("jiraApiToken") private var jiraApiToken: String = ""

    @State private var isSyncing = false
    @State private var showingResetAlert = false

    private let jiraService = JiraService()

    var body: some View {
        Form {
            Section("JIRA API Details") {
                TextField("API URL", text: $jiraBaseURL)
                    .textContentType(.URL)
                TextField("Email", text: $jiraEmail)
                    .textContentType(.emailAddress)
                SecureField("API Token", text: $jiraApiToken)
                Button(action: {
                    Task {
                        await syncJira()
                    }
                }) {
                    if isSyncing {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Connect & Sync")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(
                    isSyncing || jiraBaseURL.isEmpty || jiraEmail.isEmpty || jiraApiToken.isEmpty)
            }

            OutcomeSettingsView(outcomeManager: outcomeManager)

            Section("Database") {
                Button(role: .destructive) {
                    showingResetAlert = true
                } label: {
                    Text("Reset Database")
                        .frame(maxWidth: .infinity)
                }
            }

            ConsoleView()
        }
        .padding()
        .frame(minWidth: 280)
        .alert("Are you sure you want to reset the database?", isPresented: $showingResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                Task {
                    await resetDatabase()
                }
            }
        }
    }

    private func resetDatabase() async {
        do {
            try await DatabaseManager.shared.resetDatabase()
            LogService.shared.log("Database has been reset.", type: .success)
            NotificationCenter.default.post(name: .databaseDidReset, object: nil)
        } catch {
            LogService.shared.log(
                "Failed to reset database: \(error.localizedDescription)", type: .error)
        }
    }

    private func syncJira() async {
        isSyncing = true
        LogService.shared.log("Starting JIRA sync... (baseURL=\(jiraBaseURL))", type: .info)
        do {
            try await jiraService.sync()
            LogService.shared.log("JIRA sync completed successfully.", type: .success)
        } catch {
            // Log the basic localized description
            LogService.shared.log("JIRA sync failed: \(error.localizedDescription)", type: .error)

            // Prefer to log the underlying NSError if JiraError wraps one
            if let jiraErr = error as? JiraError, let underlying = jiraErr.underlyingError {
                let ns = underlying as NSError
                LogService.shared.log(
                    "JIRA sync error details: domain=\(ns.domain), code=\(ns.code), userInfo=\(ns.userInfo)",
                    type: .error)
            } else {
                let ns = error as NSError
                LogService.shared.log(
                    "JIRA sync error details: domain=\(ns.domain), code=\(ns.code), userInfo=\(ns.userInfo)",
                    type: .error)
            }
        }
        isSyncing = false
    }
}

// FILE: JiraModels.swift
import Foundation

struct Comment: Decodable {
    let body: ADFBody?
}

struct ADFBody: Decodable {
    let content: [ADFNode]
}

struct ADFNode: Decodable {
    let text: String?
    let content: [ADFNode]?
}

// FILE: JiraService.swift
//
//  JiraService.swift
//  Jiraiya
//
//  Created by Victor Noagbodji on 9/18/25.
//

import Foundation
import SwiftUI

// MARK: - Codable Models for JIRA API Response

private struct JiraSearchResult: Decodable {
    let issues: [Issue]
}

private struct Issue: Decodable {
    let key: String
    let fields: IssueFields
}

private struct IssueFields: Decodable {
    let summary: String
    let resolutiondate: String?
    let updated: String?
    let parent: Parent?
    let comment: CommentConnection?
}

private struct Parent: Decodable {
    let key: String?
    let fields: ParentFields
}

private struct ParentFields: Decodable {
    let summary: String
}

private struct CommentConnection: Decodable {
    let comments: [Comment]
    let total: Int
}

// MARK: - JiraError

enum JiraError: Error, LocalizedError {
    case configurationMissing
    case invalidURL
    case invalidCredentials
    case requestFailed(Error)
    case httpError(statusCode: Int, body: String)
    case decodingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .configurationMissing:
            return
                "JIRA configuration is missing. Please set the base URL, email, and API token in Settings."
        case .invalidURL:
            return "The JIRA base URL is invalid."
        case .invalidCredentials:
            return "Could not encode JIRA credentials."
        case .requestFailed(let error):
            let nsError = error as NSError
            return
                "Network request failed: \(nsError.localizedDescription) (domain: \(nsError.domain), code: \(nsError.code))"
        case .httpError(let statusCode, let body):
            return "JIRA API returned an error: HTTP \(statusCode). Response: \(body)"
        case .decodingFailed(let error):
            return "Failed to decode JIRA API response: \(error.localizedDescription)"
        }
    }

    var underlyingError: Error? {
        switch self {
        case .requestFailed(let error): return error
        case .decodingFailed(let error): return error
        default: return nil
        }
    }
}

// MARK: - JiraService

class JiraService {
    @AppStorage("jiraBaseURL") private var jiraBaseURL: String = ""
    @AppStorage("jiraEmail") private var jiraEmail: String = ""
    @AppStorage("jiraApiToken") private var jiraApiToken: String = ""

    private let outcomeManager = OutcomeManager()

    func sync() async throws {
        let jql = "statusCategory = Done order by updated DESC"
        let fields = ["summary", "updated", "resolutiondate", "parent", "comment"]
        let queryItems = [
            URLQueryItem(name: "jql", value: jql),
            URLQueryItem(name: "fields", value: fields.joined(separator: ",")),
            URLQueryItem(name: "maxResults", value: "100"),
        ]
        let data = try await performAPIRequest(
            path: "/rest/api/3/search/jql", queryItems: queryItems)

        let decoder = JSONDecoder()
        let searchResult: JiraSearchResult
        do {
            searchResult = try decoder.decode(JiraSearchResult.self, from: data)
        } catch {
            throw JiraError.decodingFailed(error)
        }

        await LogService.shared.log(
            "Fetched \(searchResult.issues.count) issues from Jira. Processing...", type: .info)

        var stories: [Story] = []
        var epicKeyByTitle: [String: String] = [:]
        for issue in searchResult.issues {
            guard let completedAtString = issue.fields.resolutiondate ?? issue.fields.updated else {
                await LogService.shared.log(
                    "Skipping issue \(issue.key): missing resolutiondate and updated fields.",
                    type: .warning)
                continue
            }

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            guard
                let completedAt = formatter.date(from: completedAtString)
                    ?? ISO8601DateFormatter().date(from: completedAtString)
            else {
                await LogService.shared.log(
                    "Skipping issue \(issue.key): failed to parse date '\(completedAtString)'.",
                    type: .warning)
                continue
            }

            let epicTitle = issue.fields.parent?.fields.summary ?? "No Epic"
            if let epicKey = issue.fields.parent?.key {
                epicKeyByTitle[epicTitle] = epicKey
            }
            let comments = try await fetchComments(for: issue.key)
            let outcome = outcomeManager.outcome(forTitle: issue.fields.summary, comments: comments)

            let story = Story(
                id: issue.key,
                title: issue.fields.summary,
                completedAt: completedAt,
                outcome: outcome.name,
                epicTitle: epicTitle
            )
            stories.append(story)
        }

        await LogService.shared.log("Successfully processed \(stories.count) stories.", type: .info)

        if stories.isEmpty { return }

        try await DatabaseManager.shared.clearStories()
        try await DatabaseManager.shared.saveStories(stories)

        // Fetch and cache epic descriptions asynchronously (non-blocking for the sync flow)
        await fetchAndCacheEpicDescriptions(epicKeyByTitle)
    }

    private func fetchAndCacheEpicDescriptions(_ map: [String: String]) async {
        for (title, key) in map {
            do {
                let desc = try await fetchEpicDescription(for: key)
                if !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    EpicDescriptionCache.shared.setDescription(desc, for: title)
                }
            } catch {
                // Best-effort; ignore failures per epic
                await LogService.shared.log(
                    "Failed fetching description for epic \(title): \(error.localizedDescription)",
                    type: .warning)
            }
        }
    }

    private struct IssueDescriptionResult: Decodable {
        let fields: IssueDescriptionFields
    }
    private struct IssueDescriptionFields: Decodable {
        let description: ADFBody?
    }

    private func fetchEpicDescription(for epicKey: String) async throws -> String {
        let data = try await performAPIRequest(
            path: "/rest/api/3/issue/\(epicKey)",
            queryItems: [URLQueryItem(name: "fields", value: "description")]
        )
        let decoder = JSONDecoder()
        let result = try decoder.decode(IssueDescriptionResult.self, from: data)
        return adfText(result.fields.description)
    }

    private func adfText(_ body: ADFBody?) -> String {
        guard let body else { return "" }
        func extract(_ node: ADFNode) -> String {
            var t = node.text ?? ""
            if let children = node.content {
                for c in children { t += (t.isEmpty ? "" : " ") + extract(c) }
            }
            return t
        }
        return body.content.map { extract($0) }.joined(separator: " ")
    }

    func fetchComments(for issueKey: String) async throws -> [Comment] {
        var allComments: [Comment] = []
        var startAt = 0
        let maxResults = 50

        while true {
            let queryItems = [
                URLQueryItem(name: "startAt", value: "\(startAt)"),
                URLQueryItem(name: "maxResults", value: "\(maxResults)"),
            ]
            let data = try await performAPIRequest(
                path: "/rest/api/3/issue/\(issueKey)/comment", queryItems: queryItems)

            let decoder = JSONDecoder()
            let commentConnection: CommentConnection
            do {
                commentConnection = try decoder.decode(CommentConnection.self, from: data)
            } catch {
                throw JiraError.decodingFailed(error)
            }

            allComments.append(contentsOf: commentConnection.comments)

            if commentConnection.total > allComments.count {
                startAt += maxResults
            } else {
                break
            }
        }
        return allComments
    }

    private func performAPIRequest(path: String, queryItems: [URLQueryItem]) async throws -> Data {
        guard !jiraBaseURL.isEmpty, !jiraEmail.isEmpty, !jiraApiToken.isEmpty else {
            throw JiraError.configurationMissing
        }

        guard var components = URLComponents(string: jiraBaseURL) else {
            throw JiraError.invalidURL
        }

        components.path = path
        components.queryItems = queryItems

        guard let url = components.url else {
            throw JiraError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let credentials = "\(jiraEmail):\(jiraApiToken)"
        guard let credentialsData = credentials.data(using: .utf8) else {
            throw JiraError.invalidCredentials
        }
        let base64Credentials = credentialsData.base64EncodedString()
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw JiraError.requestFailed(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw JiraError.requestFailed(
                NSError(
                    domain: "JiraService", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid response from server."]))
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(decoding: data, as: UTF8.self)
            throw JiraError.httpError(statusCode: httpResponse.statusCode, body: body)
        }

        return data
    }
}

// FILE: Jiraiya.entitlements
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.network.client</key>
	<true/>
</dict>
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
    @StateObject private var outcomeManager = OutcomeManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(outcomeManager)
        }
    }
}

// FILE: LogService.swift
//
//  LogService.swift
//  Jiraiya
//
//  Created by Victor Noagbodji on 9/18/25.
//

import Foundation
import SwiftUI

@MainActor
final class LogService: ObservableObject {
    static let shared = LogService()

    @Published private(set) var logEntries: [LogEntry] = []

    func log(_ message: String, type: LogType, function: String = #function) {
        let formattedMessage = "\(function): \(message)"
        let entry = LogEntry(message: formattedMessage, type: type, timestamp: Date())
        logEntries.append(entry)
    }

    func clearLogs() {
        logEntries.removeAll()
    }
}

// FILE: LogView.swift
//
//  LogView.swift
//  Jiraiya
//
//  Created by Victor Noagbodji on 9/18/25.
//

import SwiftUI

struct LogView: View {
    @ObservedObject private var logService = LogService.shared
    @Binding var selection: Set<UUID>

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                ForEach(logService.logEntries) { entry in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LogMessageView(log: entry, isSelected: selection.contains(entry.id))
                            .id(entry.id)
                    }
                    .onTapGesture {
                        if selection.contains(entry.id) {
                            selection.remove(entry.id)
                        } else {
                            selection.insert(entry.id)
                        }
                    }
                }
            }
            .onChange(of: logService.logEntries) { _, newEntries in
                if let lastEntry = newEntries.last {
                    proxy.scrollTo(lastEntry.id, anchor: .bottom)
                }
            }
        }
    }
}

struct ConsoleHeaderView: View {
    @ObservedObject private var logService = LogService.shared
    @Binding var selection: Set<UUID>

    var body: some View {
        HStack {
            Text("Console").font(.headline)

            Spacer()

            Button(action: copyLogs) {
                Image(systemName: "doc.on.doc")
            }
            .help("Copy Selected Logs")
            .disabled(selection.isEmpty)

            Button(action: {
                selection.removeAll()
                logService.clearLogs()
            }) {
                Image(systemName: "trash")
            }
            .help("Clear Logs")
        }
    }

    private func copyLogs() {
        let entriesToCopy = logService.logEntries.filter { selection.contains($0.id) }
        let logText = entriesToCopy.map { "[\($0.timestamp)] \($0.message)" }.joined(
            separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logText, forType: .string)
    }
}

struct LogMessageView: View {
    let log: LogEntry
    let isSelected: Bool

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        HStack {
            Text(Self.formatter.string(from: log.timestamp)).foregroundColor(.secondary)
            symbol.foregroundColor(color)
            Text(log.message).foregroundColor(color)
        }
        .font(.system(.body, design: .monospaced))
        .background(isSelected ? Color.accentColor : Color.clear)
    }

    private var symbol: some View {
        switch log.type {
        case .info: return Image(systemName: "info.circle")
        case .success: return Image(systemName: "checkmark.circle")
        case .error: return Image(systemName: "xmark.circle")
        case .warning: return Image(systemName: "exclamationmark.circle")
        }
    }

    private var color: Color {
        switch log.type {
        case .info: return .primary
        case .success: return .green
        case .error: return .red
        case .warning: return .orange
        }
    }
}

// FILE: Logger.swift
//
//  Logger.swift
//  Jiraiya
//
//  Created by Victor Noagbodji on 9/18/25.
//

import Foundation

enum LogType {
    case info
    case success
    case error
    case warning
}

struct LogEntry: Identifiable, Hashable, Equatable {
    let id = UUID()
    let message: String
    let type: LogType
    let timestamp: Date
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
    var id: Date { date }
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
    @EnvironmentObject private var outcomeManager: OutcomeManager

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(outcomeCounts.keys.sorted(), id: \.self) { key in
                    let count = outcomeCounts[key] ?? 0
                    if count > 0 {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(outcomeManager.color(for: key))
                                .frame(width: 8, height: 8)
                            Text("\(key) \(count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                        .padding(.horizontal, 6)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        } label: {
            Text("\(month.name) \(month.year.formatted(.number.grouping(.never)))")
                .font(.headline)
        }
    }

    private var outcomeCounts: [String: Int] {
        Dictionary(grouping: month.stories, by: { $0.outcome }).mapValues { $0.count }
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
    @EnvironmentObject private var outcomeManager: OutcomeManager
    let month: Month
    let cal = Calendar.current

    var body: some View {
        let range = cal.range(of: .day, in: .month, for: month.date) ?? 1..<1
        let firstWeekday = cal.component(.weekday, from: month.date)
        let storiesByDay = Dictionary(grouping: month.stories) { story in
            cal.component(.day, from: story.completedAt)
        }

        ScrollView {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), alignment: .topLeading), count: 7),
                spacing: 8
            ) {
                // Empty slots before first day
                ForEach((0..<(firstWeekday - 1)).map { -$0 - 1 }, id: \.self) { _ in
                    Color.clear.frame(height: 40)
                }

                // Days of the month
                ForEach(range, id: \.self) { day in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(day)")
                            .font(.caption)
                        if let stories = storiesByDay[day] {
                            HStack(spacing: 2) {
                                ForEach(stories) { story in
                                    Circle()
                                        .fill(outcomeManager.color(for: story.outcome))
                                        .frame(width: 6, height: 6)
                                        .help(story.title)
                                }
                            }
                        } else {
                            Color.clear.frame(height: 6)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
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
        .navigationTitle(
            "\(Calendar.current.monthName(for: month.date)) \(month.year.formatted(.number.grouping(.never)))"
        )
    }
}

// FILE: Outcome.swift
//
//  Outcome.swift
//  Jiraiya
//
//  Created by Victor Noagbodji on 9/20/25.
//

import Foundation
import SwiftUI

struct Outcome: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var keywords: [String]
    var color: String

    // Default outcome for stories that don't match any keywords
    static var `default`: Outcome {
        Outcome(name: "Uncategorized", keywords: [], color: PredefinedColor.gray.rawValue)
    }
}
// FILE: OutcomeManager+Color.swift
//
//  OutcomeManager+Color.swift
//  Jiraiya
//
//  Created by Victor Noagbodji on 9/20/25.
//

import Foundation
import SwiftUI

extension OutcomeManager {
    func color(for outcomeName: String) -> Color {
        if let outcome = outcomes.first(where: { $0.name == outcomeName }),
           let predefinedColor = PredefinedColor(rawValue: outcome.color) {
            return predefinedColor.color
        }
        return PredefinedColor.gray.color
    }
}

// FILE: OutcomeManager.swift
//
//  OutcomeManager.swift
//  Jiraiya
//
//  Created by Victor Noagbodji on 9/20/25.
//

import Foundation
import SwiftUI

class OutcomeManager: ObservableObject {
    @AppStorage("outcomes") private var outcomesData: Data = Data()

    @Published var outcomes: [Outcome] {
        didSet {
            if !isInitializing {
                isDirty = true
            }
        }
    }
    @Published private(set) var isDirty: Bool = false
    private var isInitializing = true

    init() {
        self.outcomes = []    // Initialize first to satisfy the compiler
        self.outcomes = loadOutcomes()

        if self.outcomes.isEmpty {
            // Provide some default outcomes for the user to start with
            self.outcomes = [
                Outcome(
                    name: "Onboarding", keywords: ["onboarding", "signup", "welcome"],
                    color: PredefinedColor.blue.rawValue),
                Outcome(
                    name: "UX Improvement", keywords: ["ux", "ui", "design", "usability"],
                    color: PredefinedColor.orange.rawValue),
                Outcome(
                    name: "Sync", keywords: ["sync", "performance", "background"],
                    color: PredefinedColor.purple.rawValue),
            ]
        }
        isInitializing = false
        isDirty = false
    }

    func addOutcome() {
        let newOutcome = Outcome(
            name: "New Outcome", keywords: [], color: PredefinedColor.red.rawValue)
        outcomes.append(newOutcome)
    }

    func deleteOutcome(at offsets: IndexSet) {
        outcomes.remove(atOffsets: offsets)
    }

    private func loadOutcomes() -> [Outcome] {
        guard !outcomesData.isEmpty,
            let decodedOutcomes = try? JSONDecoder().decode([Outcome].self, from: outcomesData)
        else {
            return []
        }
        return decodedOutcomes
    }

    // Call this explicitly from UI when the user taps "Update Outcomes"
    func commit() {
        saveOutcomes()
        isDirty = false
    }

    private func saveOutcomes() {
        if let encodedData = try? JSONEncoder().encode(outcomes) {
            outcomesData = encodedData
        }
    }

    func outcome(for comments: [Comment]) -> Outcome {
        return outcome(forTitle: nil, comments: comments)
    }

    func outcome(forTitle title: String?, comments: [Comment]) -> Outcome {
        let commentsBlob = comments.compactMap { $0.body }
            .map { extractText(from: $0) }
            .joined(separator: " ")
        let haystack = ([title ?? "", commentsBlob].joined(separator: " ")).lowercased()

        for outcome in outcomes {
            for keyword in outcome.keywords {
                if haystack.contains(keyword.lowercased()) {
                    return outcome
                }
            }
        }
        return .default
    }

    func extractText(from adf: ADFBody) -> String {
        return adf.content.map { extractText(from: $0) }.joined(separator: " ")
    }

    func extractText(from node: ADFNode) -> String {
        var text = ""
        if let nodeText = node.text {
            text += nodeText
        }
        if let content = node.content {
            for child in content {
                text += " " + extractText(from: child)
            }
        }
        return text
    }
}

// FILE: OutcomeReclassifier.swift
import Foundation

enum OutcomeReclassifier {
    static func reclassifyAll(outcomeManager: OutcomeManager) async {
        let service = JiraService()
        do {
            // Fetch current stories from DB
            let stories = try DatabaseManager.shared.fetchStories()
            if stories.isEmpty { return }

            var updatedStories: [Story] = []

            for (index, story) in stories.enumerated() {
                // Fetch comments per issue and compute outcome again
                let comments = try await service.fetchComments(for: story.id)
                let outcome = outcomeManager.outcome(forTitle: story.title, comments: comments)
                let updated = Story(
                    id: story.id,
                    title: story.title,
                    completedAt: story.completedAt,
                    outcome: outcome.name,
                    epicTitle: story.epicTitle
                )
                updatedStories.append(updated)

                let progress = Double(index + 1) / Double(stories.count)
                NotificationCenter.default.post(
                    name: .reclassifyProgress,
                    object: nil,
                    userInfo: ["progress": progress]
                )
            }

            // Persist updates in a single transaction
            try await DatabaseManager.shared.replaceStories(updatedStories)

            NotificationCenter.default.post(name: .databaseDidReset, object: nil)
        } catch {
            await LogService.shared.log(
                "Reclassification failed: \(error.localizedDescription)", type: .error)
        }
    }
}

// FILE: OutcomeSettingsView.swift
//
//  OutcomeSettingsView.swift
//  Jiraiya
//
//  Created by Victor Noagbodji on 9/20/25.
//

import SwiftUI

struct OutcomeSettingsView: View {
    @ObservedObject var outcomeManager: OutcomeManager

    @State private var reclassifyProgress: Double? = nil

    var body: some View {
        Section {
            List {
                ForEach($outcomeManager.outcomes) { $outcome in
                    HStack {
                        Picker("Color", selection: $outcome.color) {
                            ForEach(PredefinedColor.allCases) { color in
                                Text("\u{25CF}")    // ● bullet
                                    .foregroundColor(color.color)
                                    .font(.system(size: 16))
                                    .tag(color.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(MenuPickerStyle())

                        TextField("Outcome Name", text: $outcome.name)

                        // Binding to transform the keywords array to a comma-separated string
                        TextField(
                            "Keywords",
                            text: Binding(
                                get: {
                                    outcome.keywords.joined(separator: ", ")
                                },
                                set: {
                                    outcome.keywords =
                                        $0
                                        .split(separator: ",")
                                        .map { $0.trimmingCharacters(in: .whitespaces) }
                                        .filter { !$0.isEmpty }
                                }
                            ))
                    }
                }
                .onDelete(perform: outcomeManager.deleteOutcome)
            }

            if let progress = reclassifyProgress, progress < 1.0 {
                ProgressView(value: progress)
                    .padding(.top, 4)
            } else if reclassifyProgress == 1.0 {
                Text("Reclassification complete")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } header: {
            HStack(spacing: 8) {
                Text("Outcomes")
                if outcomeManager.isDirty {
                    Text("Unsaved changes")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.yellow.opacity(0.2))
                        .cornerRadius(4)
                }
                Spacer()
                HStack(spacing: 8) {
                    Button(action: { outcomeManager.addOutcome() }) {
                        Image(systemName: "plus")
                    }
                    .help("Add Outcome")
                    Button(action: {
                        outcomeManager.commit()
                        Task {
                            await OutcomeReclassifier.reclassifyAll(outcomeManager: outcomeManager)
                        }
                    }) {
                        Image(systemName: "checkmark")
                    }
                    .help("Update Outcomes")
                    .disabled(!outcomeManager.isDirty)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .reclassifyProgress)) { note in
            if let progress = note.userInfo?["progress"] as? Double {
                reclassifyProgress = progress
                if progress >= 1.0 {
                    // Briefly show completion then clear
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        reclassifyProgress = nil
                    }
                }
            }
        }
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
    var id: String { name }
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
    @EnvironmentObject private var outcomeManager: OutcomeManager

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(outcomeCounts.keys.sorted(), id: \.self) { key in
                    let count = outcomeCounts[key] ?? 0
                    if count > 0 {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(outcomeManager.color(for: key))
                                .frame(width: 8, height: 8)
                            Text("\(key) \(count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                        .padding(.horizontal, 6)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        } label: {
            Text(quarter.name)
                .font(.headline)
        }
    }

    private var outcomeCounts: [String: Int] {
        let stories = quarter.epics.flatMap { $0.stories }
        return Dictionary(grouping: stories, by: { $0.outcome }).mapValues { $0.count }
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
import GRDB

struct Story: Identifiable, Hashable, Codable, FetchableRecord, PersistableRecord {
    var id: String
    let title: String
    let completedAt: Date
    let outcome: String
    let epicTitle: String

    static var databaseTableName = "story"
}

// FILE: StoryCard.swift
//
//  StoryCard.swift
//  Jiraiya
//
//  Created by Victor Noagbodji on 9/17/25.
//

import SwiftUI

struct StoryCard: View {
    @EnvironmentObject private var outcomeManager: OutcomeManager
    let story: Story

    var body: some View {
        GroupBox {
            VStack(alignment: .leading) {
                Text(
                    "Completed: \(story.completedAt.formatted(date: .abbreviated, time: .omitted))"
                )
                .font(.caption)
                .foregroundColor(.secondary)
                Text("Outcome: \(story.outcome)")
                    .font(.caption)
                    .foregroundColor(outcomeManager.color(for: story.outcome))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(story.title)
                .font(.headline)
        }
    }
}

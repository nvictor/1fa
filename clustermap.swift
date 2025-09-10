// FILE: Client.swift
//
//  Client.swift
//  Clustermap
//
//  Created by Victor Noagbodji on 8/16/25.
//

import Foundation
import Security
import os.log

enum ClientError: Error, LocalizedError {
    case httpError(statusCode: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .httpError(let statusCode, let body):
            return "Client: request: HTTP Error: Status \(statusCode)\n\(body)"
        }
    }
}

final class Client {
    private let creds: Credentials
    private let session: URLSession

    private struct ItemList<Item: Decodable>: Decodable {
        let items: [Item]
    }

    init(creds: Credentials) throws {
        self.creds = creds

        let delegate = TLSDelegate(
            caCert: creds.caData.flatMap(IdentityService.createCert),
            clientIdentity: creds.certData.flatMap(IdentityService.find),
            insecure: creds.insecure
        )

        self.session = URLSession(
            configuration: .default,
            delegate: delegate,
            delegateQueue: nil
        )
    }

    func listNamespaces() async throws -> [KubeNamespace] {
        try await list(path: "/api/v1/namespaces")
    }

    func listDeployments(namespace: String) async throws -> [KubeDeployment] {
        try await list(path: "/apis/apps/v1/namespaces/\(namespace)/deployments")
    }

    func listPods(namespace: String, selector: String?) async throws -> [KubePod] {
        let queryItems: [URLQueryItem]? = selector.flatMap { s in
            s.isEmpty ? nil : [URLQueryItem(name: "labelSelector", value: s)]
        }
        return try await list(path: "/api/v1/namespaces/\(namespace)/pods", queryItems: queryItems)
    }

    func listPodMetrics(namespace: String) async throws -> [PodMetrics] {
        try await list(path: "/apis/metrics.k8s.io/v1beta1/namespaces/\(namespace)/pods")
    }

    private func list<Item: Decodable>(path: String, queryItems: [URLQueryItem]? = nil) async throws
        -> [Item]
    {
        let listResult: ItemList<Item> = try await request(path: path, queryItems: queryItems)
        return listResult.items
    }

    private func request<T: Decodable>(path: String, queryItems: [URLQueryItem]? = nil) async throws
        -> T
    {
        var components = URLComponents(
            url: creds.server.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = queryItems

        var req = URLRequest(url: components.url!)
        req.httpMethod = "GET"
        if let token = creds.token {
            req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        req.addValue("application/json", forHTTPHeaderField: "Accept")
        req.addValue(
            "Clustermap/1.0 (darwin/arm64) kubernetes-client", forHTTPHeaderField: "User-Agent")

        let (data, resp) = try await session.data(for: req)
        guard let httpResponse = resp as? HTTPURLResponse,
            (200..<300).contains(httpResponse.statusCode)
        else {
            let body = String(decoding: data, as: UTF8.self)
            let statusCode = (resp as? HTTPURLResponse)?.statusCode ?? -1
            throw ClientError.httpError(statusCode: statusCode, body: body)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }
}

// FILE: ClusterService.swift
//
//  ClusterService.swift
//  Clustermap
//
//  Created by Victor Noagbodji on 8/16/25.
//

import Foundation

struct ClusterService {
    func fetchTree(from path: String, metric: SizingMetric) async
        -> Result<TreeNode, Error>
    {
        do {
            let snapshot = try await fetchClusterData(from: path)
            let tree = TreeBuilder.build(snapshot: snapshot, metric: metric)
            return .success(tree)
        } catch {
            return .failure(error)
        }
    }

    private func fetchClusterData(from path: String) async throws -> ClusterSnapshot {
        let config = try ConfigLoader.parseKubeConfig(at: path)
        let creds = try await ConfigLoader.makeCredentials(config)
        let client = try Client(creds: creds)

        let namespaces = try await client.listNamespaces()
        await LogService.shared.log(
            "Loaded namespaces: \(namespaces.map(\.metadata.name))", type: .info)

        let (deploymentsByNS, podsByNS, metricsByNS) = try await fetchNamespaceResources(
            for: namespaces,
            using: client
        )

        return ClusterSnapshot(
            namespaces: namespaces,
            deploymentsByNS: deploymentsByNS,
            podsByNS: podsByNS,
            metricsByNS: metricsByNS
        )
    }

    private func fetchNamespaceResources(
        for namespaces: [KubeNamespace],
        using client: Client
    ) async throws -> ([String: [KubeDeployment]], [String: [KubePod]], [String: [PodMetrics]]) {
        var deploymentsByNS = [String: [KubeDeployment]]()
        var podsByNS = [String: [KubePod]]()
        var metricsByNS = [String: [PodMetrics]]()

        try await withThrowingTaskGroup(of: NamespaceResources.self) { group in
            for namespace in namespaces {
                group.addTask {
                    try await fetchResourcesForNamespace(namespace.metadata.name, using: client)
                }
            }

            for try await resources in group {
                deploymentsByNS[resources.name] = resources.deployments
                podsByNS[resources.name] = resources.pods
                metricsByNS[resources.name] = resources.metrics
            }
        }

        return (deploymentsByNS, podsByNS, metricsByNS)
    }

    private func fetchResourcesForNamespace(_ name: String, using client: Client) async throws
        -> NamespaceResources
    {
        async let deployments = client.listDeployments(namespace: name)
        async let pods = client.listPods(namespace: name, selector: nil)

        let metrics: [PodMetrics]
        do {
            metrics = try await client.listPodMetrics(namespace: name)
        } catch {
            await LogService.shared.log(
                "Could not fetch metrics for namespace \(name): \(error.localizedDescription)",
                type: .error)
            metrics = []
        }

        let (d, p) = try await (deployments, pods)
        return NamespaceResources(name: name, deployments: d, pods: p, metrics: metrics)
    }
}

private struct NamespaceResources {
    let name: String
    let deployments: [KubeDeployment]
    let pods: [KubePod]
    let metrics: [PodMetrics]
}

// FILE: ClusterViewModel.swift
//
//  ClusterViewModel.swift
//  Clustermap
//
//  Created by Victor Noagbodji on 8/16/25.
//

import Foundation
import SwiftUI

@MainActor
final class ClusterViewModel: ObservableObject {
    @Published var metric: SizingMetric = .count { didSet { reload() } }
    @Published var root: TreeNode = TreeNode(name: "Welcome", value: 1, children: [])
    @Published var maxLeafValue: Double = 1.0
    @Published var logEntries: [LogEntry] = []
    @Published var selectedPath: [UUID]?
    @Published var kubeconfigPath: String = ConfigLoader.loadDefaultPath()

    private let service = ClusterService()

    func reload() {
        Task { await loadCluster() }
    }

    func loadCluster() async {
        LogService.shared.clearLogs()
        LogService.shared.log("Loading cluster from \(kubeconfigPath)...", type: .info)

        let result = await service.fetchTree(
            from: kubeconfigPath,
            metric: metric
        )

        switch result {
        case .success(let newRoot):
            self.root = newRoot
            self.maxLeafValue = findMaxLeafValue(in: newRoot)
            self.selectedPath = nil    // Reset zoom when loading new data
        case .failure(let error):
            self.root = TreeNode(name: "Error", value: 1, children: [])
            LogService.shared.log("Error: \(error.localizedDescription)", type: .error)
        }
    }

    private func findMaxLeafValue(in node: TreeNode) -> Double {
        if node.isLeaf {
            return node.value
        }
        return node.children.reduce(0) { max($0, findMaxLeafValue(in: $1)) }
    }
}

// FILE: Clustermap.entitlements
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<false/>
	<key>com.apple.security.files.user-selected.read-only</key>
	<true/>
	<key>com.apple.security.network.client</key>
	<true/>
	<key>com.apple.security.personal-information.location</key>
	<false/>
	<key>keychain-access-groups</key>
	<array>
		<string>$(AppIdentifierPrefix)com.mellowfleet.Clustermap</string>
	</array>
</dict>
</plist>

// FILE: ClustermapApp.swift
//
//  ClustermapApp.swift
//  Clustermap
//
//  Created by Victor Noagbodji on 8/16/25.
//

import SwiftUI

@main
struct ClustermapApp: App {
    @StateObject private var viewModel = ClusterViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .navigationTitle("Clustermap")
        }
    }
}

// FILE: ConfigLoader.swift
//
//  ConfigLoader.swift
//  Clustermap
//
//  Created by Victor Noagbodji on 8/16/25.
//

import Foundation
import Yams

struct KubeConfig: Codable {
    let clusters: [ClusterEntry]
    let contexts: [ContextEntry]
    let users: [UserEntry]
    let currentContext: String?

    enum CodingKeys: String, CodingKey {
        case clusters, contexts, users
        case currentContext = "current-context"
    }

    struct ClusterEntry: Codable {
        let name: String
        let cluster: Cluster
    }
    struct ContextEntry: Codable {
        let name: String
        let context: Context
    }
    struct UserEntry: Codable {
        let name: String
        let user: User
    }

    struct Cluster: Codable {
        let server: String
        let caData: String?
        let ca: String?
        let insecure: Bool?

        enum CodingKeys: String, CodingKey {
            case server
            case caData = "certificate-authority-data"
            case ca = "certificate-authority"
            case insecure = "insecure-skip-tls-verify"
        }
    }

    struct Context: Codable {
        let cluster: String
        let user: String
    }

    struct User: Codable {
        let token: String?
        let exec: ExecConfig?
        let clientCertificateData: String?
        let clientCertificate: String?

        enum CodingKeys: String, CodingKey {
            case token, exec
            case clientCertificateData = "client-certificate-data"
            case clientCertificate = "client-certificate"
        }
    }

    struct ExecConfig: Codable {
        let command: String
        let args: [String]?
        let env: [EnvVar]?
        struct EnvVar: Codable {
            let name: String
            let value: String
        }
    }
}

enum ConfigLoaderError: Error, LocalizedError {
    case fileNotFound(String)
    case contextNotFound(String)
    case clusterNotFound(String)
    case userNotFound(String)
    case invalidServerURL(String)
    case execCommandFailed(command: String, exitCode: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .contextNotFound(let name):
            return "Context '\(name)' not found"
        case .clusterNotFound(let name):
            return "Cluster '\(name)' not found"
        case .userNotFound(let name):
            return "User '\(name)' not found"
        case .invalidServerURL(let url):
            return "Invalid server URL: \(url)"
        case .execCommandFailed(let command, let exitCode, let stderr):
            return "'\(command)' failed with exit code \(exitCode): \(stderr)"
        }
    }
}

final class ConfigLoader {
    static func loadDefaultPath() -> String {
        "~/.kube/config"
    }

    static func parseKubeConfig(at path: String) throws -> KubeConfig {
        let path = expandTilde(path)
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            throw ConfigLoaderError.fileNotFound(path)
        }
        return try YAMLDecoder().decode(KubeConfig.self, from: data)
    }

    static func makeCredentials(_ config: KubeConfig, usingContext contextName: String? = nil)
        async throws -> Credentials
    {
        let context = try findContext(in: config, name: contextName)
        let cluster = try findCluster(in: config, name: context.cluster)
        let user = try findUser(in: config, name: context.user)

        guard let serverURL = URL(string: cluster.server) else {
            throw ConfigLoaderError.invalidServerURL(cluster.server)
        }

        let token = try await getToken(from: user)
        let caData = parseCertificateData(path: cluster.ca, dataString: cluster.caData)
        let certData = parseCertificateData(
            path: user.clientCertificate, dataString: user.clientCertificateData)
        let insecure = cluster.insecure ?? shouldSkipTLSVerifyForServer(serverURL)

        return Credentials(
            server: serverURL, token: token, caData: caData, certData: certData, insecure: insecure)
    }

    private static func findContext(in config: KubeConfig, name: String?) throws
        -> KubeConfig.Context
    {
        let contextName = name ?? config.currentContext ?? config.contexts.first?.name
        guard let name = contextName, let entry = config.contexts.first(where: { $0.name == name })
        else {
            throw ConfigLoaderError.contextNotFound(name ?? "default")
        }
        return entry.context
    }

    private static func findCluster(in config: KubeConfig, name: String) throws
        -> KubeConfig.Cluster
    {
        guard let entry = config.clusters.first(where: { $0.name == name }) else {
            throw ConfigLoaderError.clusterNotFound(name)
        }
        return entry.cluster
    }

    private static func findUser(in config: KubeConfig, name: String) throws -> KubeConfig.User {
        guard let entry = config.users.first(where: { $0.name == name }) else {
            throw ConfigLoaderError.userNotFound(name)
        }
        return entry.user
    }

    private static func getToken(from user: KubeConfig.User) async throws -> String? {
        if let token = user.token {
            return token
        }
        if let exec = user.exec {
            return try await executeForToken(exec)
        }
        return nil
    }

    private static func executeForToken(_ exec: KubeConfig.ExecConfig) async throws -> String {
        struct ExecCredential: Codable {
            struct Status: Codable { let token: String }
            let status: Status
        }
        let env = exec.env?.reduce(into: [:]) { $0[$1.name] = $1.value } ?? [:]
        let tokenData = try await execute(command: exec.command, args: exec.args, extraEnv: env)
        let cred = try JSONDecoder().decode(ExecCredential.self, from: tokenData)
        return cred.status.token
    }

    private static func execute(command: String, args: [String]?, extraEnv: [String: String])
        async throws -> Data
    {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + (args ?? [])

        var env = ProcessInfo.processInfo.environment
        let defaultPaths = [
            "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin",
        ]
        env["PATH"] = (env["PATH"].map { "\($0):" } ?? "") + defaultPaths.joined(separator: ":")
        extraEnv.forEach { env[$0] = $1 }
        process.environment = env

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()

        // It's important to read the data before waiting for the process to exit.
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        process.waitUntilExit()

        if process.terminationStatus == 0 {
            return outputData
        } else {
            let errorString = String(decoding: errorData, as: UTF8.self)
            throw ConfigLoaderError.execCommandFailed(
                command: command, exitCode: process.terminationStatus, stderr: errorString)
        }
    }

    private static func parseCertificateData(path: String?, dataString: String?) -> Data? {
        if let path = path,
            let fileContent = try? String(
                contentsOf: URL(fileURLWithPath: expandTilde(path)), encoding: .utf8)
        {
            return convertPEMToDER(fileContent)
        }
        if let dataString = dataString, let decodedData = Data(base64Encoded: dataString) {
            // Check if the base64 data is itself a PEM string
            if let pemContent = String(data: decodedData, encoding: .utf8),
                pemContent.contains("-----BEGIN")
            {
                return convertPEMToDER(pemContent)
            }
            return decodedData    // Assume raw DER data
        }
        return nil
    }

    private static func expandTilde(_ path: String) -> String {
        path.replacingOccurrences(
            of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path)
    }

    private static func convertPEMToDER(_ pemString: String) -> Data? {
        let lines = pemString.components(separatedBy: .newlines)
        let base64Content = lines.filter { !$0.hasPrefix("-----") && !$0.isEmpty }.joined()
        return Data(base64Encoded: base64Content)
    }

    private static func shouldSkipTLSVerifyForServer(_ url: URL) -> Bool {
        guard let host = url.host else { return false }
        let devPatterns = ["minikube", "localhost", "127.0.0.1", "\\.local$"]
        if let regex = try? NSRegularExpression(pattern: devPatterns.joined(separator: "|")),
            regex.firstMatch(
                in: host, options: [], range: NSRange(location: 0, length: host.utf16.count)) != nil
        {
            return true
        }

        // Check for common private IP ranges
        return host.starts(with: "192.168.") || host.starts(with: "10.")
            || (host.starts(with: "172.")
                && (16...31).contains(Int(host.split(separator: ".")[1]) ?? 0))
    }
}

// FILE: ConsoleView.swift
//
//  ConsoleView.swift
//  Clustermap
//
//  Created by Victor Noagbodji on 8/16/25.
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

// FILE: Constants.swift
//
//  Constants.swift
//  Clustermap
//
//  Created by Victor Noagbodji on 8/16/25.
//

import Foundation
import SwiftUI

struct LayoutConstants {
    static let captionHeight: CGFloat = 12
    static let padding: CGFloat = 3
    static let minNodeWidth: CGFloat = 20
    static let minNodeHeight: CGFloat = 14
    static let minDisplayWidth: CGFloat = 40
    static let minDisplayHeight: CGFloat = 28
    static let borderWidth: CGFloat = 0.5
    static let textPadding: CGFloat = 6
    static let textVerticalPadding: CGFloat = 4
    static let mainPadding: CGFloat = 8
    static let minValueThreshold: Double = 0.1
}

struct ColorConstants {
    static let saturation: Double = 0.7
    static let brightness: Double = 0.8
    static let hoverOpacity: Double = 0.2
}

enum SizingMetric: String, CaseIterable, Identifiable {
    case count = "Count"
    case cpu = "CPU"
    case memory = "Memory"
    var id: String { rawValue }
}

extension Color {
    static func from(string: String) -> Color {
        let hash = string.unicodeScalars.reduce(0) { $0 ^ $1.value }
        let hue = Double(hash % 256) / 256.0
        return Color(
            hue: hue,
            saturation: ColorConstants.saturation,
            brightness: ColorConstants.brightness
        )
    }

    var luminance: Double {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        NSColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)
    }
}

// FILE: ContentView.swift
//
//  ContentView.swift
//  Clustermap
//
//  Created by Victor Noagbodji on 8/16/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: ClusterViewModel
    @State private var showInspector = true

    var body: some View {
        TreemapView(node: viewModel.root, maxLeafValue: viewModel.maxLeafValue)
            .inspector(isPresented: $showInspector) {
                Inspector()
            }
            .task {
                if viewModel.root.name == "Welcome" {
                    await viewModel.loadCluster()
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    Button(action: viewModel.reload) {
                        Image(systemName: "arrow.clockwise")
                    }
                    Button(action: { showInspector.toggle() }) {
                        Image(systemName: "sidebar.trailing")
                    }
                }
            }
    }
}

// FILE: IdentityService.swift
//
//  IdentityService.swift
//  Clustermap
//
//  Created by Victor Noagbodji on 8/16/25.
//

import Foundation
import Security

struct IdentityService {
    static func createCert(from data: Data) -> SecCertificate? {
        guard let cert = SecCertificateCreateWithData(nil, data as CFData) else {
            Task { @MainActor in
                LogService.shared.log("Cannot create certificate from data.", type: .error)
            }
            return nil
        }
        return cert
    }

    static func find(with data: Data) -> SecIdentity? {
        guard let cert = createCert(from: data) else {
            return nil
        }
        var identity: SecIdentity?
        let status = SecIdentityCreateWithCertificate(nil, cert, &identity)
        if status != errSecSuccess {
            Task { @MainActor in
                LogService.shared.log("Cannot find SecIdentity (status: \(status)).", type: .error)
            }
            return nil
        }
        return identity
    }
}

// FILE: Info.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSAppTransportSecurity</key>
	<dict>
		<key>NSExceptionDomains</key>
		<dict>
			<key>127.0.0.1</key>
			<dict>
				<key>NSIncludesSubdomains</key>
				<true/>
				<key>NSExceptionAllowsInsecureHTTPLoads</key>
				<true/>
			</dict>
		</dict>
	</dict>
</dict>
</plist>

// FILE: Inspector.swift
//
//  Inspector.swift
//  Clustermap
//
//  Created by Victor Noagbodji on 8/16/25.
//

import SwiftUI

struct Inspector: View {
    @EnvironmentObject private var viewModel: ClusterViewModel

    var body: some View {
        Form {
            Section("Connection") {
                TextField("kubeconfig path", text: $viewModel.kubeconfigPath)
                    .textFieldStyle(.roundedBorder)
                Button("Load config", action: viewModel.reload)
            }
            Section("Display") {
                Picker("Sizing Metric", selection: $viewModel.metric) {
                    ForEach(SizingMetric.allCases) { metric in
                        Text(metric.rawValue).tag(metric)
                    }
                }
                .pickerStyle(.segmented)
            }
            ConsoleView()
        }
    }
}

// FILE: LogService.swift
//
//  LogService.swift
//  Clustermap
//
//  Created by Victor Noagbodji on 8/16/25.
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
//  Clustermap
//
//  Created by Victor Noagbodji on 8/16/25.
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
        let logText = entriesToCopy.map { "[\($0.timestamp)] [\($0.type)] \($0.message)" }.joined(
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
        }
    }

    private var color: Color {
        switch log.type {
        case .info: return .primary
        case .success: return .green
        case .error: return .red
        }
    }
}

// FILE: Models.swift
//
//  Models.swift
//  Clustermap
//
//  Created by Victor Noagbodji on 8/16/25.
//

import Foundation

struct TreeNode: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let value: Double
    let children: [TreeNode]
    var isLeaf: Bool { children.isEmpty }
}

struct OwnerReference: Codable, Hashable {
    let apiVersion: String
    let kind: String
    let name: String
    let uid: String
}
struct ObjectMeta: Codable, Hashable {
    let name: String
    let namespace: String?
    let labels: [String: String]?
    let uid: String?
    let ownerReferences: [OwnerReference]?
}
struct KubeNamespace: Codable, Hashable, Identifiable {
    let metadata: ObjectMeta
    var id: String { metadata.name }
}
struct KubeNamespaceList: Codable { let items: [KubeNamespace] }
struct ResourceRequirements: Codable, Hashable {
    let requests: [String: String]?
    let limits: [String: String]?
}
struct ContainerSpec: Codable, Hashable {
    let name: String
    let resources: ResourceRequirements?
}
struct PodSpec: Codable, Hashable { let containers: [ContainerSpec]? }
struct PodStatus: Codable, Hashable { let phase: String? }
struct KubePod: Codable, Hashable, Identifiable {
    let metadata: ObjectMeta
    let spec: PodSpec?
    let status: PodStatus?
    var id: String { metadata.name }
}
struct KubePodList: Codable { let items: [KubePod] }
struct PodTemplate: Codable, Hashable { let spec: PodSpec? }
struct DeploymentSpec: Codable, Hashable {
    let replicas: Int?
    let template: PodTemplate?
}
struct DeploymentStatus: Codable, Hashable { let availableReplicas: Int? }
struct KubeDeployment: Codable, Hashable, Identifiable {
    let metadata: ObjectMeta
    let spec: DeploymentSpec?
    let status: DeploymentStatus?
    var id: String { metadata.name }
}
struct KubeDeploymentList: Codable { let items: [KubeDeployment] }

struct MetricUsage: Codable, Hashable {
    let cpu: String
    let memory: String
}

struct ContainerMetrics: Codable, Hashable {
    let name: String
    let usage: MetricUsage
}

struct PodMetrics: Codable, Hashable {
    let metadata: ObjectMeta
    let timestamp: String
    let window: String
    let containers: [ContainerMetrics]
}

struct PodMetricsList: Codable {
    let items: [PodMetrics]
}

struct ClusterSnapshot {
    let namespaces: [KubeNamespace]
    let deploymentsByNS: [String: [KubeDeployment]]
    let podsByNS: [String: [KubePod]]
    let metricsByNS: [String: [PodMetrics]]

    static func empty() -> ClusterSnapshot {
        .init(namespaces: [], deploymentsByNS: [:], podsByNS: [:], metricsByNS: [:])
    }
}

struct Credentials {
    let server: URL
    let token: String?
    let caData: Data?
    let certData: Data?
    let insecure: Bool
}

enum LogType {
    case info
    case success
    case error
}

struct LogEntry: Identifiable, Hashable {
    let id = UUID()
    let message: String
    let type: LogType
    let timestamp: Date
}

// FILE: TLSDelegate.swift
//
//  TLSDeleagte.swift
//  Clustermap
//
//  Created by Victor Noagbodji on 8/16/25.
//

import Foundation
import Security
import os.log

final class TLSDelegate: NSObject, URLSessionDelegate {
    private let caCert: SecCertificate?
    private let clientIdentity: SecIdentity?
    private let insecure: Bool

    init(caCert: SecCertificate?, clientIdentity: SecIdentity?, insecure: Bool = false) {
        self.caCert = caCert
        self.clientIdentity = clientIdentity
        self.insecure = insecure
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let result =
            switch challenge.protectionSpace.authenticationMethod {
            case NSURLAuthenticationMethodServerTrust:
                handleServerTrust(challenge)
            case NSURLAuthenticationMethodClientCertificate:
                handleClientCertificate(challenge)
            default:
                (URLSession.AuthChallengeDisposition.performDefaultHandling, nil as URLCredential?)
            }
        completionHandler(result.0, result.1)
    }

    private func handleServerTrust(_ challenge: URLAuthenticationChallenge) -> (
        URLSession.AuthChallengeDisposition, URLCredential?
    ) {
        guard let trust = challenge.protectionSpace.serverTrust else {
            Task { @MainActor in
                LogService.shared.log(
                    "Server trust challenge failed: no server trust object.", type: .error)
            }
            return (.cancelAuthenticationChallenge, nil)
        }

        let shouldAcceptTrust = insecure || validateWithCustomCA(trust)

        if shouldAcceptTrust {
            return (.useCredential, URLCredential(trust: trust))
        } else if caCert != nil {
            return (.cancelAuthenticationChallenge, nil)
        } else {
            return (.performDefaultHandling, nil)
        }
    }

    private func validateWithCustomCA(_ trust: SecTrust) -> Bool {
        guard let ca = caCert else { return false }

        SecTrustSetAnchorCertificates(trust, [ca] as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)
        SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, nil))

        var error: CFError?
        let isValid = SecTrustEvaluateWithError(trust, &error)

        if !isValid {
            let errorDescription = String(
                describing: error?.localizedDescription ?? "Unknown error")
            Task { @MainActor in
                LogService.shared.log(
                    "Server trust validation failed: \(errorDescription)", type: .error)
            }
        }

        return isValid
    }

    private func handleClientCertificate(_ challenge: URLAuthenticationChallenge) -> (
        URLSession.AuthChallengeDisposition, URLCredential?
    ) {
        guard let identity = clientIdentity else {
            return (.performDefaultHandling, nil)
        }

        let credential = URLCredential(
            identity: identity, certificates: nil, persistence: .forSession)
        return (.useCredential, credential)
    }
}

// FILE: TreeBuilder.swift
//
//  TreeBuilder.swift
//  Clustermap
//
//  Created by Victor Noagbodji on 8/16/25.
//

import Foundation
import SwiftUI

struct TreeBuilder {
    static func build(snapshot: ClusterSnapshot, metric: SizingMetric)
        -> TreeNode
    {
        return buildByResourceType(snapshot: snapshot, metric: metric)
    }

    private static func buildByResourceType(snapshot: ClusterSnapshot, metric: SizingMetric)
        -> TreeNode
    {
        let namespaceNodes = snapshot.namespaces.compactMap { namespace in
            createNamespaceNodeByResourceType(
                namespace: namespace,
                snapshot: snapshot,
                metric: metric
            )
        }

        return createTreeNode(name: "Cluster", children: namespaceNodes)
    }

    private static func createNamespaceNodeByResourceType(
        namespace: KubeNamespace,
        snapshot: ClusterSnapshot,
        metric: SizingMetric
    ) -> TreeNode? {
        let deployments = snapshot.deploymentsByNS[namespace.metadata.name] ?? []
        let pods = snapshot.podsByNS[namespace.metadata.name] ?? []

        let deploymentNodes = deployments.compactMap { deployment in
            createDeploymentNodeWithPods(
                deployment: deployment, pods: pods, snapshot: snapshot, metric: metric)
        }

        guard !deploymentNodes.isEmpty else { return nil }
        return createTreeNode(name: namespace.metadata.name, children: deploymentNodes)
    }

    private static func createDeploymentNodeWithPods(
        deployment: KubeDeployment,
        pods: [KubePod],
        snapshot: ClusterSnapshot,
        metric: SizingMetric
    ) -> TreeNode? {
        let ownedPods = findOwnedPods(for: deployment, in: pods)

        let podNodes = ownedPods.map { pod in
            createLeafNode(
                name: pod.metadata.name,
                value: calculateMetricValue(for: pod, in: snapshot, metric: metric)
            )
        }

        guard !podNodes.isEmpty else { return nil }
        return createTreeNode(name: deployment.metadata.name, children: podNodes)
    }

    private static func createTreeNode(name: String, children: [TreeNode]) -> TreeNode {
        let totalValue = children.reduce(0) { $0 + $1.value }
        return TreeNode(name: name, value: totalValue, children: children)
    }

    private static func createLeafNode(name: String, value: Double) -> TreeNode {
        TreeNode(name: name, value: value, children: [])
    }

    private static func findOwnedPods(for deployment: KubeDeployment, in pods: [KubePod])
        -> [KubePod]
    {
        pods.filter { pod in
            let ownerNames = pod.metadata.ownerReferences?.map { $0.name } ?? []
            return ownerNames.contains { $0.starts(with: deployment.metadata.name) }
        }
    }

    private static func calculateMetricValue(
        for pod: KubePod, in snapshot: ClusterSnapshot, metric: SizingMetric
    ) -> Double {
        switch metric {
        case .count:
            return 1.0
        case .cpu, .memory:
            guard let podMetrics = snapshot.metricsByNS[pod.metadata.namespace ?? ""]?
                .first(where: { $0.metadata.name == pod.metadata.name })
            else {
                return 0.0
            }
            return ResourceCalculator.totalUsage(for: podMetrics, metric: metric)
        }
    }
}

private struct ResourceCalculator {
    static func totalUsage(for metrics: PodMetrics, metric: SizingMetric) -> Double {
        metrics.containers.reduce(0) { total, container in
            let value: Double
            switch metric {
            case .cpu:
                value = parseCpuUsage(container.usage.cpu) ?? 0
            case .memory:
                value = parseMemoryUsage(container.usage.memory) ?? 0
            case .count:
                value = 1.0
            }
            return total + value
        }
    }

    private static func parseCpuUsage(_ value: String?) -> Double? {
        guard var value = value else { return nil }

        if value.hasSuffix("n") {
            value.removeLast()
            return (Double(value) ?? 0) / 1_000_000_000.0
        }
        if value.hasSuffix("u") {
            value.removeLast()
            return (Double(value) ?? 0) / 1_000_000.0
        }
        if value.hasSuffix("m") {
            value.removeLast()
            return (Double(value) ?? 0) / 1000.0
        }
        return Double(value)
    }

    private static func parseMemoryUsage(_ value: String?) -> Double? {
        guard let value = value else { return nil }

        let units: [(String, Double)] = [
            ("Ki", 1024), ("Mi", 1024 * 1024), ("Gi", 1024 * 1024 * 1024),
            ("K", 1000), ("M", 1_000_000), ("G", 1_000_000_000),
        ]

        for (unit, multiplier) in units {
            if value.hasSuffix(unit),
                let number = Double(value.dropLast(unit.count))
            {
                return number * multiplier
            }
        }

        return Double(value)
    }
}

// FILE: TreemapView.swift
//
//  TreemapView.swift
//  Clustermap
//
//  Created by Victor Noagbodji on 8/16/25.
//

import SwiftUI

struct TreemapView: View {
    @EnvironmentObject private var viewModel: ClusterViewModel

    let node: TreeNode
    let maxLeafValue: Double
    let path: [UUID]
    @State private var hoveredPath: [UUID]?

    init(node: TreeNode, maxLeafValue: Double? = nil, path: [UUID]? = nil) {
        self.node = node
        self.maxLeafValue = maxLeafValue ?? 1.0
        self.path = path ?? [node.id]
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: node.isLeaf ? .center : .topLeading) {
                backgroundView
                if node.isLeaf {
                    leafView
                } else {
                    labelView(geometry: geometry)
                    childrenView(geometry: geometry)
                }
            }
        }
        .background(Color(.windowBackgroundColor))
        .clipped()
        .padding(LayoutConstants.mainPadding)
    }

    private var backgroundView: some View {
        Rectangle()
            .fill(nodeColor)
            .border(.black, width: LayoutConstants.borderWidth)
            .overlay(isHovered ? Color.black.opacity(ColorConstants.hoverOpacity) : .clear)
            .onHover(perform: handleHover)
            .contentShape(Rectangle())
            .onTapGesture(perform: handleTap)
    }

    private var leafView: some View {
        VStack {
            Text(node.name)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(formatValue(node.value))
                .font(.caption2)
                .opacity(0.8)
        }
        .foregroundColor(readableTextColor)
        .padding(4)
        .contentShape(Rectangle())
        .help("\(node.name)\nValue: \(node.value)")
    }

    private func labelView(geometry: GeometryProxy) -> some View {
        Text(node.name)
            .font(.caption)
            .fontWeight(.medium)
            .multilineTextAlignment(.center)
            .foregroundStyle(labelColor)
            .frame(width: geometry.size.width - LayoutConstants.textPadding)
            .padding(.top, LayoutConstants.textVerticalPadding)
            .padding(.bottom, LayoutConstants.textVerticalPadding)
    }

    private func childrenView(geometry: GeometryProxy) -> some View {
        ForEach(layoutChildren(in: geometry.size)) { child in
            TreemapView(
                node: child.node, maxLeafValue: maxLeafValue, path: path + [child.node.id]
            )
            .frame(width: child.frame.width, height: child.frame.height)
            .position(x: child.frame.midX, y: child.frame.midY)
        }
    }

    private var nodeColor: Color {
        if node.isLeaf {
            guard maxLeafValue > 0 else { return .gray }
            let ratio = node.value / maxLeafValue
            return Color(hue: 0.3 * (1 - ratio), saturation: 0.8, brightness: 0.9)
        } else {
            return Color.from(string: node.name)
        }
    }

    private var readableTextColor: Color {
        nodeColor.luminance > 0.5 ? .black : .white
    }

    private var labelColor: Color {
        let zoomController = ZoomController(selectedPath: viewModel.selectedPath, currentPath: path)
        if zoomController.shouldHighlightLabel() {
            return readableTextColor
        } else {
            return .gray
        }
    }

    private var isHovered: Bool {
        hoveredPath?.starts(with: path) ?? false
    }

    private func handleHover(_ hovering: Bool) {
        hoveredPath = hovering ? path : (hoveredPath == path ? nil : hoveredPath)
    }

    private func handleTap() {
        if path.count == 1 {
            // Root node - clear selection
            viewModel.selectedPath = nil
        } else if !node.isLeaf {
            // Non-leaf node - toggle zoom
            viewModel.selectedPath = (viewModel.selectedPath == path) ? nil : path
        }
    }

    private func layoutChildren(in size: CGSize) -> [ChildLayout] {
        let zoomController = ZoomController(selectedPath: viewModel.selectedPath, currentPath: path)

        guard zoomController.shouldShowChildren else { return [] }

        let availableRect = calculateAvailableRect(in: size)
        guard isRectLargeEnough(availableRect) else { return [] }

        let visibleChildren = zoomController.getVisibleChildren(from: node.children)
        guard !visibleChildren.isEmpty else { return [] }

        return TreemapLayoutCalculator.layout(children: visibleChildren, in: availableRect)
    }

    private func calculateAvailableRect(in size: CGSize) -> CGRect {
        CGRect(
            x: LayoutConstants.padding,
            y: LayoutConstants.captionHeight + LayoutConstants.padding,
            width: size.width - 2 * LayoutConstants.padding,
            height: size.height - LayoutConstants.captionHeight - 2 * LayoutConstants.padding
        )
    }

    private func isRectLargeEnough(_ rect: CGRect) -> Bool {
        rect.width > LayoutConstants.minDisplayWidth
            && rect.height > LayoutConstants.minDisplayHeight
    }

    private func formatValue(_ v: Double) -> String {
        if viewModel.metric == .cpu && v < 1.0 && v > 0 {
            return String(format: "%.0fm", v * 1000)
        }
        if v >= 1_000_000_000 { return String(format: "%.1fG", v / 1_000_000_000) }
        if v >= 1_000_000 { return String(format: "%.1fM", v / 1_000_000) }
        if v >= 1000 { return String(format: "%.0fk", v / 1000) }
        return String(format: "%.0f", v)
    }
}

struct ChildLayout: Identifiable {
    let id = UUID()
    let node: TreeNode
    let frame: CGRect
}

func isPrefix(of path: [UUID], prefix: [UUID]) -> Bool {
    guard prefix.count <= path.count else { return false }
    return !zip(prefix, path).contains { $0 != $1 }
}

struct ZoomController {
    let selectedPath: [UUID]?
    let currentPath: [UUID]

    var shouldShowChildren: Bool {
        guard let selectedPath = selectedPath else { return true }

        // If this node is selected, show all children
        if currentPath == selectedPath { return true }

        // If this path leads to the selected path, show children
        if isPrefix(of: selectedPath, prefix: currentPath) { return true }

        // Otherwise, don't show children
        return false
    }

    func getVisibleChildren(from children: [TreeNode]) -> [TreeNode] {
        guard let selectedPath = selectedPath else { return children }

        // If this node is selected, show all children
        if currentPath == selectedPath { return children }

        // If this path leads to the selected path, show only the relevant child
        if isPrefix(of: selectedPath, prefix: currentPath) {
            let nextIndex = currentPath.count
            if selectedPath.count > nextIndex,
                let relevantChild = children.first(where: { $0.id == selectedPath[nextIndex] })
            {
                return [relevantChild]
            }
        }

        return []
    }

    func shouldHighlightLabel() -> Bool {
        guard let selectedPath = selectedPath else { return true }

        return selectedPath == currentPath || isPrefix(of: selectedPath, prefix: currentPath)
            || isPrefix(of: currentPath, prefix: selectedPath)
    }
}

struct TreemapLayoutCalculator {
    static func layout(children: [TreeNode], in rect: CGRect) -> [ChildLayout] {
        let sortedChildren = children.filter { $0.value > 0 }.sorted { $0.value > $1.value }
        guard !sortedChildren.isEmpty else { return [] }

        let total = sortedChildren.reduce(0) { $0 + $1.value }
        guard total > 0 else { return [] }

        var result: [ChildLayout] = []
        let scale = sqrt(total / Double(rect.width * rect.height))
        var currentRect = rect
        var index = 0

        while index < sortedChildren.count {
            let (spanRect, endIndex, sum) = calculateSpan(
                children: sortedChildren,
                currentRect: currentRect,
                scale: scale,
                total: total,
                startIndex: index
            )

            if sum / total < LayoutConstants.minValueThreshold { break }

            let layouts = createLayoutsForSpan(
                children: sortedChildren,
                spanRect: spanRect,
                startIndex: index,
                endIndex: endIndex,
                sum: sum,
                scale: scale
            )

            result.append(contentsOf: layouts)
            currentRect = updateRectAfterSpan(currentRect: currentRect, spanRect: spanRect)
            index = endIndex
        }

        return result
    }

    private static func calculateSpan(
        children: [TreeNode],
        currentRect: CGRect,
        scale: Double,
        total: Double,
        startIndex: Int
    ) -> (spanRect: CGRect, endIndex: Int, sum: Double) {
        let horizontal = currentRect.width >= currentRect.height
        let space = scale * Double(horizontal ? currentRect.width : currentRect.height)
        let (endIndex, sum) = selectOptimalSpan(children: children, space: space, start: startIndex)

        let spanRect: CGRect
        if horizontal {
            let height = (sum / space) / scale
            spanRect = CGRect(
                x: currentRect.minX, y: currentRect.minY,
                width: currentRect.width, height: height
            )
        } else {
            let width = (sum / space) / scale
            spanRect = CGRect(
                x: currentRect.minX, y: currentRect.minY,
                width: width, height: currentRect.height
            )
        }

        return (spanRect, endIndex, sum)
    }

    private static func createLayoutsForSpan(
        children: [TreeNode],
        spanRect: CGRect,
        startIndex: Int,
        endIndex: Int,
        sum: Double,
        scale: Double
    ) -> [ChildLayout] {
        var result: [ChildLayout] = []
        var cellRect = spanRect
        let horizontal = spanRect.width >= spanRect.height
        let space = scale * Double(horizontal ? spanRect.width : spanRect.height)

        for i in startIndex..<endIndex {
            let child = children[i]
            let frame = calculateChildFrame(
                child: child,
                cellRect: &cellRect,
                horizontal: horizontal,
                sum: sum,
                space: space,
                scale: scale
            )

            if frame.width > LayoutConstants.minNodeWidth
                && frame.height >= LayoutConstants.minNodeHeight
            {
                result.append(ChildLayout(node: child, frame: frame))
            }
        }

        return result
    }

    private static func calculateChildFrame(
        child: TreeNode,
        cellRect: inout CGRect,
        horizontal: Bool,
        sum: Double,
        space: Double,
        scale: Double
    ) -> CGRect {
        if horizontal {
            let width = (child.value / (sum / space)) / scale
            defer { cellRect.origin.x += width }
            return CGRect(
                x: cellRect.minX, y: cellRect.minY,
                width: width, height: cellRect.height
            )
        } else {
            let height = (child.value / (sum / space)) / scale
            defer { cellRect.origin.y += height }
            return CGRect(
                x: cellRect.minX, y: cellRect.minY,
                width: cellRect.width, height: height
            )
        }
    }

    private static func updateRectAfterSpan(currentRect: CGRect, spanRect: CGRect) -> CGRect {
        var newRect = currentRect
        if spanRect.width >= spanRect.height {
            // Horizontal span
            newRect.origin.y += spanRect.height
            newRect.size.height -= spanRect.height
        } else {
            // Vertical span
            newRect.origin.x += spanRect.width
            newRect.size.width -= spanRect.width
        }
        return newRect
    }

    private static func selectOptimalSpan(children: [TreeNode], space: Double, start: Int) -> (
        end: Int, sum: Double
    ) {
        var minValue = children[start].value
        var maxValue = minValue
        var sum = 0.0
        var lastScore = Double.infinity
        var end = start

        for i in start..<children.count {
            let value = children[i].value
            minValue = min(minValue, value)
            maxValue = max(maxValue, value)
            let newSum = sum + value
            let score = max(
                (maxValue * space * space) / (newSum * newSum),
                (newSum * newSum) / (minValue * space * space)
            )
            if score > lastScore { break }
            lastScore = score
            sum = newSum
            end = i + 1
        }
        return (end, sum)
    }
}

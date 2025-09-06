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

    private func list<Item: Decodable>(path: String, queryItems: [URLQueryItem]? = nil) async throws -> [Item] {
        let listResult: ItemList<Item> = try await request(path: path, queryItems: queryItems)
        return listResult.items
    }

    private func request<T: Decodable>(path: String, queryItems: [URLQueryItem]? = nil) async throws -> T {
        var components = URLComponents(url: creds.server.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = queryItems

        var req = URLRequest(url: components.url!)
        req.httpMethod = "GET"
        if let token = creds.token {
            req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        req.addValue("application/json", forHTTPHeaderField: "Accept")
        req.addValue("Clustermap/1.0 (darwin/arm64) kubernetes-client", forHTTPHeaderField: "User-Agent")

        let (data, resp) = try await session.data(for: req)
        guard let httpResponse = resp as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            let body = String(decoding: data, as: UTF8.self)
            let statusCode = (resp as? HTTPURLResponse)?.statusCode ?? -1
            throw ClientError.httpError(statusCode: statusCode, body: body)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

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
            ContentView().environmentObject(viewModel)
        }
    }
}

//
//  ClusterService.swift
//  Clustermap
//
//  Created by Victor Noagbodji on 8/16/25.
//

import Foundation

enum ClusterServiceError: Error, LocalizedError {
    case configError(Error)
    case clientError(Error)
    case dataFetchingError(Error)

    var errorDescription: String? {
        switch self {
        case .configError(let error):
            return "config error: \(error.localizedDescription)"
        case .clientError(let error):
            return "API client error: \(error.localizedDescription)"
        case .dataFetchingError(let error):
            return "data fetching error: \(error.localizedDescription)"
        }
    }
}

struct ClusterService {
    func fetchTree(from path: String, hierarchy: HierarchyView, metric: SizingMetric) async -> Result<TreeNode, Error> {
        do {
            let config = try ConfigLoader.parseKubeConfig(at: path)
            let creds = try await ConfigLoader.makeCredentials(config)
            let client = try Client(creds: creds)

            let namespaces = try await client.listNamespaces()

            var deploymentsByNS = [String: [KubeDeployment]]()
            var podsByNS = [String: [KubePod]]()

            try await withThrowingTaskGroup(of: (String, [KubeDeployment], [KubePod]).self) { group in
                for ns in namespaces {
                    group.addTask {
                        let name = ns.metadata.name
                        async let deployments = client.listDeployments(namespace: name)
                        async let pods = client.listPods(namespace: name, selector: nil)
                        let (d, p) = try await (deployments, pods)
                        return (name, d, p)
                    }
                }

                for try await (namespace, deployments, pods) in group {
                    deploymentsByNS[namespace] = deployments
                    podsByNS[namespace] = pods
                }
            }

            let snapshot = ClusterSnapshot(
                namespaces: namespaces,
                deploymentsByNS: deploymentsByNS,
                podsByNS: podsByNS
            )
            
            let tree = TreeBuilder.build(snapshot: snapshot, hierarchy: hierarchy, metric: metric)
            return .success(tree)
            
        } catch let error as ConfigLoaderError {
            return .failure(ClusterServiceError.configError(error))
        } catch let error as ClientError {
            return .failure(ClusterServiceError.clientError(error))
        } catch {
            return .failure(ClusterServiceError.dataFetchingError(error))
        }
    }
}

//
//  ClusterSnapshot.swift
//  Clustermap
//
//  Created by Victor Noagbodji on 8/16/25.
//

import Foundation

struct ClusterSnapshot {
    let namespaces: [KubeNamespace]
    let deploymentsByNS: [String: [KubeDeployment]]
    let podsByNS: [String: [KubePod]]
}

extension ClusterSnapshot {
    static func empty() -> ClusterSnapshot { .init(namespaces: [], deploymentsByNS: [:], podsByNS: [:]) }
}

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
    @Published var hierarchy: HierarchyView = .byResourceType { didSet { reload() } }
    @Published var metric: SizingMetric = .count { didSet { reload() } }
    @Published var root: TreeNode = TreeNode(name: "Welcome", value: 1, children: [])
    @Published var logEntries: [LogEntry] = []
    @Published var navigationPath: [TreeNode] = []
    @Published var kubeconfigPath: String = ConfigLoader.loadDefaultPath()
    @Published var nodeFrames: [UUID: CGRect] = [:]

    private let service = ClusterService()
    private let layoutEngine = TreemapLayout()

    var currentNode: TreeNode {
        navigationPath.last ?? root
    }

    func navigateTo(_ node: TreeNode) {
        navigationPath.append(node)
        updateFrames(for: currentNode)
    }

    func navigateBack() {
        guard !navigationPath.isEmpty else { return }
        _ = navigationPath.popLast()
        updateFrames(for: currentNode)
    }
    
    func navigateToRoot() {
        navigationPath.removeAll()
        updateFrames(for: root)
    }

    func reload() {
        Task { await loadCluster() }
    }

    func loadCluster() async {
        LogService.shared.clearLogs()
        LogService.shared.log("Loading cluster from \(kubeconfigPath)...", type: .info)
        
        let result = await service.fetchTree(from: kubeconfigPath, hierarchy: hierarchy, metric: metric)
        
        switch result {
        case .success(let newRoot):
            self.root = newRoot
            self.navigateToRoot()
        case .failure(let error):
            self.root = TreeNode(name: "Error", value: 1, children: [])
            LogService.shared.log("Error: \(error.localizedDescription)", type: .error)
        }
    }
    
    func updateFrames(for node: TreeNode, in size: CGSize? = nil) {
        let bounds = size.map { CGRect(origin: .zero, size: $0) } ?? nodeFrames[node.id] ?? CGRect(x: 0, y: 0, width: 800, height: 600)
        self.nodeFrames = layoutEngine.layout(node: node, in: bounds)
    }
}
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

    struct ClusterEntry: Codable { let name: String; let cluster: Cluster }
    struct ContextEntry: Codable { let name: String; let context: Context }
    struct UserEntry: Codable { let name: String; let user: User }

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

    struct Context: Codable { let cluster: String; let user: String }

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
        struct EnvVar: Codable { let name: String; let value: String }
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

    static func makeCredentials(_ config: KubeConfig, usingContext contextName: String? = nil) async throws -> Credentials {
        let context = try findContext(in: config, name: contextName)
        let cluster = try findCluster(in: config, name: context.cluster)
        let user = try findUser(in: config, name: context.user)

        guard let serverURL = URL(string: cluster.server) else {
            throw ConfigLoaderError.invalidServerURL(cluster.server)
        }

        let token = try await getToken(from: user)
        let caData = parseCertificateData(path: cluster.ca, dataString: cluster.caData)
        let certData = parseCertificateData(path: user.clientCertificate, dataString: user.clientCertificateData)
        let insecure = cluster.insecure ?? shouldSkipTLSVerifyForServer(serverURL)

        return Credentials(server: serverURL, token: token, caData: caData, certData: certData, insecure: insecure)
    }

    private static func findContext(in config: KubeConfig, name: String?) throws -> KubeConfig.Context {
        let contextName = name ?? config.currentContext ?? config.contexts.first?.name
        guard let name = contextName, let entry = config.contexts.first(where: { $0.name == name }) else {
            throw ConfigLoaderError.contextNotFound(name ?? "default")
        }
        return entry.context
    }

    private static func findCluster(in config: KubeConfig, name: String) throws -> KubeConfig.Cluster {
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
        let env = exec.env?.reduce(into: [:]) { $0[$1.name] = $1.value } ?? [: ]
        let tokenData = try await execute(command: exec.command, args: exec.args, extraEnv: env)
        let cred = try JSONDecoder().decode(ExecCredential.self, from: tokenData)
        return cred.status.token
    }

    private static func execute(command: String, args: [String]?, extraEnv: [String: String]) async throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + (args ?? [])

        var env = ProcessInfo.processInfo.environment
        let defaultPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
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
            throw ConfigLoaderError.execCommandFailed(command: command, exitCode: process.terminationStatus, stderr: errorString)
        }
    }
    
    private static func parseCertificateData(path: String?, dataString: String?) -> Data? {
        if let path = path, let fileContent = try? String(contentsOf: URL(fileURLWithPath: expandTilde(path)), encoding: .utf8) {
            return convertPEMToDER(fileContent)
        }
        if let dataString = dataString, let decodedData = Data(base64Encoded: dataString) {
            // Check if the base64 data is itself a PEM string
            if let pemContent = String(data: decodedData, encoding: .utf8), pemContent.contains("-----BEGIN") {
                return convertPEMToDER(pemContent)
            }
            return decodedData // Assume raw DER data
        }
        return nil
    }

    private static func expandTilde(_ path: String) -> String {
        path.replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path)
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
           regex.firstMatch(in: host, options: [], range: NSRange(location: 0, length: host.utf16.count)) != nil {
            return true
        }
        
        // Check for common private IP ranges
        return host.starts(with: "192.168.") || host.starts(with: "10.") ||
               (host.starts(with: "172.") && (16...31).contains(Int(host.split(separator: ".")[1]) ?? 0))
    }
}

//
//  ConsoleHeaderView.swift
//  Clustermap
//
//  Created by Victor Noagbodji on 8/16/25.
//

import SwiftUI

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
        let logText = entriesToCopy.map { "[\($0.timestamp)] [\($0.type)] \($0.message)" }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logText, forType: .string)
    }
}

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
        VStack() {
            ConsoleHeaderView(selection: $selection)
            Divider()
            LogView(selection: $selection)
        }
    }
}

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
        TreemapView(node: viewModel.currentNode)
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
                    Button { viewModel.reload() } label: { Image(systemName: "arrow.clockwise") }
                    Button { showInspector.toggle() } label: { Image(systemName: "sidebar.trailing") }
                }
            }
    }
}


//
//  Credentials.swift
//  Clustermap
//
//  Created by Victor Noagbodji on 8/16/25.
//

import Foundation

struct Credentials {
    let server: URL
    let token: String?
    let caData: Data?
    let certData: Data?
    let insecure: Bool
}

//
//  HierarchyView.swift
//  Clustermap
//
//  Created by Victor Noagbodji on 8/16/25.
//

import Foundation

enum HierarchyView: String, CaseIterable, Identifiable {
    case byResourceType = "Resource" // Namespace → Deployment → Pod
    case byNamespace = "Namespace"   // Namespace → Kind → Name
    var id: String { rawValue }
}

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
				<key>NSExceptionAllowsInsecureHTTPLoads</key>
				<true/>
				<key>NSIncludesSubdomains</key>
				<true/>
			</dict>
		</dict>
	</dict>
</dict>
</plist>

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
                Button("Load config") { viewModel.reload() }
            }
            
            Section("Display") {
                Picker("Hierarchy", selection: $viewModel.hierarchy) {
                    ForEach(HierarchyView.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                
                Picker("Sizing Metric", selection: $viewModel.metric) {
                    ForEach(SizingMetric.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            
            ConsoleView()
        }
}
}

//
//  LeafView.swift
//  Clustermap
//
//  Created by Victor Noagbodji on 8/16/25.
//

import SwiftUI

struct LeafView: View {
    let title: String
    let value: Double
    let textColor: Color

    var body: some View {
        VStack {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(formatValue(value))
                .font(.caption2)
                .opacity(0.8)
        }
        .foregroundColor(textColor)
        .padding(4)
        .contentShape(Rectangle())
        .help("\(title)\nValue: \(value)")
    }

    private func formatValue(_ v: Double) -> String {
        if v >= 1_000_000_000 { return String(format: "%.1fG", v / 1_000_000_000) }
        if v >= 1_000_000 { return String(format: "%.1fM", v / 1_000_000) }
        if v >= 1000 { return String(format: "%.0fk", v / 1000) }
        return String(format: "%.0f", v)
    }
}

//
//  LogEntry.swift
//  Clustermap
//
//  Created by Victor Noagbodji on 8/16/25.
//

import Foundation

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

//
//  LogMessageView.swift
//  Clustermap
//
//  Created by Victor Noagbodji on 8/16/25.
//

import SwiftUI

struct LogMessageView: View {
    let log: LogEntry
    let isSelected: Bool
    
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        HStack() {
            Text(Self.formatter.string(from: log.timestamp)).foregroundColor(.secondary)
            symbol.foregroundColor(color)
            Text(log.message).foregroundColor(color)
        }
        .font(.system(.body, design: .monospaced))
        .background(isSelected ? Color.accentColor : Color.clear)
    }

    private var symbol: some View {
        switch log.type {
        case .info:    return Image(systemName: "info.circle")
        case .success: return Image(systemName: "checkmark.circle")
        case .error:   return Image(systemName: "xmark.circle")
        }
    }

    private var color: Color {
        switch log.type {
        case .info:    return .primary
        case .success: return .green
        case .error:   return .red
        }
    }
}

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

struct KubeNamespace: Codable, Hashable, Identifiable {
    let metadata: ObjectMeta
    var id: String { metadata.name }
}

struct KubeDeploymentList: Codable { let items: [KubeDeployment] }
struct KubePodList: Codable { let items: [KubePod] }
struct KubeNamespaceList: Codable { let items: [KubeNamespace] }

struct KubeDeployment: Codable, Hashable, Identifiable {
    let metadata: ObjectMeta
    let spec: DeploymentSpec?
    let status: DeploymentStatus?
    var id: String { metadata.name }
}

struct KubePod: Codable, Hashable, Identifiable {
    let metadata: ObjectMeta
    let spec: PodSpec?
    let status: PodStatus?
    var id: String { metadata.name }
}

struct ObjectMeta: Codable, Hashable {
    let name: String
    let namespace: String?
    let labels: [String: String]?
    let uid: String
    let ownerReferences: [OwnerReference]?
}

struct OwnerReference: Codable, Hashable {
    let apiVersion: String
    let kind: String
    let name: String
    let uid: String
}

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

struct DeploymentSpec: Codable, Hashable {
    let replicas: Int?
    let template: PodTemplate?
}

struct PodTemplate: Codable, Hashable { let spec: PodSpec? }
struct DeploymentStatus: Codable, Hashable { let availableReplicas: Int? }

//
//  SizingMetric.swift
//  Clustermap
//
//  Created by Victor Noagbodji on 8/16/25.
//

import Foundation

enum SizingMetric: String, CaseIterable, Identifiable {
    case count = "Count"
    case cpu = "CPU"
    case memory = "Memory"
    var id: String { rawValue }
}

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

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let result = switch challenge.protectionSpace.authenticationMethod {
        case NSURLAuthenticationMethodServerTrust:
            handleServerTrust(challenge)
        case NSURLAuthenticationMethodClientCertificate:
            handleClientCertificate(challenge)
        default:
            (URLSession.AuthChallengeDisposition.performDefaultHandling, nil as URLCredential?)
        }
        completionHandler(result.0, result.1)
    }

    private func handleServerTrust(_ challenge: URLAuthenticationChallenge) -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard let trust = challenge.protectionSpace.serverTrust else {
            Task { @MainActor in
                LogService.shared.log("Server trust challenge failed: no server trust object.", type: .error)
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
            let errorDescription = String(describing: error?.localizedDescription ?? "Unknown error")
            Task { @MainActor in
                LogService.shared.log("Server trust validation failed: \(errorDescription)", type: .error)
            }
        }

        return isValid
    }

    private func handleClientCertificate(_ challenge: URLAuthenticationChallenge) -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard let identity = clientIdentity else {
            return (.performDefaultHandling, nil)
        }

        let credential = URLCredential(identity: identity, certificates: nil, persistence: .forSession)
        return (.useCredential, credential)
    }
}

//
//  TreeBuilder.swift
//  Clustermap
//
//  Created by Victor Noagbodji on 8/16/25.
//

import Foundation
import SwiftUI

struct TreeBuilder {
    static func build(snapshot: ClusterSnapshot, hierarchy: HierarchyView, metric: SizingMetric) -> TreeNode {
        switch hierarchy {
        case .byResourceType:
            return buildByResourceType(snapshot: snapshot, metric: metric)
        case .byNamespace:
            return buildByNamespace(snapshot: snapshot, metric:metric)
        }
    }

    private static func buildByResourceType(snapshot: ClusterSnapshot, metric: SizingMetric) -> TreeNode {
        var namespaceNodes: [TreeNode] = []
        for ns in snapshot.namespaces {
            let deployments = snapshot.deploymentsByNS[ns.metadata.name] ?? []
            let pods = snapshot.podsByNS[ns.metadata.name] ?? []
            var deploymentNodes: [TreeNode] = []

            for deployment in deployments {
                let ownedPods = pods.filter { pod in
                    let ownerNames = pod.metadata.ownerReferences?.map { $0.name } ?? []
                    return ownerNames.contains { $0.starts(with: deployment.metadata.name) }
                }
                
                let podNodes = ownedPods.map { pod in
                    TreeNode(name: pod.metadata.name, value: metricValue(for: pod, metric: metric), children: [])
                }
                
                if !podNodes.isEmpty {
                    let totalValue = podNodes.reduce(0) { $0 + $1.value }
                    deploymentNodes.append(TreeNode(name: deployment.metadata.name, value: totalValue, children: podNodes))
                }
            }
            
            if !deploymentNodes.isEmpty {
                let totalValue = deploymentNodes.reduce(0) { $0 + $1.value }
                namespaceNodes.append(TreeNode(name: ns.metadata.name, value: totalValue, children: deploymentNodes))
            }
        }
        
        let totalValue = namespaceNodes.reduce(0) { $0 + $1.value }
        return TreeNode(name: "Cluster", value: totalValue, children: namespaceNodes)
    }

    private static func buildByNamespace(snapshot: ClusterSnapshot, metric: SizingMetric) -> TreeNode {
        var namespaceNodes: [TreeNode] = []
        for ns in snapshot.namespaces {
            let deployments = snapshot.deploymentsByNS[ns.metadata.name] ?? []
            let pods = snapshot.podsByNS[ns.metadata.name] ?? []
            
            let deploymentNodes = deployments.map { deployment in
                TreeNode(name: deployment.metadata.name, value: metricValue(for: deployment, metric: metric), children: [])
            }
            let deploymentsNode = TreeNode(name: "Deployments", value: deploymentNodes.reduce(0) { $0 + $1.value }, children: deploymentNodes)

            let podNodes = pods.map { pod in
                TreeNode(name: pod.metadata.name, value: metricValue(for: pod, metric: metric), children: [])
            }
            let podsNode = TreeNode(name: "Pods", value: podNodes.reduce(0) { $0 + $1.value }, children: podNodes)
            
            let children = [deploymentsNode, podsNode].filter { !$0.children.isEmpty }
            if !children.isEmpty {
                let totalValue = children.reduce(0) { $0 + $1.value }
                namespaceNodes.append(TreeNode(name: ns.metadata.name, value: totalValue, children: children))
            }
        }
        
        let totalValue = namespaceNodes.reduce(0) { $0 + $1.value }
        return TreeNode(name: "Cluster", value: totalValue, children: namespaceNodes)
    }

    private static func metricValue(for pod: KubePod, metric: SizingMetric) -> Double {
        if metric == .count { return 1.0 }
        return totalRequests(for: pod.spec, metric: metric)
    }

    private static func metricValue(for deployment: KubeDeployment, metric: SizingMetric) -> Double {
        if metric == .count { return 1.0 }
        let replicas = Double(deployment.spec?.replicas ?? 1)
        return totalRequests(for: deployment.spec?.template?.spec, metric: metric) * replicas
    }

    private static func totalRequests(for spec: PodSpec?, metric: SizingMetric) -> Double {
        guard let containers = spec?.containers else { return 0 }
        return containers.reduce(0) { total, container in
            let requests = container.resources?.requests
            let value: Double? = switch metric {
            case .cpu:
                cores(from: requests?["cpu"])
            case .memory:
                Double(bytes(from: requests?["memory"]) ?? 0)
            case .count:
                1.0
            }
            return total + (value ?? 0)
        }
    }

    private static func cores(from value: String?) -> Double? {
        guard var value = value else { return nil }
        if value.hasSuffix("m") {
            value.removeLast()
            return (Double(value) ?? 0) / 1000.0
        }
        return Double(value)
    }

    private static func bytes(from value: String?) -> Int? {
        guard let value else { return nil }
        let units: [(String, Double)] = [("Ki", 1024), ("Mi", 1024*1024), ("Gi", 1024*1024*1024), ("K", 1000), ("M", 1_000_000), ("G", 1_000_000_000)]
        for (u, mult) in units {
            if value.hasSuffix(u), let n = Double(value.dropLast(u.count)) { return Int(n * mult) }
        }
        return Int(value)
    }
}
//
//  TreemapLayout.swift
//  Clustermap
//
//  Created by Victor Noagbodji on 8/16/25.
//

import Foundation
import SwiftUI

struct TreemapLayout {
    func layout(node: TreeNode, in bounds: CGRect) -> [UUID: CGRect] {
        var frames = [UUID: CGRect]()
        frames[node.id] = bounds
        layoutChildren(of: node, in: bounds, frames: &frames)
        return frames
    }

    private func layoutChildren(of node: TreeNode, in bounds: CGRect, frames: inout [UUID: CGRect]) {
        let children = node.children.filter { $0.value > 0 }.sorted { $0.value > $1.value }
        if children.isEmpty { return }

        let totalValue = children.reduce(0) { $0 + $1.value }
        squarify(children: children, in: bounds, totalValue: totalValue, frames: &frames)

        for child in children {
            if let childBounds = frames[child.id] {
                layoutChildren(of: child, in: childBounds, frames: &frames)
            }
        }
    }

    private func squarify(children: [TreeNode], in rect: CGRect, totalValue: Double, frames: inout [UUID: CGRect]) {
        if children.isEmpty { return }

        var row: [TreeNode] = []
        var remainingChildren = children
        var currentRect = rect
        
        while !remainingChildren.isEmpty {
            let length = min(currentRect.width, currentRect.height)
            let nextChild = remainingChildren.first!
            
            let currentWorst = worstAspectRatio(for: row, length: length)
            let nextWorst = worstAspectRatio(for: row + [nextChild], length: length)

            if !row.isEmpty && nextWorst > currentWorst {
                let rowValue = row.reduce(0) { $0 + $1.value }
                let (rowRect, remainingRect) = layoutRow(value: rowValue, in: currentRect, totalValue: totalValue)
                
                placeRow(row: row, in: rowRect, frames: &frames)
                
                currentRect = remainingRect
                squarify(children: remainingChildren, in: currentRect, totalValue: totalValue - rowValue, frames: &frames)
                return
            }
            
            row.append(nextChild)
            remainingChildren.removeFirst()
        }
        
        placeRow(row: row, in: currentRect, frames: &frames)
    }

    private func layoutRow(value: Double, in rect: CGRect, totalValue: Double) -> (CGRect, CGRect) {
        let area = rect.width * rect.height * (value / totalValue)
        if rect.width > rect.height {
            let rowWidth = area / rect.height
            return (
                CGRect(x: rect.minX, y: rect.minY, width: rowWidth, height: rect.height),
                CGRect(x: rect.minX + rowWidth, y: rect.minY, width: rect.width - rowWidth, height: rect.height)
            )
        } else {
            let rowHeight = area / rect.width
            return (
                CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rowHeight),
                CGRect(x: rect.minX, y: rect.minY + rowHeight, width: rect.width, height: rect.height - rowHeight)
            )
        }
    }

    private func placeRow(row: [TreeNode], in rect: CGRect, frames: inout [UUID: CGRect]) {
        let rowValue = row.reduce(0) { $0 + $1.value }
        var currentOrigin = CGPoint(x: rect.minX, y: rect.minY)
        
        for node in row {
            let nodeArea = rect.width * rect.height * (node.value / rowValue)
            if rect.width > rect.height {
                let nodeWidth = nodeArea / rect.height
                frames[node.id] = CGRect(origin: currentOrigin, size: CGSize(width: nodeWidth, height: rect.height))
                currentOrigin.x += nodeWidth
            } else {
                let nodeHeight = nodeArea / rect.width
                frames[node.id] = CGRect(origin: currentOrigin, size: CGSize(width: rect.width, height: nodeHeight))
                currentOrigin.y += nodeHeight
            }
        }
    }

    private func worstAspectRatio(for row: [TreeNode], length: CGFloat) -> Double {
        if row.isEmpty { return .infinity }
        
        let sum = row.reduce(0) { $0 + $1.value }
        if sum == 0 { return .infinity }
        
        var maxRatio: Double = 0
        let lengthSquared = length * length
        let sumSquared = sum * sum
        
        for node in row {
            let area = lengthSquared * node.value / sum
            let ratio = max(area / sumSquared, sumSquared / area)
            maxRatio = max(maxRatio, ratio)
        }
        return maxRatio
    }
}
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

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(node.children) { child in
                    if let frame = viewModel.nodeFrames[child.id] {
                        NodeView(node: child)
                            .frame(width: frame.width, height: frame.height)
                            .offset(x: frame.minX, y: frame.minY)
                    }
                }
            }
            .onChange(of: geometry.size) { _, newSize in
                viewModel.updateFrames(for: node, in: newSize)
            }
            .onAppear {
                viewModel.updateFrames(for: node, in: geometry.size)
            }
        }
        .background(Color(.windowBackgroundColor))
        .clipped()
        .navigationTitle(viewModel.currentNode.name)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                HStack {
                    Button(action: viewModel.navigateToRoot) {
                        Image(systemName: "house")
                    }
                    .disabled(viewModel.navigationPath.isEmpty)
                    
                    if !viewModel.navigationPath.isEmpty {
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                    
                    ForEach(viewModel.navigationPath.indices, id: \.self) { index in
                        let node = viewModel.navigationPath[index]
                        Button(node.name) {
                            let count = viewModel.navigationPath.count - 1 - index
                            if count > 0 {
                                viewModel.navigationPath.removeLast(count)
                                viewModel.updateFrames(for: viewModel.currentNode)
                            }
                        }
                        if index < viewModel.navigationPath.count - 1 {
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }
}

fileprivate struct NodeView: View {
    @EnvironmentObject private var viewModel: ClusterViewModel
    let node: TreeNode
    
    private var color: Color {
        Color.from(string: node.name)
    }
    
    private var textColor: Color {
        color.luminance > 0.6 ? .black : .white
    }

    var body: some View {
        let view = ZStack(alignment: .topLeading) {
            Rectangle().fill(color)
            
            if node.isLeaf {
                LeafView(title: node.name, value: node.value, textColor: textColor)
            } else {
                Text(node.name)
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(4)
                    .foregroundColor(textColor)
            }
        }
        .overlay(Rectangle().stroke(Color.white.opacity(0.4), lineWidth: 1))
        
        if node.isLeaf {
            view
        } else {
            view.onTapGesture {
                viewModel.navigateTo(node)
            }
        }
    }
}

fileprivate extension Color {
    static func from(string: String) -> Color {
        let hash = string.unicodeScalars.reduce(0) { $0 ^ $1.value }
        let hue = Double(hash % 256) / 256.0
        return Color(hue: hue, saturation: 0.7, brightness: 0.8)
    }
    
    var luminance: Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        NSColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)
    }
}
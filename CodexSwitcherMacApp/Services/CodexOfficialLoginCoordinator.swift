//
//  CodexOfficialLoginCoordinator.swift
//  Codex Switcher Mac App
//
//  Created by OpenAI on 2026-04-24.
//

import AppKit
import CryptoKit
import Foundation
import Network

nonisolated struct CodexOfficialLoginResult: Sendable, Equatable {
    let authFileContents: String
    let parsedAuth: CodexAuthSnapshot
    let sourceHomeURL: URL
}

nonisolated protocol CodexOfficialLoginCoordinating: Sendable {
    func login() async throws -> CodexOfficialLoginResult
}

nonisolated protocol CodexDirectOAuthLoginFlowing: Sendable {
    func login(applicationSupportBaseURL: URL) async throws -> CodexOfficialLoginResult
}

nonisolated enum CodexOfficialLoginError: LocalizedError, Sendable {
    case codexExecutableNotFound
    case serverDidNotBecomeReady
    case invalidServerURL
    case loginStartFailed(String)
    case loginFailed(String)
    case missingAuthFile
    case secureRandomUnavailable
    case callbackServerUnavailable(String)
    case invalidOAuthCallback
    case tokenExchangeFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .codexExecutableNotFound:
            "Codex Switcher couldn't find the installed Codex command-line tool."
        case .serverDidNotBecomeReady:
            "Codex's official login service did not become ready."
        case .invalidServerURL:
            "Codex's official login service returned an invalid local URL."
        case let .loginStartFailed(message):
            "Codex couldn't start the browser login flow. \(message)"
        case let .loginFailed(message):
            "Codex login did not finish successfully. \(message)"
        case .missingAuthFile:
            "Codex login completed but did not produce an auth.json file."
        case .secureRandomUnavailable:
            "Codex Switcher couldn't create a secure OAuth challenge."
        case let .callbackServerUnavailable(message):
            "Codex Switcher couldn't start its local OAuth callback server. \(message)"
        case .invalidOAuthCallback:
            "Codex Switcher received an invalid OAuth callback."
        case let .tokenExchangeFailed(message):
            "Codex Switcher couldn't finish the OAuth token exchange. \(message)"
        case .cancelled:
            "Codex login was cancelled."
        }
    }
}

nonisolated final class CodexOfficialLoginCoordinator: CodexOfficialLoginCoordinating, @unchecked Sendable {
    fileprivate nonisolated struct JSONRPCResponse: Decodable {
        nonisolated struct ErrorPayload: Decodable {
            let code: Int?
            let message: String
        }

        let id: Int?
        let result: JSONValue?
        let error: ErrorPayload?
    }

    fileprivate nonisolated enum JSONValue: Decodable, Equatable {
        case object([String: JSONValue])
        case array([JSONValue])
        case string(String)
        case number(Double)
        case bool(Bool)
        case null

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .null
            } else if let value = try? container.decode(Bool.self) {
                self = .bool(value)
            } else if let value = try? container.decode(Double.self) {
                self = .number(value)
            } else if let value = try? container.decode(String.self) {
                self = .string(value)
            } else if let value = try? container.decode([String: JSONValue].self) {
                self = .object(value)
            } else {
                self = .array(try container.decode([JSONValue].self))
            }
        }

        var stringValue: String? {
            guard case let .string(value) = self else {
                return nil
            }

            return value
        }

        var boolValue: Bool? {
            guard case let .bool(value) = self else {
                return nil
            }

            return value
        }

        subscript(key: String) -> JSONValue? {
            guard case let .object(values) = self else {
                return nil
            }

            return values[key]
        }
    }

    private let applicationSupportBaseURL: URL
    private let directOAuthLogin: CodexDirectOAuthLoginFlowing

    nonisolated init(
        fileManager: FileManager = .default,
        codexExecutableURL: URL? = nil,
        applicationSupportBaseURL: URL? = nil,
        directOAuthLogin: CodexDirectOAuthLoginFlowing = CodexDirectOAuthLoginFlow()
    ) {
        _ = codexExecutableURL
        self.applicationSupportBaseURL = applicationSupportBaseURL
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appending(path: "Library/Application Support", directoryHint: .isDirectory)
        self.directOAuthLogin = directOAuthLogin
    }

    nonisolated func login() async throws -> CodexOfficialLoginResult {
        try await directOAuthLogin.login(applicationSupportBaseURL: applicationSupportBaseURL)
    }

    private nonisolated func loginWithAppServer(codexExecutableURL: URL) async throws -> CodexOfficialLoginResult {
        let fileManager = FileManager.default
        let loginHomeURL = applicationSupportBaseURL
            .appending(path: "Codex Switcher/LoginHomes/\(UUID().uuidString)", directoryHint: .isDirectory)
        let sqliteHomeURL = loginHomeURL.appending(path: "sqlite", directoryHint: .isDirectory)
        let configURL = loginHomeURL.appending(path: "config.toml", directoryHint: .notDirectory)

        try fileManager.createDirectory(at: loginHomeURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: sqliteHomeURL, withIntermediateDirectories: true)
        try "cli_auth_credentials_store = \"file\"\n".write(to: configURL, atomically: true, encoding: .utf8)
        try? fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o700))],
            ofItemAtPath: loginHomeURL.path
        )

        defer {
            try? fileManager.removeItem(at: loginHomeURL)
        }

        let process = Process()
        process.executableURL = codexExecutableURL
        process.arguments = ["app-server", "--listen", "ws://127.0.0.1:0"]
        process.environment = processEnvironment(
            codexHomeURL: loginHomeURL,
            sqliteHomeURL: sqliteHomeURL
        )

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
            }
        }

        let serverURL = try await waitForServerURL(from: stdout.fileHandleForReading)
        let socket = URLSession.shared.webSocketTask(with: serverURL)
        socket.resume()
        defer {
            socket.cancel(with: .normalClosure, reason: nil)
        }

        try await sendInitialize(on: socket)
        let loginID = try await startBrowserLogin(on: socket)
        try await waitForLoginCompletion(loginID: loginID, on: socket)

        let authFileURL = loginHomeURL.appending(path: "auth.json", directoryHint: .notDirectory)
        guard fileManager.fileExists(atPath: authFileURL.path) else {
            throw CodexOfficialLoginError.missingAuthFile
        }

        let contents = try String(contentsOf: authFileURL, encoding: .utf8)
        let snapshot = try CodexAuthFile.parse(contents: contents)
        return CodexOfficialLoginResult(
            authFileContents: contents,
            parsedAuth: snapshot,
            sourceHomeURL: loginHomeURL
        )
    }

    private nonisolated static func shouldFallBackToDirectOAuth(after error: Error) -> Bool {
        if let loginError = error as? CodexOfficialLoginError {
            switch loginError {
            case .codexExecutableNotFound, .serverDidNotBecomeReady, .invalidServerURL, .loginStartFailed:
                return true
            case .loginFailed, .missingAuthFile, .secureRandomUnavailable, .callbackServerUnavailable,
                 .invalidOAuthCallback, .tokenExchangeFailed, .cancelled:
                return false
            }
        }

        let nsError = error as NSError
        return nsError.domain == NSPOSIXErrorDomain || nsError.domain == NSCocoaErrorDomain
    }

    private nonisolated static func defaultCodexExecutableURL() -> URL? {
        for path in [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex",
        ] {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(filePath: path)
            }
        }

        return nil
    }

    private nonisolated func processEnvironment(codexHomeURL: URL, sqliteHomeURL: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = codexHomeURL.path
        environment["CODEX_SQLITE_HOME"] = sqliteHomeURL.path
        return environment
    }

    private nonisolated func waitForServerURL(from handle: FileHandle) async throws -> URL {
        let deadline = Date().addingTimeInterval(15)
        let buffer = ProcessOutputBuffer()

        handle.readabilityHandler = { readableHandle in
            let data = readableHandle.availableData
            if !data.isEmpty {
                buffer.append(data)
            }
        }

        defer {
            handle.readabilityHandler = nil
        }

        while Date() < deadline {
            if let url = parseServerURL(from: buffer.text) {
                return url
            }

            try await Task.sleep(for: .milliseconds(50))
        }

        throw CodexOfficialLoginError.serverDidNotBecomeReady
    }

    private nonisolated func parseServerURL(from text: String) -> URL? {
        for line in text.components(separatedBy: .newlines) {
            guard let range = line.range(of: "ws://127.0.0.1:") else {
                continue
            }

            let suffix = line[range.lowerBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let urlString = suffix
                .split(whereSeparator: \.isWhitespace)
                .first
                .map(String.init) ?? suffix
            if let url = URL(string: urlString) {
                return url
            }
        }

        return nil
    }

    private nonisolated func sendInitialize(on socket: URLSessionWebSocketTask) async throws {
        let request: [String: Any] = [
            "id": 1,
            "method": "initialize",
            "params": [
                "clientInfo": [
                    "name": "codex-switcher",
                    "title": "Codex Switcher",
                    "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
                ],
                "capabilities": [
                    "experimentalApi": true,
                    "optOutNotificationMethods": [],
                ],
            ],
        ]
        try await send(request, on: socket)
        _ = try await receiveResponse(id: 1, on: socket)
    }

    private nonisolated func startBrowserLogin(on socket: URLSessionWebSocketTask) async throws -> String {
        let request: [String: Any] = [
            "id": 2,
            "method": "account/login/start",
            "params": [
                "type": "chatgpt",
            ],
        ]
        try await send(request, on: socket)
        let response = try await receiveResponse(id: 2, on: socket)

        if let message = response.error?.message {
            throw CodexOfficialLoginError.loginStartFailed(message)
        }

        guard
            let result = response.result,
            result["type"]?.stringValue == "chatgpt",
            let loginID = result["loginId"]?.stringValue,
            let authURLString = result["authUrl"]?.stringValue,
            let authURL = URL(string: authURLString)
        else {
            throw CodexOfficialLoginError.loginStartFailed("")
        }

        _ = await MainActor.run {
            NSWorkspace.shared.open(authURL)
        }

        return loginID
    }

    private nonisolated func waitForLoginCompletion(
        loginID: String,
        on socket: URLSessionWebSocketTask
    ) async throws {
        let deadline = Date().addingTimeInterval(10 * 60)

        while Date() < deadline {
            let value = try await receiveAnyJSON(on: socket)
            guard
                value["method"]?.stringValue == "account/login/completed",
                let params = value["params"]
            else {
                continue
            }

            let completedLoginID = params["loginId"]?.stringValue
            guard completedLoginID == nil || completedLoginID == loginID else {
                continue
            }

            if params["success"]?.boolValue == true {
                return
            }

            throw CodexOfficialLoginError.loginFailed(params["error"]?.stringValue ?? "")
        }

        throw CodexOfficialLoginError.cancelled
    }

    private nonisolated func send(_ request: [String: Any], on socket: URLSessionWebSocketTask) async throws {
        let data = try JSONSerialization.data(withJSONObject: request, options: [])
        let text = String(decoding: data, as: UTF8.self)
        try await socket.send(.string(text))
    }

    private nonisolated func receiveResponse(id: Int, on socket: URLSessionWebSocketTask) async throws -> JSONRPCResponse {
        while true {
            let value = try await receiveAnyJSON(on: socket)
            guard case let .number(receivedID)? = value["id"], Int(receivedID) == id else {
                continue
            }

            let data = try encodeJSONValue(value)
            return try JSONDecoder().decode(JSONRPCResponse.self, from: data)
        }
    }

    private nonisolated func receiveAnyJSON(on socket: URLSessionWebSocketTask) async throws -> JSONValue {
        let message = try await socket.receive()
        let data: Data

        switch message {
        case let .data(receivedData):
            data = receivedData
        case let .string(text):
            data = Data(text.utf8)
        @unknown default:
            throw CodexOfficialLoginError.loginFailed("")
        }

        return try JSONDecoder().decode(JSONValue.self, from: data)
    }
    private nonisolated func encodeJSONValue(_ value: JSONValue) throws -> Data {
        try JSONSerialization.data(withJSONObject: value.foundationObject, options: [])
    }
}

private nonisolated extension CodexOfficialLoginCoordinator.JSONValue {
    var foundationObject: Any {
        switch self {
        case let .object(values):
            Dictionary(uniqueKeysWithValues: values.map { key, value in
                (key, value.foundationObject)
            })
        case let .array(values):
            values.map(\.foundationObject)
        case let .string(value):
            value
        case let .number(value):
            value
        case let .bool(value):
            value
        case .null:
            NSNull()
        }
    }
}

private nonisolated final class ProcessOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    var text: String {
        lock.lock()
        defer {
            lock.unlock()
        }

        return String(data: data, encoding: .utf8) ?? ""
    }

    func append(_ newData: Data) {
        lock.lock()
        data.append(newData)
        lock.unlock()
    }
}

nonisolated final class CodexDirectOAuthLoginFlow: CodexDirectOAuthLoginFlowing, @unchecked Sendable {
    private nonisolated struct PKCEChallenge {
        let verifier: String
        let challenge: String
    }

    private nonisolated struct OAuthTokens: Decodable {
        let idToken: String
        let accessToken: String
        let refreshToken: String

        nonisolated enum CodingKeys: String, CodingKey {
            case idToken = "id_token"
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
        }
    }

    private nonisolated enum Constants {
        static let issuer = "https://auth.openai.com"
        static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
        static let originator = "codex_cli_rs"
        static let callbackPort: UInt16 = 1455
        static let callbackTimeout: TimeInterval = 90
    }

    nonisolated func login(applicationSupportBaseURL: URL) async throws -> CodexOfficialLoginResult {
        let loginHomeURL = applicationSupportBaseURL
            .appending(path: "Codex Switcher/LoginHomes/\(UUID().uuidString)", directoryHint: .isDirectory)
        let pkce = try Self.makePKCEChallenge()
        let state = try Self.randomBase64URL(byteCount: 32)
        let callbackServer = try await Self.makeCallbackServer(
            expectedState: state,
            timeout: Constants.callbackTimeout
        )

        defer {
            callbackServer.cancel()
        }

        let port = try await withTaskCancellationHandler {
            try await callbackServer.start()
        } onCancel: {
            callbackServer.cancel()
        }
        let redirectURI = "http://localhost:\(port)/auth/callback"
        let authURL = try Self.makeAuthorizeURL(
            redirectURI: redirectURI,
            pkce: pkce,
            state: state
        )

        _ = await MainActor.run {
            NSWorkspace.shared.open(authURL)
        }

        let code = try await withTaskCancellationHandler {
            try await callbackServer.waitForAuthorizationCode()
        } onCancel: {
            callbackServer.cancel()
        }
        let tokens = try await Self.exchangeCodeForTokens(
            code,
            redirectURI: redirectURI,
            pkce: pkce
        )
        let authFileContents = try Self.makeAuthFileContents(from: tokens, refreshedAt: Date())
        let snapshot = try CodexAuthFile.parse(contents: authFileContents)
        return CodexOfficialLoginResult(
            authFileContents: authFileContents,
            parsedAuth: snapshot,
            sourceHomeURL: loginHomeURL
        )
    }

    private nonisolated static func makeCallbackServer(
        expectedState: String,
        timeout: TimeInterval
    ) async throws -> CodexOAuthCallbackServer {
        do {
            return try CodexOAuthCallbackServer(
                expectedState: expectedState,
                timeout: timeout,
                preferredPort: Constants.callbackPort
            )
        } catch {
            await sendCancelRequest(toPort: Constants.callbackPort)
            try? await Task.sleep(for: .milliseconds(300))

            return try CodexOAuthCallbackServer(
                expectedState: expectedState,
                timeout: timeout,
                preferredPort: Constants.callbackPort
            )
        }
    }

    private nonisolated static func sendCancelRequest(toPort port: UInt16) async {
        guard let url = URL(string: "http://localhost:\(port)/cancel") else {
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        _ = try? await URLSession.shared.data(for: request)
    }

    private nonisolated static func makeAuthorizeURL(
        redirectURI: String,
        pkce: PKCEChallenge,
        state: String
    ) throws -> URL {
        var components = URLComponents(string: "\(Constants.issuer)/oauth/authorize")
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: Constants.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(
                name: "scope",
                value: "openid profile email offline_access api.connectors.read api.connectors.invoke"
            ),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "id_token_add_organizations", value: "true"),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "originator", value: Constants.originator),
        ]

        guard let url = components?.url else {
            throw CodexOfficialLoginError.loginStartFailed("")
        }

        return url
    }

    private nonisolated static func exchangeCodeForTokens(
        _ code: String,
        redirectURI: String,
        pkce: PKCEChallenge
    ) async throws -> OAuthTokens {
        guard let url = URL(string: "\(Constants.issuer)/oauth/token") else {
            throw CodexOfficialLoginError.tokenExchangeFailed("")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formURLEncodedBody([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": Constants.clientID,
            "code_verifier": pkce.verifier,
        ])

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw CodexOfficialLoginError.tokenExchangeFailed(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CodexOfficialLoginError.tokenExchangeFailed("")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw CodexOfficialLoginError.tokenExchangeFailed(
                Self.tokenEndpointErrorMessage(from: data) ?? "Status \(httpResponse.statusCode)"
            )
        }

        do {
            return try JSONDecoder().decode(OAuthTokens.self, from: data)
        } catch {
            throw CodexOfficialLoginError.tokenExchangeFailed("The token response was not valid JSON.")
        }
    }

    private nonisolated static func makeAuthFileContents(
        from tokens: OAuthTokens,
        refreshedAt: Date
    ) throws -> String {
        var tokenPayload: [String: Any] = [
            "id_token": tokens.idToken,
            "access_token": tokens.accessToken,
            "refresh_token": tokens.refreshToken,
        ]

        if let accountID = Self.chatGPTAccountID(fromJWT: tokens.idToken) {
            tokenPayload["account_id"] = accountID
        }

        let payload: [String: Any] = [
            "OPENAI_API_KEY": NSNull(),
            "auth_mode": "chatgpt",
            "last_refresh": CodexAuthSnapshotNormalizer.iso8601Timestamp(from: refreshedAt),
            "tokens": tokenPayload,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        guard let contents = String(data: data, encoding: .utf8) else {
            throw CodexAuthFileError.invalidEncoding
        }

        return contents
    }

    private nonisolated static func makePKCEChallenge() throws -> PKCEChallenge {
        let verifier = try randomBase64URL(byteCount: 64)
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return PKCEChallenge(
            verifier: verifier,
            challenge: Data(digest).base64URLEncodedString()
        )
    }

    private nonisolated static func randomBase64URL(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw CodexOfficialLoginError.secureRandomUnavailable
        }

        return Data(bytes).base64URLEncodedString()
    }

    private nonisolated static func formURLEncodedBody(_ values: [String: String]) -> Data {
        let body = values
            .map { key, value in
                "\(Self.formURLEncode(key))=\(Self.formURLEncode(value))"
            }
            .joined(separator: "&")
        return Data(body.utf8)
    }

    private nonisolated static func formURLEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed)?
            .replacingOccurrences(of: "%20", with: "+") ?? ""
    }

    private nonisolated static func tokenEndpointErrorMessage(from data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        if let description = object["error_description"] as? String, !description.isEmpty {
            return description
        }

        if let error = object["error"] as? String, !error.isEmpty {
            return error
        }

        if let error = object["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.isEmpty {
            return message
        }

        return nil
    }

    private nonisolated static func chatGPTAccountID(fromJWT jwt: String) -> String? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else {
            return nil
        }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder != 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }

        guard
            let data = Data(base64Encoded: payload),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let auth = object["https://api.openai.com/auth"] as? [String: Any],
            let accountID = auth["chatgpt_account_id"] as? String,
            !accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        return accountID
    }
}

#if DEBUG
extension CodexDirectOAuthLoginFlow {
    nonisolated static func makeAuthFileContentsForTesting(
        idToken: String,
        accessToken: String,
        refreshToken: String,
        refreshedAt: Date
    ) throws -> String {
        try makeAuthFileContents(
            from: OAuthTokens(
                idToken: idToken,
                accessToken: accessToken,
                refreshToken: refreshToken
            ),
            refreshedAt: refreshedAt
        )
    }
}
#endif

private nonisolated final class CodexOAuthCallbackServer: @unchecked Sendable {
    private let expectedState: String
    private let timeout: TimeInterval
    private let queue = DispatchQueue(label: "com.marcel2215.codexswitcher.oauth-callback")
    private let state = CodexOAuthCallbackState()
    private let cancellationLock = NSLock()
    private var listener: NWListener?
    private var isListenerCancelled = false

    nonisolated init(expectedState: String, timeout: TimeInterval, preferredPort: UInt16 = 0) throws {
        self.expectedState = expectedState
        self.timeout = timeout
        let port = NWEndpoint.Port(rawValue: preferredPort) ?? .any
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        listener = try NWListener(using: parameters, on: port)
    }

    nonisolated func start() async throws -> UInt16 {
        guard let listener else {
            throw CodexOfficialLoginError.callbackServerUnavailable("")
        }

        listener.stateUpdateHandler = { [state] newState in
            switch newState {
            case .ready:
                guard let port = listener.port else {
                    state.failStart(CodexOfficialLoginError.callbackServerUnavailable(""))
                    return
                }
                state.completeStart(port.rawValue)
            case let .failed(error):
                state.failStart(CodexOfficialLoginError.callbackServerUnavailable(error.localizedDescription))
                state.failCallback(CodexOfficialLoginError.callbackServerUnavailable(error.localizedDescription))
            case .cancelled:
                state.failStart(CodexOfficialLoginError.cancelled)
                state.failCallback(CodexOfficialLoginError.cancelled)
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            guard let self else {
                connection.cancel()
                return
            }

            self.handle(connection)
        }

        listener.start(queue: queue)
        queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.state.failCallback(CodexOfficialLoginError.cancelled)
            self?.cancelListener()
        }

        return try await state.waitForStart()
    }

    nonisolated func waitForAuthorizationCode() async throws -> String {
        try await state.waitForCallback()
    }

    nonisolated func cancel() {
        state.failStart(CodexOfficialLoginError.cancelled)
        state.failCallback(CodexOfficialLoginError.cancelled)
        cancelListener()
    }

    private nonisolated func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        Self.receiveRequest(on: connection) { [weak self] request in
            guard let self else {
                connection.cancel()
                return
            }

            let result = Self.response(for: request, expectedState: self.expectedState)
            connection.send(content: Data(result.response.utf8), completion: .contentProcessed { [weak self] _ in
                connection.cancel()
                switch result.outcome {
                case let .success(code):
                    self?.state.completeCallback(code)
                    self?.cancelListener()
                case let .failure(error):
                    self?.state.failCallback(error)
                    self?.cancelListener()
                case .none:
                    break
                }
            })
        }
    }

    private nonisolated func cancelListener() {
        cancellationLock.lock()
        defer { cancellationLock.unlock() }

        guard !isListenerCancelled else {
            return
        }

        isListenerCancelled = true
        listener?.cancel()
    }

    private nonisolated static func receiveRequest(
        on connection: NWConnection,
        buffer: Data = Data(),
        completion: @escaping @Sendable (String) -> Void
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4_096) { data, _, isComplete, error in
            if error != nil {
                completion("")
                return
            }

            var nextBuffer = buffer
            if let data {
                nextBuffer.append(data)
            }

            if nextBuffer.range(of: Data("\r\n\r\n".utf8)) != nil || nextBuffer.count > 16_384 || isComplete {
                completion(String(data: nextBuffer, encoding: .utf8) ?? "")
                return
            }

            Self.receiveRequest(on: connection, buffer: nextBuffer, completion: completion)
        }
    }

    private nonisolated static func response(
        for request: String,
        expectedState: String
    ) -> (response: String, outcome: CodexOAuthCallbackOutcome) {
        guard isAllowedCallbackHost(hostHeader(in: request)) else {
            return (httpResponse(status: 400, body: "Bad Request"), .failure(CodexOfficialLoginError.invalidOAuthCallback))
        }

        guard
            let requestLine = request.components(separatedBy: "\r\n").first,
            let target = requestLine.split(separator: " ").dropFirst().first,
            let components = URLComponents(string: "http://localhost\(target)")
        else {
            return (httpResponse(status: 400, body: "Bad Request"), .failure(CodexOfficialLoginError.invalidOAuthCallback))
        }

        switch components.path {
        case "/auth/callback":
            let queryItems = components.queryItems ?? []
            let receivedState = queryItems.first(where: { $0.name == "state" })?.value
            guard receivedState == expectedState else {
                return (httpResponse(status: 400, body: "State mismatch"), .failure(CodexOfficialLoginError.invalidOAuthCallback))
            }

            if let error = queryItems.first(where: { $0.name == "error" })?.value {
                let description = queryItems.first(where: { $0.name == "error_description" })?.value
                let message = description?.isEmpty == false ? description! : error
                return (
                    httpResponse(status: 200, body: errorHTML(message: "Sign-in failed.")),
                    .failure(CodexOfficialLoginError.loginFailed(message))
                )
            }

            guard let code = queryItems.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
                return (httpResponse(status: 400, body: "Missing authorization code"), .failure(CodexOfficialLoginError.invalidOAuthCallback))
            }

            return (
                httpResponse(status: 200, body: successHTML()),
                .success(code)
            )

        case "/cancel":
            return (httpResponse(status: 200, body: "Login cancelled"), .failure(CodexOfficialLoginError.cancelled))

        default:
            return (httpResponse(status: 404, body: "Not Found"), .none)
        }
    }

    private nonisolated static func hostHeader(in request: String) -> String? {
        let headerLines = request
            .components(separatedBy: "\r\n")
            .dropFirst()

        guard let line = headerLines.first(where: { line in
            line.range(of: "Host:", options: [.anchored, .caseInsensitive]) != nil
        })
        else {
            return nil
        }

        return String(line.dropFirst("Host:".count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func isAllowedCallbackHost(_ hostHeader: String?) -> Bool {
        guard let rawHost = hostHeader?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            !rawHost.isEmpty
        else {
            return false
        }

        if rawHost == "[::1]" || rawHost.hasPrefix("[::1]:") {
            return true
        }

        let host = rawHost
            .split(separator: ":", maxSplits: 1)
            .first
            .map(String.init)

        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    private nonisolated static func httpResponse(status: Int, body: String) -> String {
        let reason = status == 200 ? "OK" : status == 400 ? "Bad Request" : "Not Found"
        let bodyData = Data(body.utf8)
        return """
        HTTP/1.1 \(status) \(reason)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(bodyData.count)\r
        Connection: close\r
        \r
        \(body)
        """
    }

    private nonisolated static func successHTML() -> String {
        """
        <!doctype html>
        <html>
        <head><meta charset="utf-8"><title>Codex Switcher</title></head>
        <body style="font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 48px;">
        <h1>Sign-in complete</h1>
        <p>You can close this browser window and return to Codex Switcher.</p>
        </body>
        </html>
        """
    }

    private nonisolated static func errorHTML(message: String) -> String {
        """
        <!doctype html>
        <html>
        <head><meta charset="utf-8"><title>Codex Switcher</title></head>
        <body style="font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 48px;">
        <h1>Sign-in failed</h1>
        <p>\(message)</p>
        </body>
        </html>
        """
    }
}

private nonisolated enum CodexOAuthCallbackOutcome {
    case success(String)
    case failure(Error)
    case none
}

private nonisolated final class CodexOAuthCallbackState: @unchecked Sendable {
    private let lock = NSLock()
    private var startContinuation: CheckedContinuation<UInt16, Error>?
    private var callbackContinuation: CheckedContinuation<String, Error>?
    private var startResult: Result<UInt16, Error>?
    private var callbackResult: Result<String, Error>?

    nonisolated func waitForStart() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let startResult {
                lock.unlock()
                continuation.resume(with: startResult)
                return
            }

            startContinuation = continuation
            lock.unlock()
        }
    }

    nonisolated func waitForCallback() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let callbackResult {
                lock.unlock()
                continuation.resume(with: callbackResult)
                return
            }

            callbackContinuation = continuation
            lock.unlock()
        }
    }

    nonisolated func completeStart(_ port: UInt16) {
        finishStart(.success(port))
    }

    nonisolated func failStart(_ error: Error) {
        finishStart(.failure(error))
    }

    nonisolated func completeCallback(_ code: String) {
        finishCallback(.success(code))
    }

    nonisolated func failCallback(_ error: Error) {
        finishCallback(.failure(error))
    }

    private nonisolated func finishStart(_ result: Result<UInt16, Error>) {
        let continuation: CheckedContinuation<UInt16, Error>?
        lock.lock()
        guard startResult == nil else {
            lock.unlock()
            return
        }
        startResult = result
        continuation = startContinuation
        startContinuation = nil
        lock.unlock()

        continuation?.resume(with: result)
    }

    private nonisolated func finishCallback(_ result: Result<String, Error>) {
        let continuation: CheckedContinuation<String, Error>?
        lock.lock()
        guard callbackResult == nil else {
            lock.unlock()
            return
        }
        callbackResult = result
        continuation = callbackContinuation
        callbackContinuation = nil
        lock.unlock()

        continuation?.resume(with: result)
    }
}

private extension Data {
    nonisolated func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

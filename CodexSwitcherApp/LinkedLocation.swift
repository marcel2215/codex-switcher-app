//
//  LinkedLocation.swift
//  Codex Switcher
//
//  Created by Marcel Kwiatkowski on 2026-04-11.
//

import Foundation

nonisolated struct AuthFileReadResult: Sendable, Equatable {
    nonisolated let url: URL
    nonisolated let contents: String
}

nonisolated struct AuthLinkedLocation: Sendable, Equatable {
    nonisolated let folderURL: URL
    nonisolated let credentialStoreHint: CodexCredentialStoreHint

    nonisolated var authFileURL: URL {
        folderURL.appending(path: "auth.json", directoryHint: .notDirectory)
    }

    nonisolated var configFileURL: URL {
        folderURL.appending(path: "config.toml", directoryHint: .notDirectory)
    }
}

nonisolated enum CodexCredentialStoreHint: String, Sendable, Equatable {
    case unknown
    case file
    case keyring
    case auto
    case unsupported

    nonisolated var isSupportedForFileSwitching: Bool {
        switch self {
        case .unknown, .file:
            true
        case .keyring, .auto, .unsupported:
            false
        }
    }

    nonisolated var displayName: String {
        switch self {
        case .unknown:
            L10n.string("credentialStore.unknown", defaultValue: "unknown")
        case .file:
            L10n.string("credentialStore.file", defaultValue: "file")
        case .keyring:
            L10n.string("credentialStore.keyring", defaultValue: "keyring")
        case .auto:
            L10n.string("credentialStore.auto", defaultValue: "auto")
        case .unsupported:
            L10n.string("credentialStore.unsupported", defaultValue: "unsupported")
        }
    }

    nonisolated static func detect(in folderURL: URL) -> CodexCredentialStoreHint {
        let configURL = folderURL.appending(path: "config.toml", directoryHint: .notDirectory)
        guard let contents = try? String(contentsOf: configURL, encoding: .utf8) else {
            return .unknown
        }

        guard let parsedValue = parseRootCredentialStoreValue(from: contents) else {
            return .unknown
        }

        guard let parsedValue else {
            return .unsupported
        }

        return CodexCredentialStoreHint(rawValue: parsedValue.lowercased()) ?? .unsupported
    }

    private nonisolated static func parseRootCredentialStoreValue(from contents: String) -> String?? {
        for line in contents.components(separatedBy: .newlines) {
            let uncommentedLine = line.removingTOMLComment()
            let trimmedLine = uncommentedLine.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmedLine.isEmpty else {
                continue
            }

            if trimmedLine.hasPrefix("[") {
                return nil
            }

            guard let separatorIndex = trimmedLine.firstTOMLKeyValueSeparatorIndex() else {
                continue
            }

            let key = trimmedLine[..<separatorIndex]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard key == "cli_auth_credentials_store" else {
                continue
            }

            let value = trimmedLine[trimmedLine.index(after: separatorIndex)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return parseSingleLineTOMLString(value)
        }

        return nil
    }

    private nonisolated static func parseSingleLineTOMLString(_ rawValue: String) -> String? {
        guard let delimiter = rawValue.first, delimiter == "\"" || delimiter == "'" else {
            return nil
        }

        var value = ""
        var index = rawValue.index(after: rawValue.startIndex)
        var escaped = false

        while index < rawValue.endIndex {
            let character = rawValue[index]

            if delimiter == "\"" {
                if escaped {
                    value.append(character)
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == delimiter {
                    let remainder = rawValue[rawValue.index(after: index)...]
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return remainder.isEmpty ? value : nil
                } else {
                    value.append(character)
                }
            } else if character == delimiter {
                let remainder = rawValue[rawValue.index(after: index)...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return remainder.isEmpty ? value : nil
            } else {
                value.append(character)
            }

            index = rawValue.index(after: index)
        }

        return nil
    }
}

private extension String {
    nonisolated func removingTOMLComment() -> String {
        var result = ""
        var quoteDelimiter: Character?
        var escaped = false

        for character in self {
            if let delimiter = quoteDelimiter {
                result.append(character)

                if delimiter == "\"" {
                    if escaped {
                        escaped = false
                    } else if character == "\\" {
                        escaped = true
                    } else if character == delimiter {
                        quoteDelimiter = nil
                    }
                } else if character == delimiter {
                    quoteDelimiter = nil
                }

                continue
            }

            if character == "#" {
                break
            }

            result.append(character)

            if character == "\"" || character == "'" {
                quoteDelimiter = character
                escaped = false
            }
        }

        return result
    }

    nonisolated func firstTOMLKeyValueSeparatorIndex() -> Index? {
        var quoteDelimiter: Character?
        var escaped = false

        for index in indices {
            let character = self[index]

            if let delimiter = quoteDelimiter {
                if delimiter == "\"" {
                    if escaped {
                        escaped = false
                    } else if character == "\\" {
                        escaped = true
                    } else if character == delimiter {
                        quoteDelimiter = nil
                    }
                } else if character == delimiter {
                    quoteDelimiter = nil
                }

                continue
            }

            if character == "=" {
                return index
            }

            if character == "\"" || character == "'" {
                quoteDelimiter = character
                escaped = false
            }
        }

        return nil
    }
}

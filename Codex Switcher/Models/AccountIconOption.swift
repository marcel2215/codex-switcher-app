//
//  AccountIconOption.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-07.
//

import Foundation

enum AccountIconOption: String, CaseIterable, Identifiable, Sendable {
    case key = "key.fill"
    case person = "person.crop.circle.fill"
    case people = "person.2.fill"
    case profile = "person.text.rectangle.fill"
    case briefcase = "briefcase.fill"
    case building = "building.2.fill"
    case terminal = "terminal.fill"
    case shield = "shield.fill"
    case lock = "lock.shield.fill"
    case bolt = "bolt.fill"
    case star = "star.fill"
    case sparkles = "sparkles"
    case heart = "heart.fill"
    case flame = "flame.fill"
    case leaf = "leaf.fill"
    case globe = "globe"
    case cloud = "cloud.fill"
    case moon = "moon.stars.fill"
    case sun = "sun.max.fill"
    case folder = "folder.fill"
    case document = "doc.text.fill"
    case tray = "tray.full.fill"
    case bookmark = "bookmark.fill"
    case tag = "tag.fill"
    case envelope = "envelope.fill"
    case at = "at.circle.fill"
    case bubble = "bubble.left.and.bubble.right.fill"
    case phone = "phone.fill"
    case server = "server.rack"
    case drive = "externaldrive.fill"
    case laptop = "laptopcomputer"
    case cpu = "cpu.fill"
    case network = "network"
    case puzzle = "puzzlepiece.fill"
    case camera = "camera.fill"
    case music = "music.note"
    case film = "film.fill"
    case paintbrush = "paintbrush.pointed.fill"
    case gameController = "gamecontroller.fill"

    var id: String { rawValue }

    var systemName: String { rawValue }

    var title: String {
        switch self {
        case .key:
            "Key"
        case .person:
            "Person"
        case .people:
            "People"
        case .profile:
            "Profile"
        case .briefcase:
            "Briefcase"
        case .building:
            "Building"
        case .terminal:
            "Terminal"
        case .shield:
            "Shield"
        case .lock:
            "Lock"
        case .bolt:
            "Bolt"
        case .star:
            "Star"
        case .sparkles:
            "Sparkles"
        case .heart:
            "Heart"
        case .flame:
            "Flame"
        case .leaf:
            "Leaf"
        case .globe:
            "Globe"
        case .cloud:
            "Cloud"
        case .moon:
            "Moon"
        case .sun:
            "Sun"
        case .folder:
            "Folder"
        case .document:
            "Document"
        case .tray:
            "Tray"
        case .bookmark:
            "Bookmark"
        case .tag:
            "Tag"
        case .envelope:
            "Envelope"
        case .at:
            "At"
        case .bubble:
            "Messages"
        case .phone:
            "Phone"
        case .server:
            "Server"
        case .drive:
            "Drive"
        case .laptop:
            "Laptop"
        case .cpu:
            "CPU"
        case .network:
            "Network"
        case .puzzle:
            "Puzzle"
        case .camera:
            "Camera"
        case .music:
            "Music"
        case .film:
            "Film"
        case .paintbrush:
            "Paintbrush"
        case .gameController:
            "Game Controller"
        }
    }

    static let defaultOption: Self = .key

    static func resolve(from storedSystemName: String) -> Self {
        Self(rawValue: storedSystemName) ?? defaultOption
    }
}

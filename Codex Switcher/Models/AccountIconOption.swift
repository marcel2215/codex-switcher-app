//
//  AccountIconOption.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-07.
//

import Foundation

enum AccountIconOption: String, CaseIterable, Identifiable, Sendable {
    case key = "key.fill"
    case keyCard = "key.card.fill"
    case person = "person.crop.circle.fill"
    case personSquare = "person.crop.square.fill"
    case personBadgeKey = "person.badge.key.fill"
    case people = "person.2.fill"
    case profile = "person.text.rectangle.fill"
    case briefcase = "briefcase.fill"
    case building = "building.2.fill"
    case columns = "building.columns.fill"
    case house = "house.fill"
    case terminal = "terminal.fill"
    case shield = "shield.fill"
    case lock = "lock.shield.fill"
    case bolt = "bolt.fill"
    case star = "star.fill"
    case sparkles = "sparkles"
    case heart = "heart.fill"
    case flame = "flame.fill"
    case leaf = "leaf.fill"
    case crown = "crown.fill"
    case diamond = "diamond.fill"
    case trophy = "trophy.fill"
    case medal = "medal.fill"
    case globe = "globe"
    case cloud = "cloud.fill"
    case moon = "moon.stars.fill"
    case sun = "sun.max.fill"
    case bell = "bell.fill"
    case flag = "flag.fill"
    case checkSeal = "checkmark.seal.fill"
    case lightbulb = "lightbulb.fill"
    case folder = "folder.fill"
    case document = "doc.text.fill"
    case tray = "tray.full.fill"
    case archiveBox = "archivebox.fill"
    case shippingBox = "shippingbox.fill"
    case bookmark = "bookmark.fill"
    case tag = "tag.fill"
    case envelope = "envelope.fill"
    case at = "at.circle.fill"
    case bubble = "bubble.left.and.bubble.right.fill"
    case paperPlane = "paperplane.fill"
    case link = "link.circle.fill"
    case calendar = "calendar.circle.fill"
    case clock = "clock.fill"
    case timer = "timer"
    case hourglass = "hourglass"
    case phone = "phone.fill"
    case mapPin = "mappin.circle.fill"
    case map = "map.fill"
    case airplane = "airplane"
    case car = "car.fill"
    case tram = "tram.fill"
    case bicycle = "bicycle"
    case server = "server.rack"
    case drive = "externaldrive.fill"
    case laptop = "laptopcomputer"
    case tv = "tv.fill"
    case printer = "printer.fill"
    case cpu = "cpu.fill"
    case network = "network"
    case wifi = "wifi"
    case antenna = "antenna.radiowaves.left.and.right"
    case puzzle = "puzzlepiece.fill"
    case hammer = "hammer.fill"
    case wrench = "wrench.and.screwdriver.fill"
    case camera = "camera.fill"
    case photo = "photo.fill"
    case video = "video.fill"
    case music = "music.note"
    case speaker = "speaker.wave.3.fill"
    case mic = "mic.fill"
    case headphones = "headphones"
    case film = "film.fill"
    case paintbrush = "paintbrush.pointed.fill"
    case gift = "gift.fill"
    case bag = "bag.fill"
    case cart = "cart.fill"
    case banknote = "banknote.fill"
    case chartBar = "chart.bar.fill"
    case chartPie = "chart.pie.fill"
    case book = "book.fill"
    case graduationCap = "graduationcap.fill"
    case newspaper = "newspaper.fill"
    case safari = "safari.fill"
    case binoculars = "binoculars.fill"
    case ticket = "ticket.fill"
    case gameController = "gamecontroller.fill"

    var id: String { rawValue }

    var systemName: String { rawValue }

    var title: String {
        switch self {
        case .key:
            "Key"
        case .keyCard:
            "Key Card"
        case .person:
            "Person"
        case .personSquare:
            "Person Square"
        case .personBadgeKey:
            "Person Badge Key"
        case .people:
            "People"
        case .profile:
            "Profile"
        case .briefcase:
            "Briefcase"
        case .building:
            "Building"
        case .columns:
            "Columns"
        case .house:
            "House"
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
        case .crown:
            "Crown"
        case .diamond:
            "Diamond"
        case .trophy:
            "Trophy"
        case .medal:
            "Medal"
        case .globe:
            "Globe"
        case .cloud:
            "Cloud"
        case .moon:
            "Moon"
        case .sun:
            "Sun"
        case .bell:
            "Bell"
        case .flag:
            "Flag"
        case .checkSeal:
            "Checkmark Seal"
        case .lightbulb:
            "Lightbulb"
        case .folder:
            "Folder"
        case .document:
            "Document"
        case .tray:
            "Tray"
        case .archiveBox:
            "Archive Box"
        case .shippingBox:
            "Shipping Box"
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
        case .paperPlane:
            "Paper Plane"
        case .link:
            "Link"
        case .calendar:
            "Calendar"
        case .clock:
            "Clock"
        case .timer:
            "Timer"
        case .hourglass:
            "Hourglass"
        case .phone:
            "Phone"
        case .mapPin:
            "Map Pin"
        case .map:
            "Map"
        case .airplane:
            "Airplane"
        case .car:
            "Car"
        case .tram:
            "Tram"
        case .bicycle:
            "Bicycle"
        case .server:
            "Server"
        case .drive:
            "Drive"
        case .laptop:
            "Laptop"
        case .tv:
            "TV"
        case .printer:
            "Printer"
        case .cpu:
            "CPU"
        case .network:
            "Network"
        case .wifi:
            "Wi-Fi"
        case .antenna:
            "Antenna"
        case .puzzle:
            "Puzzle"
        case .hammer:
            "Hammer"
        case .wrench:
            "Wrench"
        case .camera:
            "Camera"
        case .photo:
            "Photo"
        case .video:
            "Video"
        case .music:
            "Music"
        case .speaker:
            "Speaker"
        case .mic:
            "Microphone"
        case .headphones:
            "Headphones"
        case .film:
            "Film"
        case .paintbrush:
            "Paintbrush"
        case .gift:
            "Gift"
        case .bag:
            "Bag"
        case .cart:
            "Cart"
        case .banknote:
            "Banknote"
        case .chartBar:
            "Bar Chart"
        case .chartPie:
            "Pie Chart"
        case .book:
            "Book"
        case .graduationCap:
            "Graduation Cap"
        case .newspaper:
            "Newspaper"
        case .safari:
            "Compass"
        case .binoculars:
            "Binoculars"
        case .ticket:
            "Ticket"
        case .gameController:
            "Game Controller"
        }
    }

    // Explicit display order keeps the picker focused on the icons people are
    // most likely to choose first, followed by the broader catalog.
    static let displayOrder: [Self] = [
        .key,
        .star,
        .heart,
        .house,
        .briefcase,
        .graduationCap,
        .hammer,
        .building,
        .columns,
        .person,
        .personSquare,
        .personBadgeKey,
        .people,
        .profile,
        .keyCard,
        .terminal,
        .laptop,
        .book,
        .document,
        .calendar,
        .lightbulb,
        .checkSeal,
        .shield,
        .lock,
        .bookmark,
        .tag,
        .folder,
        .tray,
        .archiveBox,
        .shippingBox,
        .envelope,
        .at,
        .bubble,
        .paperPlane,
        .link,
        .phone,
        .clock,
        .timer,
        .hourglass,
        .globe,
        .cloud,
        .sun,
        .moon,
        .bell,
        .flag,
        .mapPin,
        .map,
        .airplane,
        .car,
        .tram,
        .bicycle,
        .server,
        .drive,
        .tv,
        .printer,
        .cpu,
        .network,
        .wifi,
        .antenna,
        .puzzle,
        .wrench,
        .camera,
        .photo,
        .video,
        .music,
        .speaker,
        .mic,
        .headphones,
        .film,
        .paintbrush,
        .gift,
        .bag,
        .cart,
        .banknote,
        .chartBar,
        .chartPie,
        .newspaper,
        .safari,
        .binoculars,
        .ticket,
        .gameController,
        .bolt,
        .sparkles,
        .flame,
        .leaf,
        .crown,
        .diamond,
        .trophy,
        .medal
    ]

    static let defaultOption: Self = .key

    static func resolve(from storedSystemName: String) -> Self {
        Self(rawValue: storedSystemName) ?? defaultOption
    }
}

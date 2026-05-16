//
//  AccountIconOption.swift
//  Codex Switcher
//
//  Created by Marcel Kwiatkowski on 2026-04-07.
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
            L10n.string("Key", comment: "Display label for Key.")
        case .keyCard:
            L10n.string("Key Card", comment: "Display label for Key Card.")
        case .person:
            L10n.string("Person", comment: "Display label for Person.")
        case .personSquare:
            L10n.string("Person Square", comment: "Display label for Person Square.")
        case .personBadgeKey:
            L10n.string("Person Badge Key", comment: "Display label for Person Badge Key.")
        case .people:
            L10n.string("People", comment: "Display label for People.")
        case .profile:
            L10n.string("Profile", comment: "Display label for Profile.")
        case .briefcase:
            L10n.string("Briefcase", comment: "Display label for Briefcase.")
        case .building:
            L10n.string("Building", comment: "Display label for Building.")
        case .columns:
            L10n.string("Columns", comment: "Display label for Columns.")
        case .house:
            L10n.string("House", comment: "Display label for House.")
        case .terminal:
            L10n.string("Terminal", comment: "Display label for Terminal.")
        case .shield:
            L10n.string("Shield", comment: "Display label for Shield.")
        case .lock:
            L10n.string("Lock", comment: "Display label for Lock.")
        case .bolt:
            L10n.string("Bolt", comment: "Display label for Bolt.")
        case .star:
            L10n.string("Star", comment: "Display label for Star.")
        case .sparkles:
            L10n.string("Sparkles", comment: "Display label for Sparkles.")
        case .heart:
            L10n.string("Heart", comment: "Display label for Heart.")
        case .flame:
            L10n.string("Flame", comment: "Display label for Flame.")
        case .leaf:
            L10n.string("Leaf", comment: "Display label for Leaf.")
        case .crown:
            L10n.string("Crown", comment: "Display label for Crown.")
        case .diamond:
            L10n.string("Diamond", comment: "Display label for Diamond.")
        case .trophy:
            L10n.string("Trophy", comment: "Display label for Trophy.")
        case .medal:
            L10n.string("Medal", comment: "Display label for Medal.")
        case .globe:
            L10n.string("Globe", comment: "Display label for Globe.")
        case .cloud:
            L10n.string("Cloud", comment: "Display label for Cloud.")
        case .moon:
            L10n.string("Moon", comment: "Display label for Moon.")
        case .sun:
            L10n.string("Sun", comment: "Display label for Sun.")
        case .bell:
            L10n.string("Bell", comment: "Display label for Bell.")
        case .flag:
            L10n.string("Flag", comment: "Display label for Flag.")
        case .checkSeal:
            L10n.string("Checkmark Seal", comment: "Display label for Checkmark Seal.")
        case .lightbulb:
            L10n.string("Lightbulb", comment: "Display label for Lightbulb.")
        case .folder:
            L10n.string("Folder", comment: "Display label for Folder.")
        case .document:
            L10n.string("Document", comment: "Display label for Document.")
        case .tray:
            L10n.string("Tray", comment: "Display label for Tray.")
        case .archiveBox:
            L10n.string("Archive Box", comment: "Display label for Archive Box.")
        case .shippingBox:
            L10n.string("Shipping Box", comment: "Display label for Shipping Box.")
        case .bookmark:
            L10n.string("Bookmark", comment: "Display label for Bookmark.")
        case .tag:
            L10n.string("Tag", comment: "Display label for Tag.")
        case .envelope:
            L10n.string("Envelope", comment: "Display label for Envelope.")
        case .at:
            L10n.string("At", comment: "Display label for At.")
        case .bubble:
            L10n.string("Messages", comment: "Display label for Messages.")
        case .paperPlane:
            L10n.string("Paper Plane", comment: "Display label for Paper Plane.")
        case .link:
            L10n.string("Link", comment: "Display label for Link.")
        case .calendar:
            L10n.string("Calendar", comment: "Display label for Calendar.")
        case .clock:
            L10n.string("Clock", comment: "Display label for Clock.")
        case .timer:
            L10n.string("Timer", comment: "Display label for Timer.")
        case .hourglass:
            L10n.string("Hourglass", comment: "Display label for Hourglass.")
        case .phone:
            L10n.string("Phone", comment: "Display label for Phone.")
        case .mapPin:
            L10n.string("Map Pin", comment: "Display label for Map Pin.")
        case .map:
            L10n.string("Map", comment: "Display label for Map.")
        case .airplane:
            L10n.string("Airplane", comment: "Display label for Airplane.")
        case .car:
            L10n.string("Car", comment: "Display label for Car.")
        case .tram:
            L10n.string("Tram", comment: "Display label for Tram.")
        case .bicycle:
            L10n.string("Bicycle", comment: "Display label for Bicycle.")
        case .server:
            L10n.string("Server", comment: "Display label for Server.")
        case .drive:
            L10n.string("Drive", comment: "Display label for Drive.")
        case .laptop:
            L10n.string("Laptop", comment: "Display label for Laptop.")
        case .tv:
            L10n.string("TV", comment: "Display label for TV.")
        case .printer:
            L10n.string("Printer", comment: "Display label for Printer.")
        case .cpu:
            L10n.string("CPU", comment: "Display label for CPU.")
        case .network:
            L10n.string("Network", comment: "Display label for Network.")
        case .wifi:
            L10n.string("Wi-Fi", comment: "Display label for Wi-Fi.")
        case .antenna:
            L10n.string("Antenna", comment: "Display label for Antenna.")
        case .puzzle:
            L10n.string("Puzzle", comment: "Display label for Puzzle.")
        case .hammer:
            L10n.string("Hammer", comment: "Display label for Hammer.")
        case .wrench:
            L10n.string("Wrench", comment: "Display label for Wrench.")
        case .camera:
            L10n.string("Camera", comment: "Display label for Camera.")
        case .photo:
            L10n.string("Photo", comment: "Display label for Photo.")
        case .video:
            L10n.string("Video", comment: "Display label for Video.")
        case .music:
            L10n.string("Music", comment: "Display label for Music.")
        case .speaker:
            L10n.string("Speaker", comment: "Display label for Speaker.")
        case .mic:
            L10n.string("Microphone", comment: "Display label for Microphone.")
        case .headphones:
            L10n.string("Headphones", comment: "Display label for Headphones.")
        case .film:
            L10n.string("Film", comment: "Display label for Film.")
        case .paintbrush:
            L10n.string("Paintbrush", comment: "Display label for Paintbrush.")
        case .gift:
            L10n.string("Gift", comment: "Display label for Gift.")
        case .bag:
            L10n.string("Bag", comment: "Display label for Bag.")
        case .cart:
            L10n.string("Cart", comment: "Display label for Cart.")
        case .banknote:
            L10n.string("Banknote", comment: "Display label for Banknote.")
        case .chartBar:
            L10n.string("Bar Chart", comment: "Display label for Bar Chart.")
        case .chartPie:
            L10n.string("Pie Chart", comment: "Display label for Pie Chart.")
        case .book:
            L10n.string("Book", comment: "Display label for Book.")
        case .graduationCap:
            L10n.string("Graduation Cap", comment: "Display label for Graduation Cap.")
        case .newspaper:
            L10n.string("Newspaper", comment: "Display label for Newspaper.")
        case .safari:
            L10n.string("Compass", comment: "Display label for Compass.")
        case .binoculars:
            L10n.string("Binoculars", comment: "Display label for Binoculars.")
        case .ticket:
            L10n.string("Ticket", comment: "Display label for Ticket.")
        case .gameController:
            L10n.string("Game Controller", comment: "Display label for Game Controller.")
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

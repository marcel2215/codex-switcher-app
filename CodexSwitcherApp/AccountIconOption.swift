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
            L10n.string("accountIcon.key", defaultValue: "Key")
        case .keyCard:
            L10n.string("accountIcon.keyCard", defaultValue: "Key Card")
        case .person:
            L10n.string("accountIcon.person", defaultValue: "Person")
        case .personSquare:
            L10n.string("accountIcon.personSquare", defaultValue: "Person Square")
        case .personBadgeKey:
            L10n.string("accountIcon.personBadgeKey", defaultValue: "Person Badge Key")
        case .people:
            L10n.string("accountIcon.people", defaultValue: "People")
        case .profile:
            L10n.string("accountIcon.profile", defaultValue: "Profile")
        case .briefcase:
            L10n.string("accountIcon.briefcase", defaultValue: "Briefcase")
        case .building:
            L10n.string("accountIcon.building", defaultValue: "Building")
        case .columns:
            L10n.string("accountIcon.columns", defaultValue: "Columns")
        case .house:
            L10n.string("accountIcon.house", defaultValue: "House")
        case .terminal:
            L10n.string("accountIcon.terminal", defaultValue: "Terminal")
        case .shield:
            L10n.string("accountIcon.shield", defaultValue: "Shield")
        case .lock:
            L10n.string("accountIcon.lock", defaultValue: "Lock")
        case .bolt:
            L10n.string("accountIcon.bolt", defaultValue: "Bolt")
        case .star:
            L10n.string("accountIcon.star", defaultValue: "Star")
        case .sparkles:
            L10n.string("accountIcon.sparkles", defaultValue: "Sparkles")
        case .heart:
            L10n.string("accountIcon.heart", defaultValue: "Heart")
        case .flame:
            L10n.string("accountIcon.flame", defaultValue: "Flame")
        case .leaf:
            L10n.string("accountIcon.leaf", defaultValue: "Leaf")
        case .crown:
            L10n.string("accountIcon.crown", defaultValue: "Crown")
        case .diamond:
            L10n.string("accountIcon.diamond", defaultValue: "Diamond")
        case .trophy:
            L10n.string("accountIcon.trophy", defaultValue: "Trophy")
        case .medal:
            L10n.string("accountIcon.medal", defaultValue: "Medal")
        case .globe:
            L10n.string("accountIcon.globe", defaultValue: "Globe")
        case .cloud:
            L10n.string("accountIcon.cloud", defaultValue: "Cloud")
        case .moon:
            L10n.string("accountIcon.moon", defaultValue: "Moon")
        case .sun:
            L10n.string("accountIcon.sun", defaultValue: "Sun")
        case .bell:
            L10n.string("accountIcon.bell", defaultValue: "Bell")
        case .flag:
            L10n.string("accountIcon.flag", defaultValue: "Flag")
        case .checkSeal:
            L10n.string("accountIcon.checkmarkSeal", defaultValue: "Checkmark Seal")
        case .lightbulb:
            L10n.string("accountIcon.lightbulb", defaultValue: "Lightbulb")
        case .folder:
            L10n.string("accountIcon.folder", defaultValue: "Folder")
        case .document:
            L10n.string("accountIcon.document", defaultValue: "Document")
        case .tray:
            L10n.string("accountIcon.tray", defaultValue: "Tray")
        case .archiveBox:
            L10n.string("accountIcon.archiveBox", defaultValue: "Archive Box")
        case .shippingBox:
            L10n.string("accountIcon.shippingBox", defaultValue: "Shipping Box")
        case .bookmark:
            L10n.string("accountIcon.bookmark", defaultValue: "Bookmark")
        case .tag:
            L10n.string("accountIcon.tag", defaultValue: "Tag")
        case .envelope:
            L10n.string("accountIcon.envelope", defaultValue: "Envelope")
        case .at:
            L10n.string("accountIcon.at", defaultValue: "At")
        case .bubble:
            L10n.string("accountIcon.messages", defaultValue: "Messages")
        case .paperPlane:
            L10n.string("accountIcon.paperPlane", defaultValue: "Paper Plane")
        case .link:
            L10n.string("accountIcon.link", defaultValue: "Link")
        case .calendar:
            L10n.string("accountIcon.calendar", defaultValue: "Calendar")
        case .clock:
            L10n.string("accountIcon.clock", defaultValue: "Clock")
        case .timer:
            L10n.string("accountIcon.timer", defaultValue: "Timer")
        case .hourglass:
            L10n.string("accountIcon.hourglass", defaultValue: "Hourglass")
        case .phone:
            L10n.string("accountIcon.phone", defaultValue: "Phone")
        case .mapPin:
            L10n.string("accountIcon.mapPin", defaultValue: "Map Pin")
        case .map:
            L10n.string("accountIcon.map", defaultValue: "Map")
        case .airplane:
            L10n.string("accountIcon.airplane", defaultValue: "Airplane")
        case .car:
            L10n.string("accountIcon.car", defaultValue: "Car")
        case .tram:
            L10n.string("accountIcon.tram", defaultValue: "Tram")
        case .bicycle:
            L10n.string("accountIcon.bicycle", defaultValue: "Bicycle")
        case .server:
            L10n.string("accountIcon.server", defaultValue: "Server")
        case .drive:
            L10n.string("accountIcon.drive", defaultValue: "Drive")
        case .laptop:
            L10n.string("accountIcon.laptop", defaultValue: "Laptop")
        case .tv:
            L10n.string("accountIcon.tv", defaultValue: "TV")
        case .printer:
            L10n.string("accountIcon.printer", defaultValue: "Printer")
        case .cpu:
            L10n.string("accountIcon.cpu", defaultValue: "CPU")
        case .network:
            L10n.string("accountIcon.network", defaultValue: "Network")
        case .wifi:
            L10n.string("accountIcon.wifi", defaultValue: "Wi-Fi")
        case .antenna:
            L10n.string("accountIcon.antenna", defaultValue: "Antenna")
        case .puzzle:
            L10n.string("accountIcon.puzzle", defaultValue: "Puzzle")
        case .hammer:
            L10n.string("accountIcon.hammer", defaultValue: "Hammer")
        case .wrench:
            L10n.string("accountIcon.wrench", defaultValue: "Wrench")
        case .camera:
            L10n.string("accountIcon.camera", defaultValue: "Camera")
        case .photo:
            L10n.string("accountIcon.photo", defaultValue: "Photo")
        case .video:
            L10n.string("accountIcon.video", defaultValue: "Video")
        case .music:
            L10n.string("accountIcon.music", defaultValue: "Music")
        case .speaker:
            L10n.string("accountIcon.speaker", defaultValue: "Speaker")
        case .mic:
            L10n.string("accountIcon.microphone", defaultValue: "Microphone")
        case .headphones:
            L10n.string("accountIcon.headphones", defaultValue: "Headphones")
        case .film:
            L10n.string("accountIcon.film", defaultValue: "Film")
        case .paintbrush:
            L10n.string("accountIcon.paintbrush", defaultValue: "Paintbrush")
        case .gift:
            L10n.string("accountIcon.gift", defaultValue: "Gift")
        case .bag:
            L10n.string("accountIcon.bag", defaultValue: "Bag")
        case .cart:
            L10n.string("accountIcon.cart", defaultValue: "Cart")
        case .banknote:
            L10n.string("accountIcon.banknote", defaultValue: "Banknote")
        case .chartBar:
            L10n.string("accountIcon.barChart", defaultValue: "Bar Chart")
        case .chartPie:
            L10n.string("accountIcon.pieChart", defaultValue: "Pie Chart")
        case .book:
            L10n.string("accountIcon.book", defaultValue: "Book")
        case .graduationCap:
            L10n.string("accountIcon.graduationCap", defaultValue: "Graduation Cap")
        case .newspaper:
            L10n.string("accountIcon.newspaper", defaultValue: "Newspaper")
        case .safari:
            L10n.string("accountIcon.compass", defaultValue: "Compass")
        case .binoculars:
            L10n.string("accountIcon.binoculars", defaultValue: "Binoculars")
        case .ticket:
            L10n.string("accountIcon.ticket", defaultValue: "Ticket")
        case .gameController:
            L10n.string("accountIcon.gameController", defaultValue: "Game Controller")
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

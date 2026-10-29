import Foundation

struct SettingsWebLink: Identifiable {
    let url: URL
    var id: URL { url }
}

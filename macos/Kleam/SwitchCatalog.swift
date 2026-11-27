import SwiftUI

struct SwitchPack: Identifiable, Hashable {
    var id: String { slug }
    let slug: String
    let name: String
    let feel: String
    let colors: [Color]
    let isNew: Bool
}

enum SwitchCatalog {
    static let defaultSlug = "super-red"

    static let all: [SwitchPack] = [
        SwitchPack(
            slug: "cardboard",
            name: "Cardboard",
            feel: "Dry mid tap · short decay",
            colors: [
                Color(red: 0.72, green: 0.55, blue: 0.36),
                Color(red: 0.48, green: 0.34, blue: 0.20),
            ],
            isNew: false
        ),
        SwitchPack(
            slug: "cream",
            name: "Cream",
            feel: "Deep thock · heavy body · soft crack",
            colors: [
                Color(red: 0.96, green: 0.92, blue: 0.82),
                Color(red: 0.82, green: 0.74, blue: 0.58),
            ],
            isNew: false
        ),
        SwitchPack(
            slug: "crystal-purple",
            name: "Crystal Purple",
            feel: "Glassy mid-high · bright short body",
            colors: [
                Color(red: 0.72, green: 0.52, blue: 0.92),
                Color(red: 0.42, green: 0.22, blue: 0.68),
            ],
            isNew: false
        ),
        SwitchPack(
            slug: "japanese-black",
            name: "Japanese Black",
            feel: "Sharp click · thin body",
            colors: [
                Color(red: 0.28, green: 0.28, blue: 0.30),
                Color(red: 0.08, green: 0.08, blue: 0.09),
            ],
            isNew: false
        ),
        SwitchPack(
            slug: "milky-yellow",
            name: "Milky Yellow",
            feel: "Smooth linear · mid thock",
            colors: [
                Color(red: 0.98, green: 0.90, blue: 0.45),
                Color(red: 0.88, green: 0.72, blue: 0.18),
            ],
            isNew: false
        ),
        SwitchPack(
            slug: "oreo",
            name: "Oreo",
            feel: "Tactile mid bump · balanced",
            colors: [
                Color(red: 0.95, green: 0.95, blue: 0.94),
                Color(red: 0.14, green: 0.14, blue: 0.15),
            ],
            isNew: false
        ),
        SwitchPack(
            slug: "super-red",
            name: "Super Red",
            feel: "Linear · deep thock",
            colors: [
                Color(red: 0.98, green: 0.44, blue: 0.52),
                Color(red: 0.88, green: 0.11, blue: 0.28),
            ],
            isNew: true
        ),
    ]

    static func pack(slug: String) -> SwitchPack {
        if let match = all.first(where: { $0.slug == slug }) {
            return match
        }
        return all.first(where: { $0.slug == defaultSlug })!
    }

    static func resolvedSlug(_ slug: String) -> String {
        pack(slug: slug).slug
    }
}

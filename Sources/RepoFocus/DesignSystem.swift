import RepoFocusCore
import SwiftUI

enum Layout {
    static let grid: CGFloat = 4
    static let compact: CGFloat = 8
    static let regular: CGFloat = 12
    static let section: CGFloat = 16
    static let large: CGFloat = 24
    static let cardRadius: CGFloat = 10
    static let controlRadius: CGFloat = 7
}

extension Color {
    static let brandAccent = adaptive(light: "1677FF", dark: "66A3FF")
    static let appCanvas = adaptive(light: "F5F7FA", dark: "0F1011")
    static let panelBackground = adaptive(light: "FFFFFF", dark: "191A1C")
    static let elevatedBackground = adaptive(light: "F9FAFC", dark: "242527")
    static let sidebarBackground = adaptive(light: "EEF1F5", dark: "141516")
    static let headerBackground = adaptive(light: "FBFCFD", dark: "17181A")
    static let subtleFill = adaptive(light: "F1F4F8", dark: "212224")
    static let quietBorder = adaptive(light: "DCE2EA", dark: "303236")
    static let strongBorder = adaptive(light: "C7D0DC", dark: "484B50")

    private static func adaptive(light: String, dark: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }

    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        let red, green, blue: Double
        if cleaned.count == 6 {
            red = Double((value >> 16) & 0xff) / 255
            green = Double((value >> 8) & 0xff) / 255
            blue = Double(value & 0xff) / 255
        } else {
            red = 0.5
            green = 0.5
            blue = 0.5
        }

        self.init(red: red, green: green, blue: blue)
    }
}

private extension NSColor {
    convenience init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xff) / 255,
            green: CGFloat((value >> 8) & 0xff) / 255,
            blue: CGFloat(value & 0xff) / 255,
            alpha: 1
        )
    }
}

extension WorkStatus {
    var color: Color {
        switch self {
        case .inbox: .secondary
        case .planned: .indigo
        case .active: .blue
        case .blocked: .red
        case .paused: .orange
        case .done: .green
        case .archived: .gray
        }
    }
}

extension WorkPriority {
    var color: Color {
        switch self {
        case .low: .secondary
        case .medium: .blue
        case .high: .orange
        }
    }
}

struct PanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: Layout.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Layout.cardRadius, style: .continuous)
                    .stroke(Color.quietBorder, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.055), radius: 8, y: 2)
    }
}

extension View {
    func panelStyle() -> some View {
        modifier(PanelModifier())
    }
}

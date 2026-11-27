import AppKit
import SwiftUI

enum KleamRuntime {
    static let model = AppModel()
}

@main
struct KleamApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var model = KleamRuntime.model

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            Image(nsImage: model.enabled ? MenuIcon.sound : MenuIcon.muted)
                .accessibilityLabel(model.enabled ? "Kleam" : "Kleam, muted")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        KleamRuntime.model.start()
    }
}

enum MenuIcon {
    static let sound = image(muted: false)
    static let muted = image(muted: true)

    private static func image(muted: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let s = min(rect.width, rect.height)
            let ox = rect.midX - s / 2
            let oy = rect.midY - s / 2

            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: ox + x / 32 * s, y: oy + (32 - y) / 32 * s)
            }

            let k = NSBezierPath()
            k.move(to: p(9.2, 7.2))
            k.line(to: p(12.8, 7.2))
            k.line(to: p(12.8, 14.25))
            k.line(to: p(19.55, 7.2))
            k.line(to: p(23.6, 7.2))
            k.line(to: p(16.25, 15.35))
            k.line(to: p(24.0, 24.8))
            k.line(to: p(19.85, 24.8))
            k.line(to: p(13.8, 16.7))
            k.line(to: p(12.8, 16.7))
            k.line(to: p(12.8, 24.8))
            k.line(to: p(9.2, 24.8))
            k.close()
            NSColor.black.setFill()
            k.fill()

            if muted {
                let slash = NSBezierPath()
                slash.lineCapStyle = .round
                slash.move(to: p(5.2, 6.2))
                slash.line(to: p(26.8, 27.2))
                slash.lineWidth = s * (4.6 / 32)
                NSGraphicsContext.current?.cgContext.setBlendMode(.destinationOut)
                NSColor.black.setStroke()
                slash.stroke()
                NSGraphicsContext.current?.cgContext.setBlendMode(.normal)
                slash.lineWidth = s * (2.1 / 32)
                NSColor.black.setStroke()
                slash.stroke()
            } else {
                let tick = NSBezierPath()
                tick.lineCapStyle = .round
                tick.lineWidth = s * (2.4 / 32)
                tick.move(to: p(20.4, 21.6))
                tick.line(to: p(24.3, 24.8))
                NSColor.black.setStroke()
                tick.stroke()
            }

            return true
        }
        image.isTemplate = true
        return image
    }
}

import AppKit
import SwiftUI

@main
struct KleamApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: delegate.model)
        } label: {
            Image(nsImage: MenuIcon.image)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model.start()
    }
}

enum MenuIcon {
    static let image: NSImage = {
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

            let tick = NSBezierPath()
            tick.lineCapStyle = .round
            tick.lineWidth = s * (2.4 / 32)
            tick.move(to: p(20.4, 21.6))
            tick.line(to: p(24.3, 24.8))
            NSColor.black.setStroke()
            tick.stroke()

            return true
        }
        image.isTemplate = true
        return image
    }()
}

import AppKit
import SwiftUI

@MainActor
final class StatusItemController {
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?

    init() {
        popover.behavior = .transient
        popover.animates = false
        popover.contentSize = NSSize(width: 370, height: 440)
    }

    func install<Content: View>(rootView: Content, target: AnyObject, action: Selector) {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.target = target
        statusItem.button?.action = action
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.button?.image = NSImage(
            systemSymbolName: "die.face.1",
            accessibilityDescription: "Singletion"
        )
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "Singletion"

        self.statusItem = statusItem
        popover.contentViewController = NSHostingController(rootView: rootView)
    }

    func togglePopover(sender: AnyObject?) {
        guard let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func closePopover(sender: AnyObject? = nil) {
        if popover.isShown {
            popover.performClose(sender)
        }
    }
}

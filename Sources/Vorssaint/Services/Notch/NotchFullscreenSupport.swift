// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Native fullscreen Spaces plus players using a screen-sized desktop window.
/// Only window metadata is read: no images, window titles or AX permission.
enum NotchFullscreenSupport {
    static func activeDisplays() -> Set<CGDirectDisplayID> {
        let screens = NSScreen.screens
        let topology = SpaceWindowBridge.topology()
        var result = Set(screens.map(\.notchDisplayID).filter {
            topology?.isFullscreen(on: $0, separateSpaces: NSScreen.screensHaveSeparateSpaces) == true
        })
        // Native fullscreen already answers for these displays. Desktop video
        // modes need a fallback because they post no Space-change notification.
        let remaining = screens.map(\.notchDisplayID).filter { !result.contains($0) }
        guard !remaining.isEmpty,
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              app.bundleIdentifier != "com.apple.finder",
              app.bundleIdentifier != "com.apple.dock",
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]] else { return result }
        let displays = Dictionary(uniqueKeysWithValues: remaining.map { ($0, CGDisplayBounds($0)) })
        result.formUnion(desktopFullscreenDisplays(windows, ownerPID: app.processIdentifier, displays: displays))
        return result
    }

    static func desktopFullscreenDisplays(_ windows: [[String: Any]], ownerPID: Int32,
                                         displays: [CGDirectDisplayID: CGRect]) -> Set<CGDirectDisplayID> {
        var result = Set<CGDirectDisplayID>()
        for window in windows {
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == ownerPID,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                  let dictionary = window[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary) else { continue }
            for (id, display) in displays where coversDisplay(bounds, display: display) {
                result.insert(id)
            }
        }
        return result
    }

    /// Both rectangles use Quartz coordinates, including displays above or to
    /// the left of the main display. A maximized window below the menu bar
    /// does not qualify; a borderless window covering the display does.
    static func coversDisplay(_ window: CGRect, display: CGRect) -> Bool {
        guard !display.isEmpty, !window.isEmpty, !window.isInfinite, !window.isNull else { return false }
        let tolerance: CGFloat = 1
        return abs(window.minX - display.minX) <= tolerance
            && abs(window.minY - display.minY) <= tolerance
            && abs(window.maxX - display.maxX) <= tolerance
            && abs(window.maxY - display.maxY) <= tolerance
    }
}

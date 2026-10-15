// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// Production Space selection and visibility transitions, with no desktop changes.
enum NotchFullscreenTests {
    enum UserDefaults {
        static let standard = Preferences()
        final class Preferences {
            var enabled = false
            var preciseVolume = false
            func bool(forKey key: String) -> Bool {
                switch key {
                case DefaultsKey.notchHideInFullscreen: return enabled
                case DefaultsKey.preciseVolumeRollerEnabled: return preciseVolume
                default: return false
                }
            }
        }
    }
    enum AppFeature {
        static let mixer = Feature()
        static let brightness = Feature()
        struct Feature { let isAvailable = true }
    }
    final class BrightnessService {
        static let shared = BrightnessService()
        var syncs = 0
        func syncWithPreferences() { syncs += 1 }
    }
    enum NotchSupport {
        enum Event { case volume }
        static func routes(_ event: Event) -> Bool { true }
    }
    enum SessionActivity {
        static let shared = Session()
        struct Session { let isActive = true }
    }
    static func AXIsProcessTrusted() -> Bool { true }
    enum NotchService { static var shared = Service() }
    class VolumeState {
        var running = false
        func start() { running = true }
        func stop() { running = false }
    }
    enum NSScreen { static var screensHaveSeparateSpaces = true }
    enum SpaceWindowBridge {
        static var value: Topology?
        static var reads = 0
        static func topology() -> Topology? { reads += 1; return value }
    }
    enum NotchFullscreenSupport {
        static var desktopDisplays: Set<CGDirectDisplayID> = []
        static func activeDisplays() -> Set<CGDirectDisplayID> {
            let topology = SpaceWindowBridge.topology()
            return Set([CGDirectDisplayID(1), 2].filter {
                topology?.isFullscreen(on: $0, separateSpaces: NSScreen.screensHaveSeparateSpaces) == true
            }).union(desktopDisplays)
        }
    }
    class State {
        var fullscreenTimer: Timer?
        deinit { fullscreenTimer?.invalidate() }
        var running = true, suspended = false, hiddenInFullscreen = false
        var hoverEmphasized = false
        var panel: Bool? = true
        var windowHost: Host? = Host()
        struct Host { var isConcealedForMissionControl = false }
        var screenUpdate: (() -> Void)?
        var heldDrag = true, dragPlaceholder = true, noticeExpanded = true
        var hoverWork: DispatchWorkItem?, noticeWork: DispatchWorkItem?
        var notice: Bool? = true
        var collapses = 0, cancellations = 0, screenUpdates = 0, consumerSyncs = 0, refreshes = 0, departures = 0
        func cancelCaptureControls() { cancellations += 1 }
        func endDeparture() { departures += 1 }
        func collapse() { collapses += 1 }
        func updateScreen() { screenUpdates += 1; screenUpdate?() }
        func syncVisibleConsumers() { consumerSyncs += 1 }
        func refreshPresentation(animated: Bool) { refreshes += 1 }
        func updateFullscreenDisplays() {}
        func syncMirrors() {}
    }

    static func run(_ suite: TestSuite) {
        defer {
            UserDefaults.standard.enabled = false
            UserDefaults.standard.preciseVolume = false
            NSScreen.screensHaveSeparateSpaces = true
            SpaceWindowBridge.value = nil
            NotchService.shared = Service()
            PreciseVolumeRollerService.shared.stop()
        }
        let topology = Topology(displays: [
            .init(displayID: 1, spaces: [10, 11], fullscreenSpaces: [11], currentSpace: 10),
            .init(displayID: 2, spaces: [20, 21], fullscreenSpaces: [21], currentSpace: 21)
        ])
        suite.expect(!topology.isFullscreen(on: 1, separateSpaces: true)
                     && topology.isFullscreen(on: 2, separateSpaces: true),
                     "fullscreen on another monitor does not hide the island's desktop")
        suite.expect(topology.isFullscreen(on: 1, separateSpaces: false),
                     "a shared fullscreen Space applies to all monitors")
        suite.expect(!topology.isFullscreen(on: 99, separateSpaces: true),
                     "an unknown monitor is not mistaken for another monitor's fullscreen Space")
        let unknown = Topology(displays: [
            .init(displayID: nil, spaces: [10, 11], fullscreenSpaces: [11], currentSpace: 11)
        ])
        suite.expect(unknown.isFullscreen(on: 1, separateSpaces: false)
                     && !unknown.isFullscreen(on: 1, separateSpaces: true),
                     "a shared Space can omit its display UUID")

        let service = Service()
        SpaceWindowBridge.value = topology
        SpaceWindowBridge.reads = 0
        service.updateFullscreenVisibility(displayID: 2)
        suite.expect(!service.hiddenInFullscreen && SpaceWindowBridge.reads == 0,
                     "the opt-in preference avoids Space queries while disabled")
        UserDefaults.standard.enabled = true
        service.hoverEmphasized = true
        service.hoverWork = DispatchWorkItem {}
        service.noticeWork = DispatchWorkItem {}
        let hover = service.hoverWork!, notice = service.noticeWork!
        let brightnessSyncs = BrightnessService.shared.syncs
        service.updateFullscreenVisibility(displayID: 2)
        suite.expect(service.hiddenInFullscreen && service.collapses == 1 && service.cancellations == 1
                     && !service.heldDrag && !service.dragPlaceholder && service.notice == nil
                     && !service.hoverEmphasized && hover.isCancelled && notice.isCancelled && service.departures == 1,
                     "entering fullscreen clears hover emphasis, pending reveals, banners, departing notices, drags and capture controls")
        suite.expect(BrightnessService.shared.syncs == brightnessSyncs + 1,
                     "entering fullscreen hands the brightness keys back to the system")
        service.updateFullscreenVisibility(displayID: 2)
        suite.expect(service.collapses == 1 && BrightnessService.shared.syncs == brightnessSyncs + 1,
                     "unchanged fullscreen state does not repeat dismissal or key routing")
        service.updateFullscreenVisibility(displayID: 1)
        suite.expect(!service.hiddenInFullscreen && !service.hoverEmphasized
                     && BrightnessService.shared.syncs == brightnessSyncs + 2,
                     "returning to a desktop restores eligibility without retaining the old hover emphasis")
        service.updateFullscreenVisibility(displayID: 2)
        UserDefaults.standard.enabled = false
        service.updateFullscreenVisibility(displayID: 2)
        suite.expect(!service.hiddenInFullscreen, "disabling the option restores eligibility in fullscreen")
        UserDefaults.standard.enabled = true
        SpaceWindowBridge.value = nil
        service.updateFullscreenVisibility(displayID: 2)
        suite.expect(!service.hiddenInFullscreen, "unavailable Space queries leave the island reachable")
        service.fullscreenEnvironmentDidChange()
        suite.expect(service.screenUpdates == 1 && service.consumerSyncs == 0 && service.refreshes == 0,
                     "an unchanged fullscreen state leaves consumers and a transition on screen alone")
        service.screenUpdate = { [weak service] in service?.hiddenInFullscreen = true }
        service.fullscreenEnvironmentDidChange()
        suite.expect(service.screenUpdates == 2 && service.consumerSyncs == 1 && service.refreshes == 1,
                     "a fullscreen change reevaluates the display, consumers and presentation together")
        service.screenUpdate = nil
        service.suspended = true
        service.fullscreenEnvironmentDidChange()
        suite.expect(service.screenUpdates == 2, "Space changes cannot reveal a locked or sleeping session")
        UserDefaults.standard.enabled = false
        let idle = Service()
        idle.fullscreenEnvironmentDidChange()
        suite.expect(idle.screenUpdates == 0 && idle.consumerSyncs == 0 && idle.refreshes == 0,
                     "with the option off, app and Space changes do no fullscreen work")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchHideInFullscreen] as? Bool == true
                     && SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchHideInFullscreen),
                     "fullscreen hiding defaults on and is included in settings backup")
        volumeLifecycleChecks(topology, suite)
        desktopAndMonitoringChecks(suite)
    }

    private static func desktopAndMonitoringChecks(_ suite: TestSuite) {
        let screen = CGRect(x: -1440, y: -900, width: 1440, height: 900)
        suite.expect(Service.coversDisplay(screen, display: screen),
                     "desktop fullscreen recognizes negative display coordinates")
        suite.expect(!Service.coversDisplay(screen.insetBy(dx: 0, dy: 24), display: screen)
                     && !Service.coversDisplay(CGRect(x: 0, y: 0, width: 1440, height: 900), display: screen)
                     && !Service.coversDisplay(.zero, display: .zero),
                     "maximized windows, other displays and empty bounds are not fullscreen")
        func window(pid: Int32 = 42, layer: Int = 0, alpha: Double = 1, bounds: CGRect? = nil) -> [String: Any] {
            [kCGWindowOwnerPID as String: NSNumber(value: pid),
             kCGWindowLayer as String: NSNumber(value: layer),
             kCGWindowAlpha as String: NSNumber(value: alpha),
             kCGWindowBounds as String: (bounds ?? screen).dictionaryRepresentation]
        }
        let displays: [CGDirectDisplayID: CGRect] = [2: screen, 1: CGRect(x: 0, y: 0, width: 1440, height: 900)]
        suite.expect(Service.desktopFullscreenDisplays([window()], ownerPID: 42, displays: displays) == [2],
                     "foreground desktop video hides only the display its window fills")
        suite.expect(Service.desktopFullscreenDisplays([window(pid: 99), window(layer: 10), window(alpha: 0),
                                                       window(bounds: screen.insetBy(dx: 0, dy: 24)), [:]],
                                                      ownerPID: 42, displays: displays).isEmpty,
                     "other apps, floating overlays, transparent, maximized and malformed windows are ignored")
        UserDefaults.standard.enabled = true
        SpaceWindowBridge.value = nil
        NotchFullscreenSupport.desktopDisplays = [2]
        defer { NotchFullscreenSupport.desktopDisplays = [] }
        let service = Service()
        service.updateFullscreenVisibility(displayID: 2)
        suite.expect(service.hiddenInFullscreen && !service.acceptsUserInteraction && !service.acceptsSystemFeedback,
                     "desktop fullscreen hides even without Space APIs and blocks reveals and feedback")
        service.screenUpdate = { [weak service] in service?.updateFullscreenVisibility(displayID: 2) }
        service.syncFullscreenMonitoring()
        let timer = service.fullscreenTimer!
        suite.expect(timer.timeInterval == 0.5, "fullscreen polling remains active while the island is hidden")
        NotchFullscreenSupport.desktopDisplays = []
        timer.fire()
        suite.expect(!service.hiddenInFullscreen && service.refreshes == 1 && service.acceptsUserInteraction,
                     "timer restores the island when desktop fullscreen ends without a Space or app change")
        service.syncFullscreenMonitoring()
        suite.expect(service.fullscreenTimer === timer, "preference sync reuses the existing timer")
        service.suspended = true
        service.syncFullscreenMonitoring()
        suite.expect(service.fullscreenTimer == nil && !timer.isValid, "suspending the session stops fullscreen polling")
        service.suspended = false
        service.syncFullscreenMonitoring()
        let resumed = service.fullscreenTimer!
        UserDefaults.standard.enabled = false
        service.syncFullscreenMonitoring()
        suite.expect(service.fullscreenTimer == nil && !resumed.isValid, "disabling fullscreen hiding stops polling")
    }

    private static func volumeLifecycleChecks(_ topology: Topology, _ suite: TestSuite) {
        // Run the production volume eligibility and fullscreen callbacks with
        // an inert tap. No hardware keys, permissions or desktop Spaces change.
        UserDefaults.standard.enabled = true
        SpaceWindowBridge.value = topology
        for preciseVolume in [false, true] {
            UserDefaults.standard.preciseVolume = preciseVolume
            let service = Service()
            NotchService.shared = service
            let volume = PreciseVolumeRollerService.shared
            var displayID: CGDirectDisplayID = 2
            service.screenUpdate = { [weak service] in service?.updateFullscreenVisibility(displayID: displayID) }
            service.updateScreen()
            volume.syncWithPreferences()
            suite.expect(service.hiddenInFullscreen && volume.running == preciseVolume,
                         "fullscreen startup keeps the tap only when the precise volume roller needs it")
            displayID = 1
            service.fullscreenEnvironmentDidChange()
            suite.expect(!service.hiddenInFullscreen && service.acceptsSystemFeedback && volume.running,
                         "returning to the desktop restores the volume tap without a preference change")
            displayID = 2
            service.fullscreenEnvironmentDidChange()
            suite.expect(service.hiddenInFullscreen && volume.running == preciseVolume,
                         "entering fullscreen releases the notch tap but preserves the precise volume roller")
        }
    }
}

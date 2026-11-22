import AppKit
import OSLog

/// Opens the island when the notch is tapped with a fingertip. A tap is a
/// dip in the ambient light sensor beside the camera, which the finger
/// shades, together with a jolt in the accelerometer and gyroscope, while the
/// lid is still. Motion alone never opens it, so bumps on the desk do not.
/// Everything is read on this Mac and nothing is kept.
final class NotchTapDetector {
    static let shared = NotchTapDetector()

    private let log = Logger(subsystem: "com.nyx.utils", category: "tap")
    private var generation: UInt64 = 0
    private var enabled = false
    private var lastOpened = -Double.infinity
    private var paused = false
    private var wakeWork: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []

    private func observeSleep() {
        guard observers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        let center = DistributedNotificationCenter.default()
        func watch(_ center: NotificationCenter, _ name: Notification.Name, _ value: Bool) {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.setPaused(value)
            })
        }
        watch(workspace, NSWorkspace.willSleepNotification, true)
        watch(workspace, NSWorkspace.didWakeNotification, false)
        watch(workspace, NSWorkspace.screensDidSleepNotification, true)
        watch(workspace, NSWorkspace.screensDidWakeNotification, false)
        watch(center, Notification.Name("com.apple.screenIsLocked"), true)
        watch(center, Notification.Name("com.apple.screenIsUnlocked"), false)
    }
    private lazy var sensor = NotchTapSensor(
        onTap: { [weak self] time, generation in
            DispatchQueue.main.async { self?.tapped(at: time, generation: generation) }
        },
        onStatus: { [weak self] status, _ in
            self?.log.info("tap sensor: \(String(describing: status), privacy: .public)")
        })

    /// The sensor is stopped while the Mac sleeps or is locked and started
    /// from scratch when it wakes: its streams do not survive a closed lid.
    private func setPaused(_ value: Bool) {
        if value {
            paused = true
            wakeWork?.cancel()
            generation &+= 1
            sensor.configure(enabled: false, sensitivity: NotchTapSupport.sensitivity, generation: generation)
            return
        }
        wakeWork?.cancel()
        // Stop whatever is still running, give its thread time to end, then
        // start a fresh one once the lid has settled.
        generation &+= 1
        sensor.configure(enabled: false, sensitivity: NotchTapSupport.sensitivity, generation: generation)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.paused = false
            guard self.enabled else { return }
            self.generation &+= 1
            self.sensor.configure(enabled: true, sensitivity: NotchTapSupport.sensitivity, generation: self.generation)
        }
        wakeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    func update(enabled: Bool) {
        guard enabled != self.enabled else { return }
        self.enabled = enabled
        if enabled { observeSleep() }
        generation &+= 1
        sensor.configure(enabled: enabled, sensitivity: NotchTapSupport.sensitivity, generation: generation)
    }

    private func tapped(at time: Double, generation: UInt64) {
        let now = NotchTapClock.now
        // As in Sentient OS: a tap older than 0.4 s is stale, and a Mac that is
        // asleep or locked is not being tapped.         log.info("tap candidate: age \(now - time, format: .fixed(precision: 2)) paused \(self.paused, privacy: .public) expanded \(NotchService.shared.expanded, privacy: .public)")
        guard enabled, generation == self.generation, now - lastOpened > 1,
              now - time < 0.4, !paused,
              sensor.acceptsDelivery(at: time, generation: generation) else { return }
        let island = NotchService.shared
        guard !island.expanded else { return }
        lastOpened = now
        log.info("tap found, opening the island")
        island.open()
    }
}

import AppKit
import Observation
import Sparkle

/// What the settings model needs from an updater, so it can be tested with a fake.
@MainActor
protocol UpdateChecking: AnyObject {
    /// False while a check is already running or the updater has not started.
    var canCheckForUpdates: Bool { get }
    /// Sparkle persists this itself (`SUEnableAutomaticChecks` in the app's defaults).
    var automaticallyChecksForUpdates: Bool { get set }
    /// The version a background check found and we chose not to interrupt the user with.
    var pendingUpdateVersion: String? { get }
    /// User-initiated: shows Sparkle's own windows, including for an already-found update.
    func checkForUpdates()
}

/// Sparkle behind `UpdateChecking`. Squatter has no windows and no Dock icon, so a scheduled
/// check that finds an update must not open an alert nobody will see (Sparkle 2.2+ refuses
/// to steal focus for scheduled updates, which for a dockless app means "behind everything").
/// Instead the found version is recorded and the UI shows it; the user's click on
/// "Install Update" is a normal `checkForUpdates()`, which Sparkle presents in focus.
@MainActor
@Observable
final class SparkleUpdater: NSObject, UpdateChecking {
    private(set) var canCheckForUpdates = false
    private(set) var pendingUpdateVersion: String?

    @ObservationIgnored private var controller: SPUStandardUpdaterController!
    @ObservationIgnored private var observation: NSKeyValueObservation?

    /// - Parameter startingUpdater: pass `false` under tests — a started updater schedules
    ///   checks and can show the permission prompt, against the test host's shared defaults.
    init(startingUpdater: Bool) {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: startingUpdater,
            updaterDelegate: nil,
            userDriverDelegate: self
        )
        // KVO rather than Combine: the model is @Observable and needs a plain property to publish.
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
        }
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() { controller.updater.checkForUpdates() }

    // MARK: Decisions, kept free of Sparkle types so they can be tested

    /// Sparkle may show a scheduled update itself only when it can do so in focus — in
    /// practice, right at launch. Otherwise we hold it and surface it in the UI.
    static func shouldPresentScheduledUpdate(inImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    /// Called for every update Sparkle is about to show or that we declined to show.
    func noteUpdate(version: String, presentedBySparkle: Bool) {
        pendingUpdateVersion = presentedBySparkle ? nil : version
    }

    func noteUpdateSessionFinished() {
        pendingUpdateVersion = nil
    }

    /// The user has now seen the update — Sparkle's alert came to the front, or they chose
    /// to install, skip or dismiss it. The dot has done its job. Sparkle's header names this
    /// callback as the place to dismiss custom indicators, and it is the one that fires when
    /// a held update is brought into focus by "Install Update".
    func noteUserAttention() {
        pendingUpdateVersion = nil
    }
}

// `@preconcurrency`: Sparkle declares this protocol without an actor, and the class is
// main-actor bound. Sparkle calls its user-driver delegate on the main thread.
extension SparkleUpdater: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        Self.shouldPresentScheduledUpdate(inImmediateFocus: immediateFocus)
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        noteUpdate(version: update.displayVersionString, presentedBySparkle: handleShowingUpdate)
    }

    func standardUserDriverWillFinishUpdateSession() {
        noteUpdateSessionFinished()
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        noteUserAttention()
    }
}

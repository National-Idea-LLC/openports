import Foundation
import Testing
@testable import Squatter

@MainActor
struct SettingsModelTests {
    private func make(_ item: FakeLoginItem = FakeLoginItem()) -> (SettingsModel, FakeLoginItem) {
        (SettingsModel(loginItem: item, updater: FakeUpdater(), preferences: Preferences(defaults: freshDefaults())), item)
    }

    @Test func togglingRegistersAndUnregisters() {
        let (model, item) = make()
        #expect(!model.launchAtLogin)
        model.launchAtLogin = true
        #expect(item.registerCalls == 1)
        #expect(model.launchAtLogin)
        #expect(model.loginItemError == nil)
        model.launchAtLogin = false
        #expect(item.unregisterCalls == 1)
        #expect(!model.launchAtLogin)
    }

    @Test func requiresApprovalReadsAsOnAndOffersSystemSettings() {
        let item = FakeLoginItem()
        item.statusAfterRegister = .requiresApproval
        let (model, _) = make(item)
        model.launchAtLogin = true
        #expect(model.launchAtLogin)
        #expect(model.needsLoginItemApproval)
        model.openLoginItemsSettings()
        #expect(item.openedSettings == 1)
    }

    @Test func failureSurfacesWhatWhyNextAndKeepsRealStatus() {
        let item = FakeLoginItem()
        item.shouldFail = true
        let (model, _) = make(item)
        model.launchAtLogin = true
        #expect(!model.launchAtLogin)
        let message = model.loginItemError ?? ""
        #expect(message.contains("Couldn't turn on Launch at Login"))
        #expect(message.contains("launchd said no."))
        #expect(message.contains("System Settings"))
        item.shouldFail = false
        model.launchAtLogin = true
        #expect(model.loginItemError == nil)
    }

    @Test func refreshIntervalPersists() {
        let defaults = freshDefaults()
        let model = SettingsModel(loginItem: FakeLoginItem(), updater: FakeUpdater(), preferences: Preferences(defaults: defaults))
        #expect(model.refreshInterval == 2)
        model.refreshInterval = 5
        #expect(Preferences(defaults: defaults).refreshInterval == 5)
        #expect(SettingsModel.refreshIntervalChoices == [1, 2, 5])
    }

    @Test func sourceAndTheCompanyCreditOpenInTheBrowser() {
        let actions = RecordingActions()
        let model = SettingsModel(loginItem: FakeLoginItem(), updater: FakeUpdater(), preferences: Preferences(defaults: freshDefaults()), actions: actions, appVersion: "9.9.9 (42)")
        model.openSource()
        model.openCompany()
        #expect(actions.opened.map(\.absoluteString) == [
            "https://github.com/National-Idea-LLC/squatter",
            "https://ni.sa",
        ])
        #expect(model.appVersion == "9.9.9 (42)")
        #expect(!SettingsModel.bundleVersion.isEmpty)
    }

    /// The About credit reads `NSHumanReadableCopyright` instead of hardcoding a string, so the
    /// year Finder shows in Get Info and the year the app shows can never disagree. If this fails
    /// after an Info.plist edit, the credit in Settings has gone blank — nothing else would say so.
    @Test func theCompanyCreditComesFromTheBundle() {
        // Matched by shape, not by literal: bumping the year in project.yml is a one-line edit
        // and must not also mean editing a test that would then assert nothing new.
        let credit = SettingsModel.bundleCopyright
        #expect(credit.wholeMatch(of: /© \d{4} National Idea LLC/) != nil, "got \(credit)")
        let model = SettingsModel(loginItem: FakeLoginItem(), updater: FakeUpdater(), preferences: Preferences(defaults: freshDefaults()))
        #expect(model.copyright == credit)
    }

    @Test func reportBugOpensAPrefilledIssueForm() throws {
        let actions = RecordingActions()
        let model = SettingsModel(
            loginItem: FakeLoginItem(),
            updater: FakeUpdater(),
            preferences: Preferences(defaults: freshDefaults()),
            actions: actions,
            appVersion: "9.9.9 (42)",
            systemVersion: "Version 15.6 (Build 24G84)"
        )
        model.reportBug()
        let url = try #require(actions.opened.last)
        #expect(url.absoluteString.hasPrefix("https://github.com/National-Idea-LLC/squatter/issues/new?body="))
        let body = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "body" }?.value)
        #expect(body.contains("Squatter 9.9.9 (42)"))
        #expect(body.contains("macOS Version 15.6 (Build 24G84)"))
        #expect(body.contains("What happened:"))
        #expect(actions.opened.count == 1)
    }

    @Test func theBugReportBodyCarriesOnlyVersions() throws {
        let actions = RecordingActions()
        let model = SettingsModel(
            loginItem: FakeLoginItem(),
            updater: FakeUpdater(),
            preferences: Preferences(defaults: freshDefaults()),
            actions: actions,
            appVersion: "9.9.9 (42)",
            systemVersion: "Version 15.6 (Build 24G84)"
        )
        model.reportBug()
        let url = try #require(actions.opened.last)
        let body = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "body" }?.value)
        #expect(!body.contains(NSUserName()))
        #expect(!body.contains(NSHomeDirectory()))
        #expect(!body.lowercased().contains("port"))
    }

    @Test func statusIsReReadOnDemand() {
        let item = FakeLoginItem(status: .disabled)
        let (model, _) = make(item)
        item.status = .enabled // changed behind our back, e.g. in System Settings
        #expect(!model.launchAtLogin)
        model.refreshLoginItemStatus()
        #expect(model.launchAtLogin)
    }

    @Test func checkingForUpdatesAsksTheUpdaterNotTheBrowser() {
        let actions = RecordingActions()
        let updater = FakeUpdater()
        let model = SettingsModel(loginItem: FakeLoginItem(), updater: updater, preferences: Preferences(defaults: freshDefaults()), actions: actions)
        model.checkForUpdates()
        #expect(updater.checkCalls == 1)
        #expect(actions.opened.isEmpty)
    }

    @Test func automaticChecksRoundTripThroughTheUpdater() {
        let updater = FakeUpdater()
        let model = SettingsModel(loginItem: FakeLoginItem(), updater: updater, preferences: Preferences(defaults: freshDefaults()))
        #expect(!model.automaticUpdateChecks)
        model.automaticUpdateChecks = true
        #expect(updater.automaticallyChecksForUpdates)
        #expect(model.automaticUpdateChecks)
    }

    @Test func aVersionFoundInTheBackgroundIsSurfaced() {
        let updater = FakeUpdater(pendingUpdateVersion: "9.9.9")
        let model = SettingsModel(loginItem: FakeLoginItem(), updater: updater, preferences: Preferences(defaults: freshDefaults()))
        #expect(model.pendingUpdateVersion == "9.9.9")
        #expect(model.canCheckForUpdates)
    }

    /// The decisions the Sparkle delegate makes, tested without Sparkle objects.
    @Test func scheduledUpdatesAreOnlyShownInImmediateFocus() {
        #expect(SparkleUpdater.shouldPresentScheduledUpdate(inImmediateFocus: true))
        #expect(!SparkleUpdater.shouldPresentScheduledUpdate(inImmediateFocus: false))
    }

    @Test func aHeldUpdateIsRememberedUntilTheSessionEnds() {
        let updater = SparkleUpdater(startingUpdater: false)
        updater.noteUpdate(version: "9.9.9", presentedBySparkle: false)
        #expect(updater.pendingUpdateVersion == "9.9.9")
        updater.noteUpdate(version: "9.9.9", presentedBySparkle: true)
        #expect(updater.pendingUpdateVersion == nil)
        updater.noteUpdate(version: "9.9.9", presentedBySparkle: false)
        updater.noteUserAttention()
        #expect(updater.pendingUpdateVersion == nil)
        updater.noteUpdate(version: "9.9.9", presentedBySparkle: false)
        updater.noteUpdateSessionFinished()
        #expect(updater.pendingUpdateVersion == nil)
    }
}

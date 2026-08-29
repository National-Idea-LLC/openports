import Foundation
import Testing
@testable import Squatter

@MainActor
struct SettingsModelTests {
    private func make(_ item: FakeLoginItem = FakeLoginItem()) -> (SettingsModel, FakeLoginItem) {
        (SettingsModel(loginItem: item, preferences: Preferences(defaults: freshDefaults())), item)
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
        let model = SettingsModel(loginItem: FakeLoginItem(), preferences: Preferences(defaults: defaults))
        #expect(model.refreshInterval == 2)
        model.refreshInterval = 5
        #expect(Preferences(defaults: defaults).refreshInterval == 5)
        #expect(SettingsModel.refreshIntervalChoices == [1, 2, 5])
    }

    @Test func updatesAndSourceOpenGitHubInTheBrowser() {
        let actions = RecordingActions()
        let model = SettingsModel(loginItem: FakeLoginItem(), preferences: Preferences(defaults: freshDefaults()), actions: actions, appVersion: "9.9.9 (42)")
        model.checkForUpdates()
        model.openSource()
        #expect(actions.opened.map(\.absoluteString) == [
            "https://github.com/National-Idea-LLC/squatter/releases",
            "https://github.com/National-Idea-LLC/squatter",
        ])
        #expect(model.appVersion == "9.9.9 (42)")
        #expect(!SettingsModel.bundleVersion.isEmpty)
    }

    @Test func reportBugOpensAPrefilledIssueForm() throws {
        let actions = RecordingActions()
        let model = SettingsModel(
            loginItem: FakeLoginItem(),
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
}

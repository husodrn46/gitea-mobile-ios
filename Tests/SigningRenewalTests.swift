import XCTest
@testable import KisiselGitea

@MainActor final class SigningRenewalTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private let now = ISO8601DateFormatter().date(from:"2026-09-22T08:00:00Z")!
    private let expiration = ISO8601DateFormatter().date(from:"2026-09-29T19:00:00Z")!

    override func setUp() {
        super.setUp()
        suite = "test.signing." + UUID().uuidString
        defaults = UserDefaults(suiteName:suite)!
    }
    override func tearDown() {
        defaults.removePersistentDomain(forName:suite)
        super.tearDown()
    }
    private func manager(_ notifications: TestSigningNotifications,expiration: Date? = nil) -> SigningRenewal {
        let expectedExpiration = expiration ?? self.expiration
        let current = now
        return SigningRenewal(defaults:defaults,notifications:notifications,
                              readExpiration:{ expectedExpiration },clock:{ current })
    }

    func testRefreshDefaultsToOffAndNeverAsksForPermission() async {
        let notifications = TestSigningNotifications()
        let renewal = manager(notifications)
        XCTAssertFalse(renewal.enabled)
        XCTAssertFalse(renewal.isFixture)
        XCTAssertFalse(defaults.bool(forKey:SigningRenewal.enabledKey))

        await renewal.refresh()
        await renewal.refresh()

        XCTAssertFalse(renewal.enabled)
        XCTAssertTrue(renewal.scheduled.isEmpty)
        XCTAssertNil(renewal.error)
        XCTAssertEqual(notifications.authorizationCalls,2)
        XCTAssertEqual(notifications.requestCalls,0)
        XCTAssertEqual(notifications.replaceCalls.count,0)
        XCTAssertEqual(notifications.clearCalls,2)
        XCTAssertFalse(renewal.busy)
    }

    func testPreviouslyDeniedPermissionDoesNotEnableOrRequestAgain() async {
        let notifications = TestSigningNotifications()
        notifications.status = .denied
        let renewal = manager(notifications)

        await renewal.setEnabled(true)

        XCTAssertFalse(renewal.enabled)
        XCTAssertFalse(defaults.bool(forKey:SigningRenewal.enabledKey))
        XCTAssertNotNil(renewal.error)
        XCTAssertTrue(renewal.scheduled.isEmpty)
        XCTAssertEqual(notifications.requestCalls,0)
        XCTAssertTrue(notifications.replaceCalls.isEmpty)
        XCTAssertFalse(renewal.busy)
    }

    func testDecliningSystemPromptKeepsPreferenceOff() async {
        let notifications = TestSigningNotifications()
        notifications.answer = .denied
        let renewal = manager(notifications)

        await renewal.setEnabled(true)

        XCTAssertEqual(notifications.requestCalls,1)
        XCTAssertEqual(renewal.authorization,.denied)
        XCTAssertFalse(renewal.enabled)
        XCTAssertFalse(defaults.bool(forKey:SigningRenewal.enabledKey))
        XCTAssertTrue(notifications.replaceCalls.isEmpty)
        XCTAssertNotNil(renewal.error)
    }

    func testGrantedPermissionSchedulesAndPersistsOnlyAfterSuccess() async {
        let notifications = TestSigningNotifications()
        notifications.onReplace = { [defaults] in
            XCTAssertFalse(defaults!.bool(forKey:SigningRenewal.enabledKey))
        }
        let renewal = manager(notifications)

        await renewal.setEnabled(true)

        let expected = SigningReminderPlan.reminders(expiration:expiration,now:now)
        XCTAssertEqual(expected.count,2)
        XCTAssertEqual(notifications.requestCalls,1)
        XCTAssertEqual(notifications.replaceCalls.count,1)
        XCTAssertEqual(notifications.replaceCalls.first?.reminders,expected)
        XCTAssertEqual(notifications.replaceCalls.first?.expiration,expiration)
        XCTAssertEqual(renewal.scheduled,expected)
        XCTAssertTrue(renewal.enabled)
        XCTAssertTrue(defaults.bool(forKey:SigningRenewal.enabledKey))
        XCTAssertNil(renewal.error)
        XCTAssertFalse(renewal.busy)

        let reopenedNotifications = TestSigningNotifications()
        reopenedNotifications.status = .allowed
        let reopened = manager(reopenedNotifications)
        XCTAssertTrue(reopened.enabled)
        await reopened.refresh()
        XCTAssertEqual(reopened.scheduled,expected)
        XCTAssertEqual(reopenedNotifications.requestCalls,0)
    }

    func testQuietAuthorizationCanScheduleWithoutRequestingAgain() async {
        let notifications = TestSigningNotifications()
        notifications.status = .quiet
        let renewal = manager(notifications)
        await renewal.setEnabled(true)
        XCTAssertTrue(renewal.enabled)
        XCTAssertEqual(renewal.authorization,.quiet)
        XCTAssertEqual(renewal.scheduled.count,2)
        XCTAssertEqual(notifications.requestCalls,0)
    }

    func testDisableOnlyClearsRemindersAndPersistsOff() async {
        defaults.set(true,forKey:SigningRenewal.enabledKey)
        let notifications = TestSigningNotifications()
        notifications.status = .allowed
        let renewal = manager(notifications)
        await renewal.refresh()
        let authorizationCalls = notifications.authorizationCalls
        let replaceCalls = notifications.replaceCalls.count

        await renewal.setEnabled(false)

        XCTAssertFalse(renewal.enabled)
        XCTAssertFalse(defaults.bool(forKey:SigningRenewal.enabledKey))
        XCTAssertTrue(renewal.scheduled.isEmpty)
        XCTAssertTrue(notifications.pending.isEmpty)
        XCTAssertEqual(notifications.clearCalls,1)
        XCTAssertEqual(notifications.authorizationCalls,authorizationCalls)
        XCTAssertEqual(notifications.replaceCalls.count,replaceCalls)
        XCTAssertEqual(notifications.requestCalls,0)
        XCTAssertNil(renewal.error)
    }

    func testSavedPreferenceRefreshesWhenSigningProfileChanges() async {
        defaults.set(true,forKey:SigningRenewal.enabledKey)
        let notifications = TestSigningNotifications()
        notifications.status = .allowed
        var profile = expiration
        let current = now
        let renewal = SigningRenewal(defaults:defaults,notifications:notifications,
                                     readExpiration:{ profile },clock:{ current })
        await renewal.refresh()
        let previous = renewal.scheduled
        profile = expiration.addingTimeInterval(7 * 86400)

        await renewal.refresh()

        XCTAssertEqual(renewal.expiration,profile)
        XCTAssertNotEqual(renewal.scheduled,previous)
        XCTAssertEqual(renewal.scheduled,SigningReminderPlan.reminders(expiration:profile,now:now))
        XCTAssertEqual(notifications.replaceCalls.count,2)
        XCTAssertEqual(notifications.replaceCalls.last?.expiration,profile)
        XCTAssertEqual(notifications.requestCalls,0)
        XCTAssertTrue(defaults.bool(forKey:SigningRenewal.enabledKey))
    }

    func testMissingOrExpiredProfileClearsPreviouslyScheduledReminders() async {
        defaults.set(true,forKey:SigningRenewal.enabledKey)
        let notifications = TestSigningNotifications()
        notifications.status = .allowed
        var profile: Date? = expiration
        let current = now
        let renewal = SigningRenewal(defaults:defaults,notifications:notifications,
                                     readExpiration:{ profile },clock:{ current })
        await renewal.refresh()
        XCTAssertFalse(renewal.scheduled.isEmpty)

        profile = nil
        await renewal.refresh()
        XCTAssertNil(renewal.expiration)
        XCTAssertFalse(renewal.canEnable)
        XCTAssertTrue(renewal.scheduled.isEmpty)
        XCTAssertTrue(notifications.pending.isEmpty)
        XCTAssertEqual(notifications.clearCalls,1)

        profile = expiration
        await renewal.refresh()
        XCTAssertFalse(renewal.scheduled.isEmpty)
        profile = now.addingTimeInterval(-1)
        await renewal.refresh()
        XCTAssertFalse(renewal.canEnable)
        XCTAssertTrue(renewal.scheduled.isEmpty)
        XCTAssertTrue(notifications.pending.isEmpty)
        XCTAssertEqual(notifications.clearCalls,2)
        XCTAssertEqual(notifications.replaceCalls.count,2)
        XCTAssertEqual(notifications.requestCalls,0)
    }

    func testRevokedPermissionClearsSchedulesDuringRefreshWithoutPrompt() async {
        defaults.set(true,forKey:SigningRenewal.enabledKey)
        let notifications = TestSigningNotifications()
        notifications.status = .allowed
        let renewal = manager(notifications)
        await renewal.refresh()
        notifications.status = .denied

        await renewal.refresh()

        XCTAssertEqual(renewal.authorization,.denied)
        XCTAssertTrue(renewal.scheduled.isEmpty)
        XCTAssertTrue(notifications.pending.isEmpty)
        XCTAssertEqual(notifications.clearCalls,1)
        XCTAssertEqual(notifications.requestCalls,0)
        XCTAssertEqual(notifications.replaceCalls.count,1)
    }

    func testReplaceFailureRollsBackPreferenceAndClearsPartialSchedule() async {
        let notifications = TestSigningNotifications()
        notifications.status = .allowed
        notifications.failReplacement = true
        let renewal = manager(notifications)

        await renewal.setEnabled(true)

        XCTAssertEqual(notifications.replaceCalls.count,1)
        XCTAssertEqual(notifications.clearCalls,1)
        XCTAssertTrue(notifications.pending.isEmpty)
        XCTAssertTrue(renewal.scheduled.isEmpty)
        XCTAssertFalse(renewal.enabled)
        XCTAssertFalse(defaults.bool(forKey:SigningRenewal.enabledKey))
        XCTAssertNotNil(renewal.error)
        XCTAssertFalse(renewal.busy)

        notifications.failReplacement = false
        await renewal.setEnabled(true)
        XCTAssertTrue(renewal.enabled)
        XCTAssertTrue(defaults.bool(forKey:SigningRenewal.enabledKey))
        XCTAssertEqual(renewal.scheduled.count,2)
        XCTAssertNil(renewal.error)
    }

    func testAuthorizationFailureDoesNotPersistOrScheduleAndReleasesBusy() async {
        let notifications = TestSigningNotifications()
        notifications.failAuthorization = true
        let renewal = manager(notifications)
        await renewal.setEnabled(true)
        XCTAssertFalse(renewal.enabled)
        XCTAssertFalse(defaults.bool(forKey:SigningRenewal.enabledKey))
        XCTAssertEqual(notifications.requestCalls,1)
        XCTAssertTrue(notifications.replaceCalls.isEmpty)
        XCTAssertNotNil(renewal.error)
        XCTAssertFalse(renewal.busy)
    }

    func testBusyPreventsDuplicatePermissionRequestsAndScheduleReplacement() async {
        let notifications = TestSigningNotifications()
        notifications.pauseAuthorization = true
        let started = expectation(description:"System permission request started")
        notifications.onRequest = { started.fulfill() }
        let renewal = manager(notifications)
        let first = Task { await renewal.setEnabled(true) }
        await fulfillment(of:[started],timeout:2)
        XCTAssertTrue(renewal.busy)

        await renewal.setEnabled(true)
        await renewal.refresh()

        XCTAssertEqual(notifications.requestCalls,1)
        XCTAssertEqual(notifications.authorizationCalls,1)
        XCTAssertTrue(notifications.replaceCalls.isEmpty)
        XCTAssertFalse(defaults.bool(forKey:SigningRenewal.enabledKey))
        notifications.finishAuthorization()
        await first.value
        XCTAssertFalse(renewal.busy)
        XCTAssertTrue(renewal.enabled)
        XCTAssertEqual(notifications.replaceCalls.count,1)
        XCTAssertEqual(renewal.scheduled.count,2)
    }
}

@MainActor private final class TestSigningNotifications: SigningNotifying {
    struct Replacement {
        let reminders: [SigningReminder]
        let expiration: Date
    }
    private enum Failure: Error { case synthetic }
    var status: ReminderAuthorization = .notDetermined
    var answer: ReminderAuthorization = .allowed
    var failAuthorization = false
    var failReplacement = false
    var pauseAuthorization = false
    var onRequest: (() -> Void)?
    var onReplace: (() -> Void)?
    private var authorizationContinuation: CheckedContinuation<Void,Never>?
    private(set) var authorizationCalls = 0
    private(set) var requestCalls = 0
    private(set) var replaceCalls: [Replacement] = []
    private(set) var clearCalls = 0
    private(set) var pending: [SigningReminder] = []

    func authorization() async -> ReminderAuthorization {
        authorizationCalls += 1
        return status
    }
    func requestAuthorization() async throws -> Bool {
        requestCalls += 1
        if pauseAuthorization {
            await withCheckedContinuation { continuation in
                authorizationContinuation = continuation
                onRequest?()
            }
        } else { onRequest?() }
        if failAuthorization { throw Failure.synthetic }
        status = answer
        return status == .allowed || status == .quiet
    }
    func finishAuthorization() {
        let continuation = authorizationContinuation
        authorizationContinuation = nil
        continuation?.resume()
    }
    func replace(_ reminders: [SigningReminder],expiration: Date) async throws -> [SigningReminder] {
        replaceCalls.append(Replacement(reminders:reminders,expiration:expiration))
        onReplace?()
        if failReplacement {
            pending = Array(reminders.prefix(1))
            throw Failure.synthetic
        }
        pending = reminders
        return pending
    }
    func clear() {
        clearCalls += 1
        pending = []
    }
}

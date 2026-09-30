import XCTest
import LocalAuthentication
@testable import KisiselGitea

@MainActor final class PrivacyTests: XCTestCase {
    var suite: String!
    var defaults: UserDefaults!
    override func setUp() {
        super.setUp(); suite = "test.privacy." + UUID().uuidString; defaults = UserDefaults(suiteName:suite)!
    }
    override func tearDown() { defaults.removePersistentDomain(forName:suite); super.tearDown() }
    func save(_ value: PrivacyPreferences) throws { defaults.set(try JSONEncoder().encode(value),forKey:AppAccess.preferencesKey) }

    func testEnableAndDisableRequireSuccessfulDeviceAuthentication() async {
        let device = TestDeviceAuthenticator(); let access = AppAccess(defaults:defaults,authenticator:device)
        device.answer = .deny
        await access.setEnabled(true)
        XCTAssertFalse(access.preferences.enabled); XCTAssertNotNil(access.error)
        device.answer = .accept
        await access.setEnabled(true)
        XCTAssertTrue(access.preferences.enabled); XCTAssertFalse(access.locked)
        let next = AppAccess(defaults:defaults,authenticator:device)
        XCTAssertTrue(next.locked); XCTAssertFalse(next.contentHasOpened)
        device.answer = .cancel
        await access.setEnabled(false)
        XCTAssertTrue(access.preferences.enabled)
        device.answer = .accept
        await access.setEnabled(false)
        XCTAssertFalse(access.preferences.enabled)
        XCTAssertFalse(AppAccess(defaults:defaults,authenticator:device).locked)
        XCTAssertEqual(device.calls,4)
    }
    func testFailedAutomaticUnlockDoesNotRetryAndNeverExposesContent() async throws {
        try save(PrivacyPreferences(enabled:true))
        let device = TestDeviceAuthenticator(); device.answer = .deny
        let access = AppAccess(defaults:defaults,authenticator:device)
        await access.tryAutomaticUnlock(); await access.tryAutomaticUnlock()
        XCTAssertEqual(device.calls,1); XCTAssertTrue(access.locked); XCTAssertFalse(access.contentHasOpened); XCTAssertTrue(access.shouldCover)
        device.answer = .accept; await access.unlock()
        XCTAssertFalse(access.locked); XCTAssertTrue(access.contentHasOpened)
        access.lockNow(); await access.tryAutomaticUnlock()
        XCTAssertEqual(device.calls,2); XCTAssertTrue(access.locked)
    }
    func testBackgroundExpiryUsesMonotonicTimeAndRestartAlwaysLocks() async throws {
        try save(PrivacyPreferences(enabled:true,delay:.seconds30))
        var time: TimeInterval = 100
        let device = TestDeviceAuthenticator(); let access = AppAccess(defaults:defaults,authenticator:device,clock:{ time })
        await access.unlock(); access.changeActivity(.inactive); access.changeActivity(.background)
        XCTAssertFalse(access.locked); XCTAssertTrue(access.shouldCover)
        time = 129; access.changeActivity(.active)
        XCTAssertFalse(access.locked); XCTAssertFalse(access.shouldCover)
        access.changeActivity(.inactive); access.changeActivity(.background)
        time = 159; access.changeActivity(.active)
        XCTAssertTrue(access.locked); XCTAssertTrue(access.contentHasOpened)
        await access.unlock()
        XCTAssertTrue(AppAccess(defaults:defaults,authenticator:device).locked)
    }
    func testLateAuthenticationCannotUnlockAfterBackgroundOrManualLock() async throws {
        try save(PrivacyPreferences(enabled:true))
        let device = TestDeviceAuthenticator(); device.answer = .pending
        let access = AppAccess(defaults:defaults,authenticator:device)
        let first = Task { await access.unlock() }
        while !device.waiting { await Task.yield() }
        access.changeActivity(.inactive); access.changeActivity(.background); access.changeActivity(.active)
        device.finish(true); await first.value
        XCTAssertTrue(access.locked); XCTAssertFalse(access.contentHasOpened); XCTAssertFalse(access.authenticating)
        let second = Task { await access.unlock() }
        while !device.waiting { await Task.yield() }
        access.lockNow(); device.finish(true); await second.value
        XCTAssertTrue(access.locked); XCTAssertEqual(device.cancels,2)
    }
    func testAuthenticationDialogInactiveTransitionDoesNotRelockOrRetry() async throws {
        try save(PrivacyPreferences(enabled:true))
        let device = TestDeviceAuthenticator(); device.answer = .pending
        let access = AppAccess(defaults:defaults,authenticator:device)
        let generation = access.activationID
        let task = Task { await access.tryAutomaticUnlock() }
        while !device.waiting { await Task.yield() }
        access.changeActivity(.inactive)
        device.finish(true); await task.value
        XCTAssertFalse(access.locked); XCTAssertTrue(access.shouldCover)
        access.changeActivity(.active); await access.tryAutomaticUnlock()
        XCTAssertFalse(access.shouldCover); XCTAssertEqual(device.calls,1); XCTAssertEqual(access.activationID,generation)
    }
    func testDisableAndDelayChangeCannotCompleteFromBackground() async throws {
        try save(PrivacyPreferences(enabled:true))
        let device = TestDeviceAuthenticator(); let access = AppAccess(defaults:defaults,authenticator:device)
        await access.unlock(); device.answer = .pending
        let task = Task { await access.setEnabled(false) }
        while !device.waiting { await Task.yield() }
        access.changeActivity(.background); device.finish(true); await task.value
        XCTAssertTrue(access.preferences.enabled); XCTAssertTrue(access.locked)
        access.changeActivity(.active); device.answer = .accept; await access.unlock()
        device.answer = .deny; await access.setDelay(.minutes5)
        XCTAssertEqual(access.preferences.delay,.immediately)
        device.answer = .accept; await access.setDelay(.minutes5)
        XCTAssertEqual(AppAccess(defaults:defaults,authenticator:device).preferences.delay,.minutes5)
    }
    func testPrivacyMaskIsDefaultAndMandatoryWithLock() async throws {
        let device = TestDeviceAuthenticator(); let access = AppAccess(defaults:defaults,authenticator:device)
        access.changeActivity(.inactive); XCTAssertTrue(access.shouldCover)
        access.changeActivity(.active); access.setHidePreview(false)
        access.changeActivity(.inactive); XCTAssertFalse(access.shouldCover)
        access.changeActivity(.active); await access.setEnabled(true)
        access.setHidePreview(false); access.changeActivity(.inactive)
        XCTAssertTrue(access.shouldCover); XCTAssertTrue(access.locked)
    }
    func testCorruptRecordsFailClosedAndRecoveryKeepsOriginal() async {
        for original: Any in [Data("broken".utf8),"wrong value type",false] {
            defaults.set(original,forKey:AppAccess.preferencesKey)
            let device = TestDeviceAuthenticator(); let access = AppAccess(defaults:defaults,authenticator:device)
            XCTAssertTrue(access.locked); XCTAssertFalse(access.contentHasOpened); XCTAssertNotNil(access.storageNotice)
            await access.unlock()
            XCTAssertFalse(access.locked); XCTAssertTrue(access.preferences.enabled); XCTAssertNil(access.storageNotice)
            XCTAssertTrue(defaults.dictionaryRepresentation().keys.contains { $0.hasPrefix(AppAccess.preferencesKey + ".unreadable.") })
            XCTAssertTrue(AppAccess(defaults:defaults,authenticator:device).locked)
        }
    }
    func testStyleResetCannotDisablePrivacy() async throws {
        let device = TestDeviceAuthenticator(); let access = AppAccess(defaults:defaults,authenticator:device)
        await access.setEnabled(true); let before = defaults.data(forKey:AppAccess.preferencesKey)
        let appearance = Appearance(defaults:defaults)
        try appearance.saveStyle(named:"Örnek"); try appearance.resetStyle(); try appearance.applyStyle(appearance.savedStyles[0])
        XCTAssertEqual(defaults.data(forKey:AppAccess.preferencesKey),before)
        XCTAssertTrue(AppAccess(defaults:defaults,authenticator:device).locked)
    }
}

@MainActor private final class TestDeviceAuthenticator: DeviceAuthenticating {
    enum Answer { case accept, deny, cancel, pending }
    var answer: Answer = .accept
    var calls = 0
    var cancels = 0
    private var continuation: CheckedContinuation<Bool,Error>?
    var waiting: Bool { continuation != nil }
    func authenticate(reason: String) async throws -> Bool {
        calls += 1
        switch answer {
        case .accept: return true
        case .deny: return false
        case .cancel: throw LAError(.userCancel)
        case .pending: return try await withCheckedThrowingContinuation { continuation = $0 }
        }
    }
    func finish(_ success: Bool) { let pending = continuation; continuation = nil; pending?.resume(returning:success) }
    func cancel() { cancels += 1 }
}

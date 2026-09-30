import XCTest
@testable import KisiselGitea

@MainActor final class ProductTests: XCTestCase {
    func testFreshInstallRequiresAnExplicitChoiceAndDemoChoicePersists() {
        let name = "test.product." + UUID().uuidString
        let defaults = UserDefaults(suiteName:name)!
        defer { defaults.removePersistentDomain(forName:name) }
        let workspace = Workspace(defaults:defaults)
        XCTAssertTrue(workspace.requiresOnboarding)
        workspace.chooseDemo()
        XCTAssertFalse(workspace.requiresOnboarding)
        XCTAssertFalse(workspace.live)
        XCTAssertEqual(workspace.login,"Demo")
        XCTAssertFalse(Workspace(defaults:defaults).requiresOnboarding)
        XCTAssertNil(defaults.string(forKey:"server"))
    }
    func testCredentialsAreSeparatedForTwoUsersOnTheSameServer() throws {
        let origin = URL(string:"https://git.example.com")!
        let first = ConnectionIdentity(origin:origin,login:"alice-" + UUID().uuidString)
        let second = ConnectionIdentity(origin:origin,login:"bob-" + UUID().uuidString)
        defer { try? TokenVault.delete(account:first.credentialKey); try? TokenVault.delete(account:second.credentialKey) }
        try TokenVault.save("synthetic-alice",account:first.credentialKey)
        try TokenVault.save("synthetic-bob",account:second.credentialKey)
        XCTAssertEqual(try TokenVault.load(account:first.credentialKey),"synthetic-alice")
        XCTAssertEqual(try TokenVault.load(account:second.credentialKey),"synthetic-bob")
        try TokenVault.delete(account:first.credentialKey)
        XCTAssertEqual(try TokenVault.load(account:second.credentialKey),"synthetic-bob")
        XCTAssertNotEqual(first.credentialKey,ConnectionIdentity(origin:URL(string:"https://other.example.com")!,login:first.login).credentialKey)
    }
}

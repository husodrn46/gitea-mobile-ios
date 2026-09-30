import XCTest
@testable import KisiselGitea

final class SigningProfileTests: XCTestCase {
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from:text)! }
    private func calendar(_ zone: String = "UTC",identifier: Calendar.Identifier = .gregorian) -> Calendar {
        var value = Calendar(identifier:identifier)
        value.timeZone = TimeZone(identifier:zone)!
        return value
    }
    private func xml(_ values: [String:Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList:values,format:.xml,options:0)
    }

    func testReadsExpirationInsideBinaryCMSWrapper() throws {
        let expected = date("2026-09-29T19:22:03Z")
        var payload = Data([0x30,0x82,0xff,0x00])
        payload.append(try xml(["ExpirationDate":expected,"Name":"Synthetic test profile"]))
        payload.append(Data([0x00,0xff,0x81]))
        XCTAssertEqual(SigningProfile.expiration(in:payload),expected)
    }

    func testRejectsMissingOrWrongExpirationType() throws {
        let cases: [[String:Any]] = [[:],["ExpirationDate":"2026-09-29T19:22:03Z"],
                                   ["ExpirationDate":123],["ExpirationDate":true]]
        for values in cases {
            XCTAssertNil(SigningProfile.expiration(in:try xml(values)))
        }
    }

    func testRejectsMalformedOrIncompleteXML() throws {
        let valid = try xml(["ExpirationDate":date("2026-09-29T19:22:03Z")])
        let text = String(decoding:valid,as:UTF8.self)
        let invalid = ["", "not a profile", "<?xml version=\"1.0\"?><plist><dict></plist>",
                       text.replacingOccurrences(of:"</plist>",with:""),
                       text.replacingOccurrences(of:"<?xml",with:"<!--xml"),
                       text.replacingOccurrences(of:"2026-09-29T19:22:03Z",with:"not-a-date")]
        for value in invalid { XCTAssertNil(SigningProfile.expiration(in:Data(value.utf8))) }
        let arrayRoot = try PropertyListSerialization.data(fromPropertyList:[date("2026-09-29T19:22:03Z")],format:.xml,options:0)
        XCTAssertNil(SigningProfile.expiration(in:arrayRoot))
    }

    func testAcceptsSizeLimitAndRejectsOneByteOver() throws {
        let expected = date("2026-09-29T19:22:03Z")
        var payload = try xml(["ExpirationDate":expected])
        payload.append(Data(repeating:0,count:4 * 1024 * 1024 - payload.count))
        XCTAssertEqual(SigningProfile.expiration(in:payload),expected)
        payload.append(0)
        XCTAssertNil(SigningProfile.expiration(in:payload))
    }

    func testUTCUsesTenOClockOnTwoPreviousCalendarDays() {
        let reminders = SigningReminderPlan.reminders(expiration:date("2026-09-29T02:15:48Z"),
                                                      now:date("2026-09-22T08:00:00Z"),calendar:calendar())
        XCTAssertEqual(reminders,[
            SigningReminder(id:"gitea.signing.two-days",date:date("2026-09-27T10:00:00Z")),
            SigningReminder(id:"gitea.signing.one-day",date:date("2026-09-28T10:00:00Z"))
        ])
        XCTAssertEqual(reminders.map(\.id),SigningReminderPlan.identifiers)
    }

    func testLocalTimeHonorsFractionalTimeZoneOffset() {
        let reminders = SigningReminderPlan.reminders(expiration:date("2026-09-29T01:00:00Z"),
                                                      now:date("2026-09-22T08:00:00Z"),calendar:calendar("Asia/Kathmandu"))
        XCTAssertEqual(reminders.map(\.date),[date("2026-09-27T04:15:00Z"),date("2026-09-28T04:15:00Z")])
    }

    func testDSTTransitionsKeepTenOClockInsteadOfSubtracting24Hours() {
        let cases = [
            ("2026-03-09T16:00:00Z","2026-03-07T15:00:00Z","2026-03-08T14:00:00Z"),
            ("2026-11-02T17:00:00Z","2026-10-31T14:00:00Z","2026-11-01T15:00:00Z")
        ]
        for (expiration,twoDays,oneDay) in cases {
            let reminders = SigningReminderPlan.reminders(expiration:date(expiration),now:date("2026-01-01T00:00:00Z"),
                                                          calendar:calendar("America/New_York"))
            XCTAssertEqual(reminders.map(\.date),[date(twoDays),date(oneDay)])
        }
    }

    func testCalendarArithmeticCrossesLeapDayAndYearBoundary() {
        let cases = [
            ("2028-03-01T00:01:00Z","2028-02-28T10:00:00Z","2028-02-29T10:00:00Z"),
            ("2027-01-01T00:01:00Z","2026-12-30T10:00:00Z","2026-12-31T10:00:00Z")
        ]
        for (expiration,twoDays,oneDay) in cases {
            let reminders = SigningReminderPlan.reminders(expiration:date(expiration),now:date("2026-01-01T00:00:00Z"),calendar:calendar())
            XCTAssertEqual(reminders.map(\.date),[date(twoDays),date(oneDay)])
        }
    }

    func testSupportsNonGregorianCalendar() {
        let reminders = SigningReminderPlan.reminders(expiration:date("2026-09-14T02:00:00Z"),
                                                      now:date("2026-09-01T00:00:00Z"),calendar:calendar(identifier:.hebrew))
        XCTAssertEqual(reminders.map(\.date),[date("2026-09-12T10:00:00Z"),date("2026-09-13T10:00:00Z")])
    }

    func testElapsedFirstReminderLeavesOnlySecondReminder() {
        for now in ["2026-09-27T10:00:00Z","2026-09-27T11:00:00Z"] {
            let reminders = SigningReminderPlan.reminders(expiration:date("2026-09-29T02:00:00Z"),now:date(now),calendar:calendar())
            XCTAssertEqual(reminders,[SigningReminder(id:"gitea.signing.one-day",date:date("2026-09-28T10:00:00Z"))])
        }
    }

    func testNeverAddsLastDayFallbackOrSchedulesAtNow() {
        for now in ["2026-09-28T10:00:00Z","2026-09-28T23:00:00Z","2026-09-29T01:00:00Z"] {
            XCTAssertTrue(SigningReminderPlan.reminders(expiration:date("2026-09-29T02:00:00Z"),now:date(now),calendar:calendar()).isEmpty)
        }
    }

    func testExpiredAndNonFiniteDatesDoNotSchedule() {
        let expiration = date("2026-09-29T02:00:00Z")
        for now in [expiration,expiration.addingTimeInterval(1),Date(timeIntervalSince1970:.infinity)] {
            XCTAssertTrue(SigningReminderPlan.reminders(expiration:expiration,now:now,calendar:calendar()).isEmpty)
        }
        XCTAssertTrue(SigningReminderPlan.reminders(expiration:Date(timeIntervalSince1970:.infinity),now:expiration,calendar:calendar()).isEmpty)
    }
}

import Foundation

enum SigningProfile {
    private static let maximumSize = 4 * 1024 * 1024

    /// Reads profile metadata only; this does not verify the CMS signature.
    static func expiration(in data: Data) -> Date? {
        guard data.count <= maximumSize,
              let start = data.range(of:Data("<?xml".utf8)),
              let end = data.range(of:Data("</plist>".utf8),in:start.lowerBound..<data.endIndex) else { return nil }
        let xml = data.subdata(in:start.lowerBound..<end.upperBound)
        guard let plist = try? PropertyListSerialization.propertyList(from:xml,options:[],format:nil),
              let values = plist as? [String:Any],
              let expiration = values["ExpirationDate"] as? Date,
              expiration.timeIntervalSince1970.isFinite else { return nil }
        return expiration
    }

    static func bundledExpiration(bundle: Bundle = .main) -> Date? {
        guard let url = bundle.url(forResource:"embedded",withExtension:"mobileprovision"),
              let handle = try? FileHandle(forReadingFrom:url) else { return nil }
        defer { try? handle.close() }
        // Limit the read itself as well as the parser, including a byte to detect oversized input.
        guard let data = try? handle.read(upToCount:maximumSize + 1) else { return nil }
        return expiration(in:data)
    }
}

struct SigningReminder: Equatable {
    let id: String
    let date: Date
}

enum SigningReminderPlan {
    static let identifiers = ["gitea.signing.two-days", "gitea.signing.one-day"]

    static func reminders(expiration: Date, now: Date, calendar: Calendar = .current) -> [SigningReminder] {
        guard expiration.timeIntervalSince1970.isFinite,now.timeIntervalSince1970.isFinite,
              now < expiration else { return [] }
        let expirationDay = calendar.startOfDay(for:expiration)
        return zip(identifiers,[2,1]).compactMap { id,days in
            guard let day = calendar.date(byAdding:.day,value:-days,to:expirationDay),
                  let date = calendar.date(bySettingHour:10,minute:0,second:0,of:day,
                                           matchingPolicy:.strict,repeatedTimePolicy:.first,direction:.forward),
                  calendar.isDate(date,inSameDayAs:day),date > now,date < expiration else { return nil }
            return SigningReminder(id:id,date:date)
        }
    }
}

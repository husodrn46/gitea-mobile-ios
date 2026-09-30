#if DEBUG
import Foundation

/// Only enabled by the UI-test launch argument. No external requests or real credentials.
final class RemoteFixtureProtocol: URLProtocol {
    static let sha = String(repeating:"a",count:40)
    static let base = String(repeating:"b",count:40)
    static let metadata = """
    {"number":7,"title":"Mobil inceleme akışı","body":"Dosyaları telefonda okuyabilme.","user":{"login":"Claude"},"state":"open","merged":false,"draft":false,"head":{"sha":"\(sha)"},"base":{"sha":"\(base)"},"updated_at":"2026-09-21T10:00:00Z","assignees":[{"login":"Codex"}],"requested_reviewers":[{"login":"reviewer"}]}
    """
    static let review = """
    {"id":2,"user":{"login":"Codex"},"state":"APPROVED","body":"Kaynaklar incelendi.","commit_id":"\(sha)","stale":false,"dismissed":false,"official":true,"submitted_at":"2026-09-21T10:00:00Z"}
    """
    static let diff = "diff --git a/App.swift b/App.swift\n--- a/App.swift\n+++ b/App.swift\n@@ -1 +1 @@\n-oldTitle\n+newTitle\n"
    static func issueJSON(_ number: Int = 12) -> String { """
    {"id":\(number),"number":\(number),"title":"Telefondan fikir takibi","body":"## Amaç\\nFikirleri **tek yerde** topla.\\n- Listeyi oku\\n- Görüşünü paylaş","state":"open","user":{"login":"demo"},"labels":[{"id":1,"name":"fikir","color":"7952CD"}],"assignees":[{"login":"reviewer"}],"html_url":"https://fixture.invalid/ornek/mobile/issues/\(number)","updated_at":"2026-09-22T10:00:00Z"}
    """ }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard request.httpMethod == "GET",request.url?.host == "fixture.invalid" else { client?.urlProtocol(self,didFailWithError:URLError(.unsupportedURL));return }
        let path = request.url!.path
        let body: String
        if path.hasSuffix("/issues") { body = "[" + ([Self.issueJSON()] + IssueFixtureProtocol.createdBodies).joined(separator:",") + "]" }
        else if path.contains("/issues/"),path.hasSuffix("/comments") { body = "[" + ([#"{"id":1,"body":"Bu akışı telefonda deneyelim.","user":{"login":"reviewer"}}"#] + IssueFixtureProtocol.commentBodies).joined(separator:",") + "]" }
        else if path.contains("/issues/") { body = path.hasSuffix("/99") ? (IssueFixtureProtocol.createdBodies.last ?? Self.issueJSON(99)) : Self.issueJSON(Int(path.split(separator:"/").last ?? "12") ?? 12) }
        else if path.hasSuffix("/labels") { body = #"[{"id":1,"name":"fikir","color":"7952CD"}]"# }
        else if path.hasSuffix("/assignees") { body = #"[{"login":"reviewer"},{"login":"demo"}]"# }
        else if path == "/api/v1/repos/ornek/mobile" { body = #"{"permissions":{"push":true,"admin":false}}"# }
        else if path.hasSuffix("/reviews") { body = "[" + Self.review + "]" }
        else if path.hasSuffix("/statuses") { body = ProcessInfo.processInfo.arguments.contains("--fixture-updated") ? #"[{"id":2,"context":"CI / fast","status":"pending","description":"Kontroller sürüyor"}]"# : #"[{"id":1,"context":"CI / fast","status":"success","description":"Kontroller geçti"}]"# }
        else if path.hasSuffix("/files") { body = #"[{"filename":"App.swift","status":"modified","additions":1,"deletions":1}]"# }
        else if path.hasSuffix(".diff") {
            if ProcessInfo.processInfo.arguments.contains("--fixture-long-diff") {
                let added = ["+newTitle","+let message = \"" + String(repeating:"long_text_",count:70) + "\""] + (0..<180).map { "+long_row_\($0)" }
                body = "diff --git a/App.swift b/App.swift\n--- a/App.swift\n+++ b/App.swift\n@@ -1 +1,\(added.count) @@\n-oldTitle\n" + added.joined(separator:"\n") + "\n"
            } else { body = Self.diff }
        }
        else if path.hasSuffix("/notifications") {
            body = #"[{"id":1,"unread":true,"updated_at":"2026-09-21T10:00:00Z","subject":{"title":"Mobil inceleme akışı","type":"Pull","html_url":"https://fixture.invalid/ornek/mobile/pulls/7"},"repository":{"id":1,"name":"Mobil","full_name":"ornek/mobile","description":"Test deposu","private":true}},{"id":2,"unread":true,"updated_at":"2026-09-22T10:00:00Z","subject":{"title":"Telefondan fikir takibi","type":"Issue","html_url":"https://fixture.invalid/ornek/mobile/issues/12"},"repository":{"id":1,"name":"Mobil","full_name":"ornek/mobile","description":"Test deposu","private":true}}]"#
        } else if path.hasSuffix("/pulls") { body = #"[{"number":7,"title":"Mobil inceleme akışı","body":"Dosyaları telefonda okuyabilme.","user":{"login":"Claude"}}]"# }
        else { body = ProcessInfo.processInfo.arguments.contains("--fixture-updated") ? Self.metadata.replacingOccurrences(of:Self.sha,with:String(repeating:"c",count:40)) : Self.metadata }
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:Data(body.utf8));client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif

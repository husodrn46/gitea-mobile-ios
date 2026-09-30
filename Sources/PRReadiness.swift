import SwiftUI

struct PRWaitingSummary {
    let snapshot: PRSnapshot
    var baseChanged = false
    var testText: String {
        let rows = snapshot.latestStatuses
        if rows.isEmpty { return "Bilinmiyor · Bu commit için test kaydı yok" }
        if rows.contains(where: { ["failure","error"].contains($0.status) }) { return "Başarısız test var" }
        if rows.contains(where: { $0.status == "pending" }) { return "Testler sürüyor" }
        if rows.allSatisfy({ $0.status == "success" }) { return "Bildirilen testler geçti" }
        return "Bilinmiyor · Tanınmayan test durumu"
    }
    var decisions: [PRReview] {
        let rows = snapshot.reviews.filter { ["APPROVED","REQUEST_CHANGES"].contains($0.state.uppercased()) && $0.user != nil }
        return Dictionary(grouping:rows,by: { $0.user!.login.lowercased() }).values.compactMap { $0.max { $0.id < $1.id } }
    }
    var reviewText: String {
        if baseChanged { return "Taban dal değişti · Onayların taban sürümü doğrulanamıyor" }
        if decisions.contains(where: { $0.state.uppercased() == "REQUEST_CHANGES" && $0.dismissed == false }) { return "Düzeltme isteği var · İncelemeyi oku" }
        let current = decisions.filter { $0.state.uppercased() == "APPROVED" && $0.isCurrent(snapshot.metadata.head.sha) }
        if !current.isEmpty { return "\(current.count) onay bu commit ile eşleşiyor" }
        return "Güncel onay doğrulanmadı"
    }
    var conflictText: String {
        switch snapshot.metadata.mergeable {
        case true: return "Sunucu birleştirilebilir bildiriyor; tüm kurallar doğrulanmadı"
        case false: return "Sunucu birleştirilemez bildiriyor · Çakışma veya başka engel olabilir"
        case nil: return "Çakışma durumu bilinmiyor"
        }
    }
    var actorText: String {
        if snapshot.metadata.merged == true { return "Birleştirilmiş" }
        if snapshot.metadata.state == "closed" { return "Kapatılmış" }
        if snapshot.metadata.draft == true { return "Taslak · İncelemeye hazır olduğu doğrulanmadı" }
        return snapshot.requested.isEmpty ? "Sıradaki kişi bilinmiyor · Açık inceleme isteği yok" : "İnceleme: " + snapshot.requested.joined(separator:", ")
    }
}
struct PRWaitingCard: View {
    let snapshot: PRSnapshot
    var baseChanged: Bool
    var testTone: WorkflowTone {
        let tests = snapshot.latestStatuses
        if tests.contains(where:{ ["failure","error"].contains($0.status) }) { return .failure }
        if tests.contains(where:{ $0.status == "pending" }) { return .waiting }
        if !tests.isEmpty && tests.allSatisfy({ $0.status == "success" }) { return .success }
        return .unknown
    }
    var reviewTone: WorkflowTone {
        let summary = PRWaitingSummary(snapshot:snapshot,baseChanged:baseChanged)
        if baseChanged { return .unknown }
        if summary.decisions.contains(where: { $0.state.uppercased() == "REQUEST_CHANGES" && $0.dismissed == false }) { return .waiting }
        return summary.decisions.contains(where: { $0.state.uppercased() == "APPROVED" && $0.isCurrent(snapshot.metadata.head.sha) }) ? .review : .unknown
    }
    var body: some View {
        let summary = PRWaitingSummary(snapshot:snapshot,baseChanged:baseChanged)
        Surface {
            VStack(alignment:.leading,spacing:12) {
                HStack {
                    Text("Neyi bekliyoruz?").font(.title3.bold()).accessibilityIdentifier("waitingSummary")
                    Spacer()
                    ContextInfoButton(title:"Özetin kaynağı",details:"Kaynak: commit durumları, incelemeler ve PR kaydı. Gerekli test/onay sayısı ve dal kuralları bilinmiyor. Taban dalın inceleme anındaki sürümü API’de yok; bu kart birleştirme izni vermez.")
                }
                WorkflowSignal(title:summary.testText,symbol:"checklist",tone:testTone)
                WorkflowSignal(title:summary.reviewText,symbol:"person.crop.circle.badge.checkmark",tone:reviewTone)
                WorkflowSignal(title:summary.conflictText,symbol:"arrow.triangle.branch",tone:snapshot.metadata.mergeable == false ? .waiting : .unknown)
                WorkflowSignal(title:summary.actorText,symbol:"person.crop.circle.badge.clock",tone:snapshot.requested.isEmpty ? .unknown : .review)
                Text("Dal kuralları bilinmiyor · Birleştirme izni değildir.").font(.caption).foregroundStyle(.secondary)
            }.font(.subheadline).fixedSize(horizontal:false,vertical:true)
        }
    }
}

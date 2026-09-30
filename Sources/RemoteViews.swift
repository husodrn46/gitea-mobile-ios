import SwiftUI

struct ContextInfoButton: View {
    let title: String
    let details: String
    @State private var shown = false
    var body: some View {
        Button { shown = true } label: { Image(systemName:"info.circle").frame(width:44,height:44) }
            .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel(title)
            .sheet(isPresented:$shown) {
                NavigationStack {
                    ScrollView { Text(details).frame(maxWidth:.infinity,alignment:.leading).padding(24).textSelection(.enabled) }
                        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Bitti") { shown = false } } }
                }.presentationDetents([.medium,.large]).presentationDragIndicator(.visible)
            }
    }
}
struct FreshnessView: View {
    let date: Date
    let cached: Bool
    let note: String?
    var time: String {
        if Calendar.current.isDateInToday(date) { return date.formatted(.dateTime.locale(Locale(identifier:"tr_TR")).hour().minute()) }
        return date.formatted(.dateTime.locale(Locale(identifier:"tr_TR")).day().month(.abbreviated).hour().minute())
    }
    var details: String {
        let full = date.formatted(.dateTime.locale(Locale(identifier:"tr_TR")).day().month(.abbreviated).year().hour().minute())
        let extra = note == "Çevrimdışı kayıt; güncel olmayabilir." ? nil : note
        return "Son alınma: " + full + (cached ? "\nBu saklanmış kayıt güncel olmayabilir." : "\nBu ekran en son bu zamanda yenilendi.") + (extra.map { "\n\n" + $0 } ?? "")
    }
    var body: some View {
        HStack(spacing:4) {
            Label((cached ? "Çevrimdışı · Son kayıt " : "Son alınan · ") + time,systemImage:cached ? "wifi.slash" : "clock")
                .font(.caption).foregroundStyle(cached ? Color.waiting : Color.secondary)
                .accessibilityIdentifier("freshnessLabel")
            Spacer(minLength:4)
            ContextInfoButton(title:"Kaydın zamanı",details:details)
        }
    }
}
struct RemotePRView: View {
    let pull: PullRequest
    @EnvironmentObject var workspace: Workspace
    @State private var result: ReadResult<PRSnapshot>?
    @State private var error: String?
    @State private var loading = false
    @State private var section = "Açıklama"
    @State private var baseChanged = false
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                DemoCaption()
                Text(result?.value.metadata.title ?? pull.title).font(.largeTitle.bold())
                NavigationLink { RemoteFilesView(pull:pull) } label: { Label("Dosyaları gör",systemImage:"doc.text.magnifyingglass") }
                    .buttonStyle(.glass).accessibilityIdentifier("prFilesShortcut")
                if loading { ProgressView("Güncel PR bilgileri alınıyor") }
                if let error { Text(error).foregroundStyle(Color.waiting); Button("Yeniden dene") { Task { await load() } }.buttonStyle(.glass) }
                if let result {
                    let snapshot = result.value
                    if section != "Konuşma" { FreshnessView(date:snapshot.fetchedAt,cached:result.cached,note:result.note) }
                    if section == "Açıklama" {
                    Surface {
                        VStack(alignment:.leading,spacing:10) {
                            HStack {
                                Text("Sıradaki adım").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                ContextInfoButton(title:"Sorumluluk bilgisi",details:snapshot.reason + (snapshot.requested.isEmpty ? "" : "\n\nİnceleme istenenler: " + snapshot.requested.joined(separator:", ")))
                            }
                            Text(snapshot.actionTitle(for:workspace.identity?.login ?? workspace.login)).font(.title3.bold()).accessibilityIdentifier("nextActionTitle")
                            if !snapshot.assignees.isEmpty { Text("İşi yürüten: " + snapshot.assignees.joined(separator:", ")).font(.subheadline).foregroundStyle(.secondary) }
                        }
                    }
                    PRWaitingCard(snapshot:snapshot,baseChanged:baseChanged || snapshot.observedBaseChange == true)
                    }
                    if section == "Dosyalar" {
                        NavigationLink { RemoteFilesView(pull:pull) } label: { Label("Dosyaları ve kod farkını aç",systemImage:"doc.text.magnifyingglass") }.buttonStyle(.glass)
                    } else if section == "Konuşma" {
                        IssueConversationView(project:pull.project,number:pull.id,embedded:true)
                    } else {
                    Text("PR açıklaması").font(.title2.bold())
                    IssueMarkdown(text:snapshot.metadata.body?.isEmpty == false ? snapshot.metadata.body! : "Açıklama eklenmemiş.")
                    Text("Commit: " + String(snapshot.metadata.head.sha.prefix(10))).font(.caption.monospaced()).foregroundStyle(.secondary)
                    Text("Test durumları").font(.title2.bold())
                    if snapshot.latestStatuses.isEmpty { Text("Bu commit için test durumu bildirilmemiş. Başarılı sayılmaz.").foregroundStyle(.secondary) }
                    ForEach(snapshot.latestStatuses) { status in
                        Surface { VStack(alignment:.leading,spacing:8) { HStack { Text(status.context).font(.headline); Spacer(); Text(status.label).font(.caption).foregroundStyle(status.status == "success" ? Color.success : Color.waiting) }; if let text = status.description { Text(text).font(.subheadline).foregroundStyle(.secondary) } } }
                    }
                    Text("İncelemeler").font(.title2.bold())
                    if snapshot.reviews.isEmpty { Text("Henüz inceleme yok.").foregroundStyle(.secondary) }
                    ForEach(snapshot.reviews.sorted { $0.id > $1.id }) { review in
                        Surface {
                            VStack(alignment:.leading,spacing:8) {
                                Text(review.user?.login ?? "Ekip incelemesi").font(.headline)
                                Text(review.label).font(.subheadline)
                                Text(review.isCurrent(snapshot.metadata.head.sha) ? "Bu commit için · Kaynak: Gitea" : "Güncel onay sayılmaz · Eski, geri çekilmiş veya commit bilgisi eksik")
                                    .font(.caption).foregroundStyle(.secondary)
                                if let body = review.body,!body.isEmpty { Text(body).font(.subheadline).textSelection(.enabled) }
                            }
                        }
                    }
                    }
                    Text("Bunlar alınan test ve inceleme kayıtlarıdır. Dal koruması ve tüm birleştirme koşulları doğrulanmadığından hazır etiketi üretilmez.").font(.footnote).foregroundStyle(.secondary)
                }
                if let url = pull.url { Link("Gitea’da aç",destination:url).buttonStyle(.glass) }
            }.padding(22)
        }.background(Color.canvas).navigationTitle("PR #\(pull.id)").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge:.top) {
                Picker("PR bölümü",selection:$section) {
                    Text("Açıklama").tag("Açıklama")
                    Text("Konuşma").tag("Konuşma")
                    Text("Dosyalar").tag("Dosyalar")
                }.pickerStyle(.segmented).padding(6).glassEffect(.regular,in:RoundedRectangle(cornerRadius:18)).padding(.horizontal,22).accessibilityIdentifier("prSections")
            }
            .toolbar(.hidden,for:.tabBar).task(id:workspace.identity?.scope) { await load() }.refreshable { await load() }
    }
    func load() async {
        loading = true; error = nil; result = nil
        defer { loading = false }
        do {
            let old = workspace.identity.flatMap { try? workspace.cache.load(PRSnapshot.self,key:"pr|\(pull.project.fullName)|\(pull.id)",identity:$0) }
            let fetched = try await workspace.loadSnapshot(pull)
            if !fetched.cached,let old { baseChanged = baseChanged || old.metadata.base.sha != fetched.value.metadata.base.sha }
            result = fetched
        }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
struct RemoteFilesView: View {
    let pull: PullRequest
    @EnvironmentObject var workspace: Workspace
    @State private var result: ReadResult<FileSnapshot>?
    @State private var error: String?
    @State private var query = ""
    var body: some View {
        List {
            if let result {
                Section { DemoCaption(); FreshnessView(date:result.value.fetchedAt,cached:result.cached,note:result.note)
                    Text("Commit: " + String(result.value.head.prefix(10))).font(.caption.monospaced()) }
                Section("Değişen dosyalar") {
                    ForEach(result.value.files.filter { query.isEmpty || $0.filename.localizedStandardContains(query) }) { file in
                        VStack(alignment:.leading,spacing:5) {
                            Text(file.filename).font(.subheadline.monospaced()).textSelection(.enabled)
                            HStack { Text(file.status); Text("+\(file.additions)").foregroundStyle(Color.success); Text("−\(file.deletions)").foregroundStyle(Color.waiting) }.font(.caption)
                            if let old = file.previous_filename { Text("Önceki ad: " + old).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
                Section {
                    NavigationLink("Kod farkını oku") { DiffTextView(diff:result.value.diff) }
                    Text("Kod çalıştırılmaz. İkili dosyalarda içerik yerine fark bildirimi olabilir. Fark 4 MB sınırını aşarsa Gitea’da aç.").font(.footnote).foregroundStyle(.secondary)
                }
            } else if let error { Text(error); Button("Yeniden dene") { Task { await load() } } }
            else { ProgressView("Dosyalar alınıyor") }
            if let url = pull.url { Link("Gitea’da aç",destination:url) }
        }.navigationTitle("Dosyalar").searchable(text:$query,prompt:"Dosya ara").task { await load() }.refreshable { await load() }
    }
    func load() async { result = nil; error = nil; do { result = try await workspace.loadFiles(pull) } catch { if !Task.isCancelled { self.error = error.localizedDescription } } }
}
struct DiffTextView: View {
    let diff: String
    @ScaledMetric(relativeTo:.callout) private var codeSize: CGFloat = 16
    @State private var query = ""
    var lines: [String] { diff.components(separatedBy:"\n") }
    var codeWidth: CGFloat {
        let font = UIFont.monospacedSystemFont(ofSize:codeSize,weight:.regular)
        return ceil(lines.prefix(12000).map { ($0 as NSString).size(withAttributes:[.font:font]).width }.max() ?? 0)
    }
    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            DemoCaption().padding(.horizontal,16).padding(.vertical,8)
            if lines.count > 12000 { Text("İlk 12.000 satır gösteriliyor. Tamamı için Gitea’yı aç.").font(.caption).foregroundStyle(Color.waiting).padding(.horizontal,16) }
            GeometryReader { bounds in
                ScrollView([.horizontal,.vertical]) {
                    LazyVStack(alignment:.leading,spacing:4) {
                        ForEach(Array(lines.prefix(12000).enumerated()),id:\.offset) { row in
                            if query.isEmpty || row.element.localizedStandardContains(query) {
                                if row.element.hasPrefix("diff --git ") {
                                    VStack(alignment:.leading,spacing:5) {
                                        Text("Dosya karşılaştırması").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                        Text(String(row.element.dropFirst(11))).font(.system(size:codeSize,design:.monospaced)).fixedSize(horizontal:true,vertical:false)
                                    }.padding(.vertical,12).accessibilityIdentifier("diffHeader-\(row.offset)")
                                } else {
                                    Text(row.element.isEmpty ? " " : row.element).font(.system(size:codeSize,design:.monospaced))
                                        .fixedSize(horizontal:true,vertical:false)
                                        .foregroundStyle(row.element.hasPrefix("+") ? Color.success : row.element.hasPrefix("-") ? Color.waiting : Color.primary)
                                        .textSelection(.enabled).accessibilityIdentifier("diffLine-\(row.offset)")
                                }
                            }
                        }
                    }.frame(width:max(bounds.size.width-32,codeWidth),alignment:.leading).padding(16).frame(minHeight:bounds.size.height,alignment:.topLeading)
                }.defaultScrollAnchor(.topLeading).accessibilityIdentifier("diffScroll")
            }
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        .background(Color.canvas).navigationTitle("Kod farkı").navigationBarTitleDisplayMode(.inline)
        .searchable(text:$query,prompt:"Satırlarda ara")
    }
}
struct RemoteInboxView: View {
    @EnvironmentObject var workspace: Workspace
    @State private var result: ReadResult<InboxSnapshot>?
    @State private var error: String?
    @State private var unreadOnly = true
    @State private var marking: Int?
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack(spacing:12) {
                Picker("Bildirim filtresi",selection:$unreadOnly) { Text("Okunmamış").tag(true); Text("Tümü").tag(false) }.pickerStyle(.segmented)
                Button("Yenile",systemImage:"arrow.clockwise") { Task { await load() } }.labelStyle(.iconOnly).buttonStyle(.plain).frame(width:44,height:44).disabled(marking != nil)
            }
            if let result {
                FreshnessView(date:result.value.fetchedAt,cached:result.cached,note:result.note)
                let rows = result.value.threads.filter { !unreadOnly || $0.unread }
                if rows.isEmpty { ContentUnavailableView("Bildirim yok",systemImage:"bell.slash",description:Text("Bu filtrede bildirim bulunmuyor.")) }
                ForEach(rows) { thread in
                    Surface {
                        VStack(alignment:.leading,spacing:14) {
                            if let identity = workspace.identity,let pull = thread.nativePull(origin:identity.origin) {
                                NavigationLink { RemotePRView(pull:pull) } label: { notificationContent(thread,native:true) }.buttonStyle(.plain).accessibilityIdentifier("notification-\(thread.id)")
                            } else if let identity = workspace.identity,let number = thread.nativeIssue(origin:identity.origin) {
                                NavigationLink { IssueDetailView(project:thread.repository.project(index:0),number:number) } label: { notificationContent(thread,native:true) }.buttonStyle(.plain).accessibilityIdentifier("notification-\(thread.id)")
                            } else { notificationContent(thread,native:false) }
                            if thread.unread {
                                Divider()
                                HStack(alignment:.center,spacing:12) {
                                    if let identity = workspace.identity { Text("\(identity.login)\n\(identity.origin.host ?? identity.origin.absoluteString)").font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true) }
                                    Spacer(minLength:0)
                                    Button { Task { await mark(thread) } } label: {
                                        Label(marking == thread.id ? "Doğrulanıyor…" : "Okundu işaretle",systemImage:"checkmark")
                                    }.font(.subheadline.weight(.medium)).buttonStyle(.plain).frame(minHeight:44).disabled(workspace.offlineOnly || marking != nil).accessibilityIdentifier("markRead-\(thread.id)")
                                }
                            }
                        }
                    }
                }
            } else if let error { Text(error).foregroundStyle(Color.waiting) }
            else { ProgressView("Bildirimler alınıyor") }
            if result != nil,let error { Text(error).foregroundStyle(Color.waiting) }
            ContextInfoButton(title:"Gelen kutusu hakkında",details:"Bildirimler konu başına toplanır. Bir kart yorum sayısı değildir. Konuyu açmak sunucuda okundu işaretlemez.")
                .frame(maxWidth:.infinity,alignment:.trailing)
        }.task(id:workspace.identity?.scope) { await load() }
    }
    func notificationContent(_ thread: NotificationThread,native: Bool) -> some View {
        VStack(alignment:.leading,spacing:8) {
            HStack {
                Text(thread.repository.full_name).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if native { Image(systemName:"chevron.right").font(.caption).foregroundStyle(.tertiary) }
            }
            Text(thread.subject.title).font(.headline).foregroundStyle(.primary)
            Text("\(thread.typeLabel) · \(thread.unread ? "Okunmamış" : "Okunmuş")").font(.caption).foregroundStyle(.secondary)
            if !native,let identity = workspace.identity,let url = GiteaClient.safeLink(thread.subject.html_url,origin:identity.origin) { Link("Gitea’da aç",destination:url).font(.subheadline) }
        }.frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
    }
    func mark(_ thread: NotificationThread) async {
        let selected = workspace.identity; let revision = workspace.accountRevision
        marking = thread.id; error = nil
        defer { if workspace.identity == selected,workspace.accountRevision == revision { marking = nil } }
        do {
            let verified = try await workspace.markNotificationRead(thread)
            guard workspace.identity == selected,workspace.accountRevision == revision,let old = result else { return }
            let snapshot = InboxSnapshot(threads:old.value.threads.map { $0.id == verified.id ? verified : $0 },fetchedAt:old.value.fetchedAt)
            result = ReadResult(value:snapshot,cached:old.cached,note:old.note)
            if let selected { try? workspace.cache.save(snapshot,key:"inbox",identity:selected) }
        } catch { if workspace.identity == selected,workspace.accountRevision == revision { self.error = "Okundu durumu kesinleşmedi: " + error.localizedDescription } }
    }
    func load() async { marking = nil; result = nil; error = nil; do { result = try await workspace.loadInbox() } catch { if !Task.isCancelled { self.error = error.localizedDescription } } }
}

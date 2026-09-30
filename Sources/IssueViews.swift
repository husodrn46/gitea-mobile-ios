import SwiftUI

/// Native text rendering preserves paragraph breaks without executing HTML or remote images.
struct IssueMarkdown: View {
    let text: String
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            ForEach(Array(text.components(separatedBy:"\n").enumerated()),id:\.offset) { _,line in
                if line.hasPrefix("### ") { Text(String(line.dropFirst(4))).font(.headline) }
                else if line.hasPrefix("## ") { Text(String(line.dropFirst(3))).font(.title3.bold()) }
                else if line.hasPrefix("# ") { Text(String(line.dropFirst(2))).font(.title2.bold()) }
                else { Text((try? AttributedString(markdown:line,options:.init(interpretedSyntax:.inlineOnlyPreservingWhitespace))) ?? AttributedString(line)).textSelection(.enabled) }
            }
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}
struct IssueListView: View {
    let project: Project
    @EnvironmentObject var workspace: Workspace
    @State private var result: ReadResult<IssueListSnapshot>?
    @State private var error: String?
    @State private var search = ""
    @State private var openOnly = true
    @State private var compose = false
    @State private var newDraft: DraftIdea?
    var body: some View {
        List {
            Section {
                Toggle("Yalnız açık konular",isOn:$openOnly)
                if let result { FreshnessView(date:result.value.fetchedAt,cached:result.cached,note:result.note) }
                if let error { Text(error).foregroundStyle(Color.waiting); Button("Yenile") { Task { await load() } } }
            }
            if let result {
                let issues = result.value.issues.filter { (!openOnly || $0.state == "open") && (search.isEmpty || $0.title.localizedStandardContains(search)) }
                if issues.isEmpty { ContentUnavailableView("Konu yok",systemImage:"text.bubble",description:Text("Yeni bir fikir gönder veya filtreyi değiştir.")) }
                ForEach(issues) { issue in
                    NavigationLink { IssueDetailView(project:project,number:issue.number) } label: {
                        VStack(alignment:.leading,spacing:7) {
                            Text(issue.title).font(.headline)
                            Text("#\(issue.number) · \(issue.state == "open" ? "Açık" : "Kapalı")").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical,5)
                    }.accessibilityIdentifier("issue-\(issue.number)")
                }
            } else if error == nil { ProgressView("Konular alınıyor") }
        }.navigationTitle("Konular").searchable(text:$search,prompt:"Konularda ara")
            .toolbar { Button { newDraft = DraftIdea(title:"",text:"",project:project.fullName); compose = true } label: { Image(systemName:"square.and.pencil") }.accessibilityLabel("Yeni konu").disabled(workspace.offlineOnly) }
            .sheet(isPresented:$compose,onDismiss:{ Task { await load() } }) { NavigationStack { if let newDraft { IssueComposer(draft:newDraft) } } }
            .task(id:workspace.identity?.scope) { await load() }.refreshable { await load() }
    }
    func load() async { error = nil; result = nil; do { result = try await workspace.loadIssues(project) } catch { if !Task.isCancelled { self.error = error.localizedDescription } } }
}
struct IssueDetailView: View {
    let project: Project
    let number: Int
    var body: some View { IssueConversationView(project:project,number:number).navigationTitle("Konu #\(number)").navigationBarTitleDisplayMode(.inline) }
}
struct IssueConversationView: View {
    @EnvironmentObject var appearance: Appearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    let project: Project
    let number: Int
    var embedded = false
    @EnvironmentObject var workspace: Workspace
    @State private var result: ReadResult<IssueDetailSnapshot>?
    @State private var error: String?
    @State private var text = ""
    @State private var sending = false
    @State private var sent = false
    @State private var storageKey: String?
    @State private var commentDraft = IssueCommentDraft()
    @State private var draftReady = false
    @State private var editingPeople = false
    @State private var composerExpanded = false
    @FocusState private var commentFocused: Bool
    var discussion: some View {
            VStack(alignment:.leading,spacing:20) {
                if let result {
                    FreshnessView(date:result.value.fetchedAt,cached:result.cached,note:result.note)
                    if !embedded {
                    Text(result.value.issue.title).font(.title.bold())
                    Label(result.value.issue.state == "open" ? "Açık" : "Kapalı",systemImage:"text.bubble").font(.subheadline)
                    IssueMarkdown(text:result.value.issue.body ?? "Açıklama eklenmemiş.")
                    if let labels = result.value.issue.labels,!labels.isEmpty { Text("Etiketler: " + labels.map(\.name).joined(separator:", ")).font(.subheadline) }
                    if let people = result.value.issue.assignees,!people.isEmpty { Text("Atananlar: " + people.map(\.login).joined(separator:", ")).font(.subheadline) }
                    Button("Etiket ve sorumlular") { editingPeople = true }.buttonStyle(.glass).disabled(workspace.offlineOnly)
                    Divider()
                    }
                    Text("Konuşma").font(.title2.bold())
                    if result.value.comments.isEmpty { Text("Henüz yorum yok.").foregroundStyle(.secondary) }
                    ForEach(result.value.comments) { comment in
                        Surface { VStack(alignment:.leading,spacing:10) {
                            Text(comment.user?.login ?? "Kullanıcı").font(.headline)
                            IssueMarkdown(text:comment.body)
                            if let identity = workspace.identity,let url = GiteaClient.safeLink(comment.html_url,origin:identity.origin) { Link("Yoruma git",destination:url).font(.caption) }
                        } }
                    }
                    if let identity = workspace.identity,let url = GiteaClient.safeLink(result.value.issue.html_url,origin:identity.origin) { Link("Gitea’da aç",destination:url).buttonStyle(.glass) }
                } else if error == nil { ProgressView("Konuşma alınıyor") }
                if let error { Text(error).foregroundStyle(Color.waiting).accessibilityIdentifier("issueWriteError") }
                if result != nil {
                    if sent { Label("Yorum sunucuya kaydedildi",systemImage:"checkmark.circle.fill").foregroundStyle(Color.success) }
                    if composerExpanded {
                        VStack(alignment:.leading,spacing:12) {
                            let editorHeader = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading,spacing:4)) : AnyLayout(HStackLayout())
                            editorHeader {
                                Text("Yorumun").font(.headline)
                                if !typeSize.isAccessibilitySize { Spacer() }
                                Button("Küçült") {
                                    commentFocused = false
                                    withAnimation(appearance.animation(reduced:reduceMotion)) { composerExpanded = false }
                                }.frame(minHeight:44).disabled(sending).accessibilityIdentifier("collapseComment")
                            }
                            SendTargetView(repository:project.fullName)
                            TextEditor(text:$text).disabled(sending).focused($commentFocused).scrollContentBackground(.hidden)
                                .frame(minHeight:140,maxHeight:220).padding(12).background(Color.surface,in:RoundedRectangle(cornerRadius:18))
                                .overlay(RoundedRectangle(cornerRadius:18).strokeBorder(.secondary.opacity(0.2)))
                                .accessibilityIdentifier("commentEditor")
                            Text("@mention bir bildirimdir; ajanın çalıştığını doğrulamaz. Gönder düğmesi sunucuya yazar.").font(.footnote).foregroundStyle(.secondary)
                            Button(sending ? "Gönderiliyor…" : "Yorumu gönder") { Task { await send() } }.buttonStyle(.glassProminent)
                                .disabled(sending || !draftReady || workspace.offlineOnly || text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty).accessibilityIdentifier("sendComment")
                        }.transition(.opacity)
                    } else {
                        Button {
                            withAnimation(appearance.animation(reduced:reduceMotion)) { composerExpanded = true }
                            commentFocused = true
                        } label: {
                            HStack(spacing:12) {
                                Image(systemName:"square.and.pencil")
                                Text(text.isEmpty ? "Görüşünü yaz…" : "Taslağına devam et").font(.body)
                                Spacer(minLength:0)
                                Image(systemName:"chevron.down").font(.caption)
                            }.foregroundStyle(.secondary).padding(16).frame(maxWidth:.infinity,minHeight:52,alignment:.leading)
                                .background(Color.surface,in:RoundedRectangle(cornerRadius:18))
                        }.buttonStyle(.plain).accessibilityIdentifier("expandComment")
                    }
                }
                Button("Yenile") { Task { await load() } }.buttonStyle(.glass).disabled(sending)
            }.padding(embedded ? 0 : 22)
    }
    var body: some View {
        Group {
            if embedded { discussion }
            else { ScrollView { discussion } }
        }.background(Color.canvas).sensoryFeedback(.success,trigger:sent) { _,new in new && appearance.haptics }
            .animation(reduceMotion || !appearance.motion ? nil : .easeInOut(duration:0.2),value:sent)
            .onChange(of:text) { _,value in
                if draftReady,let storageKey { commentDraft.text = value; do { try commentDraft.save(key:storageKey) } catch { self.error = error.localizedDescription; draftReady = false } }
            }
            .task(id:workspace.identity?.scope) {
                result = nil; error = nil; sent = false; composerExpanded = false; commentFocused = false
                storageKey = workspace.identity.map { IssueWriteLedger.shared.key(identity:$0,operation:"draftComment|\(project.fullName)|\(number)") }
                draftReady = false
                if let storageKey,let identity = workspace.identity {
                    do {
                        commentDraft = try IssueCommentDraft.load(key:storageKey)
                        let operation = IssueWriteLedger.commentOperation(project:project,number:number,attempt:commentDraft.attempt)
                        if IssueWriteLedger.shared.receipt(identity:identity,operation:operation)?.state == "sent" { commentDraft = IssueCommentDraft() }
                        try commentDraft.save(key:storageKey,flush:true)
                        text = commentDraft.text; draftReady = true
                    } catch { self.error = "Yorum taslağı okunamadı; korumak için gönderim kapalı. " + error.localizedDescription }
                }
                await load()
            }.refreshable { await load() }
            .sheet(isPresented:$editingPeople,onDismiss:{ Task { await load() } }) { if let result { NavigationStack { IssueMetadataEditor(project:project,issue:result.value.issue) } } }
    }
    func load() async { do { result = try await workspace.loadIssue(project,number:number) } catch { if !Task.isCancelled { self.error = error.localizedDescription } } }
    func send() async {
        sending = true; error = nil; sent = false; defer { sending = false }
        do {
            guard draftReady,let storageKey else { throw ClientError.message("Yorum taslağı hazır değil.") }
            commentDraft.text = text
            try commentDraft.save(key:storageKey,flush:true)
            _ = try await workspace.postComment(project:project,number:number,text:text,attempt:commentDraft.attempt)
            let nextDraft = IssueCommentDraft()
            try nextDraft.save(key:storageKey,flush:true)
            commentDraft = nextDraft
            commentFocused = false
            withAnimation(appearance.animation(reduced:reduceMotion)) { text = ""; sent = true; composerExpanded = false }
            await load()
        }
        catch { self.error = error.localizedDescription }
    }
}
struct IssueSelectionFields: View {
    let options: IssueOptions
    @Binding var labels: Set<Int>
    @Binding var people: Set<String>
    var body: some View {
        if options.canManage {
            Section("Etiketler") {
                if options.labels.isEmpty { Text("Depoda etiket yok").foregroundStyle(.secondary) }
                ForEach(options.labels) { label in Toggle(label.name,isOn:Binding(get:{ labels.contains(label.id) },set:{ if $0 { labels.insert(label.id) } else { labels.remove(label.id) } })) }
            }
            Section("Sorumlular") {
                if options.assignees.isEmpty { Text("Seçilebilir kişi yok").foregroundStyle(.secondary) }
                ForEach(options.assignees,id:\.login) { person in Toggle(person.login,isOn:Binding(get:{ people.contains(person.login) },set:{ if $0 { people.insert(person.login) } else { people.remove(person.login) } })) }
            }
        } else if let note = options.note { Section { Text(note).font(.footnote).foregroundStyle(.secondary) } }
    }
}
struct IssueComposer: View {
    @EnvironmentObject var appearance: Appearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let draft: DraftIdea
    @EnvironmentObject var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var bodyText = ""
    @State private var projectName = ""
    @State private var labels: Set<Int> = []
    @State private var people: Set<String> = []
    @State private var options: IssueOptions?
    @State private var error: String?
    @State private var sending = false
    @State private var created: GiteaIssue?
    @State private var initialized = false
    @State private var formIdentity: ConnectionIdentity?
    @State private var accountChanged = false
    var project: Project? { workspace.projects.first { $0.fullName == projectName } }
    var edited: DraftIdea { var value = draft; value.title = title; value.text = bodyText; value.project = projectName; return value }
    var receipt: IssueWriteLedger.Receipt? { guard let identity = workspace.identity else { return nil }; return IssueWriteLedger.shared.receipt(identity:identity,operation:"create|\(projectName)|\(draft.id)") }
    var body: some View {
        Form {
            if let project,let created {
                Section {
                    Label("Konu #\(created.number) sunucuya kaydedildi",systemImage:"checkmark.circle.fill")
                    SendTargetView(repository:project.fullName)
                    Text("Yerel fikrin korundu.").font(.footnote)
                    NavigationLink("Konuşmayı aç") { IssueDetailView(project:project,number:created.number) }
                }
            } else {
            Section("Fikrini konuya dönüştür") {
                SendTargetView(repository:projectName)
                Picker("Depo",selection:$projectName) { Text("Depo seç").tag(""); ForEach(workspace.projects) { Text($0.fullName).tag($0.fullName) } }.disabled(sending || created != nil)
                TextField("Başlık",text:$title).disabled(sending || created != nil).accessibilityIdentifier("issueTitle")
                TextEditor(text:$bodyText).disabled(sending || created != nil).frame(minHeight:150).accessibilityIdentifier("issueBody")
                Text("Yerel fikir korunur. Gönder düğmesi seçtiğin depoda gerçek bir konu oluşturur.").font(.footnote).foregroundStyle(.secondary)
            }
            if let options { IssueSelectionFields(options:options,labels:$labels,people:$people).disabled(sending || created != nil) }
            if let error { Section { Text(error).foregroundStyle(Color.waiting) } }
            if created == nil,let receipt {
                Section {
                    Text(receipt.state == "sent" ? "Bu fikir daha önce gönderilmiş." : "Bu fikrin önceki gönderiminin sonucu belirsiz. Mükerrer konu açmamak için tekrar gönderim kapalı; konu listesini kontrol et.")
                    if let project,let number = receipt.number { NavigationLink("Gönderilen konuyu aç") { IssueDetailView(project:project,number:number) } }
                    if let project { NavigationLink("Konuları kontrol et") { IssueListView(project:project) } }
                }
            } else if created == nil {
                Section { Button(sending ? "Gönderiliyor…" : "Konuyu gönder") { Task { await send() } }.disabled(sending || project == nil || workspace.offlineOnly || accountChanged || title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty).accessibilityIdentifier("createIssue") }
            }
            }
        }.navigationTitle("Fikir → Konu").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Kapat") { do { if initialized && !accountChanged { try workspace.save(edited) }; dismiss() } catch { self.error = error.localizedDescription } }.disabled(sending) } }
            .interactiveDismissDisabled(true)
            .sensoryFeedback(.success,trigger:created?.number) { _,new in new != nil && appearance.haptics }
            .animation(reduceMotion || !appearance.motion ? nil : .easeInOut(duration:0.2),value:created?.number)
            .onAppear { if !initialized { formIdentity = workspace.identity; title = draft.title; bodyText = draft.text; projectName = workspace.projects.first { $0.fullName == draft.project || $0.name == draft.project }?.fullName ?? ""; initialized = true } }
            .onChange(of:workspace.identity?.scope) { _,_ in accountChanged = true; error = "Hesap değişti. Bu form kapatıldı; yeni hesapta yeni bir gönderim formu aç."; created = nil; projectName = ""; labels = []; people = []; options = nil }
            .task(id:projectName) { await loadOptions() }
    }
    func loadOptions() async {
        options = nil; labels = []; people = []; guard let project else { return }
        do { let fetched = try await workspace.issueOptions(project); guard !Task.isCancelled,projectName == project.fullName else { return }; options = fetched }
        catch { if !Task.isCancelled { self.error = "Etiket/sorumlu seçenekleri alınamadı: " + error.localizedDescription } }
    }
    func send() async {
        guard !accountChanged,formIdentity == workspace.identity,let project else { return }; sending = true; error = nil; defer { sending = false }
        do { created = try await workspace.createIssue(draft:edited,project:project,labels:labels,assignees:people) }
        catch { self.error = error.localizedDescription }
    }
}

struct IssueMetadataEditor: View {
    let project: Project
    let issue: GiteaIssue
    @EnvironmentObject var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var options: IssueOptions?
    @State private var labels: Set<Int> = []
    @State private var people: Set<String> = []
    @State private var error: String?
    @State private var sending = false
    @State private var formIdentity: ConnectionIdentity?
    @State private var formRevision: UUID?
    @State private var appliedPeople: Set<String> = []
    @State private var appliedLabels: Set<Int> = []
    var body: some View {
        Form {
            SendTargetView(repository:project.fullName)
            if let options { IssueSelectionFields(options:options,labels:$labels,people:$people).disabled(sending) } else if error == nil { ProgressView("Yetkiler alınıyor") }
            if let error { Text(error).foregroundStyle(Color.waiting) }
            if options?.canManage == true { Button(sending ? "Kaydediliyor…" : "Değişiklikleri sunucuya kaydet") { Task { await save() } }.disabled(sending || formIdentity != workspace.identity || formRevision != workspace.accountRevision) }
        }.navigationTitle("Etiket ve sorumlular")
            .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Kapat") { dismiss() }.disabled(sending) } }.interactiveDismissDisabled(sending)
            .task {
                formIdentity = workspace.identity; formRevision = workspace.accountRevision
                do {
                    let fresh = try await workspace.freshIssue(project,number:issue.number)
                    labels = Set((fresh.labels ?? []).map(\.id)); people = Set((fresh.assignees ?? []).map(\.login))
                    appliedLabels = labels; appliedPeople = people
                    options = try await workspace.issueOptions(project)
                } catch { self.error = error.localizedDescription }
            }
    }
    func save() async {
        guard formIdentity == workspace.identity,formRevision == workspace.accountRevision else { error = "Hesap değişti; bu formu yeniden aç."; return }
        sending = true; defer { sending = false }; error = nil
        do {
            let path = try GiteaClient.issueRepoPath(project)+"/issues/\(issue.number)"
            let fresh = try await workspace.freshIssue(project,number:issue.number)
            guard formIdentity == workspace.identity,formRevision == workspace.accountRevision else { throw CancellationError() }
            try IssueMetadataBaseline(people:appliedPeople,labels:appliedLabels).validate(fresh)
            if people != appliedPeople {
                let _: GiteaIssue = try await workspace.issueWrite(EditIssuePeopleBody(assignees:people.sorted()),path:path,method:"PATCH",operation:"people|\(project.fullName)|\(issue.number)|\(issue.updated_at ?? "unknown")|\(people.sorted().joined(separator:","))",as:GiteaIssue.self)
                appliedPeople = people
            }
            if labels != appliedLabels {
                // A fresh read after the people write also catches changes during that request.
                let current = try await workspace.freshIssue(project,number:issue.number)
                guard formIdentity == workspace.identity,formRevision == workspace.accountRevision else { throw CancellationError() }
                try IssueMetadataBaseline(people:appliedPeople,labels:appliedLabels).validate(current)
                let _: [IssueLabel] = try await workspace.issueWrite(EditIssueLabelsBody(labels:labels.sorted()),path:path+"/labels",method:"PUT",operation:"labels|\(project.fullName)|\(issue.number)|\(issue.updated_at ?? "unknown")|\(labels.sorted())",as:[IssueLabel].self)
                appliedLabels = labels
            }
            dismiss()
        } catch { self.error = "Bazı değişiklikler kaydedilmiş olabilir; kapatıp konuyu yenile. " + error.localizedDescription }
    }
}

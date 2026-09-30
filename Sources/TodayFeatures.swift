import SwiftUI

/// Categories are evidence, not a merge decision; one PR may belong to several.
enum TodayCategory: String, CaseIterable, Identifiable {
    case mine = "Senden beklenen", others = "İnceleme bekleyen", testing = "Testleri süren", uncertain = "Diğer PR’lar"
    var id: String { rawValue }
    static func classify(_ snapshot: PRSnapshot, login: String) -> Set<TodayCategory> {
        guard snapshot.metadata.state == "open", snapshot.metadata.merged != true else { return [] }
        var result: Set<TodayCategory> = []
        if snapshot.metadata.draft != true {
            let requested = snapshot.metadata.requested_reviewers ?? []
            if requested.contains(where: { $0.login.caseInsensitiveCompare(login) == .orderedSame }) { result.insert(.mine) }
            if requested.contains(where: { $0.login.caseInsensitiveCompare(login) != .orderedSame }) || !(snapshot.metadata.requested_reviewers_teams ?? []).isEmpty { result.insert(.others) }
        }
        if snapshot.latestStatuses.contains(where: { $0.status == "pending" }) { result.insert(.testing) }
        if result.isEmpty { result.insert(.uncertain) }
        return result
    }
}
struct TodayObservation: Codable {
    let head: String
    let base: String
    let statuses: [String:String]
    let reviews: [Int:String]
    let currentApprovals: Set<Int>
    let observedAt: Date
    init(_ snapshot: PRSnapshot) {
        head = snapshot.metadata.head.sha; base = snapshot.metadata.base.sha
        statuses = Dictionary(uniqueKeysWithValues:snapshot.latestStatuses.map { ($0.context,$0.status) })
        reviews = Dictionary(snapshot.reviews.map { ($0.id,[$0.state,$0.commit_id ?? "",String($0.stale ?? true),String($0.dismissed ?? true)].joined(separator:"|")) },uniquingKeysWith: { _,new in new })
        currentApprovals = Set(snapshot.reviews.filter { $0.state.uppercased() == "APPROVED" && $0.isCurrent(snapshot.metadata.head.sha) }.map(\.id))
        observedAt = snapshot.fetchedAt
    }
    func changes(since old: TodayObservation) -> [String] {
        var changes: [String] = []
        if head != old.head { changes.append("PR commit’i değişti: \(old.head.prefix(7)) → \(head.prefix(7)).") }
        if base != old.base { changes.append("Hedef dal değişti; önceki onayların yeni birleşim için geçerliliği doğrulanmadı.") }
        for context in Set(statuses.keys).union(old.statuses.keys).sorted() where statuses[context] != old.statuses[context] {
            changes.append("\(context): \(Self.statusLabel(old.statuses[context])) → \(Self.statusLabel(statuses[context])).")
        }
        let added = Set(reviews.keys).subtracting(old.reviews.keys).count
        if added > 0 { changes.append("\(added) yeni inceleme kaydı var.") }
        let updated = reviews.keys.filter { old.reviews[$0] != nil && old.reviews[$0] != reviews[$0] }.count
        if updated > 0 { changes.append("\(updated) inceleme kaydı değişti.") }
        let stale = old.currentApprovals.subtracting(currentApprovals).count
        if stale > 0 { changes.append("\(stale) önceki onay artık güncel olarak doğrulanamıyor.") }
        return changes
    }
    static func statusLabel(_ value: String?) -> String {
        switch value { case "pending":return "sürüyor";case "success":return "geçti";case "failure","error":return "başarısız";case nil:return "bildirilmemiş";default:return "bilinmiyor" }
    }
}
struct TodayBaseline: Codable {
    var records: [String:TodayObservation] = [:]
    mutating func observe(key: String, snapshot: PRSnapshot, cached: Bool, acknowledge: Bool = false) -> [String] {
        // A fallback/cache or failed request never mutates the baseline or produces changes.
        guard !cached else { return [] }
        let observation = TodayObservation(snapshot)
        let differences = records[key].map { observation.changes(since:$0) } ?? []
        if records[key] == nil || acknowledge { records[key] = observation }
        if records.count > 100 {
            let keep = Set(records.sorted { $0.value.observedAt > $1.value.observedAt }.prefix(100).map(\.key))
            records = records.filter { keep.contains($0.key) }
        }
        return differences
    }
}
struct TodayRow: Identifiable {
    let pull: PullRequest
    let result: ReadResult<PRSnapshot>
    let changes: [String]
    var id: String { pull.project.fullName + "#" + String(pull.id) }
}

enum WorkflowTone {
    case review, waiting, unknown, success, failure
    func color(accent: Color) -> Color {
        switch self { case .review:return accent;case .waiting:return .waiting;case .unknown:return .secondary;case .success:return .success;case .failure:return .red }
    }
}
struct WorkflowSignal: View {
    let title: String
    let symbol: String
    let tone: WorkflowTone
    @EnvironmentObject var appearance: Appearance
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading,spacing:8)) : AnyLayout(HStackLayout(spacing:8))
        layout {
            Image(systemName:symbol).accessibilityHidden(true)
            Text(title).fixedSize(horizontal:false,vertical:true)
        }.font(.subheadline.weight(.semibold))
            .foregroundStyle(tone.color(accent:appearance.accent(scheme)))
    }
}
struct TodayAction {
    let title: String
    let symbol: String
    let tone: WorkflowTone
    init(_ snapshot: PRSnapshot,login: String) {
        let categories = TodayCategory.classify(snapshot,login:login)
        if snapshot.metadata.merged == true { title = "Birleştirilmiş"; symbol = "arrow.triangle.merge";tone = .unknown }
        else if snapshot.metadata.state == "closed" { title = "Kapatılmış";symbol = "xmark.circle";tone = .unknown }
        else if snapshot.metadata.draft == true { title = "Taslak PR";symbol = "pencil.circle";tone = .unknown }
        else if categories.contains(.mine) { title = "İncelemen bekleniyor";symbol = "person.crop.circle.badge.clock";tone = .review }
        else if categories.contains(.others) { title = "Başka inceleme bekleniyor";symbol = "person.2";tone = .review }
        else if snapshot.latestStatuses.contains(where:{ ["failure","error"].contains($0.status) }) { title = "Başarısız test var";symbol = "exclamationmark.circle";tone = .failure }
        else if categories.contains(.testing) { title = "Testler sürüyor";symbol = "hourglass";tone = .waiting }
        else { title = "Sonraki adım belirsiz";symbol = "questionmark.circle";tone = .unknown }
    }
}

struct RemoteTodayView: View {
    @EnvironmentObject var workspace: Workspace
    @EnvironmentObject var appearance: Appearance
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var baselineWarning: String?
    @State private var selected: Set<String> = []
    @State private var rows: [TodayRow] = []
    @State private var notices: [String] = []
    @State private var baseline = TodayBaseline()
    @State private var loading = false
    @State private var choosing = false
    @State private var category: TodayCategory? = nil
    @State private var runID = UUID()
    @State private var coverageExpanded = false
    @State private var changesExpanded = false
    @State private var lists: [String: ReadResult<PullListSnapshot>] = [:]
    @State private var pendingDetails: [PullRequest] = []
    @State private var detailFailures = 0
    private let baselineKey = "today-observations-v1"
    var selectionKey: String { "today-projects-" + workspace.cache.digest(workspace.identity?.scope ?? "none") }
    var taskKey: String { (workspace.identity?.scope ?? "none") + "|" + String(workspace.offlineOnly) }
    var body: some View {
        VStack(alignment:.leading,spacing:appearance.layout.density.gap) {
            HStack(alignment:.firstTextBaseline) {
                Text("İş kuyruğun").font(.title2.bold()).accessibilityIdentifier("todayQueueTitle")
                Spacer()
                ContextInfoButton(title:"Kuyruğun kaynağı",details:"Seçili projelerdeki açık PR’lar, açık inceleme istekleri ve commit test durumları okunur. Uyarı varsa sayılar yalnız okunabilen kayıtlara aittir.")
                Button { Task { await load() } } label: { Image(systemName:"arrow.clockwise").frame(width:44,height:44) }
                    .buttonStyle(.plain).disabled(loading || selected.isEmpty).accessibilityLabel("Kuyruğu yenile")
            }
            if appearance.layout.showDailySummary && !loading && !rows.isEmpty {
                Text(dailySummary).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("todaySummary")
            }
            HStack(spacing:12) {
                Button { choosing = true } label: { Label("\(selected.count) proje",systemImage:"folder") }.accessibilityLabel("Projeler").accessibilityIdentifier("todayProjects")
                Spacer()
                Menu {
                    Button("Tümü") { category = nil }
                    ForEach(TodayCategory.allCases) { item in Button(item.rawValue) { category = item } }
                } label: { Label(category?.rawValue ?? "Tümü",systemImage:"line.3.horizontal.decrease") }.accessibilityIdentifier("todayFilter")
            }.font(.subheadline).buttonStyle(.plain).padding(.bottom,4)
            if loading { ProgressView("Seçili projeler okunuyor…").font(.footnote) }
            if !pendingDetails.isEmpty || detailFailures > 0 || lists.values.contains(where: { $0.value.hasMore }) {
                DisclosureGroup(isExpanded:$coverageExpanded) {
                    VStack(alignment:.leading,spacing:12) {
                        if !pendingDetails.isEmpty || detailFailures > 0 {
                            Text("\(pendingDetails.count + detailFailures) yüklenen PR henüz doğrulanmadı. Bu PR’lar hazır veya sağlıklı sayılmıyor.").font(.footnote).foregroundStyle(.secondary)
                        }
                        if !pendingDetails.isEmpty { Button("Sonraki 10 PR’ı incele") { Task { await details(run:runID) } }.buttonStyle(.bordered).disabled(loading).accessibilityIdentifier("moreTodayDetails") }
                        if lists.values.contains(where: { $0.value.hasMore }) {
                            Text("PR listelerinde okunmamış sayfalar var; toplam açık PR sayısı henüz bilinmiyor.").font(.footnote).foregroundStyle(.secondary)
                            Button("Sonraki PR sayfasını getir") { Task { await moreList() } }.buttonStyle(.bordered).disabled(loading || workspace.offlineOnly).accessibilityIdentifier("moreTodayPulls")
                        }
                    }.padding(.top,10)
                } label: {
                    Text("\(rows.count) incelendi · \(pendingDetails.count + detailFailures) bekliyor" + (lists.values.contains(where: { $0.value.hasMore }) ? " · Liste eksik" : ""))
                        .font(.caption).foregroundStyle(.secondary).frame(minHeight:28,alignment:.leading).contentShape(Rectangle())
                        .accessibilityIdentifier("todayCoverageLabel")
                }.disclosureGroupStyle(QuietDisclosureStyle(animation:appearance.animation(reduced:reduced))).tint(.primary).accessibilityElement(children:.contain).padding(10).background(Color.surface,in:RoundedRectangle(cornerRadius:14))
            }
            ForEach(Array(notices.enumerated()),id:\.offset) { _,notice in Text(notice).font(.footnote).foregroundStyle(Color.waiting) }
            if selected.isEmpty {
                Text("Projeler düğmesinden takip edeceğin depoları seç veya favorilerini kullan.").foregroundStyle(.secondary)
            } else if !loading && rows.isEmpty {
                Text(notices.isEmpty ? "Seçili projelerde açık PR yok." : "Kuyruk tamamen doğrulanamadı. Yukarıdaki uyarıları incele.").foregroundStyle(.secondary)
            }
            if appearance.layout.showChanges && rows.contains(where: { !$0.changes.isEmpty }) { changesSection }
            ForEach(visibleRows) { row in
                Surface {
                    let cardLayout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading,spacing:8)) : AnyLayout(HStackLayout(alignment:.top,spacing:6))
                    cardLayout {
                        NavigationLink { PullDestination(pull:row.pull) } label: {
                            VStack(alignment:.leading,spacing:10) {
                                Text(row.pull.project.fullName + " · #\(row.pull.id)").font(.caption).foregroundStyle(appearance.projectAccent(row.pull.project,scope:workspace.identity?.scope,scheme:scheme))
                                Text(row.result.value.metadata.title).font(.headline).foregroundStyle(.primary)
                                let action = TodayAction(row.result.value,login:workspace.identity?.login ?? "")
                                WorkflowSignal(title:action.title,symbol:action.symbol,tone:row.result.cached ? .unknown : action.tone)
                                if action.title != "Testler sürüyor",action.title != "Başarısız test var" {
                                    let tests = row.result.value.latestStatuses
                                    if tests.contains(where:{ ["failure","error"].contains($0.status) }) {
                                        WorkflowSignal(title:"Başarısız test var",symbol:"exclamationmark.circle",tone:row.result.cached ? .unknown : .failure)
                                    } else if tests.contains(where:{ $0.status == "pending" }) {
                                        WorkflowSignal(title:"Testler sürüyor",symbol:"hourglass",tone:row.result.cached ? .unknown : .waiting)
                                    }
                                }
                                if row.result.cached { Label("Son kayıt · Güncel olmayabilir",systemImage:"wifi.slash").font(.caption).foregroundStyle(Color.waiting) }
                            }.frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        ContextInfoButton(title:"PR #\(row.pull.id) durumunun kaynağı",details:evidence(row.result.value) + "\n\nSon alınma: " + row.result.value.fetchedAt.formatted(date:.abbreviated,time:.shortened) + (row.result.note.map { "\n" + $0 } ?? ""))
                            .accessibilityIdentifier("todaySource-\(row.pull.id)")
                    }
                }
            }
            if appearance.layout.showChanges && !rows.isEmpty && !rows.contains(where: { !$0.changes.isEmpty }) { changesSection }
            if !rows.isEmpty,let category,!rows.contains(where: { TodayCategory.classify($0.result.value,login:workspace.identity?.login ?? "").contains(category) }) {
                Text("Bu filtrede PR yok.").foregroundStyle(.secondary)
            }
        }
        .task(id:taskKey) { await initialize() }
        .onChange(of:appearance.layout.queueFilter) { _,value in category = value.category }
        .sheet(isPresented:$choosing) { projectSheet }
    }
    var visibleRows: [TodayRow] {
        let login = workspace.identity?.login ?? ""
        return rows.filter { row in category.map { TodayCategory.classify(row.result.value,login:workspace.identity?.login ?? "").contains($0) } ?? true }
            .sorted { left,right in
                func rank(_ row: TodayRow) -> Int {
                    let c = TodayCategory.classify(row.result.value,login:login)
                    return c.contains(.mine) ? 0 : c.contains(.testing) ? 1 : c.contains(.others) ? 2 : 3
                }
                return rank(left) == rank(right) ? left.id < right.id : rank(left) < rank(right)
            }
    }
    var dailySummary: String {
        let categories = rows.map { TodayCategory.classify($0.result.value,login:workspace.identity?.login ?? "") }
        let mine = categories.filter { $0.contains(.mine) }.count
        let testing = categories.filter { $0.contains(.testing) }.count
        let others = categories.filter { $0.contains(.others) }.count
        var parts: [String] = []
        if mine > 0 { parts.append("\(mine) inceleme senden bekleniyor") }
        if testing > 0 { parts.append("\(testing) PR testte") }
        if parts.isEmpty { parts.append(others > 0 ? "\(others) PR inceleme bekliyor" : "\(rows.count) PR · Sonraki adım belirsiz") }
        let prefix = rows.contains(where: { $0.result.cached }) ? "Son kayıtlarda: " : (!notices.isEmpty || !pendingDetails.isEmpty || detailFailures > 0 || lists.values.contains(where: { $0.value.hasMore })) ? "Okunabilenlerde: " : ""
        return prefix + parts.joined(separator:" · ")
    }
    var changeExplanation: String { "İlk başarılı okuma başlangıç kaydıdır. Sonrasında ‘Gördüm’ dediğin kayıtla karşılaştırılır; ilk okumada geçmiş üretilmez. Cihazda en son 100 PR’ın başlangıç kaydı tutulur; kapsam dışına çıkan kaydın sonraki okuması yeni başlangıçtır. Yenileme hataları değişiklik sayılmaz." }
    var changesSection: some View {
        let changed = rows.filter { !$0.changes.isEmpty }
        return VStack(alignment:.leading,spacing:10) {
            if changed.isEmpty {
                HStack(spacing:4) {
                    Text(rows.allSatisfy { $0.result.cached } ? "Karşılaştırma için güncel kayıt bekleniyor." : "Doğrulanmış yeni değişiklik yok.").font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("todayNoChanges")
                    Spacer(minLength:0)
                    ContextInfoButton(title:"Değişikliklerin kaynağı",details:changeExplanation)
                }
            } else {
                DisclosureGroup(isExpanded:$changesExpanded) {
                    VStack(alignment:.leading,spacing:14) {
                        ForEach(changed) { row in
                            NavigationLink { PullDestination(pull:row.pull) } label: {
                                VStack(alignment:.leading,spacing:5) {
                                    Text("\(row.pull.project.name) #\(row.pull.id)").font(.headline)
                                    ForEach(row.changes,id:\.self) { Text($0).font(.subheadline) }
                                }.frame(maxWidth:.infinity,alignment:.leading)
                            }.buttonStyle(.plain)
                        }
                        HStack {
                            Button("Değişiklikleri gördüm") { acknowledge() }.buttonStyle(.bordered).accessibilityIdentifier("todayAcknowledge")
                            Spacer()
                            ContextInfoButton(title:"Değişikliklerin kaynağı",details:changeExplanation)
                        }
                    }.padding(.top,10)
                } label: {
                    Text("Ben yokken ne oldu? · \(changed.count) PR").font(.subheadline.weight(.medium))
                        .frame(minHeight:32,alignment:.leading).contentShape(Rectangle())
                        .accessibilityIdentifier("todayChangesTitle")
                }.disclosureGroupStyle(QuietDisclosureStyle(animation:appearance.animation(reduced:reduced))).tint(.primary)
            }
        }
    }
    var projectSheet: some View {
        NavigationStack {
            List {
                Button("Favorilerimi seç") { selected = Set(workspace.projects.filter { workspace.favorites.contains($0.fullName) }.map(\.fullName)) }
                ForEach(workspace.projects) { project in
                    Toggle(project.fullName,isOn:Binding(get:{ selected.contains(project.fullName) },set:{ on in if on { selected.insert(project.fullName) } else { selected.remove(project.fullName) } }))
                }
            }.navigationTitle("Bugün için projeler")
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Uygula") { workspace.defaults.set(Array(selected),forKey:selectionKey); choosing = false; Task { await load() } } } }
        }.interactiveDismissDisabled()
    }
    func evidence(_ snapshot: PRSnapshot) -> String {
        if snapshot.metadata.draft == true { return "Taslak PR · İncelemeye hazır olduğu varsayılmaz." }
        var lines: [String] = []
        if !snapshot.requested.isEmpty { lines.append("İnceleme istenen: " + snapshot.requested.joined(separator:", ")) }
        if snapshot.latestStatuses.contains(where:{ $0.status == "pending" }) { lines.append("Commit testleri sürüyor.") }
        if lines.isEmpty { lines.append("Sıradaki kişi bilinmiyor; açık inceleme isteği yok.") }
        if !snapshot.assignees.isEmpty { lines.append("Atanmış: " + snapshot.assignees.joined(separator:", ") + " (sıradaki kişi olduğu anlamına gelmez).") }
        let labels = (snapshot.metadata.labels ?? []).map(\.name)
        if !labels.isEmpty { lines.append("Etiketler: " + labels.joined(separator:", ") + ". Etiket, açık inceleme isteği veya güncel hazır olma kanıtı değildir.") }
        return lines.joined(separator:"\n")
    }
    @MainActor func initialize() async {
        category = appearance.layout.queueFilter.category
        rows = []; notices = []; baseline = TodayBaseline(); baselineWarning = nil
        selected = Set(workspace.defaults.stringArray(forKey:selectionKey) ?? workspace.projects.filter { workspace.favorites.contains($0.fullName) }.map(\.fullName))
        selected.formIntersection(Set(workspace.projects.map(\.fullName)))
        if let identity = workspace.identity {
            do { baseline = try workspace.cache.load(TodayBaseline.self,key:baselineKey,identity:identity) ?? TodayBaseline() }
            catch { baselineWarning = "Önceki karşılaştırma kaydı okunamadı; bu okumada yeni başlangıç kaydı oluşturulacak, geçmiş çıkarımı yapılmayacak." }
        }
        await load()
    }
    @MainActor func load() async {
        let run = UUID(); runID = run
        guard let identity = workspace.identity else { return }
        loading = true; rows = []; lists = [:]; pendingDetails = []; detailFailures = 0; notices = baselineWarning.map { [$0] } ?? []
        defer { if runID == run { loading = false } }
        let projects = workspace.projects.filter { selected.contains($0.fullName) }
        if projects.count > 20 { notices.append("Bu yenilemede ilk 20 proje taranıyor. Kapsamı daraltarak diğerlerini görebilirsin.") }
        for project in projects.prefix(20) {
            do {
                let list = try await workspace.loadPullList(project)
                guard runID == run,workspace.identity == identity,!Task.isCancelled else { return }
                lists[project.fullName] = list; pendingDetails += list.value.pulls
                if let note = list.note { notices.append(project.name + ": " + note) }
            } catch is CancellationError { return }
            catch { guard runID == run,workspace.identity == identity else { return }; notices.append(project.name + ": " + error.localizedDescription) }
        }
        guard runID == run,workspace.identity == identity,!Task.isCancelled else { return }
        loading = false
        await details(run:run)
    }
    @MainActor func moreList() async {
        let run = runID
        guard let identity = workspace.identity,let project = workspace.projects.first(where: { lists[$0.fullName]?.value.hasMore == true }),let previous = lists[project.fullName] else { return }
        loading = true; defer { if runID == run { loading = false } }
        do {
            let list = try await workspace.loadMorePulls(project,previous:previous.value,previousCached:previous.cached)
            guard runID == run,workspace.identity == identity,!Task.isCancelled else { return }
            let known = Set(previous.value.pulls.map(\.id))
            pendingDetails += list.value.pulls.filter { !known.contains($0.id) }
            lists[project.fullName] = list
        } catch { if runID == run,workspace.identity == identity { notices.append("Sonraki sayfa alınamadı; mevcut liste korundu: " + error.localizedDescription) } }
    }
    @MainActor func details(run: UUID) async {
        guard let identity = workspace.identity,runID == run,!loading else { return }
        loading = true; defer { if runID == run { loading = false } }
        let batch = Array(pendingDetails.prefix(10))
        for pull in batch {
            do {
                let response = try await workspace.loadSnapshot(pull)
                guard runID == run,workspace.identity == identity,!Task.isCancelled else { return }
                let listCached = lists[pull.project.fullName]?.cached == true
                let result = ReadResult(value:response.value,cached:response.cached || listCached,note:response.note)
                let key = pull.project.fullName + "#" + String(pull.id)
                let changes = baseline.observe(key:key,snapshot:result.value,cached:result.cached)
                rows.append(TodayRow(pull:pull,result:result,changes:changes))
                if let note = response.note { notices.append("\(pull.project.name) #\(pull.id): " + note) }
            } catch is CancellationError { return }
            catch {
                guard runID == run,workspace.identity == identity,!Task.isCancelled else { return }
                detailFailures += 1; notices.append("\(pull.project.name) #\(pull.id) doğrulanmadı: " + error.localizedDescription)
            }
            pendingDetails.removeAll { $0.project.fullName == pull.project.fullName && $0.id == pull.id }
        }
        if !workspace.offlineOnly { saveBaseline(identity) }
    }
    @MainActor func acknowledge() {
        guard let identity = workspace.identity else { return }
        var next = baseline
        for row in rows { _ = next.observe(key:row.id,snapshot:row.result.value,cached:row.result.cached,acknowledge:true) }
        do {
            try workspace.cache.save(next,key:baselineKey,identity:identity)
            withAnimation(appearance.animation(reduced:reduced)) {
                baseline = next; rows = rows.map { TodayRow(pull:$0.pull,result:$0.result,changes:[]) }
            }
            appearance.tap()
        } catch { notices.append("Görüldü bilgisi kaydedilemedi; önceki karşılaştırma korunuyor.") }
    }
    @MainActor func saveBaseline(_ identity: ConnectionIdentity) {
        do { try workspace.cache.save(baseline,key:baselineKey,identity:identity) }
        catch { notices.append("Karşılaştırma kaydı cihazda saklanamadı: " + error.localizedDescription) }
    }
}

import SwiftUI

@main struct KisiselGiteaApp: App {
    @StateObject private var appearance = Appearance(defaults:Appearance.appDefaults)
    @StateObject private var workspace = Workspace()
    @StateObject private var access = AppAccess(defaults:Appearance.appDefaults)
    @StateObject private var renewal = SigningRenewal(defaults:Appearance.appDefaults)
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            AppPrivacyGate { RootView() }.environmentObject(appearance).environmentObject(workspace).environmentObject(access)
                .environmentObject(renewal)
                .preferredColorScheme(appearance.scheme)
                .fontDesign(appearance.layout.textStyle.design)
                .task { await renewal.refresh() }
                .onChange(of:scenePhase) { _,phase in if phase == .active { Task { await renewal.refresh() } } }
        }
    }
}
struct RootView: View {
    @EnvironmentObject var appearance: Appearance
    @Environment(\.colorScheme) var scheme
    @EnvironmentObject var workspace: Workspace
    @State private var selected: AppPage = .today
    @State private var opened = false
    var body: some View {
        if workspace.requiresOnboarding { WelcomeView() } else { tabs }
    }
    var tabs: some View {
        TabView(selection:$selected) {
            Tab(value:AppPage.today) { NavigationStack { TodayView() } } label: { Label { Text("Bugün") } icon: { tabImage(0) } }
            Tab(value:AppPage.projects) { NavigationStack { ProjectsView() } } label: { Label { Text("Projeler") } icon: { tabImage(1) } }
            Tab(value:AppPage.inbox) { NavigationStack { InboxView() } } label: { Label { Text("Gelen kutusu") } icon: { tabImage(2) } }
            Tab(value:AppPage.profile) { NavigationStack { ProfileView() } } label: { Label { Text("Profil") } icon: { tabImage(3) } }
        }
        .id((workspace.identity?.scope ?? "demo") + String(workspace.offlineOnly))
        .tint(appearance.accent(scheme))
        .onAppear { if !opened { selected = appearance.layout.startPage; opened = true } }
        .onChange(of:selected) { _,_ in appearance.tap() }
    }
}
struct PageTools: ToolbarContent {
    @Binding var appearanceShown: Bool
    @Binding var ideaShown: Bool
    var body: some ToolbarContent {
        ToolbarItem(placement:.topBarTrailing) {
            Button("Kişiselleştir",systemImage:"slider.horizontal.3") { appearanceShown = true }.accessibilityIdentifier("appearanceButton")
        }
        ToolbarItem(placement:.topBarTrailing) {
            Button("Yeni fikir",systemImage:"plus") { ideaShown = true }.accessibilityIdentifier("ideaButton")
        }
    }
}
struct DemoCaption: View {
    @EnvironmentObject var workspace: Workspace
    var body: some View {
        HStack(spacing:6) {
            Circle().fill(workspace.live ? Color.success : Color.secondary).frame(width:6,height:6)
            Text(workspace.isFixture ? "Önizleme · Örnek API" : workspace.live ? (workspace.offlineOnly ? "Çevrimdışı · Saklanmış kayıt" : "Bağlı · Kişisel alan") : "Önizleme · Örnek veriler")
        }.font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("dataMode")
    }
}
struct TodayView: View {
    @EnvironmentObject var workspace: Workspace
    @EnvironmentObject var appearance: Appearance
    @Environment(\.colorScheme) var scheme
    @State var appearanceShown = false
    @State var ideaShown = false
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:appearance.layout.density.gap + 8) {
                DemoCaption()
                SigningExpiryNotice()
                ForEach(appearance.layout.visibleSections) { section in
                    switch section {
                    case .queue: queueSection
                    case .ideas: ideasSection
                    case .favorites: favoritesSection
                    }
                }
                if appearance.layout.visibleSections.isEmpty {
                    ContentUnavailableView {
                        Label("Bugün sana ait",systemImage:"slider.horizontal.3")
                    } description: { Text("Görmek istediğin bölümleri kişiselleştirmeden açabilirsin.") } actions: {
                        Button("Bölümleri seç") { appearanceShown = true }.buttonStyle(.glass)
                    }
                }
            }.padding(.horizontal,22).padding(.top,6).padding(.bottom,30)
        }
        .background(Color.canvas).navigationTitle("Bugün").navigationBarTitleDisplayMode(.inline)
        .toolbar { PageTools(appearanceShown:$appearanceShown,ideaShown:$ideaShown) }
        .sheet(isPresented:$appearanceShown) { AppearanceSheet() }
        .sheet(isPresented:$ideaShown) { IdeaSheet() }
    }
    @ViewBuilder var queueSection: some View {
        if workspace.live { RemoteTodayView() }
        else {
            VStack(alignment:.leading,spacing:appearance.layout.density.gap) {
                HStack { Text("Sıra kimde?").font(.title2.bold()); Spacer(); Text("2").font(.callout.weight(.medium)).foregroundStyle(.secondary) }
                ForEach(workspace.pulls) { pull in
                    NavigationLink { PullDestination(pull:pull) } label: { PullCard(pull:pull) }.buttonStyle(.plain)
                }
            }
            VStack(alignment:.leading,spacing:14) {
                Text("Son hareketler").font(.title2.bold())
                ActivityRows()
            }
        }
    }
    @ViewBuilder var ideasSection: some View {
        if !workspace.drafts.isEmpty || !appearance.layout.visibleSections.contains(.queue) {
            VStack(alignment:.leading,spacing:appearance.layout.density.gap) {
                HStack { Text("Fikir defterin").font(.title2.bold()).accessibilityIdentifier("todayIdeasTitle"); Spacer(); Text("Cihazında").font(.caption).foregroundStyle(.secondary) }
                ForEach(workspace.drafts.prefix(appearance.layout.normalized().ideaCount)) { draft in
                    NavigationLink { DraftDetail(draft:draft) } label: {
                        Surface { HStack { MarkView(kind:5).foregroundStyle(appearance.accent(scheme)); VStack(alignment:.leading,spacing:5) { Text(draft.title).font(.headline); Text(draft.project).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName:"chevron.right").font(.caption).foregroundStyle(.secondary) } }
                    }.buttonStyle(.plain)
                }
                if workspace.drafts.isEmpty { Button("İlk fikrini yaz") { ideaShown = true }.buttonStyle(.glass) }
            }
        }
    }
    var favoritesSection: some View {
        let projects = appearance.layout.sortedProjects(workspace.projects.filter { workspace.favorites.contains($0.fullName) },favorites:workspace.favorites)
        return VStack(alignment:.leading,spacing:appearance.layout.density.gap) {
            Text("Favori projelerin").font(.title2.bold()).accessibilityIdentifier("todayFavoritesTitle")
            if projects.isEmpty { Text("Projeler’de yıldız verdiğin depolar burada görünür.").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(projects) { project in
                NavigationLink { ProjectDetail(project:project) } label: {
                    Surface {
                        HStack(spacing:12) {
                            ProjectMark(kind:project.mark,color:appearance.projectAccent(project,scope:workspace.identity?.scope,scheme:scheme))
                            VStack(alignment:.leading,spacing:4) {
                                Text(project.name).font(.headline).foregroundStyle(.primary)
                                Text(project.fullName).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(); Image(systemName:"chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.buttonStyle(.plain)
            }
        }
    }
}
struct PullCard: View {
    @EnvironmentObject var workspace: Workspace
    let pull: PullRequest
    @EnvironmentObject var appearance: Appearance
    @Environment(\.colorScheme) var scheme
    var body: some View {
        Surface {
            VStack(alignment:.leading,spacing:18) {
                HStack(spacing:12) {
                    ProjectMark(kind:pull.project.mark,color:appearance.projectAccent(pull.project,scope:workspace.identity?.scope,scheme:scheme))
                    VStack(alignment:.leading,spacing:5) {
                        Text(pull.project.name).font(.subheadline.weight(.semibold))
                        Text("#\(pull.id) · \(pull.author)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(); Image(systemName:"chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
                Text(pull.title).font(.title3.weight(.semibold)).foregroundStyle(.primary).fixedSize(horizontal:false,vertical:true)
                Text(pull.nextActor).font(.subheadline.weight(.semibold)).foregroundStyle(appearance.accent(scheme))
                HStack {
                    StatusPill(text:!pull.isDemo ? "Açık PR" : (pull.approved ? "Birleştirmeye hazır" : "Görüşün bekleniyor"),color:!pull.isDemo ? .secondary : (pull.approved ? .success : .waiting))
                    Spacer()

                }
                if pull.checksPassed { Label("Testler geçti",systemImage:"checkmark.circle.fill").font(.caption).foregroundStyle(Color.success) }
            }
        }
    }
}
struct ActivityRows: View {
    var titles = ["Claude incelemeyi tamamladı", "Testler başarıyla geçti", "Yeni fikir kaydedildi"]
    var subtitles = ["Görev Takibi · PR #179", "Görev Takibi · 111 kontrol", "Not Defteri · Cihazında"]
    var body: some View {
        Surface {
            VStack(spacing:22) {
                ForEach(0..<3) { i in
                    HStack(alignment:.top,spacing:14) {
                        MarkView(kind:[2,0,5][i],size:24).foregroundStyle(i == 1 ? Color.success : Color.secondary).frame(width:34,height:34).background(.primary.opacity(0.05),in:Circle())
                        VStack(alignment:.leading,spacing:6) { Text(titles[i]).font(.subheadline.weight(.medium)); Text(subtitles[i]).font(.caption).foregroundStyle(.secondary) }
                        Spacer(minLength:2); Text(["2 sa", "4 sa", "Dün"][i]).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
}
struct ProjectsView: View {
    @EnvironmentObject var workspace: Workspace
    @EnvironmentObject var appearance: Appearance
    @Environment(\.colorScheme) var scheme
    @Environment(\.accessibilityReduceMotion) var reduced
    @Namespace private var projectTransition
    @State private var query = ""
    @State private var favoritesOnly = false
    @State private var appearanceShown = false
    @State private var ideaShown = false
    var filtered: [Project] {
        appearance.layout.sortedProjects(workspace.projects.filter { (!favoritesOnly || workspace.favorites.contains($0.fullName)) && (query.isEmpty || $0.name.localizedStandardContains(query) || $0.fullName.localizedStandardContains(query)) },favorites:workspace.favorites)
    }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:appearance.layout.density.gap) {
                DemoCaption()
                Picker("Proje filtresi",selection:$favoritesOnly) { Text("Tümü").tag(false); Text("Favoriler").tag(true) }.pickerStyle(.segmented).padding(.vertical,6)
                if filtered.isEmpty { ContentUnavailableView.search(text:query) }
                ForEach(filtered) { project in
                    Surface {
                        VStack(alignment:.leading,spacing:15) {
                            HStack(alignment:.top,spacing:13) {
                                NavigationLink { ProjectDetail(project:project).modifier(ProjectNavigationMotion(id:project.id,namespace:projectTransition,enabled:appearance.motion && !reduced)) } label: {
                                    HStack(spacing:13) {
                                        ProjectMark(kind:project.mark,color:appearance.projectAccent(project,scope:workspace.identity?.scope,scheme:scheme))
                                        VStack(alignment:.leading,spacing:6) {
                                            Text(project.name).font(.headline).foregroundStyle(.primary)
                                            if appearance.layout.showProjectDescriptions { Text(project.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
                                        }
                                    }.frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle()).matchedTransitionSource(id:project.id,in:projectTransition)
                                }.buttonStyle(.plain)
                                Button {
                                    withAnimation(appearance.animation(reduced:reduced)) { workspace.toggleFavorite(project) }; appearance.tap()
                                } label: {
                                    Image(systemName:workspace.favorites.contains(project.fullName) ? "star.fill" : "star").font(.body).foregroundStyle(workspace.favorites.contains(project.fullName) ? Color.waiting : Color.secondary).frame(width:44,height:44)
                                }.buttonStyle(.plain).accessibilityLabel("\(project.name) favori").accessibilityValue(workspace.favorites.contains(project.fullName) ? "Evet" : "Hayır")
                            }
                            HStack(spacing:12) {
                                Text(project.language).font(.caption.weight(.medium))
                                Circle().frame(width:3,height:3)
                                Text("\(project.issues) açık konu").font(.caption)
                                Spacer()
                                if project.isPrivate { Image(systemName:"lock").font(.caption).accessibilityLabel("Özel depo") }
                            }.foregroundStyle(.secondary)
                        }
                    }
                }
            }.padding(.horizontal,22).padding(.bottom,25)
        }.background(Color.canvas).navigationTitle("Projeler").navigationBarTitleDisplayMode(.inline)
            .searchable(text:$query,prompt:"Proje ara")
            .animation(appearance.animation(reduced:reduced),value:favoritesOnly)
            .toolbar { PageTools(appearanceShown:$appearanceShown,ideaShown:$ideaShown) }
            .sheet(isPresented:$appearanceShown) { AppearanceSheet() }
            .sheet(isPresented:$ideaShown) { IdeaSheet() }
            .onAppear { favoritesOnly = appearance.layout.favoritesOnly }
            .onChange(of:appearance.layout.favoritesOnly) { _,value in favoritesOnly = value }
    }
}
struct ProjectDetail: View {
    let project: Project
    @EnvironmentObject var workspace: Workspace
    @State private var informationExpanded = false
    @State private var pulls: [PullRequest] = []
    @State private var listResult: ReadResult<PullListSnapshot>?
    @State private var ideaShown = false
    @State private var loading = true
    @State private var error: String?
    @State private var loadingMore = false
    @State private var runID = UUID()
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                Text(project.summary).foregroundStyle(.secondary)
                DisclosureGroup(isExpanded:$informationExpanded) {
                    VStack(alignment:.leading,spacing:12) {
                        Text(project.fullName).font(.subheadline.monospaced()).textSelection(.enabled)
                        Label(project.isPrivate ? "Özel depo" : "Herkese açık depo",systemImage:project.isPrivate ? "lock" : "globe").font(.subheadline).foregroundStyle(.secondary)
                        if !project.language.isEmpty { Text("Dil: " + project.language).font(.subheadline).foregroundStyle(.secondary) }
                        Divider()
                        ProjectAccentPicker(project:project)
                    }.padding(.top,8).padding(.bottom,6)
                } label: {
                    Label("Proje bilgileri",systemImage:"info.circle").font(.subheadline.weight(.semibold)).accessibilityIdentifier("projectInformation")
                }.disclosureGroupStyle(QuietDisclosureStyle()).accessibilityElement(children:.contain)
                if workspace.live { NavigationLink { IssueListView(project:project) } label: { Label("Konular",systemImage:"bubble.left.and.bubble.right") }.buttonStyle(.glass).accessibilityIdentifier("projectIssues") }
                Text("Açık PR’lar").font(.title2.bold())
                if let listResult { FreshnessView(date:listResult.value.fetchedAt,cached:listResult.cached,note:listResult.note) }
                if loading { ProgressView("Yükleniyor").frame(maxWidth:.infinity) }
                else if let error { Text(error).foregroundStyle(.secondary); if pulls.isEmpty { Button("Yeniden dene") { Task { await load() } }.buttonStyle(.glass) } }
                else if pulls.isEmpty { ContentUnavailableView("Açık PR yok",systemImage:"checkmark.circle",description:Text("Bu projede bekleyen bir PR bulunmuyor.")) }
                ForEach(pulls) { pull in NavigationLink { PullDestination(pull:pull) } label: { PullCard(pull:pull) }.buttonStyle(.plain) }
                if let listResult {
                    Text("\(pulls.count) PR yüklendi · " + (listResult.value.hasMore ? "Daha fazlası bulunabilir" : "Liste sonuna ulaşıldı")).font(.footnote).foregroundStyle(.secondary)
                    if listResult.value.hasMore {
                        Button(loadingMore ? "Yükleniyor…" : "Daha fazla yükle") { Task { await more() } }.buttonStyle(.glass).disabled(loadingMore || loading || workspace.offlineOnly).accessibilityIdentifier("morePulls")
                    }
                }
            }.padding(22)
        }.background(Color.canvas).navigationTitle(project.name).navigationBarTitleDisplayMode(.inline).task(id:workspace.identity?.scope) { await load() }.refreshable { await load() }
        .toolbar { Button("Yeni fikir",systemImage:"plus") { ideaShown = true } }
        .sheet(isPresented:$ideaShown) { IdeaSheet(initialProject:project.fullName) }
    }
    func load() async {
        let run = UUID(); runID = run
        loading = true; loadingMore = false; error = nil; defer { if runID == run { loading = false } }
        do {
            if workspace.live { let value = try await workspace.loadPullList(project); guard runID == run,!Task.isCancelled else { return }; listResult = value; pulls = value.value.pulls }
            else { pulls = try await workspace.loadPulls(project) }
        } catch { if runID == run,!Task.isCancelled { self.error = error.localizedDescription } }
    }
    func more() async {
        guard let previous = listResult else { return }; let run = runID
        loadingMore = true; error = nil; defer { if runID == run { loadingMore = false } }
        do { let value = try await workspace.loadMorePulls(project,previous:previous.value,previousCached:previous.cached); guard runID == run,!Task.isCancelled else { return }; listResult = value; pulls = value.value.pulls }
        catch { if runID == run,!Task.isCancelled { self.error = error.localizedDescription } }
    }
}
struct PullDetail: View {
    @EnvironmentObject var appearance: Appearance
    @Environment(\.colorScheme) var scheme
    let pull: PullRequest
    @State private var reviewShown = false
    @State private var diffShown = false
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                Text("PR #\(pull.id)").font(.subheadline).foregroundStyle(.secondary)
                Text(pull.title).font(.largeTitle.bold()).fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("pullTitle")
                if pull.isDemo { StatusPill(text:"Örnek PR",color:.secondary) }
                Surface {
                    VStack(alignment:.leading,spacing:14) {
                        Text("Sıra kimde?").font(.caption).foregroundStyle(.secondary)
                        Text(pull.nextActor).font(.title3.bold())
                        Text(pull.nextReason).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment:.leading,spacing:16) {
                    summaryRow("Ne değişiyor?",text:pull.body.isEmpty ? "PR açıklaması eklenmemiş." : pull.body)
                    summaryRow("Bana etkisi",text:pull.impact)
                    summaryRow("Ne eksik?",text:pull.missing)
                    Text(pull.isDemo ? "Kaynak: örnek senaryo" : "Kaynak: PR açıklaması · Otomatik özet üretilmedi")
                        .font(.caption).foregroundStyle(.secondary)
                }.textSelection(.enabled)
                if pull.isDemo {
                    Surface {
                        VStack(spacing:17) {
                            checkRow("Testler geçti",value:"111 / 111",passed:pull.checksPassed)
                            Divider()
                            checkRow(pull.approved ? "Claude onayladı" : "İnceleme bekliyor",value:nil,passed:pull.approved)
                            Divider()
                            checkRow("Çakışma yok",value:nil,passed:true)
                        }
                    }
                    Surface {
                        VStack(alignment:.leading,spacing:14) {
                            Text("Neler değişti?").font(.headline)
                            Label("Otomatik test takibi",systemImage:"checkmark").font(.subheadline)
                            Label("Test sonrası güvenli temizlik",systemImage:"checkmark").font(.subheadline)
                        }
                    }
                    Button { diffShown = true } label: { HStack { Text("Örnek değişikliği gör"); Spacer(); Image(systemName:"chevron.right") }.padding(8) }.buttonStyle(.glass)
                    Text("Önizlemedeki onay ve test sonuçları örnektir. Gerçek bir birleştirme yapılmaz.").font(.footnote).foregroundStyle(.secondary)
                } else {
                    Surface { Text("Bu sürüm PR metnini salt okunur gösterir. Test, bağımsız onay ve birleşebilirlik henüz uygulamada doğrulanmıyor.").font(.subheadline).foregroundStyle(.secondary) }
                    if let url = pull.url { Link("Gitea’da incele",destination:url).buttonStyle(.glassProminent).controlSize(.large) }
                }
            }.padding(22).padding(.bottom,12)
        }.background(Color.canvas).navigationTitle(pull.project.name).navigationBarTitleDisplayMode(.inline).toolbar(.hidden,for:.tabBar)
        .safeAreaInset(edge:.bottom) {
            if pull.isDemo {
                Button { reviewShown = true } label: { Text("Birleştirmeyi gözden geçir").font(.headline).frame(maxWidth:.infinity).padding(.vertical,10) }
                    .buttonStyle(.glassProminent).foregroundStyle(appearance.buttonInk(scheme)).padding(.horizontal,22).padding(.bottom,12).disabled(!pull.approved)
            }
        }
        .sheet(isPresented:$reviewShown) { NavigationStack { VStack(spacing:20) { MarkView(kind:2,size:64).foregroundStyle(.tint); Text("Önce son bir bakış.").font(.title.bold()); Text("Bu bir tasarım önizlemesi. Gerçek PR birleştirme ve yorum gönderme kapalı; depolarında hiçbir değişiklik yapılmaz.").multilineTextAlignment(.center).foregroundStyle(.secondary); Button("Anladım") { reviewShown = false }.buttonStyle(.glassProminent).controlSize(.large) }.padding(28).navigationTitle("Birleştirme önizlemesi").navigationBarTitleDisplayMode(.inline) }.presentationDetents([.medium]) }
        .sheet(isPresented:$diffShown) { NavigationStack { ScrollView { VStack(alignment:.leading,spacing:16) { StatusPill(text:"Örnek değişiklik",color:.secondary); Text("test-takibi.yml").font(.headline); Text("+ Her yeni commit için ayrı test ortamı\n+ Başarısız kontrolde işlemi durdur\n+ Sonuçtan sonra geçici kaynakları temizle").font(.system(.body,design:.monospaced)).foregroundStyle(Color.success) }.padding(22) }.navigationTitle("Değişiklik").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement:.confirmationAction) { Button("Bitti") { diffShown = false } } } }.presentationDetents([.medium,.large]) }
    }
    func summaryRow(_ title: String,text: String) -> some View {
        VStack(alignment:.leading,spacing:6) { Text(title).font(.headline); Text(text).font(.subheadline).foregroundStyle(.secondary) }
    }
    func checkRow(_ text: String,value: String?,passed: Bool) -> some View { HStack(spacing:12) { Image(systemName:passed ? "checkmark.circle.fill" : "clock").foregroundStyle(passed ? Color.success : Color.waiting).font(.title3); Text(text).font(.subheadline); Spacer(); if let value { Text(value).font(.caption).foregroundStyle(.secondary) } } }
}

struct PullDestination: View { let pull: PullRequest; var body: some View { if pull.isDemo { PullDetail(pull:pull) } else { RemotePRView(pull:pull) } } }

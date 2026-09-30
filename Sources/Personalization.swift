import SwiftUI

enum AppPage: String, Codable, CaseIterable, Identifiable {
    case today, projects, inbox, profile
    var id: String { rawValue }
    var title: String {
        switch self { case .today: "Bugün"; case .projects: "Projeler"; case .inbox: "Gelen kutusu"; case .profile: "Profil" }
    }
}
enum TodaySection: String, Codable, CaseIterable, Identifiable {
    case queue, ideas, favorites
    var id: String { rawValue }
    var title: String {
        switch self { case .queue: "İş kuyruğun"; case .ideas: "Fikir defterin"; case .favorites: "Favori projelerin" }
    }
}
enum CardDensity: String, Codable, CaseIterable, Identifiable {
    case compact, balanced, spacious
    var id: String { rawValue }
    var title: String { switch self { case .compact: "Sık"; case .balanced: "Dengeli"; case .spacious: "Ferah" } }
    var padding: CGFloat { switch self { case .compact: 12; case .balanced: 18; case .spacious: 24 } }
    var gap: CGFloat { switch self { case .compact: 12; case .balanced: 18; case .spacious: 26 } }
}
enum TextStyle: String, Codable, CaseIterable, Identifiable {
    case system, rounded, serif
    var id: String { rawValue }
    var title: String { switch self { case .system: "Sistem"; case .rounded: "Yuvarlak"; case .serif: "Serif" } }
    var design: Font.Design { switch self { case .system: .default; case .rounded: .rounded; case .serif: .serif } }
}
enum QueueFilter: String, Codable, CaseIterable, Identifiable {
    case all, mine, others, testing, uncertain
    var id: String { rawValue }
    var category: TodayCategory? {
        switch self { case .all: nil; case .mine: .mine; case .others: .others; case .testing: .testing; case .uncertain: .uncertain }
    }
    var title: String { category?.rawValue ?? "Tümü" }
}
enum ProjectSort: String, Codable, CaseIterable, Identifiable {
    case server, name, favorites, issues
    var id: String { rawValue }
    var title: String {
        switch self { case .server: "Gitea sırası"; case .name: "Ada göre"; case .favorites: "Önce favoriler"; case .issues: "Açık konu sayısı" }
    }
}

struct PersonalLayout: Codable, Equatable {
    var startPage: AppPage = .today
    var density: CardDensity = .balanced
    var corners: Double = 24
    var textStyle: TextStyle = .system
    var todayOrder: [TodaySection] = [.queue,.ideas,.favorites]
    var hiddenSections: Set<TodaySection> = [.favorites]
    var queueFilter: QueueFilter = .all
    var showDailySummary = true
    var showChanges = true
    var projectSort: ProjectSort = .server
    var favoritesOnly = false
    var showProjectDescriptions = true
    var ideaCount = 3

    var visibleSections: [TodaySection] { normalized().todayOrder.filter { !hiddenSections.contains($0) } }
    func normalized() -> Self {
        var copy = self
        var seen = Set<TodaySection>()
        copy.todayOrder = (todayOrder + TodaySection.allCases).filter { seen.insert($0).inserted }
        copy.corners = corners.isFinite ? min(32,max(0,corners)) : 24
        copy.ideaCount = min(20,max(1,ideaCount))
        return copy
    }
    func sortedProjects(_ projects: [Project],favorites: Set<String>) -> [Project] {
        guard projectSort != .server else { return projects }
        return projects.sorted { a,b in
            if projectSort == .favorites, favorites.contains(a.fullName) != favorites.contains(b.fullName) { return favorites.contains(a.fullName) }
            if projectSort == .issues,a.issues != b.issues { return a.issues > b.issues }
            let comparison = a.name.localizedStandardCompare(b.name)
            return comparison == .orderedSame ? a.fullName < b.fullName : comparison == .orderedAscending
        }
    }
}
struct StyleSnapshot: Codable, Equatable {
    var mode: String
    var accentName: String
    var customHex: String
    var motion: Bool
    var haptics: Bool
    var projectColors: [String:String]
    var layout: PersonalLayout
}
struct SavedStyle: Codable, Identifiable {
    var id = UUID()
    let name: String
    let savedAt: Date
    let style: StyleSnapshot
}
struct PersonalizationArchive: Codable {
    var version = 1
    var layout = PersonalLayout()
    var saved: [SavedStyle] = []
    var previous: StyleSnapshot?
}

extension Appearance {
    var styleSnapshot: StyleSnapshot {
        StyleSnapshot(mode:mode,accentName:accentName,customHex:customHex,motion:motion,haptics:haptics,projectColors:projectColors,layout:layout.normalized())
    }
    func saveStyle(named rawName: String) throws {
        try ensurePersonalizationWritable()
        let name = rawName.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !name.isEmpty,name.count <= 48 else { throw ClientError.message("Düzenine en fazla 48 karakterlik bir ad ver.") }
        guard !savedStyles.contains(where:{ $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else { throw ClientError.message("Bu adla bir düzen var. Başka bir ad kullan.") }
        guard savedStyles.count < 30 else { throw ClientError.message("30 düzen saklanabilir. Yeni kayıt için kullanmadığın bir düzeni kaldır.") }
        savedStyles.insert(SavedStyle(name:name,savedAt:Date(),style:styleSnapshot),at:0)
        persistPersonalization()
    }
    func applyStyle(_ saved: SavedStyle) throws {
        try ensurePersonalizationWritable()
        previousStyle = styleSnapshot
        restoreStyle(saved.style)
    }
    func undoStyle() throws {
        try ensurePersonalizationWritable()
        guard let previousStyle else { return }
        self.previousStyle = nil
        restoreStyle(previousStyle)
    }
    func resetStyle() throws {
        try ensurePersonalizationWritable()
        previousStyle = styleSnapshot
        restoreStyle(StyleSnapshot(mode:"Sistem",accentName:"Mor",customHex:"9975DD",motion:true,haptics:true,projectColors:[:],layout:PersonalLayout()))
    }
    func deleteStyle(_ id: UUID) throws {
        try ensurePersonalizationWritable()
        savedStyles.removeAll { $0.id == id }
        persistPersonalization()
    }
    private func restoreStyle(_ value: StyleSnapshot) {
        mode = value.mode; accentName = value.accentName; customHex = value.customHex
        motion = value.motion; haptics = value.haptics; projectColors = value.projectColors
        layout = value.layout.normalized()
        persistPersonalization()
    }
}

struct LayoutSettingsView: View {
    @EnvironmentObject private var appearance: Appearance
    var body: some View {
        Form {
            Section {
                Picker("Açılış ekranı",selection:$appearance.layout.startPage) {
                    ForEach(AppPage.allCases) { Text($0.title).tag($0) }
                }.accessibilityIdentifier("startPagePicker")
            } footer: { Text("Uygulamayı bir sonraki açışında bu sekmeyle başlarsın.") }
            Section {
                ForEach(appearance.layout.todayOrder) { item in
                    Toggle(item.title,isOn:Binding(get:{ !appearance.layout.hiddenSections.contains(item) },set:{ visible in
                        if visible { appearance.layout.hiddenSections.remove(item) }
                        else { appearance.layout.hiddenSections.insert(item) }
                    })).accessibilityIdentifier("section-" + item.rawValue)
                }.onMove { from,to in appearance.layout.todayOrder.move(fromOffsets:from,toOffset:to) }
            } header: { Text("Bugün’de göreceklerin") } footer: { Text("Sıralamak için sağdaki tutamaçtan sürükle. Gizlediğin içerik silinmez.") }
            Section("İş kuyruğu") {
                Picker("Başlangıç filtresi",selection:$appearance.layout.queueFilter) { ForEach(QueueFilter.allCases) { Text($0.title).tag($0) } }.accessibilityIdentifier("queueFilterPicker")
                Toggle("Günlük sayımı göster",isOn:$appearance.layout.showDailySummary).accessibilityIdentifier("showDailySummary")
                Toggle("Ben yokken değişenleri göster",isOn:$appearance.layout.showChanges).accessibilityIdentifier("showChanges")
            }
            Section("Projeler") {
                Picker("Sıralama",selection:$appearance.layout.projectSort) { ForEach(ProjectSort.allCases) { Text($0.title).tag($0) } }.accessibilityIdentifier("projectSortPicker")
                Toggle("Favorilerle başla",isOn:$appearance.layout.favoritesOnly).accessibilityIdentifier("defaultFavorites")
                Toggle("Proje açıklamalarını göster",isOn:$appearance.layout.showProjectDescriptions)
            }
            Section("Fikir defterin") {
                Stepper("Bugün’de \(appearance.layout.ideaCount) fikir",value:$appearance.layout.ideaCount,in:1...20).accessibilityIdentifier("ideaCount")
            }
        }.navigationTitle("Ekran düzeni").navigationBarTitleDisplayMode(.inline)
            .environment(\.editMode,.constant(.active))
    }
}

struct CardSettingsView: View {
    @EnvironmentObject private var appearance: Appearance
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Form {
            Section("Anında gör") {
                Surface {
                    VStack(alignment:.leading,spacing:10) {
                        Text("Kendi çalışma alanın").font(.headline)
                        Text("Kart aralığı, köşeler ve yazı seçimin burada görünür.").font(.subheadline).foregroundStyle(.secondary)
                        WorkflowSignal(title:"İncelemen bekleniyor",symbol:"person.crop.circle.badge.clock",tone:.review)
                    }
                }.fontDesign(appearance.layout.textStyle.design).padding(12).accessibilityIdentifier("personalizationPreview")
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            Section {
                Picker("Kart aralığı",selection:$appearance.layout.density) {
                    ForEach(CardDensity.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).accessibilityIdentifier("densityPicker")
            } header: { Text("Kart aralığı") } footer: { Text("Yazı boyutun değişmez. Büyük erişilebilir yazıda dokunma alanları ve iç boşluk korunur.") }
            Section("Köşeler") {
                Slider(value:$appearance.layout.corners,in:0...32,step:2) { Text("Köşe yuvarlaklığı") } minimumValueLabel: { Image(systemName:"square") } maximumValueLabel: { Image(systemName:"app") }
                    .accessibilityIdentifier("cornerSlider")
                Text(appearance.layout.corners == 0 ? "Düz köşeler" : "Yuvarlaklık: \(Int(appearance.layout.corners))").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Picker("Yazı stili",selection:$appearance.layout.textStyle) {
                    ForEach(TextStyle.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).accessibilityIdentifier("textStylePicker")
            } header: { Text("Yazı") } footer: { Text("iPhone’un yazı boyutu ayarı korunur. Kod farkları kendi sabit aralıklı yazısını kullanır.") }
        }.navigationTitle("Kartlar ve yazı").navigationBarTitleDisplayMode(.inline)
    }
}

struct SavedStylesView: View {
    @EnvironmentObject private var appearance: Appearance
    @State private var name = ""
    @State private var message: String?
    @State private var error: String?
    @State private var deleting: SavedStyle?
    @State private var resetting = false
    var body: some View {
        Form {
            Section {
                TextField("Örneğin: Akşam çalışma",text:$name).accessibilityIdentifier("styleName")
                Button("Bu düzeni kaydet") { perform {
                    try appearance.saveStyle(named:name); message = "Düzen kaydedildi."; name = ""
                } }.disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty).accessibilityIdentifier("saveStyle")
            } header: { Text("Şu anki görünümün") } footer: { Text("Tema, renkler, yazı, hareket ve ekran düzenin birlikte saklanır. Bağlantın ve içeriklerin değişmez.") }
            if let message { Section { Text(message).foregroundStyle(Color.success).accessibilityIdentifier("styleMessage") } }
            if let error { Section { Text(error).foregroundStyle(.red) } }
            if appearance.previousStyle != nil {
                Section {
                    Button("Önceki düzenimi geri getir") { perform { try appearance.undoStyle(); message = "Önceki düzenin geri geldi." } }.accessibilityIdentifier("undoStyle")
                }
            }
            Section("Kayıtlı düzenlerin") {
                if appearance.savedStyles.isEmpty { Text("Beğendiğin ayarları kaydet; istediğinde geri dön.").foregroundStyle(.secondary) }
                ForEach(appearance.savedStyles) { saved in
                    VStack(alignment:.leading,spacing:10) {
                        Text(saved.name).font(.headline)
                        Text("\(saved.style.layout.density.title) · \(saved.style.layout.textStyle.title) · \(saved.style.layout.startPage.title)").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("Uygula") { perform { try appearance.applyStyle(saved); message = "\(saved.name) uygulandı." } }
                                .buttonStyle(.bordered).accessibilityIdentifier("applyStyle-" + saved.name)
                            Spacer()
                            Button("Sil",systemImage:"trash",role:.destructive) { deleting = saved }.labelStyle(.iconOnly).frame(minWidth:44,minHeight:44).buttonStyle(.borderless).accessibilityLabel(saved.name + " düzenini sil")
                        }
                    }.padding(.vertical,5)
                }
            }
            Section {
                Button("Varsayılan görünüme dön") { resetting = true }.accessibilityIdentifier("resetStyle")
            } footer: { Text("Dönüşten sonra önceki düzenini geri getirebilirsin. Kayıtlı düzenlerin saklanır.") }
        }.navigationTitle("Kayıtlı düzenler").navigationBarTitleDisplayMode(.inline)
            .alert("Bu düzen silinsin mi?",isPresented:Binding(get:{ deleting != nil },set:{ if !$0 { deleting = nil } })) {
                Button("Sil",role:.destructive) { if let deleting { perform { try appearance.deleteStyle(deleting.id) } }; deleting = nil }
                Button("Vazgeç",role:.cancel) { deleting = nil }
            } message: { Text("Uyguladığın görünüm değişmez; yalnız kayıt kaldırılır.") }
            .confirmationDialog("Varsayılan görünüme dönülsün mü?",isPresented:$resetting,titleVisibility:.visible) {
                Button("Varsayılana dön") { perform { try appearance.resetStyle(); message = "Varsayılan görünüm uygulandı." } }
            }
    }
    func perform(_ action: () throws -> Void) {
        error = nil
        do { try action() } catch { self.error = error.localizedDescription }
    }
}

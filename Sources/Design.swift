import SwiftUI
import UIKit

@MainActor final class Appearance: ObservableObject {
    private let defaults: UserDefaults
    static let personalizationKey = "personalization.v1"
    static var appDefaults: UserDefaults {
        #if DEBUG
        if let suite = ProcessInfo.processInfo.environment["GITEA_TEST_PREFERENCES"],suite.hasPrefix("test.") {
            return UserDefaults(suiteName:suite) ?? .standard
        }
        #endif
        return .standard
    }
    @Published var layout: PersonalLayout { didSet { persistPersonalization() } }
    @Published var savedStyles: [SavedStyle]
    @Published var previousStyle: StyleSnapshot?
    @Published private(set) var personalizationError: String?
    @Published var projectColors: [String:String] { didSet { defaults.set(projectColors,forKey:"projectColors") } }
    @Published var mode: String { didSet { defaults.set(mode,forKey:"appearance") } }
    @Published var accentName: String { didSet { defaults.set(accentName,forKey:"accent") } }
    @Published var customHex: String { didSet { defaults.set(customHex,forKey:"customAccent") } }
    @Published var motion: Bool { didSet { defaults.set(motion,forKey:"motion") } }
    @Published var haptics: Bool { didSet { defaults.set(haptics,forKey:"haptics") } }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = defaults.string(forKey:"appearance") ?? "Sistem"
        accentName = defaults.string(forKey:"accent") ?? "Mor"
        customHex = defaults.string(forKey:"customAccent") ?? "9975DD"
        motion = defaults.object(forKey:"motion") as? Bool ?? true
        haptics = defaults.object(forKey:"haptics") as? Bool ?? true
        projectColors = defaults.dictionary(forKey:"projectColors") as? [String:String] ?? [:]
        var archive = PersonalizationArchive()
        if let data = defaults.data(forKey:Self.personalizationKey) {
            do {
                archive = try JSONDecoder().decode(PersonalizationArchive.self,from:data)
                guard archive.version == 1,archive.saved.count <= 30,Set(archive.saved.map(\.id)).count == archive.saved.count else {
                    throw ClientError.message("Desteklenmeyen düzen kaydı.")
                }
            } catch {
                archive = PersonalizationArchive()
                personalizationError = "Kişisel düzen kaydı okunamadı. Eski kayıt korunuyor; yeni düzen değişiklikleri henüz kaydedilmiyor."
            }
        }
        layout = archive.layout.normalized(); savedStyles = archive.saved; previousStyle = archive.previous
    }
    func ensurePersonalizationWritable() throws {
        if let personalizationError { throw ClientError.message(personalizationError) }
    }
    func persistPersonalization() {
        guard personalizationError == nil else { return }
        do {
            let archive = PersonalizationArchive(layout:layout.normalized(),saved:savedStyles,previous:previousStyle)
            defaults.set(try JSONEncoder().encode(archive),forKey:Self.personalizationKey)
        } catch { personalizationError = "Düzen kaydedilemedi; önceki kayıt korunuyor." }
    }
    func recoverPersonalization() {
        if let data = defaults.data(forKey:Self.personalizationKey) {
            defaults.set(data,forKey:Self.personalizationKey + ".unreadable." + UUID().uuidString)
        }
        personalizationError = nil; savedStyles = []; previousStyle = nil; layout = PersonalLayout()
    }
    func projectKey(_ project: Project,scope: String?) -> String { (scope ?? "demo") + "|" + project.fullName }
    func projectAccent(_ project: Project,scope: String?,scheme: ColorScheme) -> Color {
        guard let name = projectColors[projectKey(project,scope:scope)] else { return accent(scheme) }
        let colors = scheme == .dark ? ["Mor":"BC9CFF","Mavi":"83B5FF","Nane":"75D6BA","Mercan":"FFA18E"] : ["Mor":"7044BC","Mavi":"225EB0","Nane":"16745C","Mercan":"AD4838"]
        return colors[name].map { Color(hex:$0) } ?? accent(scheme)
    }

    var scheme: ColorScheme? { mode == "Sistem" ? nil : (mode == "Koyu" ? .dark : .light) }
    func accent(_ scheme: ColorScheme) -> Color {
        if accentName == "Özel" { return Color(hex: customHex) }
        let colors = scheme == .dark ? ["Mor":"BC9CFF", "Mavi":"83B5FF", "Nane":"75D6BA", "Mercan":"FFA18E", "Pembe":"F1A6D7"] : ["Mor":"7044BC", "Mavi":"225EB0", "Nane":"16745C", "Mercan":"AD4838", "Pembe":"A0367D"]
        return Color(hex: colors[accentName] ?? "9975DD")
    }
    func buttonInk(_ scheme: ColorScheme) -> Color {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(accent(scheme)).getRed(&r,green:&g,blue:&b,alpha:&a)
        func linear(_ v: CGFloat) -> Double { let n = Double(v); return n <= 0.04045 ? n/12.92 : pow((n+0.055)/1.055,2.4) }
        let luminance = 0.2126*linear(r)+0.7152*linear(g)+0.0722*linear(b)
        return luminance > 0.179 ? .black : .white
    }
    func animation(reduced: Bool) -> Animation? { motion && !reduced ? .spring(response: 0.36, dampingFraction: 0.84) : nil }
    func tap() { if haptics { UISelectionFeedbackGenerator().selectionChanged() } }
}
extension Color {
    init(hex: String) {
        let v = UInt64(hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted), radix: 16) ?? 0x9975DD
        self.init(.sRGB, red: Double((v >> 16) & 255)/255, green: Double((v >> 8) & 255)/255, blue: Double(v & 255)/255, opacity: 1)
    }
    static var success: Color { Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red:0.53,green:0.87,blue:0.65,alpha:1) : UIColor(red:0.11,green:0.43,blue:0.23,alpha:1) }) }
    static var waiting: Color { Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red:0.96,green:0.78,blue:0.5,alpha:1) : UIColor(red:0.57,green:0.31,blue:0.04,alpha:1) }) }
    static var canvas: Color { Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red:0.075,green:0.08,blue:0.095,alpha:1) : UIColor(red:0.953,green:0.953,blue:0.969,alpha:1) }) }
    static var surface: Color { Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red:0.125,green:0.13,blue:0.15,alpha:1) : .white }) }
}

/// Original monoline marks: orbit, offset leaves, converging paths and linked arcs.
/// No stock folder/cube/globe/house motifs. Rendered as vector paths at every scale.
struct Mark: Shape {
    var kind: Int
    func path(in r: CGRect) -> Path {
        let s = min(r.width, r.height), x = r.midX-s/2, y = r.midY-s/2
        func p(_ a: CGFloat,_ b: CGFloat) -> CGPoint { CGPoint(x:x+a*s,y:y+b*s) }
        var q = Path()
        switch kind % 6 {
        case 0:
            q.addEllipse(in: CGRect(x:x+s*0.2,y:y+s*0.2,width:s*0.6,height:s*0.6))
            q.move(to:p(0.12,0.65)); q.addCurve(to:p(0.88,0.35),control1:p(0.36,0.92),control2:p(0.64,0.08))
            q.move(to:p(0.73,0.16));q.addLine(to:p(0.83,0.16));q.addLine(to:p(0.83,0.26))
        case 1:
            q.move(to:p(0.2,0.6)); q.addLine(to:p(0.2,0.18)); q.addLine(to:p(0.63,0.18)); q.addLine(to:p(0.8,0.35))
            q.move(to:p(0.37,0.4)); q.addLine(to:p(0.8,0.4)); q.addLine(to:p(0.8,0.82)); q.addLine(to:p(0.37,0.82)); q.closeSubpath()
        case 2:
            q.move(to:p(0.18,0.2));q.addLine(to:p(0.82,0.2));q.addLine(to:p(0.82,0.59))
            q.addQuadCurve(to:p(0.66,0.75),control:p(0.82,0.75));q.addLine(to:p(0.48,0.75));q.addLine(to:p(0.3,0.9));q.addLine(to:p(0.3,0.75));q.addQuadCurve(to:p(0.18,0.59),control:p(0.18,0.75));q.closeSubpath()
            q.move(to:p(0.33,0.42));q.addLine(to:p(0.67,0.42))
            q.move(to:p(0.33,0.56));q.addLine(to:p(0.52,0.56))
        case 3:
            q.addArc(center:p(0.5,0.42),radius:s*0.25,startAngle:.degrees(210),endAngle:.degrees(30),clockwise:false)
            q.addArc(center:p(0.5,0.58),radius:s*0.25,startAngle:.degrees(30),endAngle:.degrees(210),clockwise:false)
            q.move(to:p(0.32,0.82));q.addLine(to:p(0.68,0.82))
        case 4:
            q.move(to:p(0.2,0.2));q.addLine(to:p(0.2,0.8));q.addLine(to:p(0.48,0.52));q.addLine(to:p(0.48,0.18))
            q.move(to:p(0.52,0.82));q.addLine(to:p(0.52,0.48));q.addLine(to:p(0.8,0.2));q.addLine(to:p(0.8,0.8))
        default:
            q.move(to:p(0.18,0.35));q.addLine(to:p(0.5,0.16));q.addLine(to:p(0.82,0.35));q.addLine(to:p(0.5,0.54));q.closeSubpath()
            q.move(to:p(0.18,0.55));q.addLine(to:p(0.5,0.74));q.addLine(to:p(0.82,0.55))
            q.move(to:p(0.18,0.72));q.addLine(to:p(0.5,0.91));q.addLine(to:p(0.82,0.72))
        }
        return q
    }
}
struct MarkView: View {
    var kind: Int
    var size: CGFloat = 28
    var body: some View { Mark(kind:kind).stroke(style:StrokeStyle(lineWidth:1.8,lineCap:.round,lineJoin:.round)).frame(width:size,height:size).accessibilityHidden(true) }
}
@MainActor func tabImage(_ kind: Int) -> Image {
    let renderer = ImageRenderer(content: MarkView(kind:kind,size:25).foregroundStyle(.black).padding(1))
    renderer.scale = 3
    return Image(uiImage:(renderer.uiImage ?? UIImage()).withRenderingMode(.alwaysTemplate))
}
struct ProjectMark: View {
    let kind: Int
    let color: Color
    var body: some View {
        MarkView(kind:kind,size:29).foregroundStyle(color).frame(width:52,height:52)
            .background(color.opacity(0.12),in:RoundedRectangle(cornerRadius:17))
    }
}
struct Surface<Content: View>: View {
    @EnvironmentObject private var appearance: Appearance
    @Environment(\.dynamicTypeSize) private var typeSize
    @ViewBuilder var content: Content
    var body: some View {
        let padding = typeSize.isAccessibilitySize ? max(18,appearance.layout.density.padding) : appearance.layout.density.padding
        let shape = RoundedRectangle(cornerRadius:appearance.layout.normalized().corners)
        content.padding(padding).frame(maxWidth:.infinity,alignment:.leading).background(Color.surface,in:shape).overlay(shape.strokeBorder(.primary.opacity(0.045),lineWidth:1))
    }
}
struct StatusPill: View {
    let text: String
    var color: Color = .success
    var body: some View { Text(text).font(.caption.weight(.semibold)).foregroundStyle(color).padding(.horizontal,10).padding(.vertical,6).background(color.opacity(0.12),in:Capsule()) }
}

struct ProjectAccentPicker: View {
    let project: Project
    @EnvironmentObject var appearance: Appearance
    @EnvironmentObject var workspace: Workspace
    @Environment(\.colorScheme) var scheme
    var body: some View {
        let key = appearance.projectKey(project,scope:workspace.identity?.scope)
        VStack(alignment:.leading,spacing:4) {
        Text("Proje rengi").font(.caption).foregroundStyle(.secondary)
        Picker("Proje rengi",selection:Binding(get:{ appearance.projectColors[key] ?? "Genel" },set:{ value in appearance.projectColors[key] = value; appearance.tap() })) {
            ForEach(["Genel","Mor","Mavi","Nane","Mercan"],id:\.self) { Text($0).tag($0) }
        }.tint(appearance.projectAccent(project,scope:workspace.identity?.scope,scheme:scheme)).accessibilityIdentifier("projectAccent")
        }
    }
}

struct ProjectNavigationMotion: ViewModifier {
    let id: Int
    let namespace: Namespace.ID
    let enabled: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if enabled { content.navigationTransition(.zoom(sourceID:id,in:namespace)) }
        else { content }
    }
}

/// One full-width disclosure target; detail controls stay inside the expanded area.
struct QuietDisclosureStyle: DisclosureGroupStyle {
    var animation: Animation? = nil
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment:.leading,spacing:0) {
            Button {
                withAnimation(animation) { configuration.isExpanded.toggle() }
            } label: {
                HStack(spacing:12) {
                    configuration.label
                    Spacer(minLength:4)
                    Image(systemName:configuration.isExpanded ? "chevron.down" : "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }.frame(maxWidth:.infinity,minHeight:44,alignment:.leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityValue(configuration.isExpanded ? "Açık" : "Kapalı")
            if configuration.isExpanded { configuration.content }
        }
    }
}

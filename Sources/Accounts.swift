import SwiftUI

struct AccountManagerView: View {
    @EnvironmentObject var workspace: Workspace
    @State private var adding = false
    @State private var managing: ConnectionIdentity?
    @State private var error: String?
    var body: some View {
        List {
            Section {
                ForEach(workspace.accounts,id:\.scope) { account in
                    Button { managing = account } label: {
                        HStack(spacing:14) {
                            Image(systemName:"person.crop.circle").font(.title2).foregroundStyle(.secondary)
                            VStack(alignment:.leading,spacing:5) {
                                Text(account.login).font(.headline).foregroundStyle(.primary)
                                Text(account.origin.absoluteString).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength:4)
                            if workspace.identity?.scope == account.scope { Image(systemName:"checkmark.circle.fill").foregroundStyle(.tint).accessibilityLabel("Seçili hesap") }
                            Image(systemName:"chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }.padding(.vertical,7)
                    }.buttonStyle(.plain).accessibilityIdentifier("account-" + account.login + "-" + (account.origin.host ?? ""))
                }
                if workspace.accounts.isEmpty { Text("Gitea hesabını ekleyerek başla.").foregroundStyle(.secondary) }
            } header: { Text("Kayıtlı hesaplar") } footer: { Text("Bir hesabın bağlantı ve kaldırma işlemleri için satırına dokun.") }
            if !workspace.deviceDrafts.isEmpty {
                Section {
                    NavigationLink("\(workspace.deviceDrafts.count) fikir") { DeviceIdeasView() }
                    if workspace.identity != nil { Button("Seçili hesaba kopyala") { do { try workspace.copyDeviceDraftsToAccount() } catch { self.error = error.localizedDescription } } }
                } header: { Text("Cihaz fikirleri") } footer: { Text("Kopyaladığında cihazdaki asılları korunur.") }
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }.scrollContentBackground(.hidden).background(Color.canvas)
        .navigationTitle("Hesaplar").navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("Hesap ekle",systemImage:"plus") { adding = true } }
        .sheet(isPresented:$adding) { ConnectionSheet() }
        .sheet(isPresented:Binding(get:{ managing != nil },set:{ if !$0 { managing = nil } })) {
            if let account = managing { AccountActionsView(account:account) }
        }
    }
}
struct AccountActionsView: View {
    let account: ConnectionIdentity
    @EnvironmentObject var workspace: Workspace
    @Environment(\.dismiss) var dismiss
    @State private var removing = false
    @State private var reauthenticating = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(account.login).font(.title3.bold())
                    Text(account.origin.absoluteString).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
                    if workspace.identity?.scope == account.scope { Label(workspace.offlineOnly ? "Çevrimdışı kayıt seçili" : "Canlı bağlantı seçili",systemImage:workspace.offlineOnly ? "wifi.slash" : "checkmark.circle").font(.caption).foregroundStyle(.secondary) }
                }
                Section {
                    Button("Canlı bağlantıya geç") { Task { do { try await workspace.reconnect(account); dismiss() } catch { self.error = error.localizedDescription } } }.disabled(workspace.busy)
                    Button("Hesabı seç") { do { try workspace.selectAccount(account); dismiss() } catch { self.error = error.localizedDescription } }
                } header: { Text("Bağlantı") } footer: { Text("Hesabı seç, saklanmış kaydı internet kullanmadan açar.") }
                if let error { Section { Text(error).foregroundStyle(.red); Button("Anahtarı yeniden gir") { reauthenticating = true } } }
                Section { Button("Bu hesabı kaldır",role:.destructive) { removing = true } }
            }.navigationTitle("Hesap").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Bitti") { dismiss() } } }
                .confirmationDialog("Bu hesap kaldırılsın mı?",isPresented:$removing,titleVisibility:.visible) {
                    Button("Hesabı ve cihazdaki hesap kayıtlarını kaldır",role:.destructive) { do { try workspace.removeAccount(account); dismiss() } catch { self.error = error.localizedDescription } }
                } message: { Text("Yalnız seçilen hesabın anahtarı, önbelleği ve hesaba ait fikirleri kaldırılır. Sunucuda işlem yapılmaz; diğer hesaplar ve eski cihaz fikirleri korunur.") }
                .sheet(isPresented:$reauthenticating) { ConnectionSheet() }
        }.presentationDetents([.medium,.large]).presentationDragIndicator(.visible)
    }
}
struct DeviceIdeasView: View {
    @EnvironmentObject var workspace: Workspace
    var body: some View {
        List(workspace.deviceDrafts) { draft in
            VStack(alignment:.leading,spacing:8) { Text(draft.title).font(.headline); Text(draft.text); ShareLink(item:draft.markdown) { Label("Paylaş",systemImage:"square.and.arrow.up") } }
        }.navigationTitle("Cihaz fikirleri")
    }
}
struct SendTargetView: View {
    @EnvironmentObject var workspace: Workspace
    let repository: String
    var body: some View {
        if let identity = workspace.identity {
            VStack(alignment:.leading,spacing:4) {
                Text("Gönderim hedefi").font(.caption.bold())
                Text(identity.origin.absoluteString)
                Text("\(identity.login) · \(repository)")
            }.font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }
}

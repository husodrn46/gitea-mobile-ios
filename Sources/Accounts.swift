import SwiftUI

struct AccountManagerView: View {
    @EnvironmentObject var workspace: Workspace
    @State private var adding = false
    @State private var removing: ConnectionIdentity?
    @State private var error: String?
    var body: some View {
        List {
            Section("Kayıtlı hesaplar") {
                ForEach(workspace.accounts,id:\.scope) { account in
                    VStack(alignment:.leading,spacing:10) {
                        Text(account.login).font(.headline)
                        Text(account.origin.absoluteString).font(.caption).textSelection(.enabled)
                        if workspace.identity?.scope == account.scope { Text(workspace.offlineOnly ? "Seçili · Çevrimdışı" : "Seçili · Canlı").font(.caption).foregroundStyle(.secondary) }
                        HStack {
                            Button("Hesabı seç") { do { try workspace.selectAccount(account) } catch { self.error = error.localizedDescription } }
                            Button("Canlı bağlantıya geç") { Task { do { try await workspace.reconnect(account) } catch { self.error = error.localizedDescription } } }.disabled(workspace.busy)
                        }.buttonStyle(.borderless)
                        Button("Bu hesabı kaldır",role:.destructive) { removing = account }.buttonStyle(.borderless)
                    }.padding(.vertical,4)
                }
                Button("Hesap ekle") { adding = true }
            }
            if !workspace.deviceDrafts.isEmpty {
                Section("Cihazındaki eski fikirler") {
                    Text("\(workspace.deviceDrafts.count) fikir cihazda korunuyor. İstersen seçili hesaba kopyala; cihazdaki asılları kalır.").font(.footnote)
                    NavigationLink("Cihaz fikirlerini aç") { DeviceIdeasView() }
                    if workspace.identity != nil { Button("Seçili hesaba kopyala") { do { try workspace.copyDeviceDraftsToAccount() } catch { self.error = error.localizedDescription } } }
                }
            }
            if let error { Section { Text(error).foregroundStyle(.red); Button("Anahtarı yeniden gir") { adding = true } } }
        }.navigationTitle("Hesaplar").sheet(isPresented:$adding) { ConnectionSheet() }
        .confirmationDialog("Bu hesap kaldırılsın mı?",isPresented:Binding(get:{removing != nil},set:{if !$0 { removing = nil }}),titleVisibility:.visible) {
            Button("Hesabı ve cihazdaki hesap kayıtlarını kaldır",role:.destructive) { if let account = removing { do { try workspace.removeAccount(account) } catch { self.error = error.localizedDescription } }; removing = nil }
        } message: { Text("Yalnız seçilen hesabın anahtarı, önbelleği ve hesaba ait fikirleri kaldırılır. Sunucuda işlem yapılmaz; diğer hesaplar ve eski cihaz fikirleri korunur.") }
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

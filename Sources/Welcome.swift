import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var workspace: Workspace
    @State private var connect = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:26) {
                    Image(systemName:"point.3.connected.trianglepath.dotted").font(.system(size:56)).foregroundStyle(.tint).accessibilityHidden(true)
                    Text("Projelerin, yanında.").font(.largeTitle.bold())
                    Text("Gitea sunucuna bağlan; depolarını, konuları ve pull request’leri tek yerde takip et.").font(.title3).foregroundStyle(.secondary)
                    VStack(alignment:.leading,spacing:18) {
                        Label("Kendi sunucun ve kendi hesabın",systemImage:"server.rack")
                        Label("Erişim anahtarın cihazın Keychain’inde",systemImage:"key.fill")
                        Label("Fikirler, incelemeler ve konuşmalar",systemImage:"bubble.left.and.bubble.right")
                    }.font(.body)
                    Button("Sunucuma bağlan",systemImage:"link") { connect = true }
                        .buttonStyle(.borderedProminent).controlSize(.large).accessibilityIdentifier("welcomeConnect")
                    Button("Örnek verilerle keşfet") { workspace.chooseDemo() }
                        .accessibilityIdentifier("welcomeDemo")
                    Text("Demo gerçek bir hesaba bağlanmaz. Sunucu bağlantısı için HTTPS ve Gitea erişim anahtarı gerekir.").font(.footnote).foregroundStyle(.secondary)
                }.frame(maxWidth:560,alignment:.leading).padding(28)
            }.background(Color.canvas).navigationTitle("Gitea Mobile")
                .sheet(isPresented:$connect) { ConnectionSheet() }
        }.interactiveDismissDisabled()
    }
}

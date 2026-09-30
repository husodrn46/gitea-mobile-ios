# Gitea Mobile

Gitea sunucularına bağlanan bağımsız bir iPhone/iPad istemcisi. SwiftUI ve iOS 26 üzerine kuruludur. Proje geliştirme aşamasındadır; Gitea projesinin resmî uygulaması değildir.

## İlk kullanım

Sunucuma bağlan seçeneğinde kendi HTTPS sunucu adresini ve kişisel erişim anahtarını gir. `user`, `repository`, `notification` için okuma; konuları okumak için `issue` okuma, konu/yorum göndermek için `issue` yazma izni gerekir. Yönetici anahtarı gerekmez. Örnek verilerle keşfet, sunucuya bağlanmadan demo açar.

İlk sürüm yalnız kök HTTPS adreslerini destekler; alt dizindeki kurulumlar, HTTP ve özel CA/self-signed sertifikalar desteklenmez. Sertifika doğrulaması veya yönlendirme koruması kapatılmaz.

## Özellikler

- Depolar, favoriler, konu ve PR konuşmaları, dosya/kod farkları, bildirimler.
- Günlük PR kuyruğu ve sunucudan doğrulanan test/inceleme durumları.
- Konu/yorum yazma: yalnız açık kullanıcı hareketiyle. Belirsiz gönderimler otomatik tekrarlanmaz.
- Hesap ve sunucu ayrımlı okuma önbelleği ve anahtarlar. Çevrimdışı içerik eskilik uyarısıyla gösterilir.
- Cihazda fikir defteri; bu ilk sürümde fikirler cihaz düzeyindedir ve hesaplara göre ayrılmaz.
- Tema, renkler, düzenler ve cihaz kimliğiyle isteğe bağlı uygulama kilidi.
- Geliştirme kurulumlarında profil bitiş tarihinden hesaplanan yerel yenileme hatırlatması.

## Geliştirme

Xcode 26 veya daha yeni, iOS 26 SDK ve XcodeGen gerekir.

```sh
brew install xcodegen
xcodegen generate
open KisiselGitea.xcodeproj
```

Şema: `KisiselGitea`. Mevcut bundle kimliği yükseltme sürekliliği için korunmuştur; dağıtım marka/kimliği yayın aşamasında kararlaştırılır. İmzalama takımını Xcode'da kendi hesabına göre seç. Sertifika, profil, token ve geliştirici hesabı kaynak koduna eklenmez.

CI, uygun iOS 26+ simülatörünü seçerek birim testlerini çalıştırır. Yerel UI testleri sentetik veriler kullanır; gerçek hesaba bağlanmış ürün kabulünün yerine geçmez. Test fixture'ları yalnız Debug yapıda bulunur.

## Veriler ve sınırlar

Erişim anahtarları cihaz Keychain'inde tutulur; kayıtlara ve önbelleğe yazılmaz. Kimlikli istekler yönlendirmeyi takip etmez. Anahtar sunucu + kullanıcı kimliğiyle saklanır. Eski sunucu düzeyindeki anahtarı kullanarak yeniden bağlanmak, sunucunun bildirdiği gerçek kullanıcı adına yeni kayıt oluşturur; eski anahtar doğrudan başka hesap adına kullanılmaz.

Bu sürüm tek aktif bağlantı sunar; birden fazla kayıtlı hesabı değiştirme arayüzü henüz yoktur. Fikir defteri cihaz düzeyindedir. API listeleri 1.000 kayıtla, PR listesi ilk 50 kayıtla sınırlıdır. Gerçek merge, push bildirimleri ve App Store dağıtımı henüz yoktur. Arayüz şu an Türkçedir.

Ürün hedefi ve yayın öncesi eksikler için [ROADMAP.md](ROADMAP.md).

# Gitea Mobile

Gitea sunucularına bağlanan bağımsız bir iPhone/iPad istemcisi. SwiftUI ve iOS 26 üzerine kuruludur. Proje geliştirme aşamasındadır; Gitea projesinin resmî uygulaması değildir.

## İlk kullanım

Sunucuma bağlan seçeneğinde kendi HTTPS sunucu adresini ve kişisel erişim anahtarını gir. `user`, `repository`, `notification` için okuma; konuları okumak için `issue` okuma, konu/yorum göndermek için `issue` yazma izni gerekir. Bildirimleri okundu işaretlemek için isteğe bağlı `notification` yazma izni ekle. Yönetici anahtarı gerekmez. Örnek verilerle keşfet, sunucuya bağlanmadan demo açar.

İlk sürüm yalnız kök HTTPS adreslerini destekler; alt dizindeki kurulumlar, HTTP ve özel CA/self-signed sertifikalar desteklenmez. Sertifika doğrulaması veya yönlendirme koruması kapatılmaz.

## Özellikler

- Depolar, favoriler, konu ve PR konuşmaları, dosya/kod farkları, bildirimler.
- Günlük PR kuyruğu ve sunucudan doğrulanan test/inceleme durumları.
- Konu/yorum yazma: yalnız açık kullanıcı hareketiyle. Belirsiz gönderimler otomatik tekrarlanmaz.
- Hesap ve sunucu ayrımlı okuma önbelleği ve anahtarlar. Çevrimdışı içerik eskilik uyarısıyla gösterilir.
- Kayıtlı sunucu/hesap seçici; anahtarı yeniden girmeden açık canlı bağlantı eylemi. Uygulama yeniden açıldığında çevrimdışı kalır.
- Hesaba ait fikir defteri; eski cihaz fikirleri korunur ve yalnız açık seçimle seçili hesaba kopyalanır.
- Tek bildirim için açık okundu işlemi, sunucudan durum doğrulaması ve belirsiz sonuç sonrası tekrar yazmadan önce durum okuma.
- PR listesinde 50’lik sayfalar; Bugün ekranında 10’luk ayrıntı grupları ve doğrulanmamış PR sayısı.
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

Birden fazla sunucu/hesap kaydedilebilir; aynı anda bir hesap seçilidir. Hesap kaldırma yalnız seçilen hesabın anahtarını, önbelleğini ve fikirlerini kaldırır; cihaz fikirleri ve diğer hesaplar korunur. Genel API listeleri 1.000 kayıtla sınırlıdır. PR sayfaları açık kullanıcı hareketiyle ilerletilir; son sayfa doğrulanana kadar liste tamamlanmış sayılmaz. Sayfalar arasında sunucudaki liste değişirse yeni bir yenileme gerekir; numaralarla tekrarlar ayıklanır. Gerçek merge, push bildirimleri ve App Store dağıtımı henüz yoktur. Arayüz şu an Türkçedir.

Ürün hedefi ve yayın öncesi eksikler için [ROADMAP.md](ROADMAP.md).

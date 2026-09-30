# Doğrulama — 30 Eylül 2026

- 86 birim testi geçti: API/önbellek/yazma güvenliği, kişiselleştirme/kilit, imza takvimi ve yeni ilk kullanım/hesap anahtarı ayrımı.
- İlk kurulum ekran testi geçti: kişisel sunucu bulunmayan bağlantı formu, anahtar olmadan gönderimin kapalı olması, açık demo seçimi ve yeniden açılışta korunması.
- Mevcut sentetik PR dosya/gelen kutusu ekran akışı geçti.
- iOS cihaz hedefi için imzasız Release derlemesi geçti; test amaçlı demo bayrağı ve kişisel sunucu adresi ikilide bulunmadı.
- GitHub deposunun private olduğu API üzerinden doğrulandı.

Testler Xcode 26.4 / iOS 26.4 simülatöründe çalıştırıldı. Bu değişiklik için fiziksel telefona yükleme veya gerçek kullanıcı hesabında yazma yapılmadı. Yeni ücretli Apple Developer hesabıyla imzalama, gerçek çoklu sunucu kabulü ve TestFlight dağıtımı M3 aşamasındadır.

GitHub Actions otomatik birim testi çalıştırır; her çalışmanın gerçek sonucu Actions sayfasından ayrı kontrol edilmelidir.

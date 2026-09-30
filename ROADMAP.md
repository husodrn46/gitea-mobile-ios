# Ürün hedefi

Kullanıcının kendi Gitea sunucusundaki depolarını, konularını ve PR incelemelerini iPhone'dan güvenle yönetebildiği, kişisel sunucuya bağlı olmayan bağımsız bir istemci geliştirmek.

## M1 — Genel kullanıma geçiş

- [x] Sunucu adresi içermeyen ilk kullanım; demo için açık seçim.
- [x] Kişisel proje/adların sentetik içeriklerden kaldırılması.
- [x] Aynı sunucudaki kullanıcılar için ayrı Keychain kayıtları.
- [x] Sunucu/hesap ayrımlı favoriler; eski favoriler son bilinen hesaba taşınır.
- [x] Private GitHub deposu ve birim testi CI altyapısı.
- [ ] Farklı gerçek Gitea kurulumlarıyla kullanıcı kabulü.

## M2 — Çoklu hesap ve uluslararası kullanım

Kayıtlı sunucu/hesap seçici, hesap bazında fikir defteri, açık hesap adıyla yazma onayı, İngilizce/Türkçe yerelleştirme, alt dizinli HTTPS kurulumları için güvenli URL modeli ve erişilebilirlik incelemesi.

## M3 — Beta dağıtım

Ücretli geliştirici hesabı ile imzalama, TestFlight, gizlilik manifesti ve App Store gizlilik beyanı, son kullanıcı yardım sayfaları, hata raporlama tercihleri, sürümleme/geri alma ve gerçek cihaz ağ/kilit testleri. TestFlight veya App Store'a bu ilk geliştirme adımında yayın yapılmaz.

## Kabul ölçütü

Temiz kurulum hiçbir kişisel sunucuya kendiliğinden bağlanmaz. Aynı sunucuda iki kullanıcı birbirinin anahtarını veya önbelleğini kullanamaz. Çevrimdışı içerik güncelmiş gibi gösterilmez. Yazma başarısı gerçek sunucu makbuzuyla doğrulanır; belirsiz istekler yeniden gönderilmez.

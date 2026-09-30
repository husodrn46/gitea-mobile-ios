# Doğrulama — 30 Eylül 2026

## Tasarım sadeleştirme — 30 Eylül 2026

Yalnız mevcut ekran sunumu değişti. API, kimlik doğrulama, önbellek, yazma doğrulaması ve fikir saklama modeli değiştirilmedi.

- Bugün: küçük gezinme başlığı, tek proje/filtre satırı, sade yenileme; kapsam ve değişiklik geçmişi açılır özet. Doğrulanmamış PR sayısı kapalı özette de görünür. Boş değişiklik bilgisi listenin sonuna alındı.
- Gelen kutusu: okunmamış/tümü filtresi, aynı kartın içinde hedef hesap/sunucu ve açık okundu hareketi. Ayrı ayrı yüzen işlem blokları kaldırıldı.
- Hesaplar: sade hesap satırları; seçili hesap işareti. Mevcut bağlantı, çevrimdışı seçim ve onaylı kaldırma işlemleri hesaba dokununca açılan panelde.
- Profil: hesap/bağlantı ile kişiselleştirme ayrıldı; çevrimdışı ayrıntıları ve uygulama açıklaması açılır alanlara taşındı.
- Projeler: filtre etrafındaki ikinci cam yüzey kaldırıldı. Mor vurgu, cihaz temasına uyum ve kişiselleştirme ayarları korundu.

Tasarım dili: SF sistem yazısı; sayfa başlığı gezinmede, bölüm başlığı title2, içerik headline/subheadline, bağlam caption. Açık zemin #F3F3F7, açık yüzey #FFFFFF, mevcut mor #7044BC; koyu zemin #131418 ve koyu mor #BC9CFF. Cam ana iOS gezinmesine bırakıldı; içerik işlemleri düz veya bordered. İçerik sola hizalı, açıklama ve yönetim işlemleri ikinci planda.

Son simülatör koşusunda 4 mevcut akış geçti: tek bildirim okundu, hesap panelinden seçim, açılır kapsam içinden 10’luk yükleme ve değişiklik geçmişi/PR navigasyonu. Ayrı koşuda koyu tema ve erişilebilirlikte en büyük yazı ile mevcut proje/konu akışı geçti. Yeni görüntüler görsel olarak incelendi. Açılır grubun erişilebilirlik kimliğinin alt düğmeleri ezmesi testte tespit edildi ve son geçen koşudan önce düzeltildi.

Kanıt: `/private/tmp/gitea-design-pass-ui-20260930.xcresult`; büyük yazı/koyu tema: `/private/tmp/gitea-design-ui-20260930.xcresult`. Fiziksel telefona yükleme yapılmadı. Aşağıdaki 105 birim testi, önceki işlev geliştirme aşamasının kanıtıdır; tasarım aşamasında tekrarlanmadı.

## Açık issue geliştirmeleri (#1–#4)

- Son kaynakla **105 birim testi geçti** (86 mevcut + 19 yeni regresyon).
- Kayıtlı hesaba anahtar girmeden yeniden bağlanma; yanlış hesap/401/ağ hatasında eski kayıt ve alınma zamanının korunması; bağlantı sürerken hesap değiştirme.
- Aynı sunucuda iki hesap ve ikinci sunucuda bir hesap için anahtar/favori/fikir/önbellek ayrımı; yalnız seçili hesabı kaldırma; eski cihaz fikirlerini açık seçimle ve asıllarını koruyarak kopyalama.
- Bildirim okundu işlemi için taze ön okuma, açık PATCH, ayrı GET doğrulaması; yazma izni reddi, doğrulanmayan yanıt, bağlantı kesintisi ve istek sürerken hesap değişimi. Belirsiz sonuç sonrası yeniden hareket, önce durumu okur; zaten okunduysa tekrar yazmaz.
- 51 ve 101 PR sayfalaması; yinelenen numaraları ayıklama; başarısız sayfayı aynı cursor ile yeniden isteme; yenileme/hesap değişimi/iptal sonrasında geç gelen sayfanın reddi.
- Sunucunun sayfa boyutunu sınırlaması: kısa sayfa tek başına tamamlanma kanıtı değildir. Link/ilk sayfanın toplam sayısı yoksa boş sayfa gelene kadar devam olasılığı gösterilir.
- Çevrimdışı sayfa kapsamı ve en eski alınma zamanı korunur. Yeni sayfa, önceden önbellekten gelen sayfaları güncelmiş gibi göstermez.

## Simülatör ekran akışları

Ayrı seçili test koşularında dokuz akış geçti:

1. Temiz ilk kurulum ve açık demo seçiminin yeniden açılışta korunması.
2. PR dosya/kod farkı ve gelen kutusu navigasyonu.
3. Açık okundu hareketi sonrası yalnız doğrulanan bildirimin okunmamış filtresinden çıkması.
4. Üç kayıtlı hesabın sunucu ve kullanıcıyla gösterilmesi, hesap seçimi.
5. Bugün ayrıntılarının 10’luk gruplar halinde yüklenmesi; doğrulanmamış sayının 40 → 30 değişmesi.
6. Bugün kuyruğu, değişen commit ve PR görünümünün bağlantısı.
7. Fikirden konu oluşturma, görünür başarı ekranı ve yerel fikrin korunması.
8. Konu okuma ve açık yorum gönderme.
9. Yorum taslağının küçültme ve yeniden açılışta korunması.

Ekran görüntüleri hesap seçici, kuyruk ve bildirim için görsel olarak incelendi. Konu formundaki yeni hedef satırı sonrasında kaydırma testini güncelledik; başarılı gönderimi ayrı kısa bir sonuç görünümüne çevirdik.

Son kaynakla iOS cihaz hedefi için **imzasız Release derlemesi geçti**. Testler Xcode 26.4 / iOS 26.4 simülatöründedir. Bu geliştirmelerde fiziksel telefona yükleme veya gerçek bir Gitea hesabında yazma yapılmadı. Ücretli Apple Developer hesabıyla imzalama, gerçek çoklu sunucu kabulü ve TestFlight ayrı yayın aşamasındadır.

## Kanıt konumları

- Son birim sonucu: `/private/tmp/gitea-issues-unit-final-20260930.xcresult`
- Hesap/bildirim/kademeli kuyruk ve yorum akışları: `/private/tmp/gitea-issues-acceptance2-20260930.xcresult` (konu başarı görünümü bu koşuda bulunamadı; aşağıdaki sonraki koşuda düzeltildi).
- Konu oluşturma için geçen son koşu: `/private/tmp/gitea-issues-verified-20260930.xcresult`
- İlk kullanım/PR akışları: `/private/tmp/gitea-issues-ui-20260930.xcresult`
- Bugün/commit akışı: `/private/tmp/gitea-issues-final-20260930.xcresult`
- Son Release günlüğü: `/private/tmp/gitea-issues-release-final.log`

Bildirim rotası ve 205 yanıtı [resmî Gitea kaynağından](https://github.com/go-gitea/gitea/blob/main/routers/api/v1/notify/threads.go) doğrulandı. Fixture işlemleri Debug yapıda ve sentetik verilerle sınırlıdır.

GitHub Actions birim testlerini çalıştıracak biçimde yapılandırılmıştır; her uzak koşunun sonucu ve yerel test kanıtı ayrı değerlendirilir.

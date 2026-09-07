# 🚀 Simpleks - Windows 11 Optimizasyon Motoru

**Simpleks**, Windows 11 (24H2/25H2) için kanıta dayalı, geri alınabilir ve
şeffaf bir PowerShell optimizasyon motorudur. Hedefi maksimum oyun
performansı/FPS, düşük gecikme ve boştayken (idle) minimum RAM/CPU
kullanımıdır - popüler ama mekanizması olmayan "gaming registry tweak"leri
kasıtlı olarak dışarıda bırakır (bkz. [`docs/RESEARCH.md`](docs/RESEARCH.md)).

Özellikle üst düzey sistemler (ör. Ryzen 7 9800X3D & RTX 5070 Ti) için
tasarlanmış olsa da tüm modern Windows 11 masaüstü/dizüstü sistemlerinde
çalışır (donanım-farkında kontroller dizüstü/HDD sistemlerde riskli
tweak'leri otomatik atlar).

## Neden Simpleks?

- **Kanıta dayalı**: her tweak `docs/RESEARCH.md`'de gerekçelendirilmiştir;
  5 büyük açık kaynak Windows debloat/optimizasyon projesiyle karşılaştırılıp
  hiçbirinde bulunmayan "placebo" ayarlar (ör. `NetworkThrottlingIndex`,
  per-arayüz Nagle kapatma, zorla core-parking) kataloğa alınmamıştır.
- **Şeffaf**: `-ListTweaks` ile tüm katalog, `-Status` ile sisteminizdeki
  güncel durum (Uygulanmış/Uygulanmamış/Bilinmiyor) görüntülenir.
- **Geri alınabilir**: her çalıştırma öncesi bir Sistem Geri Yükleme noktası
  oluşturulur ve her değişiklik `logs\backup-*.json` içine kaydedilir;
  `-Rollback last` ile tek komutla geri alınır.
- **Güvenliği asla varsayılan olarak zayıflatmaz**: Defender, Güvenlik
  Duvarı, Windows Update servisi ve UAC'nin kendisi hiçbir presette
  kapatılmaz. Güvenlik etkisi olan 4 "expert" tweak (ör. CPU mitigasyonlarını
  kapatma) yalnızca `-IncludeRisky` ile VE çalışma zamanında ayrıca
  onaylanarak uygulanabilir.
- **Donanım-farkında**: dizüstü/pil tespit edilirse Hazırda Beklet
  kapatılmaz; HDD tespit edilirse SysMain/Prefetch kapatılmaz; yazıcı
  tespit edilirse Print Spooler kapatılmaz.

## Presetler

Presetler kümülatiftir: her üst seviye bir alttakini kapsar.

| Preset | Kapsam |
|---|---|
| **Safe** | Kozmetik + apaçık güvenli ayarlar (HAGS, Oyun Modu, Game DVR kapatma, fare ivmesi, görev çubuğu/Başlat kozmetikleri). Windows işlevselliğinden hiçbir şey feda edilmez. |
| **Balanced** *(varsayılan)* | Safe + telemetri/aktivite geçmişi kapatma, arka plan UWP kısıtlaması, Recall/Copilot kapatma, Teslimat Optimizasyonu (P2P kapalı), nadir kullanılan servisler, telemetri zamanlanmış görevleri. Windows Update, Store, Defender, ağ, Bluetooth, yazdırma korunur. |
| **Performance** | Balanced + MMCSS oyun önceliği, CPU zamanlayıcı önceliği, SysMain/Prefetch kapatma (yalnızca SSD), koşullu servisler (Harita/Konum/WMP Ağı). |
| **Extreme** | Performance + Arama indeksleme kapatma, Print Spooler kapatma (yazıcı yoksa), OneDrive kaldırma. Güvenlik etkili tweak'ler **bu preset dahil hiçbir zaman otomatik açılmaz** - `-IncludeRisky` ayrıca gereklidir. |

Tam katalog için [`docs/TWEAKS.md`](docs/TWEAKS.md).

## Kurulum ve Kullanım

PowerShell'i **Yönetici olarak** açın:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
irm https://raw.githubusercontent.com/muratbulat/simpleks/main/Simpleks-Win11.ps1 -OutFile Simpleks-Win11.ps1
irm https://raw.githubusercontent.com/muratbulat/simpleks/main/Simpleks.Definitions.ps1 -OutFile Simpleks.Definitions.ps1
.\Simpleks-Win11.ps1
```

> `Simpleks-Win11.ps1`, yanındaki `Simpleks.Definitions.ps1` dosyasına ihtiyaç
> duyar - ikisini de aynı klasöre indirin (tek satırlık `iex` ile doğrudan
> pipe'lama artık desteklenmez, çünkü motor iki dosyaya bölündü).

### Komutlar

```powershell
# Varsayılan (Balanced) preset ile uygula
.\Simpleks-Win11.ps1

# Belirli bir preset
.\Simpleks-Win11.ps1 -Preset Performance
.\Simpleks-Win11.ps1 -Preset Extreme -IncludeRisky

# Sadece belirli tweak'leri uygula
.\Simpleks-Win11.ps1 -OnlyIds "gaming.game-mode-hags","ai.copilot-off"

# Neyin değişeceğini görmek için hiçbir şeyi uygulamadan simüle et
.\Simpleks-Win11.ps1 -Preset Extreme -WhatIf

# Tüm katalogu listele (yönetici gerekmez)
.\Simpleks-Win11.ps1 -ListTweaks

# Sisteminizdeki mevcut durumu görün (yönetici gerekmez)
.\Simpleks-Win11.ps1 -Status

# Son çalıştırmayı geri al
.\Simpleks-Win11.ps1 -Rollback last

# İsteğe bağlı yazılım kurulumu (Chocolatey) ve ön yüklü uygulama temizliği
.\Simpleks-Win11.ps1 -InstallPackages
.\Simpleks-Win11.ps1 -RemoveOptionalApps
```

### Etkileşimli Menü

Komut satırı parametreleri yerine profil seçip çalıştırmak için:

```powershell
.\Simpleks-Menu.ps1
```

Menü; Safe/Balanced/Performance/Extreme profillerinden birini seçmenizi,
isteğe bağlı olarak önce `-WhatIf` ile simüle etmenizi, Extreme profilinde
`-IncludeRisky` dahil edip etmeyeceğinizi sormanızı ve ardından
`Simpleks-Win11.ps1`'i uygun parametrelerle çalıştırmanızı sağlar. Ayrıca
katalog listeleme, durum görüntüleme ve son çalıştırmayı geri alma
seçeneklerini de içerir. Yönetici gerektiren bir işlem seçildiğinde ve
oturum yönetici değilse, yeniden yönetici olarak başlatılması önerilir.

## Güvenlik Modeli

1. Her çalıştırma (yönetici + değişiklik modu) öncesi bir **Sistem Geri
   Yükleme noktası** oluşturulmaya çalışılır (`-SkipRestorePoint` ile
   atlanabilir).
2. Her registry/servis/görev değişikliği, önceki değeriyle birlikte
   `logs\backup-<zaman damgası>.json` dosyasına kaydedilir.
3. `-Rollback last` (veya belirli bir backup dosyası yolu) bu kayıtları
   ters sırayla geri uygular.
4. Güvenlik etkisi taşıyan 4 tweak (UAC seviyesi, Sistem Geri Yükleme,
   VBS/Çekirdek Yalıtımı, CPU mitigasyonları) **hiçbir preset tarafından
   otomatik uygulanmaz**; yalnızca `-IncludeRisky` ile VE (silent mod
   dışında) çalışma zamanında elle onaylanarak uygulanır.
5. Windows Update servisi, Microsoft Defender, Güvenlik Duvarı, SmartScreen
   hiçbir preset/bayrak kombinasyonuyla kapatılmaz.

## Kapsam Dışı (bilinçli olarak yapılmayanlar)

- Microsoft Defender/SmartScreen/Güvenlik Duvarını kapatmak.
- Windows Update'i tamamen durdurmak (yalnızca P2P dağıtımı ayarlanır).
- WinSxS/DriverStore gibi servis dosyalarını elle silmek.
- Kanıtlanmamış "gaming ping tweak"leri (bkz. `docs/RESEARCH.md` "Kasıtlı
  Olarak Yapılmayanlar" bölümü).

## Test

```powershell
Install-Module Pester -MinimumVersion 5.0.0 -Scope CurrentUser
Invoke-Pester ./tests
```

Testler yalnızca saf mantığı (tweak şeması, preset çözümleme, güvenlik
kapısı) doğrular; hiçbir registry/servis değişikliği yapmaz, bu yüzden
Windows dışı ortamlarda (CI dahil) da güvenle çalışır. `.github/workflows/ci.yml`
her push/PR'da PSScriptAnalyzer + Pester çalıştırır.

## Katkı

Yeni bir tweak önerirken lütfen:

1. Mekanizmayı açıklayın (hangi registry/servis/görev neyi neden değiştiriyor).
2. En az bir sürdürülen referans projede (yukarıdaki 5 proje) uygulandığını
   gösterin, ya da Microsoft dokümantasyonuna bağlantı verin.
3. `Detect`/`Apply` scriptblock'larını ve `docs/TWEAKS.md`/`docs/RESEARCH.md`
   güncellemesini birlikte gönderin.

## Lisans

MIT - bkz. [`LICENSE`](LICENSE).

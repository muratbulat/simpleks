# Simpleks - Tweak Kataloğu

Bu belge `Simpleks.Definitions.ps1` içindeki `Get-SimpleksTweaks` fonksiyonunun
insan tarafından okunabilir dökümüdür. Güncel kaynak her zaman koddur; bu
belge kod değiştiğinde güncellenmelidir.

Alan açıklamaları:

- **Seviye (Tier)**: tweak'in dahil olduğu en düşük preset. Presetler
  kümülatiftir: Balanced = Safe+Balanced, Performance = Safe+Balanced+Performance,
  Extreme = hepsi. Güvenlik etkili (🔒) tweak'ler presete girse bile
  `-IncludeRisky` verilmeden ASLA uygulanmaz.
- **Risk**: Safe / Moderate / Aggressive / Experimental - subjektif değil,
  geri alınabilirlik + yan etki büyüklüğüne göre atanmıştır.
- **Geri Alınabilir**: `-Rollback last` ile önceki registry/servis/görev
  değerine dönülüp dönülemeyeceği. "Kısmi" = teknik olarak tersine çevrilebilir
  ama otomatik değil (ör. kaldırılan bir uygulamayı yeniden kurmak gerekir).

## Power / CPU

| Id | Ad | Seviye | Risk | Yeniden Başlatma | Geri Alınabilir |
|---|---|---|---|---|---|
| `power.ultimate-plan` | Ultimate Performance Güç Planı | Safe | Safe | Hayır | Evet |
| `power.hibernate-off` | Hazırda Beklet Kapatma (laptop'ta atlanır) | Balanced | Moderate | Hayır | Evet |
| `power.reset-forced-timer-resolution` | Zorlanmış Zamanlayıcı Çözünürlüğünü Sıfırlama | Balanced | Safe | Hayır | Evet |
| `cpu.win32-priority-separation` | Ön Plan Uygulaması İçin CPU Zaman Dilimi Önceliği | Performance | Moderate | Evet | Evet |

## Gaming

| Id | Ad | Seviye | Risk | Yeniden Başlatma | Geri Alınabilir |
|---|---|---|---|---|---|
| `gaming.game-mode-hags` | Oyun Modu + HAGS | Safe | Safe | Evet | Evet |
| `gaming.gamedvr-off` | Game DVR Kapatma | Safe | Safe | Hayır | Evet |
| `gaming.gamebar-off` | Xbox Game Bar Overlay Kapatma | Balanced | Safe | Hayır | Evet |
| `gaming.mmcss-games-priority` | MMCSS Oyun Görev Önceliği | Performance | Moderate | Hayır | Evet |

## Network

| Id | Ad | Seviye | Risk | Yeniden Başlatma | Geri Alınabilir |
|---|---|---|---|---|---|
| `network.delivery-optimization-http` | Teslimat Optimizasyonu: Sadece HTTP | Balanced | Safe | Hayır | Evet |

## Storage

| Id | Ad | Seviye | Risk | Yeniden Başlatma | Geri Alınabilir |
|---|---|---|---|---|---|
| `storage.sysmain-prefetch-off` | SysMain + Prefetch Kapatma (yalnızca SSD/NVMe) | Performance | Moderate | Evet | Evet |
| `storage.ntfs-last-access-off` | NTFS Son Erişim Damgalamayı Kapatma | Performance | Safe | Hayır | Evet |

## Search

| Id | Ad | Seviye | Risk | Yeniden Başlatma | Geri Alınabilir |
|---|---|---|---|---|---|
| `search.indexing-off` | Windows Arama İndekslemeyi Kapatma | Extreme | Aggressive | Hayır | Evet |

## Privacy / Background / AI

| Id | Ad | Seviye | Risk | Yeniden Başlatma | Geri Alınabilir |
|---|---|---|---|---|---|
| `privacy.telemetry-off` | Telemetri (DiagTrack) Kapatma | Balanced | Safe | Hayır | Evet |
| `privacy.activity-history-off` | Aktivite Geçmişini Kapatma | Balanced | Safe | Hayır | Evet |
| `background.uwp-apps-off` | Arka Plan UWP Uygulamaları Kapatma | Balanced | Safe | Hayır | Evet |
| `ai.recall-off` | Windows Recall / Click to Do Kapatma | Balanced | Safe | Hayır | Kısmi (registry kısmı tam geri alınır, isteğe bağlı Recall özelliği kapatma denemesi izlenmez) |
| `ai.copilot-off` | Windows Copilot Kapatma | Balanced | Safe | Hayır | Evet |

## Services / Scheduled Tasks

| Id | Ad | Seviye | Risk | Yeniden Başlatma | Geri Alınabilir |
|---|---|---|---|---|---|
| `services.legacy-off` | Fax / Uzak Kayıt Defteri / RetailDemo / Wallet Kapatma | Balanced | Safe | Hayır | Evet |
| `services.conditional-off` | Harita / Konum / WMP Ağı / PCA Kapatma | Performance | Moderate | Hayır | Evet |
| `services.print-spooler-off` | Print Spooler Kapatma (yazıcı varsa atlanır) | Extreme | Aggressive | Hayır | Evet |
| `tasks.telemetry-tasks-off` | Telemetri/CEIP Zamanlanmış Görevlerini Kapatma | Balanced | Safe | Hayır | Evet |

## UI / Explorer

| Id | Ad | Seviye | Risk | Geri Alınabilir |
|---|---|---|---|---|
| `ui.taskbar-left-align` | Görev Çubuğunu Sola Hizalama | Safe | Safe | Evet |
| `ui.widgets-off` | Widget'ları Kapatma | Safe | Safe | Evet |
| `ui.start-suggestions-off` | Başlat Menüsü Önerilerini Kapatma | Safe | Safe | Evet |
| `ui.web-search-off` | Görev Çubuğu Web Aramasını Kapatma | Safe | Safe | Evet |
| `ui.taskbar-search-off` | Görev Çubuğu Arama Kutusunu Kapatma | Safe | Safe | Evet |
| `ui.numlock-on-boot` | Açılışta NumLock | Safe | Safe | **Kısmi** (reg.exe ile yazılır, yedekleme motorundan geçmez - elle geri alma komutu tweak açıklamasında) |
| `ui.menu-delay-off` | Menü Açılış Gecikmesini Sıfırlama | Safe | Safe | Evet |

## Bloatware

| Id | Ad | Seviye | Risk | Geri Alınabilir |
|---|---|---|---|---|
| `onedrive.remove` | OneDrive'ı Kaldırma | Extreme | Aggressive | **Kısmi** (yeniden kurulum gerekir) |

## 🔒 Security (yalnızca `-IncludeRisky` ile, her biri çalışma zamanında ayrıca onay ister)

| Id | Ad | Seviye | Risk | Güvenlik Etkisi |
|---|---|---|---|---|
| `security.uac-lowest` | UAC'yi En Düşük Seviyeye Ayarlama | Extreme | Aggressive | UAC istemlerini sessizleştirir |
| `security.system-restore-off` | Sistem Geri Yüklemeyi Kapatma | Extreme | Aggressive | Geri dönüş imkanını kaldırır |
| `security.vbs-off` | VBS / Çekirdek Yalıtımını Kapatma | Extreme | Experimental | Hypervisor tabanlı bellek koruması kapanır |
| `security.cpu-mitigations-off` | CPU Spekülatif Yürütme Önlemlerini Kapatma | Extreme | Experimental | Spectre/Meltdown sınıfı saldırılara açık hale gelir |

---

Her tweak'in tam teknik gerekçesi (registry yolu, kaynak proje karşılaştırması,
neden dahil edildiği/edilmediği) için bkz. [`RESEARCH.md`](RESEARCH.md).
Canlı durumu görmek için: `.\Simpleks-Win11.ps1 -Status`. Tam kataloğu ve
alanları uçtan uca görmek için: `.\Simpleks-Win11.ps1 -ListTweaks`.

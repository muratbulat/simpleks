# Simpleks - Optimizasyon Araştırma Notları

Bu belge, Simpleks'e eklenen (veya kasıtlı olarak eklenmeyen) her optimizasyonun
teknik gerekçesini belgeler. Amaç: popüler olduğu için değil, kanıtlanabilir bir
mekanizması olduğu için tweak eklemek.

Karşılaştırma için incelenen aktif olarak sürdürülen projeler:

- [ChrisTitusTech/winutil](https://github.com/ChrisTitusTech/winutil)
- [Raphire/Win11Debloat](https://github.com/Raphire/Win11Debloat)
- [Atlas-OS/Atlas](https://github.com/Atlas-OS/Atlas)
- [farag2/Sophia-Script-for-Windows](https://github.com/farag2/Sophia-Script-for-Windows)
- [hellzerg/optimizer](https://github.com/hellzerg/optimizer)

Yöntem: her projenin kaynak kodu klonlanıp ilgili tweak için grep edildi (bir
ayarın "popüler" olup olmadığına değil, gerçekten sürdürülen kodda uygulanıp
uygulanmadığına bakıldı). Zaten Simpleks'e eklenmiş olanlar dahil, kararı
etkileyebilecek yeni bulgular bu belgede işaretlidir.

## Karar Tablosu

| Tweak | Mekanizma | Kanıt | Karar |
|---|---|---|---|
| Ultimate Performance güç planı | Gizli, agresif bir powercfg şemasını çoğaltır | Yaygın, MS tarafından belgelenmiş şema GUID'i | **Dahil** (Safe) |
| HAGS + Oyun Modu | GPU zamanlamasını sürücüye devreder | MS tarafından belgelenmiş, Win10 2004+ | **Dahil** (Safe) |
| MMCSS `SystemProfile\Tasks\Games` önceliği | MMCSS'e "Games" görev sınıfı için GPU/CPU önceliği bildirir | hellzerg/optimizer aynı bloğu (GPU Priority=8, Priority=6, Scheduling Category=High, SFIO Priority=High) uygular | **Dahil** (Performance) - VERIFIED |
| Win32PrioritySeparation=38 | Zamanlayıcı kotasını ön plan sürecine kısa/sabit dilimlerle ayırır | Atlas-OS açıkça "Prioritize Foreground Applications" olarak uygular | **Dahil** (Performance) - LIKELY BENEFICIAL |
| `NetworkThrottlingIndex` / `SystemResponsiveness` | Vista/Win7 dönemi MMCSS ağ kısıtlama ayarı | 5 projenin **hiçbirinde** yok | **REDDEDİLDİ** - PLACEBO/LEGACY. Modern MMCSS bu değerleri farklı yönetiyor; sürdürülen hiçbir proje artık taşımıyor. |
| Per-arayüz `TcpAckFrequency`/`TCPNoDelay` (Nagle kapatma) | Windows XP/7 döneminde TCP ACK gecikmesini/Nagle'ı kapatan registry hilesi | 5 projenin **hiçbirinde** yok | **REDDEDİLDİ** - PLACEBO/LEGACY. Modern NDIS/TCP yığını bu anahtarları büyük ölçüde göz ardı ediyor; kanıtlanmamış "gaming ping tweak" kategorisine giriyor. |
| `powercfg CPMINCORES=100` (core parking kapatma) | Çekirdek parklamayı zorla kapatır | 5 projenin **hiçbirinde** doğrudan bu şekilde yok | **REDDEDİLDİ** (literal knob olarak) - PLACEBO/LEGACY. Modern zamanlayıcı + EcoQoS bunu dinamik yönetiyor. |
| `GlobalTimerResolutionRequests` / HPET / dynamictick zorlama | Zamanlayıcı çözünürlüğünü zorla yükseltir | Atlas'ın **varsayılan davranışı bu anahtarı SİLMEK** (zorlayıcıları kaldırmak), zorlamak değil | **Ters yönde dahil**: Simpleks zorlanmış çözünürlüğü *kaldıran* bir temizlik tweak'i içerir (`power.reset-forced-timer-resolution`), zorlayan bir tweak değil. |
| `LargeSystemCache` | Dosya sistemi önbelleğini "sunucu" moduna alır | 5 projenin **hiçbirinde** yok | **REDDEDİLDİ** - PLACEBO/LEGACY, masaüstü/oyun iş yükü için yanlış varsayılan. |
| `DisablePagingExecutive` | Çekirdek/sürücü sayfalanabilir havuzunu RAM'de sabit tutar | Yalnızca Atlas, `DisablePageCombining` ile birlikte, adlandırılmış bir "expert" tweak olarak | **REDDEDİLDİ (varsayılan settten)** - EXPERIMENTAL. Gerçek bir mekanizması var ama yetersiz RAM'de kararsızlığa yol açabilir; Simpleks'in hedef kitlesi (16-64GB masaüstü) için riski faydasından yüksek görüldü, güvenli varsayılana dahil edilmedi. |
| SysMain (Superfetch) + Prefetch kapatma | Disk/RAM önbellekleme sezgiselini kapatır | Atlas ve hellzerg/optimizer ikisi de **opsiyonel** tweak olarak sunuyor, zorunlu değil | **Dahil** (Performance, yalnızca SSD/NVMe tespit edilirse - HDD'de otomatik atlanır) - WORKLOAD-SPECIFIC |
| Windows Arama (WSearch) kapatma | İndeksleme servisini durdurur | Win11Debloat ve Atlas ikisi de **açık onay gerektiren** ayrı bir toggle olarak sunuyor | **Dahil** (yalnızca Extreme preset - varsayılan hiçbir presette değil) - WORKLOAD-SPECIFIC |
| Delivery Optimization | P2P güncelleme paylaşımı | Sophia/Atlas/Win11Debloat/winutil dördü de servisi öldürmek yerine **`DODownloadMode` politikasını** ayarlıyor | **Dahil** (Balanced, `DODownloadMode=1`) - VERIFIED; Windows Update servisine dokunulmaz. |
| CPU mitigasyonlarını kapatma (`FeatureSettingsOverride=3`) | Spectre/Meltdown mikro-kod önlemlerini devre dışı bırakır (KB4073119) | Yalnızca Atlas, ayrı "Disable All Mitigations" adımı olarak, **hiçbir projede varsayılan değil** | **Dahil ama sıkı kapılı**: yalnızca Extreme + `-IncludeRisky` + çalışma zamanı onayı ile. Ölçülebilir FPS kazancı donanıma bağlı ve genelde küçük; güvenlik bedeli açıkça etiketlenir. |
| Windows Recall / Click to Do kapatma | `WindowsAI` politika anahtarları + (varsa) isteğe bağlı özelliği kapatma | Win11Debloat/Atlas/winutil üçü de aynı `DisableAIDataAnalysis`/`AllowRecallEnablement`/`DisableClickToDo` anahtarlarını kullanıyor; winutil ayrıca `TurnOffSavingSnapshots` da ekliyor (Simpleks'e eklendi) | **Dahil** (Balanced). Not: Recall yalnızca NPU'lu "Copilot+ PC" donanımında var olur; bu projenin hedef donanımında (Ryzen 9800X3D + RTX 5070 Ti, NPU yok) özellik zaten mevcut değildir - ayar önleyici niteliktedir. |
| Windows Copilot kapatma | `WindowsCopilot` politika anahtarı | Atlas açıkça not düşüyor: **yalnızca HKCU çalışır, HKLM kopyası onurlandırılmaz** | **Dahil** (Balanced), yalnızca HKCU yazılır (HKLM'e boşuna yazmıyoruz). |

## Presets ve AppX Yaklaşımı - Referans Projelerden Öğrenilenler

- **winutil**: adlandırılmış preset dizileri (`Standard`/`Minimal`/`Advanced`)
  tweak ID'lerine referans veriyor; AppX kaldırma için display-name değil
  paket-ailesi-adı allowlist'i kullanıyor. Simpleks bu iki deseni de benimsedi
  (`Tier` alanı + `$OptionalAppxPackages` allowlist).
- **Win11Debloat**: düz bir `DefaultSettings.json` boolean toggle listesi
  kullanıyor, kademeli preset yok. Simpleks bunun yerine kümülatif
  Safe→Balanced→Performance→Extreme kademesini tercih etti çünkü kullanıcıya
  "bir üst seviye her zaman bir alttakini kapsar" garantisini veriyor.
- **Sophia-Script / Atlas**: tweak'leri tekil, tipli aksiyon modülleri olarak
  yapılandırıyor. Simpleks tek-dosyalık PowerShell projesi kapsamını aşmamak
  için tweak'leri `Simpleks.Definitions.ps1` içinde nesne dizisi olarak tutar,
  ama her nesne aynı meta-veri modelini (Id/Category/Risk/Detect/Apply) taşır.

## Kasıtlı Olarak Yapılmayanlar

- **Microsoft Defender / SmartScreen / Güvenlik Duvarını kapatmak**: hiçbir
  presette yok, hiçbir bayrakla açılmıyor. Performans kazancı ölçülebilir
  olsa da güvenlik bedeli orantısız; bu proje "aggressive performance" ile
  "sistemi savunmasız bırakmak" arasına kasıtlı bir çizgi çekiyor.
- **Windows Update'i tamamen kapatmak**: yalnızca Delivery Optimization'ın
  P2P bileşeni ayarlanıyor; güncelleme servisinin kendisi hiçbir presette
  durdurulmuyor.
- **WinSxS / DriverStore'u elle silmek**: yalnızca DISM'in kendi
  desteklediği temizlik mekanizmaları güvenli kabul edilir; bu proje şu an
  için depolama temizliği modülü içermiyor (bkz. README "Kapsam Dışı").
- **HPET/dynamictick zorlama, LargeSystemCache, per-arayüz Nagle kapatma**:
  yukarıdaki tabloda gerekçelendirildiği gibi placebo/legacy kabul edildi.

## Kalan Fırsatlar (bu iterasyonda tamamlanmadı)

- Tam AppX envanteri + "provisioned package" çoklu-kapsam desteği (şu an
  yalnızca kullanıcı tanımlı allowlist + mevcut/provisioned temel kaldırma var).
- Donanım-farkında ağ adaptörü ayarları (Energy Efficient Ethernet vb.) -
  sürücüye göre anahtar adları değiştiği için güvenilir şekilde
  otomatikleştirilemedi; README'de elle yapılacak adım olarak önerilir.
- Gerçek bir "önce/sonra" ölçüm modülü (Phase 20) - süreç/servis/görev sayımı
  gibi basit metrikler `-Status` ile kısmen karşılanıyor, ama tam bir
  benchmark modülü henüz yok.
- CI'daki Pester testleri yalnızca saf mantığı (şema, preset çözümleme)
  kapsıyor; gerçek registry/servis Apply/Revert, bu ortamda gerçek Windows
  olmadığı için yalnızca fonksiyonları taklit eden (mock) manuel testlerle
  doğrulanabildi - gerçek bir Windows makinesinde uçtan uca doğrulama hâlâ
  önerilir.
- `-Silent -IncludeRisky` birlikte kullanıldığında güvenlik etkili
  tweak'lerin çalışma zamanı onayını atlaması **kasıtlı bir tasarım
  kararıdır** (otomatik/tekrarlanan çalıştırmalar için) - `-IncludeRisky`
  bayrağının kendisi zaten açık bir onaydır. Bu davranışı beklemiyorsanız
  `-Silent` kullanmayın.

### Bağımsız kod incelemesi sonrası düzeltmeler

Bu motorun ilk taslağı bağımsız bir statik inceleme (Codex) ve ardından
gerçek bir PowerShell 7 çalışma zamanında (Linux üzerinde, mock'lanmış
Windows cmdlet'leriyle) doğrulamadan geçirildi. Bulunan ve düzeltilen somut
hatalar:

- **Kritik**: `Get-SimpleksTweaks` içindeki yerel değişkenler
  (`$gamesTaskPath`, `$prefetchPath`, `$expAdvPath`) döndürülen
  `Detect`/`Apply` scriptblock'ları tarafından görülemiyordu (PowerShell
  scriptblock'ları closure değildir) - `$script:` kapsamına taşınarak
  düzeltildi ve gerçek çağrıyla doğrulandı.
- Yedekleme dosyası artık her tweak'ten sonra yazılıyor (yalnızca çalıştırma
  sonunda değil) - yarıda kesilen bir çalıştırma geri alınabilir kalır.
- `Set-Reg`/`Set-SvcState`/`Set-ScheduledTaskState` artık gerçek hatalarda
  `throw` ediyor; önceden başarısızlık sessizce yutulup tweak "Uygulandı"
  olarak loglanıyordu.
- Servis geri alma artık önceki `Status`'u (Running/Stopped) da yedekliyor
  ve geri almada gerekirse servisi yeniden başlatıyor.
- Zamanlanmış görev geri alması artık çalışma zamanı durumu (`State`) yerine
  `Settings.Enabled` kullanıyor - çalışmakta olan etkin bir görev yanlışlıkla
  "etkin değildi" sanılıp kapatılmıyor.
- `power.ultimate-plan` artık oluşturduğu şemayı GERÇEKTEN etkinleştiriyor
  (`-setactive`), GUID'i yerel olarak izleyerek tekrar çalıştırmalarda
  yinelenen şema oluşturmuyor, ve tespiti dile göre değişen şema adı yerine
  GUID karşılaştırmasıyla yapıyor.
- `Get-SimpleksActiveTweaks`, `-OnlyIds` ile çağrıldığında da güvenlik
  filtresini uyguluyor (önceden yalnızca çağıran taraftaki ikinci kontrole
  güveniyordu).
- `Restore-SimpleksBackupFile` artık yedek dosyasını güvenilmeyen veri
  olarak ele alıyor: yalnızca bilinen `Type` değerleri işleniyor, registry
  yolları yalnızca `HKLM:\`/`HKCU:\` ile başlıyorsa yazılıyor - ve bu
  doğrulamanın başarısız olduğu durumda (bir test sırasında bizzat
  yakalandığı gibi) PowerShell `switch`+`continue` etkileşimindeki bir
  incelik yüzünden hata sessizce "başarılı" olarak raporlanıyordu; bu da
  `throw`'a çevrilerek düzeltildi.
- Disk tespiti başarısız olduğunda (`Get-PhysicalDisk` hata verirse ya da
  hiç disk dönmezse) artık "SSD" değil "bilinmiyor" varsayılıyor, bu yüzden
  SysMain/Prefetch kapatma tespit edilemeyen bir HDD'de yanlışlıkla
  uygulanmıyor.
- `power.hibernate-off`, `security.system-restore-off` ve
  `storage.ntfs-last-access-off` artık gerçekten geri alınabilir hale
  getirildi (önceden `Reversible = $true` yazıyordu ama yedekleme
  motorundan hiç geçmiyorlardı); `ui.numlock-on-boot` ve `ai.recall-off` ise
  gerçek durumlarını yansıtacak şekilde `Reversible = "Partial"` olarak
  düzeltildi.

# 🚀 Simpleks - Windows 11 Optimizasyon Aracı

Windows 11 için tek dosyalık, grafik arayüzlü PowerShell optimizasyon
aracı. Kanıta dayalı, geri alınabilir, donanım-farkında (dizüstü/HDD/
yazıcı tespit edilirse uygunsuz tweak'ler otomatik atlanır).

## Çalıştır

Yönetici gerekmez - tek satır otomatik yükseltir ve arayüzü açar:

```powershell
irm https://raw.githubusercontent.com/muratbulat/simpleks/main/Simpleks.ps1 | iex
```

Açılan pencerede bir profil seçin, isterseniz tweak'leri tek tek
işaretleyin/kaldırın, **UYGULA**'ya basın.

## Özellikler

- **Grafik arayüz**: profil seç, tweak işaretle, uygula - komut satırı yok.
- **Profiller**: Safe / Balanced / Performance / Extreme (kümülatif).
- **Şeffaf**: "Durumu Yenile" sisteminizdeki güncel durumu (uygulanmış/
  uygulanmamış) her tweak için gösterir.
- **Geri alınabilir**: her uygulamadan önce Sistem Geri Yükleme noktası
  oluşturulur, her değişiklik kaydedilir; "Son Çalıştırmayı Geri Al" ile
  tek tıkla geri alınır.
- **Simülasyon**: "Sadece simüle et (WhatIf)" ile hiçbir şeyi
  değiştirmeden neyin uygulanacağını görün.
- **Güvenliği zayıflatmaz**: Defender, Güvenlik Duvarı, Windows Update ve
  UAC hiçbir profilde kapatılmaz. Güvenlik etkili birkaç tweak yalnızca
  "Riskli tweak'leri göster" açıkça işaretlenip elle seçilirse ve
  onaylanırsa uygulanır.

## Profiller

| Profil | Kapsam |
|---|---|
| **Safe** | Kozmetik + apaçık güvenli ayarlar. Windows işlevselliğinden ödün verilmez. |
| **Balanced** *(varsayılan)* | Safe + telemetri/arka plan kısıtlamaları, gereksiz servisler. |
| **Performance** | Balanced + oyun/CPU zamanlayıcı ayarları, koşullu servisler. |
| **Extreme** | Performance + arama indeksleme, yazıcı/OneDrive kaldırma. |

## Test

```powershell
Install-Module Pester -MinimumVersion 5.0.0 -Scope CurrentUser
Invoke-Pester ./tests
```

`Simpleks.ps1` dot-source edildiğinde hiçbir pencere açmaz ve hiçbir
sistem değişikliği yapmaz - testler yalnızca saf mantığı doğrular (tweak
şeması, preset çözümleme, güvenlik kapısı).

## Lisans

MIT - bkz. [`LICENSE`](LICENSE).

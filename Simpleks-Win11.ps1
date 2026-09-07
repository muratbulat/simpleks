<#
    Simpleks - Windows 11 Pro (24H2/25H2) Optimizasyon Motoru
    Hedef: Maksimum oyun performansı/FPS, düşük gecikme, boştayken (idle)
           minimum RAM ve CPU tüketimi - ölçülebilir mekanizması olmayan
           "placebo" ayarlar dahil edilmez (bkz. docs/RESEARCH.md).

    Kullanım örnekleri:
        .\Simpleks-Win11.ps1                          # Balanced preset uygular
        .\Simpleks-Win11.ps1 -Preset Performance
        .\Simpleks-Win11.ps1 -Preset Extreme -IncludeRisky
        .\Simpleks-Win11.ps1 -ListTweaks
        .\Simpleks-Win11.ps1 -Status
        .\Simpleks-Win11.ps1 -WhatIf
        .\Simpleks-Win11.ps1 -OnlyIds "gaming.game-mode-hags","ai.copilot-off"
        .\Simpleks-Win11.ps1 -Rollback last
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet("Safe", "Balanced", "Performance", "Extreme")]
    [string]$Preset = "Balanced",

    [string[]]$OnlyIds,

    [switch]$IncludeRisky,
    [switch]$Silent,
    [switch]$ListTweaks,
    [switch]$Status,
    [string]$Rollback,
    [switch]$SkipRestorePoint,
    [switch]$InstallPackages,
    [switch]$RemoveOptionalApps
)

# Windows PowerShell 5.1'in konsol çıkışı varsayılan olarak sistemin eski
# (OEM/ANSI) kod sayfasını kullanır - kaynak dosya UTF-8 BOM ile doğru
# okunsa bile, Türkçe karakterler (ş, ı, ğ, ç, ö, ü) konsola yazılırken
# bozulur (mojibake). Konsol çıkış kodlamasını burada zorlayarak düzeltiyoruz.
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
    chcp 65001 | Out-Null
} catch {}

. (Join-Path $PSScriptRoot "Simpleks.Definitions.ps1")

# --- Çalışma zamanı durumu ---
$script:Silent        = $Silent.IsPresent
$script:IncludeRisky  = $IncludeRisky.IsPresent
$script:BuildInfo     = Get-SimpleksBuildInfo
$script:LogDir        = Join-Path $PSScriptRoot "logs"
$runStamp             = Get-Date -Format "yyyyMMdd-HHmmss"
$script:JsonLogPath   = Join-Path $script:LogDir "simpleks-$runStamp.jsonl"
$script:TextLogPath   = Join-Path $script:LogDir "simpleks-$runStamp.log"
$script:BackupEntries = [System.Collections.Generic.List[object]]::new()

# --- Kullanıcı düzenleyebilir listeler (isteğe bağlı otomasyon) ---
$ChocoPackages = @("googlechrome", "nanazip", "sharex", "discord", "notepadplusplus", "vcredist140", "jre8", "sumatrapdf.install")

# Yalnızca -RemoveOptionalApps ile, elle onaylanarak kaldırılır. Windows'un
# kendi işlevselliği (Store, Ayarlar, WSL/Sanal Alan bileşenleri vb.) için
# gerekli hiçbir paket bu listede yer almaz.
$OptionalAppxPackages = @(
    "Microsoft.549981C3F5F10",       # Cortana (kalıntı)
    "Microsoft.BingNews",
    "Microsoft.BingWeather",
    "Microsoft.GetHelp",
    "Microsoft.Getstarted",
    "Microsoft.MicrosoftOfficeHub",
    "Microsoft.MicrosoftSolitaireCollection",
    "Microsoft.People",
    "Microsoft.WindowsFeedbackHub",
    "Microsoft.YourPhone",
    "Microsoft.ZuneMusic",
    "Microsoft.ZuneVideo",
    "Clipchamp.Clipchamp",
    "MicrosoftTeams"
)

function Test-SimpleksAdmin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
}

function Show-SimpleksTweakTable {
    param([Parameter(Mandatory)] [object[]]$Tweaks, [switch]$WithStatus)
    $Tweaks | ForEach-Object {
        $row = [ordered]@{
            Id             = $_.Id
            Ad             = $_.Name
            Kategori       = $_.Category
            Seviye         = $_.Tier
            Risk           = $_.Risk
            YenidenBaslatma = $_.RequiresReboot
            GeriAlinabilir = $_.Reversible
        }
        if ($WithStatus) { $row["Durum"] = Get-SimpleksTweakStatus $_ }
        [PSCustomObject]$row
    } | Format-Table -AutoSize | Out-Host
}

# =========================================================================
# SALT-OKUNUR MODLAR (Yönetici gerektirmez)
# =========================================================================

if ($ListTweaks) {
    Write-Host "Simpleks - Tüm Optimizasyon Kataloğu ($($script:BuildInfo.Caption), build $($script:BuildInfo.BuildNumber))" -ForegroundColor Cyan
    Show-SimpleksTweakTable -Tweaks (Get-SimpleksTweaks)
    return
}

if ($Status) {
    Write-Host "Simpleks - Mevcut Durum ($($script:BuildInfo.Caption), build $($script:BuildInfo.BuildNumber))" -ForegroundColor Cyan
    Show-SimpleksTweakTable -Tweaks (Get-SimpleksTweaks) -WithStatus
    return
}

# =========================================================================
# YÖNETİCİ GEREKTİREN MODLAR
# =========================================================================

if (-not (Test-SimpleksAdmin)) {
    Write-Host "LÜTFEN BU SCRIPT'I YÖNETİCİ OLARAK ÇALIŞTIRIN!" -ForegroundColor Red
    exit 1
}

if ($Rollback) {
    $backupPath = $Rollback
    if ($Rollback -eq "last") {
        $latest = Get-ChildItem -Path $script:LogDir -Filter "backup-*.json" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $latest) { Write-Err2 "logs\ klasöründe geri alınacak bir yedek bulunamadı."; exit 1 }
        $backupPath = $latest.FullName
    }
    Write-Step "Geri alma uygulanıyor: $backupPath"
    Restore-SimpleksBackupFile -Path $backupPath
    Write-Host "`nGeri alma tamamlandı. Değişikliklerin yansıması için Windows Gezgini yeniden başlatılıyor..." -ForegroundColor Yellow
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    return
}

Write-Host "--- Simpleks: Windows 11 Optimizasyon Motoru Başlıyor (Preset: $Preset) ---" -ForegroundColor Cyan

if (-not $SkipRestorePoint -and -not $WhatIfPreference) {
    Write-Step "Değişiklik öncesi Sistem Geri Yükleme noktası oluşturuluyor..."
    try {
        Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description "Simpleks-Win11 Optimizasyon Öncesi" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        Write-Ok "Geri yükleme noktası oluşturuldu."
    } catch {
        Write-Warn2 "Geri yükleme noktası oluşturulamadı (24 saatlik sınır ya da Sistem Koruması kapalı olabilir): $($_.Exception.Message)"
    }
}

$activeTweaks = Get-SimpleksActiveTweaks -Preset $Preset -IncludeRisky:$script:IncludeRisky -OnlyIds $OnlyIds
Write-Host "Uygulanacak optimizasyon sayısı: $($activeTweaks.Count) / $((Get-SimpleksTweaks).Count) (preset: $Preset$(if ($script:IncludeRisky) { ', güvenlik-etkili dahil' }))" -ForegroundColor Cyan

$backupFile = Join-Path $script:LogDir "backup-$runStamp.json"
foreach ($tweak in $activeTweaks) {
    Invoke-SimpleksTweak -Tweak $tweak -WhatIfOnly:$WhatIfPreference
    # Her tweak sonrası yeniden yazılır: bir çökme/Ctrl+C/beklenmeyen yeniden
    # başlatma o ana kadarki değişiklikleri geri alınamaz bırakmasın diye.
    if (-not $WhatIfPreference) { Save-SimpleksBackupFile -Path $backupFile | Out-Null }
}

if ($InstallPackages -and -not $WhatIfPreference) {
    Write-Step "Chocolatey ve Paket Kurulumları Kontrol Ediliyor..."
    if (!(Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Host "-> Chocolatey bulunamadı. Kuruluyor..." -ForegroundColor Yellow
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        Write-Ok "Chocolatey başarıyla kuruldu."
    } else {
        Write-Ok "Chocolatey zaten kurulu."
    }
    foreach ($pkg in $ChocoPackages) {
        Write-Host "-> [$pkg] paketi kuruluyor..." -ForegroundColor Cyan
        choco install $pkg -y | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Ok "$pkg başarıyla kuruldu/güncellendi." }
        else { Write-Warn2 "$pkg kurulamadı (choco çıkış kodu: $LASTEXITCODE)." }
    }
}

if ($RemoveOptionalApps -and -not $WhatIfPreference) {
    Write-Step "İsteğe bağlı ön yüklü uygulamalar kaldırılıyor..."
    foreach ($pkgName in $OptionalAppxPackages) {
        $installed = Get-AppxPackage -AllUsers -Name $pkgName -ErrorAction SilentlyContinue
        if ($installed) {
            $installed | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
            Write-Ok "$pkgName kaldırıldı."
        }
        Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -eq $pkgName } |
            ForEach-Object { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null }
    }
    Write-Warn2 "Kaldırılan uygulamalar Microsoft Store üzerinden yeniden yüklenebilir; kayıt defteri geri alma bu paketleri geri getirmez."
}

if (-not $WhatIfPreference) {
    $saved = Save-SimpleksBackupFile -Path $backupFile
    if ($saved) { Write-Host "Geri alma verisi kaydedildi: $saved  (geri almak için: -Rollback last)" -ForegroundColor DarkCyan }

    Write-Host "`n=== TÜM İŞLEMLER TAMAMLANDI! ($($activeTweaks.Count) optimizasyon işlendi) ===" -ForegroundColor Yellow
    Write-Host "Görev çubuğu ve Başlat menüsü değişikliklerinin hemen yansıması için Windows Gezgini yeniden başlatılıyor..." -ForegroundColor Cyan
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Write-Host "Lütfen bilgisayarınızı YENİDEN BAŞLATMAYI unutmayın (bazı ayarlar için gereklidir)." -ForegroundColor White
} else {
    Write-Host "`n(-WhatIf modu: hiçbir değişiklik uygulanmadı.)" -ForegroundColor DarkCyan
}

<#
    Simpleks-Menu.ps1

    Simpleks-Win11.ps1 için etkileşimli konsol arayüzü: preset (profil) ve
    ek seçenekleri ok tuşları/numara ile seçip motoru başlatır. Bu dosya
    Simpleks-Win11.ps1'i doğrudan çağırır; kendi başına hiçbir kayıt
    defteri/servis değişikliği yapmaz.

    Kullanım:
        .\Simpleks-Menu.ps1
#>

[CmdletBinding()]
param()

$script:EnginePath = Join-Path $PSScriptRoot "Simpleks-Win11.ps1"

try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
    chcp 65001 | Out-Null
} catch {}

if (-not (Test-Path $script:EnginePath)) {
    Write-Host "HATA: Simpleks-Win11.ps1 bulunamadı ($script:EnginePath). Aynı klasörde olduğundan emin olun." -ForegroundColor Red
    return
}

function Test-SimpleksMenuAdmin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
}

function Read-SimpleksMenuChoice {
    param(
        [Parameter(Mandatory)] [string]$Prompt,
        [Parameter(Mandatory)] [string[]]$ValidChoices
    )
    while ($true) {
        Write-Host ""
        $answer = Read-Host $Prompt
        if ($ValidChoices -contains $answer) { return $answer }
        Write-Host "Geçersiz seçim: '$answer'. Lütfen şunlardan birini girin: $($ValidChoices -join ', ')" -ForegroundColor DarkYellow
    }
}

function Read-SimpleksMenuYesNo {
    param([Parameter(Mandatory)] [string]$Prompt, [bool]$DefaultYes = $false)
    $suffix = if ($DefaultYes) { "[E/h]" } else { "[e/H]" }
    $answer = Read-Host "$Prompt $suffix"
    if ([string]::IsNullOrWhiteSpace($answer)) { return $DefaultYes }
    return $answer -match "^(e|evet|y|yes)$"
}

function Show-SimpleksMainMenu {
    Clear-Host
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host "   SIMPLEKS - Windows 11 Optimizasyon Motoru (Menü)" -ForegroundColor Cyan
    Write-Host "==========================================================" -ForegroundColor Cyan
    $adminState = if (Test-SimpleksMenuAdmin) { "Yönetici" } else { "Yönetici DEĞİL" }
    Write-Host "  Oturum: $adminState" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Profil seçin:" -ForegroundColor White
    Write-Host "    1) Safe          - Kozmetik + apaçık güvenli ayarlar"
    Write-Host "    2) Balanced      - Safe + telemetri/arka plan kısıtlamaları (varsayılan)"
    Write-Host "    3) Performance   - Balanced + oyun/CPU zamanlayıcı ayarları"
    Write-Host "    4) Extreme       - Performance + arama indeksleme, yazıcı/OneDrive"
    Write-Host ""
    Write-Host "  Diğer işlemler:" -ForegroundColor White
    Write-Host "    5) Katalogu listele (-ListTweaks)"
    Write-Host "    6) Mevcut durumu göster (-Status)"
    Write-Host "    7) Son çalıştırmayı geri al (-Rollback last)"
    Write-Host "    0) Çıkış"
}

function Invoke-SimpleksMenuEngine {
    param([Parameter(Mandatory)] [hashtable]$EngineArgs)
    $display = ($EngineArgs.GetEnumerator() | ForEach-Object {
        if ($_.Value -is [bool]) { "-$($_.Key)" } else { "-$($_.Key) $($_.Value)" }
    }) -join ' '
    Write-Host ""
    Write-Host "-> Çalıştırılıyor: Simpleks-Win11.ps1 $display" -ForegroundColor DarkCyan
    & $script:EnginePath @EngineArgs
}

function Invoke-SimpleksMenuPreset {
    param([Parameter(Mandatory)] [ValidateSet("Safe", "Balanced", "Performance", "Extreme")] [string]$Preset)

    if (-not (Test-SimpleksMenuAdmin)) {
        Write-Host ""
        Write-Host "Bu işlem Yönetici hakları gerektirir." -ForegroundColor DarkYellow
        if (Read-SimpleksMenuYesNo -Prompt "Yönetici olarak yeniden başlatılsın mı?" -DefaultYes $true) {
            $relaunchArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"")
            Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $relaunchArgs
        }
        return
    }

    $whatIf = Read-SimpleksMenuYesNo -Prompt "Önce sadece simülasyon yapılsın mı (-WhatIf, hiçbir şey değişmez)?" -DefaultYes $false
    $includeRisky = $false
    if ($Preset -eq "Extreme") {
        $includeRisky = Read-SimpleksMenuYesNo -Prompt "Güvenlik etkili 'risky' tweak'ler de dahil edilsin mi (-IncludeRisky)?" -DefaultYes $false
    }

    $engineArgs = @{ Preset = $Preset }
    if ($whatIf) { $engineArgs["WhatIf"] = $true }
    if ($includeRisky) { $engineArgs["IncludeRisky"] = $true }

    Invoke-SimpleksMenuEngine -EngineArgs $engineArgs

    if ($whatIf) {
        Write-Host ""
        if (Read-SimpleksMenuYesNo -Prompt "Simülasyon tamamlandı. Aynı profil gerçekten uygulansın mı?" -DefaultYes $false) {
            $realArgs = @{ Preset = $Preset }
            if ($includeRisky) { $realArgs["IncludeRisky"] = $true }
            Invoke-SimpleksMenuEngine -EngineArgs $realArgs
        }
    }
}

$script:Choices = @("0", "1", "2", "3", "4", "5", "6", "7")
do {
    Show-SimpleksMainMenu
    $choice = Read-SimpleksMenuChoice -Prompt "Seçiminiz" -ValidChoices $script:Choices

    switch ($choice) {
        "1" { Invoke-SimpleksMenuPreset -Preset "Safe" }
        "2" { Invoke-SimpleksMenuPreset -Preset "Balanced" }
        "3" { Invoke-SimpleksMenuPreset -Preset "Performance" }
        "4" { Invoke-SimpleksMenuPreset -Preset "Extreme" }
        "5" { Invoke-SimpleksMenuEngine -EngineArgs @{ ListTweaks = $true } }
        "6" { Invoke-SimpleksMenuEngine -EngineArgs @{ Status = $true } }
        "7" {
            if (Read-SimpleksMenuYesNo -Prompt "Son çalıştırmadaki tüm değişiklikler geri alınacak. Emin misiniz?" -DefaultYes $false) {
                Invoke-SimpleksMenuEngine -EngineArgs @{ Rollback = "last" }
            }
        }
        "0" { Write-Host "Çıkılıyor..." -ForegroundColor Cyan }
    }

    if ($choice -ne "0") {
        Write-Host ""
        Read-Host "Devam etmek için ENTER'a basın" | Out-Null
    }
} while ($choice -ne "0")

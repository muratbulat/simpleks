<#
    Simpleks.ps1 - Tek komutla başlatıcı (bootstrap)

    Tek satırla çalıştırmak için:
        irm https://raw.githubusercontent.com/muratbulat/simpleks/main/Simpleks.ps1 | iex

    Bu dosya `iex` ile pipe'lanarak (dosya olarak değil, metin olarak)
    çalıştırıldığında $PSScriptRoot/$PSCommandPath boş olur - bu yüzden
    motoru oluşturan diğer dosyaları (Simpleks-Win11.ps1,
    Simpleks.Definitions.ps1, Simpleks-Menu.ps1) geçici bir klasöre indirip
    oradan başlatır. Yönetici değilse otomatik olarak yönetici olarak
    yeniden başlatılır (UAC onayı istenir).
#>

$ErrorActionPreference = "Stop"

$script:RepoRawBase = "https://raw.githubusercontent.com/muratbulat/simpleks/main"
$script:BootstrapFiles = @("Simpleks-Win11.ps1", "Simpleks.Definitions.ps1", "Simpleks-Menu.ps1")

function Test-SimpleksBootstrapAdmin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
}

if (-not (Test-SimpleksBootstrapAdmin)) {
    Write-Host "Simpleks, Yönetici olarak yeniden başlatılıyor (UAC onayı isteyecek)..." -ForegroundColor Yellow
    $relaunchCommand = "irm $script:RepoRawBase/Simpleks.ps1 | iex"
    Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $relaunchCommand)
    return
}

try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
    chcp 65001 | Out-Null
} catch {}

$script:WorkDir = Join-Path $env:TEMP "Simpleks"
New-Item -Path $script:WorkDir -ItemType Directory -Force | Out-Null

Write-Host "Simpleks indiriliyor -> $script:WorkDir" -ForegroundColor Cyan
foreach ($file in $script:BootstrapFiles) {
    $dest = Join-Path $script:WorkDir $file
    Invoke-WebRequest -Uri "$script:RepoRawBase/$file" -OutFile $dest -UseBasicParsing
}

& (Join-Path $script:WorkDir "Simpleks-Menu.ps1")

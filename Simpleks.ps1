<#
    Simpleks.ps1

    Windows 11 için kanıta dayalı, geri alınabilir, donanım-farkında
    PowerShell optimizasyon aracı. Tek dosyadır - grafik arayüzü (WPF),
    tweak kataloğu ve motor mantığının tamamını içerir.

    Tek satırla çalıştırmak için (Yönetici PowerShell gerekmez, otomatik
    yükseltir):
        irm https://raw.githubusercontent.com/muratbulat/simpleks/main/Simpleks.ps1 | iex

    Bu dosya dot-source edildiğinde (ör. Pester testlerinde) HİÇBİR pencere
    açmaz ve HİÇBİR sistem değişikliği yapmaz - sadece fonksiyon/veri
    tanımlar. Arayüz yalnızca dosya doğrudan çalıştırıldığında veya `iex`
    ile değerlendirildiğinde açılır (bkz. dosya sonundaki başlatma bloğu).
#>

$script:RepoRawBase = "https://raw.githubusercontent.com/muratbulat/simpleks/main"

# =========================================================================
# ÇIKTI / KONSOL + GUI GÜNLÜK KUTUSU
# =========================================================================

$script:LogBox = $null

function Write-SimpleksOutput {
    param([string]$Text, [string]$Color = "Gray")
    Write-Host $Text -ForegroundColor $Color
    if ($script:LogBox) {
        try {
            $script:LogBox.AppendText("$Text`r`n")
            $script:LogBox.ScrollToEnd()
        } catch {}
    }
}

function Write-Step  { param([string]$Text) Write-SimpleksOutput "[İŞLEM] $Text" "Cyan" }
function Write-Ok    { param([string]$Text) Write-SimpleksOutput "   -> $Text" "Green" }
function Write-Warn2 { param([string]$Text) Write-SimpleksOutput "   [UYARI] $Text" "DarkYellow" }
function Write-Err2  { param([string]$Text) Write-SimpleksOutput "   [HATA] $Text" "Red" }

# =========================================================================
# SİSTEM / DONANIM TESPİTİ
# =========================================================================

function Test-SimpleksAdmin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
}

function Get-SimpleksBuildInfo {
    $verKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    [PSCustomObject]@{
        Caption        = if ($os) { $os.Caption } else { "Unknown" }
        BuildNumber    = if ($os) { [int]$os.BuildNumber } else { 0 }
        UBR            = (Get-ItemProperty -Path $verKey -Name "UBR" -ErrorAction SilentlyContinue).UBR
        DisplayVersion = (Get-ItemProperty -Path $verKey -Name "DisplayVersion" -ErrorAction SilentlyContinue).DisplayVersion
    }
}

function Get-SimpleksHardwareInfo {
    $isLaptop  = $false
    $hasBattery = $false
    try {
        $chassisTypes = (Get-CimInstance Win32_SystemEnclosure -ErrorAction SilentlyContinue).ChassisTypes
        $laptopChassis = 8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32
        if ($chassisTypes) { $isLaptop = ($chassisTypes | Where-Object { $laptopChassis -contains $_ }).Count -gt 0 }
    } catch {}
    try {
        $hasBattery = $null -ne (Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
    } catch {}

    # SsdLikely yalnızca disk(ler) POZİTİF olarak SSD/NVMe/Unspecified diye
    # tespit edilebildiğinde $true olur. Get-PhysicalDisk başarısız olur ya da
    # hiçbir disk döndürmezse (Sanal Alan, bazı RAID denetleyicileri, vb.)
    # "bilinmiyor" muhafazakar şekilde HDD gibi ele alınır - aksi halde
    # SysMain/Prefetch kapatma tweak'i tespit edilemeyen bir HDD'de yanlışlıkla
    # uygulanabilir.
    $diskCheckSucceeded = $false
    $hasHdd = $false
    try {
        $disks = Get-PhysicalDisk -ErrorAction Stop
        if ($disks -and $disks.Count -gt 0) {
            $diskCheckSucceeded = $true
            $hasHdd = ($disks | Where-Object { $_.MediaType -eq "HDD" }).Count -gt 0
        }
    } catch {}

    [PSCustomObject]@{
        IsLaptop   = ($isLaptop -or $hasBattery)
        HasBattery = $hasBattery
        SsdLikely  = ($diskCheckSucceeded -and -not $hasHdd)
    }
}

# =========================================================================
# KAYIT DEFTERİ / SERVİS YARDIMCILARI (yedekleme farkında)
# =========================================================================

function Add-SimpleksBackupEntry {
    param(
        [Parameter(Mandatory)] [string]$Type,      # Registry | Service | ScheduledTask
        [Parameter(Mandatory)] [string]$Path,
        [string]$Name = "",
        $PreviousValue = $null,
        [bool]$PreviousExisted = $false,
        $NewValue = $null
    )
    if (-not $script:BackupEntries) { $script:BackupEntries = [System.Collections.Generic.List[object]]::new() }
    $script:BackupEntries.Add([PSCustomObject]@{
        TweakId         = $script:CurrentTweakId
        Type            = $Type
        Path            = $Path
        Name            = $Name
        PreviousValue   = $PreviousValue
        PreviousExisted = $PreviousExisted
        NewValue        = $NewValue
        Timestamp       = (Get-Date).ToString("o")
    })
}

function Get-RegValue {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Name,
        $Default = $null
    )
    if (Test-Path $Path) {
        $item = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
        if ($null -ne $item -and $null -ne $item.$Name) { return $item.$Name }
    }
    return $Default
}

# HKCU:\ / HKLM:\ altında değer oluşturur/günceller, önceki değeri yedek listesine ekler.
function Set-Reg {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] $Value,
        [string]$Type = "DWord"
    )
    $existed = $false
    $prev = $null
    if (Test-Path $Path) {
        $item = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
        if ($null -ne $item -and $null -ne $item.$Name) { $existed = $true; $prev = $item.$Name }
    }
    Add-SimpleksBackupEntry -Type "Registry" -Path $Path -Name $Name -PreviousValue $prev -PreviousExisted $existed -NewValue $Value

    try {
        if (!(Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
        return $true
    } catch {
        Write-Warn2 "$Path [$Name] ayarlanamadı: $($_.Exception.Message)"
        throw
    }
}

function Get-SvcStartType {
    param([Parameter(Mandatory)] [string]$Name)
    (Get-Service -Name $Name -ErrorAction SilentlyContinue).StartType
}

# Bir servisi durdurup başlangıç türünü değiştirir, önceki durumu yedekler.
function Set-SvcState {
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [ValidateSet("Disabled", "Manual", "Automatic")] [string]$StartupType
    )
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) { return $false }   # Bu Windows sürümünde/SKU'sunda servis yok - hata değil, atlanır.

    Add-SimpleksBackupEntry -Type "Service" -Path $Name -PreviousValue ([PSCustomObject]@{
        StartType = $svc.StartType.ToString()
        Status    = $svc.Status.ToString()
    }) -PreviousExisted $true -NewValue $StartupType

    try {
        if ($StartupType -eq "Disabled") {
            Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
            $stillRunning = (Get-Service -Name $Name -ErrorAction SilentlyContinue).Status -eq "Running"
            if ($stillRunning) { Write-Warn2 "$Name servisi durdurulamadı (başlangıç türü yine de Disabled olarak ayarlandı, sonraki açılışta başlamayacak)." }
        }
        Set-Service -Name $Name -StartupType $StartupType -ErrorAction Stop
        return $true
    } catch {
        Write-Warn2 "$Name servisi ayarlanamadı: $($_.Exception.Message)"
        throw
    }
}

function Set-ScheduledTaskState {
    param(
        [Parameter(Mandatory)] [string]$TaskPath,
        [Parameter(Mandatory)] [string]$TaskName,
        [Parameter(Mandatory)] [ValidateSet("Enabled", "Disabled")] [string]$State
    )
    $task = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $task) { return $false }   # Bu Windows sürümünde görev yok - hata değil, atlanır.

    # NOT: $task.State çalışma zamanı durumudur (Ready/Running/Queued/Disabled).
    # "Etkin miydi?" sorusunun doğru cevabı $task.Settings.Enabled'dır - aksi
    # halde çalışmakta olan (Running/Queued) etkin bir görev, geri almada
    # yanlışlıkla "etkin değildi" sanılıp kapatılabilir.
    Add-SimpleksBackupEntry -Type "ScheduledTask" -Path $TaskPath -Name $TaskName -PreviousValue $task.Settings.Enabled -PreviousExisted $true -NewValue $State

    try {
        if ($State -eq "Disabled") { Disable-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction Stop | Out-Null }
        else { Enable-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction Stop | Out-Null }
        return $true
    } catch {
        Write-Warn2 "Görev '$TaskPath$TaskName' ayarlanamadı: $($_.Exception.Message)"
        throw
    }
}

# =========================================================================
# GÜNLÜKLEME / YEDEKLEME DOSYASI
# =========================================================================

function Write-SimpleksLog {
    param(
        [Parameter(Mandatory)] [string]$TweakId,
        [Parameter(Mandatory)] [string]$Result,   # Applied | Skipped-* | Error
        [string]$Message = ""
    )
    if (-not $script:LogDir) { return }
    if (!(Test-Path $script:LogDir)) { New-Item -Path $script:LogDir -ItemType Directory -Force | Out-Null }

    $entry = [PSCustomObject]@{
        Timestamp = (Get-Date).ToString("o")
        TweakId   = $TweakId
        Result    = $Result
        Message   = $Message
        Build     = if ($script:BuildInfo) { $script:BuildInfo.BuildNumber } else { $null }
    }
    try {
        Add-Content -Path $script:JsonLogPath -Value ($entry | ConvertTo-Json -Compress) -Encoding utf8
        Add-Content -Path $script:TextLogPath -Value "$($entry.Timestamp) [$Result] $TweakId $Message" -Encoding utf8
    } catch {
        Write-Warn2 "Günlük yazılamadı: $($_.Exception.Message)"
    }
}

# Her tweak işlendikten sonra çağrılır (yalnızca en sonda değil) - bir çökme,
# Ctrl+C veya beklenmeyen yeniden başlatma o ana kadar yapılan değişiklikleri
# geri alınamaz bırakmasın diye dosya her seferinde baştan yazılır.
function Save-SimpleksBackupFile {
    param([Parameter(Mandatory)] [string]$Path)
    if (-not $script:BackupEntries -or $script:BackupEntries.Count -eq 0) { return $null }
    try {
        $dir = Split-Path -Path $Path -Parent
        if ($dir -and !(Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
        $script:BackupEntries | ConvertTo-Json -Depth 5 | Set-Content -Path $Path -Encoding utf8
        return $Path
    } catch {
        Write-Warn2 "Geri alma dosyası yazılamadı: $($_.Exception.Message)"
        return $null
    }
}

# Geri alma dosyası GÜVENİLMEYEN VERİ olarak ele alınır: registry yolu yalnızca
# HKLM:\ veya HKCU:\ ile başlıyorsa işlenir, Type alanı yalnızca bilinen
# değerlerden biriyse işlenir. Bu fonksiyon dosyadan hiçbir zaman kod
# ÇALIŞTIRMAZ (Invoke-Expression yoktur) - yalnızca sabit kodlanmış, türe göre
# dallanan aksiyonlar alınır.
function Restore-SimpleksBackupFile {
    param([Parameter(Mandatory)] [string]$Path)
    if (!(Test-Path $Path)) {
        Write-Err2 "Geri alma dosyası bulunamadı: $Path"
        return
    }
    $raw = Get-Content -Path $Path -Raw | ConvertFrom-Json
    if (-not $raw) { Write-Warn2 "Geri alma dosyası boş."; return }
    $entries = @($raw)
    $knownTypes = @("Registry", "Service", "ScheduledTask", "PowerScheme", "Hibernate", "SystemRestore", "FsutilLastAccess")

    # LIFO: aynı anahtara birden çok yazım olduysa en eskiye (ilk yedeklenen değere) dön
    for ($i = $entries.Count - 1; $i -ge 0; $i--) {
        $e = $entries[$i]
        if ($knownTypes -notcontains $e.Type) {
            Write-Warn2 "Bilinmeyen yedek türü atlandı: $($e.Type)"
            continue
        }
        try {
            switch ($e.Type) {
                "Registry" {
                    if ($e.Path -notmatch '^(HKLM|HKCU):\\') {
                        throw "Güvenli olmayan registry yolu: $($e.Path)"
                    }
                    if ($e.PreviousExisted) {
                        Set-ItemProperty -Path $e.Path -Name $e.Name -Value $e.PreviousValue -Force -ErrorAction Stop
                    } else {
                        Remove-ItemProperty -Path $e.Path -Name $e.Name -Force -ErrorAction SilentlyContinue
                    }
                }
                "Service" {
                    Set-Service -Name $e.Path -StartupType $e.PreviousValue.StartType -ErrorAction Stop
                    if ($e.PreviousValue.Status -eq "Running") {
                        Start-Service -Name $e.Path -ErrorAction SilentlyContinue
                    }
                }
                "ScheduledTask" {
                    if ($e.PreviousValue -eq $true) {
                        Enable-ScheduledTask -TaskPath $e.Path -TaskName $e.Name -ErrorAction SilentlyContinue | Out-Null
                    } else {
                        Disable-ScheduledTask -TaskPath $e.Path -TaskName $e.Name -ErrorAction SilentlyContinue | Out-Null
                    }
                }
                "PowerScheme" {
                    powercfg -setactive $e.PreviousValue | Out-Null
                    if ($e.NewValue) { powercfg -delete $e.NewValue | Out-Null }
                }
                "Hibernate" {
                    if ($e.PreviousValue -eq $true) { powercfg -h on } else { powercfg -h off }
                }
                "SystemRestore" {
                    if ($e.PreviousValue -eq $true) { Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue }
                    else { Disable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue }
                }
                "FsutilLastAccess" {
                    fsutil behavior set disablelastaccess $e.PreviousValue | Out-Null
                }
            }
            Write-Ok "$($e.Type) geri alındı: $($e.Path) $($e.Name)"
        } catch {
            Write-Warn2 "$($e.Type) geri alınamadı ($($e.Path) $($e.Name)): $($_.Exception.Message)"
        }
    }
}

# =========================================================================
# TWEAK MOTORU
# =========================================================================
# Her tweak nesnesi şu alanları taşır:
#   Id, Name, Category, Tier (Safe|Balanced|Performance|Extreme),
#   Risk (Safe|Moderate|Aggressive|Experimental), SecurityImpact (bool),
#   Reversible (bool|"Partial"), RequiresReboot (bool), MinBuild,
#   Description, Detect (scriptblock -> $true/$false/$null), Apply (scriptblock)

function Test-SimpleksTweakSupported {
    param([Parameter(Mandatory)] $Tweak)
    if ($Tweak.MinBuild -and $script:BuildInfo -and $script:BuildInfo.BuildNumber -lt $Tweak.MinBuild) { return $false }
    return $true
}

function Get-SimpleksTweakStatus {
    param([Parameter(Mandatory)] $Tweak)
    if (-not $Tweak.Detect) { return "Unknown" }
    try {
        $r = & $Tweak.Detect
        if ($r -eq $true) { return "Applied" }
        if ($r -eq $false) { return "NotApplied" }
        return "Unknown"
    } catch {
        return "Unknown"
    }
}

$script:PresetOrder = @("Safe", "Balanced", "Performance", "Extreme")

function Get-SimpleksActiveTweaks {
    param(
        [Parameter(Mandatory)] [string]$Preset,
        [switch]$IncludeRisky,
        [string[]]$OnlyIds
    )
    $idx = $script:PresetOrder.IndexOf($Preset)
    if ($idx -lt 0) { throw "Bilinmeyen preset: $Preset" }
    $activeTiers = $script:PresetOrder[0..$idx]

    # NOT: SecurityImpact filtresi -OnlyIds ile de dahil olmak üzere HER ZAMAN
    # uygulanır - preset/tier seçimi ne olursa olsun güvenlik kapısı bu
    # fonksiyonun döndürdüğü kümenin bir DEĞİŞMEZİ'dir (Invoke-SimpleksTweak
    # ayrıca ikinci bir kontrol daha yapar, ama bu fonksiyon da kendi başına
    # doğru sonuç vermelidir).
    $all = Get-SimpleksTweaks | Where-Object { -not $_.SecurityImpact -or $IncludeRisky }
    if ($OnlyIds -and $OnlyIds.Count -gt 0) {
        return $all | Where-Object { $OnlyIds -contains $_.Id }
    }
    $all | Where-Object { $activeTiers -contains $_.Tier }
}

function Invoke-SimpleksTweak {
    param(
        [Parameter(Mandatory)] $Tweak,
        [switch]$WhatIfOnly
    )
    $script:CurrentTweakId = $Tweak.Id

    if (-not (Test-SimpleksTweakSupported $Tweak)) {
        Write-Warn2 "$($Tweak.Name) atlandı: bu Windows sürümü için desteklenmiyor (min build $($Tweak.MinBuild))."
        Write-SimpleksLog -TweakId $Tweak.Id -Result "Skipped-Unsupported"
        return
    }

    if ($Tweak.SecurityImpact -and -not $script:IncludeRisky) {
        Write-Warn2 "$($Tweak.Name) atlandı: güvenlik etkisi var, önce 'riskli tweak'leri göster' seçilmeden uygulanmaz."
        Write-SimpleksLog -TweakId $Tweak.Id -Result "Skipped-SecurityGate"
        return
    }

    if ($WhatIfOnly) {
        Write-SimpleksOutput "[WHATIF] $($Tweak.Name) uygulanacaktı." "DarkCyan"
        return
    }

    Write-Step $Tweak.Name
    try {
        & $Tweak.Apply
        Write-Ok "Uygulandı."
        Write-SimpleksLog -TweakId $Tweak.Id -Result "Applied"
    } catch {
        Write-Err2 "$($Tweak.Name) uygulanırken hata: $($_.Exception.Message)"
        Write-SimpleksLog -TweakId $Tweak.Id -Result "Error" -Message $_.Exception.Message
    }
}

# =========================================================================
# TWEAK KATALOĞU
# =========================================================================

function Get-SimpleksTweaks {
    # NOT: Bu değişkenler $script: kapsamında olmalı. Apply/Detect scriptblock'ları
    # burada TANIMLANIR ama çok sonra, başka bir fonksiyondan (Invoke-SimpleksTweak)
    # çağrılır - PowerShell scriptblock'ları closure DEĞİLDİR, bu yüzden bu fonksiyonun
    # yerel (local) değişkenleri çağrı anında artık mevcut olmaz ve $null'a çözülür.
    # $script: kapsamı ise çağrı zincirinde her zaman erişilebilir kalır.
    $script:gamesTaskPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"
    $script:prefetchPath  = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters"
    $script:expAdvPath    = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"

    @(
        [PSCustomObject]@{
            Id = "power.ultimate-plan"; Name = "Ultimate Performance Güç Planı"; Category = "Power"
            Tier = "Safe"; Risk = "Safe"; SecurityImpact = $false; Reversible = $true; RequiresReboot = $false
            Description = "Gizli 'Ultimate Performance' güç planını etkinleştirir ve etkinleştirir (yalnızca çoğaltmakla kalmaz). GUID, tekrar çalıştırmalarda yinelenen şema oluşturmamak için yerel olarak izlenir; tespit, dile göre değişen şema adı yerine GUID karşılaştırmasıyla yapılır."
            Detect = {
                $stateFile = Join-Path $script:LogDir "ultimate-scheme.guid"
                if (-not (Test-Path $stateFile)) { return $false }
                $recordedGuid = (Get-Content $stateFile -Raw -ErrorAction SilentlyContinue).Trim()
                $activeLine = powercfg -getactivescheme
                $activeGuid = $null
                if ($activeLine -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') { $activeGuid = $matches[1] }
                return ($recordedGuid -and $activeGuid -and $recordedGuid -eq $activeGuid)
            }
            Apply  = {
                $stateFile = Join-Path $script:LogDir "ultimate-scheme.guid"
                $activeLine = powercfg -getactivescheme
                $previousGuid = $null
                if ($activeLine -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') { $previousGuid = $matches[1] }

                $recordedGuid = $null
                if (Test-Path $stateFile) { $recordedGuid = (Get-Content $stateFile -Raw -ErrorAction SilentlyContinue).Trim() }
                $schemeStillExists = $recordedGuid -and ((powercfg -list) -match [regex]::Escape($recordedGuid))
                $freshlyCreated = -not $schemeStillExists

                if ($schemeStillExists) {
                    $newGuid = $recordedGuid
                } else {
                    $dupOutput = powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61
                    $newGuid = $null
                    if ($dupOutput -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') { $newGuid = $matches[1] }
                    if (-not $newGuid) { throw "Ultimate Performance şeması oluşturuldu ama GUID ayrıştırılamadı: $dupOutput" }
                    if (!(Test-Path $script:LogDir)) { New-Item -Path $script:LogDir -ItemType Directory -Force | Out-Null }
                    Set-Content -Path $stateFile -Value $newGuid -Encoding utf8
                }

                powercfg -setactive $newGuid | Out-Null
                # NewValue yalnızca bu çalıştırmada YENİ oluşturulduysa dolu bırakılır - aksi
                # halde geri alma, daha önceden var olan bir şemayı yanlışlıkla siler.
                Add-SimpleksBackupEntry -Type "PowerScheme" -Path "ActiveScheme" -PreviousValue $previousGuid -PreviousExisted ([bool]$previousGuid) -NewValue $(if ($freshlyCreated) { $newGuid } else { $null })
            }
        },
        [PSCustomObject]@{
            Id = "power.hibernate-off"; Name = "Hazırda Beklet (Hibernate) Kapatma"; Category = "Power"
            Tier = "Balanced"; Risk = "Moderate"; SecurityImpact = $false; Reversible = $true; RequiresReboot = $false
            Description = "hiberfil.sys dosyasını kaldırır, disk alanı boşaltır. Dizüstü sistemlerde pil/uyku senaryoları için atlanır."
            Detect = { (Get-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Power" "HibernateEnabled" 1) -eq 0 }
            Apply  = {
                $hw = Get-SimpleksHardwareInfo
                if ($hw.IsLaptop) {
                    Write-Warn2 "Dizüstü bilgisayar/pil tespit edildi; Hazırda Beklet güvenlik payı için kapatılmadı."
                    return
                }
                $wasEnabled = (Get-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Power" "HibernateEnabled" 1) -eq 1
                Add-SimpleksBackupEntry -Type "Hibernate" -Path "Hibernate" -PreviousValue $wasEnabled -PreviousExisted $true -NewValue $false
                powercfg -h off
            }
        },
        [PSCustomObject]@{
            Id = "power.reset-forced-timer-resolution"; Name = "Zorlanmış Zamanlayıcı Çözünürlüğünü Sıfırlama"; Category = "CPU"
            Tier = "Balanced"; Risk = "Safe"; SecurityImpact = $false; Reversible = $true; RequiresReboot = $false
            Description = "Bazı üçüncü parti 'timer tool' uygulamalarının bıraktığı zorlanmış yüksek çözünürlüklü zamanlayıcı isteğini temizler. Modern Windows zamanlayıcıyı dinamik yönetir; sürekli zorlanmış yüksek çözünürlük boşta güç tüketimini artırır ve genelde faydasızdır."
            Detect = { $null }
            Apply  = {
                Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" -Name "GlobalTimerResolutionRequests" -Force -ErrorAction SilentlyContinue
            }
        },
        [PSCustomObject]@{
            Id = "gaming.game-mode-hags"; Name = "Oyun Modu + Donanım Hızlandırmalı GPU Zamanlama (HAGS)"; Category = "Gaming"
            Tier = "Safe"; Risk = "Safe"; SecurityImpact = $false; Reversible = $true; RequiresReboot = $true; MinBuild = 19041
            Description = "Windows Oyun Modu'nu ve GPU zamanlamasını donanıma devreden HAGS özelliğini açar."
            Detect = { (Get-RegValue "HKCU:\Software\Microsoft\GameBar" "AllowAutoGameMode" 0) -eq 1 -and (Get-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode" 0) -eq 2 }
            Apply  = {
                Set-Reg "HKCU:\Software\Microsoft\GameBar" "AllowAutoGameMode" 1
                Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode" 2
            }
        },
        [PSCustomObject]@{
            Id = "gaming.mmcss-games-priority"; Name = "MMCSS: Oyunlar İçin CPU/GPU Zamanlayıcı Önceliği"; Category = "Gaming"
            Tier = "Performance"; Risk = "Moderate"; SecurityImpact = $false; Reversible = $true; RequiresReboot = $false
            Description = "MMCSS 'Games' görev profilinde GPU/CPU önceliğini ve zamanlama kategorisini yükseltir. Yalnızca MMCSS'in önceliklendirdiği süreçleri etkiler; sonuç oyuna göre değişir."
            Detect = { (Get-RegValue $script:gamesTaskPath "Scheduling Category") -eq "High" }
            Apply  = {
                Set-Reg $script:gamesTaskPath "GPU Priority" 8
                Set-Reg $script:gamesTaskPath "Priority" 6
                Set-Reg $script:gamesTaskPath "Scheduling Category" "High" "String"
                Set-Reg $script:gamesTaskPath "SFIO Priority" "High" "String"
            }
        },
        [PSCustomObject]@{
            Id = "cpu.win32-priority-separation"; Name = "Ön Plan Uygulaması İçin CPU Zaman Dilimi Önceliği"; Category = "CPU"
            Tier = "Performance"; Risk = "Moderate"; SecurityImpact = $false; Reversible = $true; RequiresReboot = $true
            Description = "Win32PrioritySeparation değerini ön plandaki uygulamaya (oyuna) sabit/kısa zaman dilimleri ile öncelik verecek şekilde ayarlar."
            Detect = { (Get-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" "Win32PrioritySeparation") -eq 38 }
            Apply  = { Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" "Win32PrioritySeparation" 38 }
        },
        [PSCustomObject]@{
            Id = "network.delivery-optimization-http"; Name = "Teslimat Optimizasyonu: Sadece HTTP (P2P Kapalı)"; Category = "Network"
            Tier = "Balanced"; Risk = "Safe"; SecurityImpact = $false; Reversible = $true; RequiresReboot = $false
            Description = "Windows Update'in diğer bilgisayarlarla eşler arası (P2P) veri paylaşımını kapatır, güncellemeleri yalnızca Microsoft sunucularından indirir. Windows Update servisi çalışmaya devam eder."
            Detect = { (Get-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" "DODownloadMode") -eq 1 }
            Apply  = { Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" "DODownloadMode" 1 }
        },
        [PSCustomObject]@{
            Id = "input.mouse-accel-off"; Name = "Fare İvmesini (Mouse Acceleration) Kapatma"; Category = "Input"
            Tier = "Safe"; Risk = "Safe"; SecurityImpact = $false; Reversible = $true; RequiresReboot = $false
            Description = "1:1 fare hareketi için Windows'un 'Enhance Pointer Precision' ivmesini kapatır."
            Detect = { (Get-RegValue "HKCU:\Control Panel\Mouse" "MouseSpeed") -eq "0" }
            Apply  = { Set-Reg "HKCU:\Control Panel\Mouse" "MouseSpeed" "0" "String" }
        },
        [PSCustomObject]@{
            Id = "storage.sysmain-prefetch-off"; Name = "SysMain (Superfetch) ve Prefetch Kapatma"; Category = "Storage"
            Tier = "Performance"; Risk = "Moderate"; SecurityImpact = $false; Reversible = $true; RequiresReboot = $true
            Description = "NVMe/SSD sistemlerde disk erişimi zaten hızlı olduğundan SysMain'in RAM/CPU önbellekleme yükü genelde faydadan çok maliyettir. Dönen disk (HDD) tespit edilirse atlanır."
            Detect = { (Get-SvcStartType "SysMain") -eq "Disabled" }
            Apply  = {
                $hw = Get-SimpleksHardwareInfo
                if (-not $hw.SsdLikely) {
                    Write-Warn2 "HDD tespit edildi; SysMain/Prefetch kapatılmadı (HDD sistemlerde performansı düşürebilir)."
                    return
                }
                Set-SvcState -Name "SysMain" -StartupType Disabled
                Set-Reg $script:prefetchPath "EnablePrefetcher" 0
                Set-Reg $script:prefetchPath "EnableSuperfetch" 0
            }
        },
        [PSCustomObject]@{
            Id = "storage.ntfs-last-access-off"; Name = "NTFS Son Erişim Zamanı Damgalamayı Kapatma"; Category = "Storage"
            Tier = "Performance"; Risk = "Safe"; SecurityImpact = $false; Reversible = $true; RequiresReboot = $false
            Description = "Her dosya okumasında NTFS'in son erişim zaman damgasını güncellemesini durdurur, gereksiz disk yazımını azaltır."
            Detect = { $null }
            Apply  = {
                $prevRaw = fsutil behavior query disablelastaccess
                $prevValue = if ($prevRaw -match '=\s*1\b') { 1 } else { 0 }
                Add-SimpleksBackupEntry -Type "FsutilLastAccess" -Path "NtfsLastAccess" -PreviousValue $prevValue -PreviousExisted $true -NewValue 1
                fsutil behavior set disablelastaccess 1 | Out-Null
            }
        },
        [PSCustomObject]@{
            Id = "search.indexing-off"; Name = "Windows Arama İndekslemeyi Kapatma"; Category = "Search"
            Tier = "Extreme"; Risk = "Aggressive"; SecurityImpact = $false; Reversible = $true; RequiresReboot = $false
            Description = "WSearch servisini kapatır: boşta CPU/disk kullanımını azaltır ama Başlat menüsü/Gezgin/Outlook araması yavaşlar ve sonuçlar indekslenmeden (dosya içeriği taranmadan) gelir."
            Detect = { (Get-SvcStartType "WSearch") -eq "Disabled" }
            Apply  = { Set-SvcState -Name "WSearch" -StartupType Disabled }
        },
        [PSCustomObject]@{
            Id = "privacy.telemetry-off"; Name = "Telemetri (DiagTrack) Kapatma"; Category = "Privacy"
            Tier = "Balanced"; Risk = "Safe"; SecurityImpact = $false; Reversible = $true; RequiresReboot = $false
            Description = "Bağlantılı Kullanıcı Deneyimleri ve Telemetri servisini kapatır, AllowTelemetry politikasını 0 yapar."
            Detect = { (Get-SvcStartType "DiagTrack") -eq "Disabled" }
            Apply  = {
                Set-SvcState -Name "DiagTrack" -StartupType Disabled
                Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry" 0
            }
        },
        [PSCustomObject]@{
            Id = "privacy.activity-history-off"; Name = "Aktivite Geçmişini Kapatma"; Category = "Privacy"
            Tier = "Balanced"; Risk = "Safe"; SecurityImpact = $false; Reversible = $true; RequiresReboot = $false
            Description = "Etkinlik geçmişinin toplanmasını ve Microsoft hesabıyla eşitlenmesini kapatır."
            Detect = { (Get-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "EnableActivityFeed") -eq 0 }
            Apply  = {
                Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "PublishUserActivities" 0
                Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "EnableActivityFeed" 0
            }
        },
        [PSCustomObject]@{
            Id = "background.uwp-apps-off"; Name = "Arka Planda Çalışan UWP Uygulamalarını Kapatma"; Category = "Background"
            Tier = "Balanced"; Risk = "Safe"; SecurityImpact = $false; Reversible = $true; RequiresReboot = $false
            Description = "UWP/Store uygulamalarının arka planda çalışmasını genel olarak kapatır (bildirimler etkilenebilir)."
            Detect = { (Get-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" "GlobalUserDisabled") -eq 1 }
            Apply  = {
                Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" "GlobalUserDisabled" 1
                Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "BackgroundAppGlobalToggle" 0
            }
        },
        [PSCustomObject]@{
            Id = "gaming.gamedvr-off"; Name = "Oyun Kaydını (Game DVR) Kapatma"; Category = "Gaming"
            Tier = "Safe"; Risk = "Safe"; SecurityImpact = $false; Reversible = $true; RequiresReboot = $false
            Description = "Arka planda kayıt tamponu tutan Game DVR'ı kapatır; tam ekran oyunlarda küçük performans/gecikme kazancı sağlar."
            Detect = { (Get-RegValue "HKCU:\System\GameConfigStore" "GameDVR_Enabled") -eq 0 }
            Apply  = {
                Set-Reg "HKCU:\System\GameConfigStore" "GameDVR_Enabled" 0
                Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" "AllowGameDVR" 0
            }
        },
        [PSCustomObject]@{
            Id = "gaming.gamebar-off"; Name = "Xbox Game Bar Arka Plan Overlay'lerini Kapatma"; Category = "Gaming"
            Tier = "Balanced"; Risk = "Safe"; SecurityImpact = $false; Reversible = $true; RequiresReboot = $false
            Description = "Game Bar açılış panelini ve Nexus overlay'ini kapatır; uygulama kaldırılmaz, sadece otomatik başlaması engellenir."
            Detect = { (Get-RegValue "HKCU:\SOFTWARE\Microsoft\GameBar" "ShowStartupPanel") -eq 0 }
            Apply  = {
                Set-Reg "HKCU:\SOFTWARE\Microsoft\GameBar" "ShowStartupPanel" 0
                Set-Reg "HKCU:\SOFTWARE\Microsoft\GameBar" "UseNexusForGameBarEnabled" 0
            }
        },
        [PSCustomObject]@{
            Id = "ai.recall-off"; Name = "Windows Recall / Click to Do Kapatma"; Category = "AI"
            Tier = "Balanced"; Risk = "Safe"; SecurityImpact = $false; Reversible = "Partial"; RequiresReboot = $false; MinBuild = 26100
            Description = "Recall anlık görüntü toplamayı ve Click to Do'yu HKCU+HKLM politikaları üzerinden kapatır, donanımda mevcutsa Recall isteğe bağlı Windows özelliğini de kapatmayı dener. Not: Recall yalnızca NPU'lu 'Copilot+ PC' donanımında etkinleşir; NPU'suz sistemlerde bu ayar önleyici/gelecek-güvence niteliğindedir, çünkü özellik zaten mevcut değildir."
            Detect = { (Get-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" "DisableAIDataAnalysis") -eq 1 }
            Apply  = {
                $aiPathHkcu = "HKCU:\Software\Policies\Microsoft\Windows\WindowsAI"
                $aiPathHklm = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"
                foreach ($aiPath in @($aiPathHkcu, $aiPathHklm)) {
                    Set-Reg $aiPath "DisableAIDataAnalysis" 1
                    Set-Reg $aiPath "AllowRecallEnablement" 0
                    Set-Reg $aiPath "TurnOffSavingSnapshots" 1
                    Set-Reg $aiPath "DisableClickToDo" 1
                }
                try { Disable-WindowsOptionalFeature -Online -FeatureName "Recall" -NoRestart -ErrorAction Stop | Out-Null }
                catch { Write-Warn2 "Recall isteğe bağlı Windows özelliği bu sistemde bulunamadı (beklenen: NPU'suz donanımda zaten yok)." }
            }
        },
        [PSCustomObject]@{
            Id = "ai.copilot-off"; Name = "Windows Copilot Kapatma"; Category = "AI"
            Tier = "Balanced"; Risk = "Safe"; SecurityImpact = $false; Reversible = $true; RequiresReboot = $false
            Description = "Copilot'u politika üzerinden kapatır ve görev çubuğu düğmesini kaldırır. Not: bu politika yalnızca HKCU altında çalışır - HKLM kopyası Microsoft tarafından onurlandırılmaz, bu yüzden burada kasıtlı olarak sadece HKCU ayarlanır."
            Detect = { (Get-RegValue "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot") -eq 1 }
            Apply  = { Set-Reg "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot" 1 }
        },
        [PSCustomObject]@{
            Id = "services.legacy-off"; Name = "Nadiren Kullanılan Servisleri Kapatma (Fax, Uzak Kayıt Defteri vb.)"; Category = "Services"
            Tier = "Balanced"; Risk = "Safe"; SecurityImpact = $false; Reversible = $true; RequiresReboot = $false
            Description = "Fax, RemoteRegistry, RetailDemo, WalletService servislerini kapatır - modern ev/oyun sistemlerinde neredeyse hiç kullanılmaz."
            Detect = { (Get-SvcStartType "Fax") -eq "Disabled" }
            Apply  = {
                foreach ($svc in @("Fax", "RemoteRegistry", "RetailDemo", "WalletService")) {
                    Set-SvcState -Name $svc -StartupType Disabled
                }
            }
        },
        [PSCustomObject]@{
            Id = "services.conditional-off"; Name = "Koşullu Servisleri Kapatma (Harita, Konum, WMP Ağı)"; Category = "Services"
            Tier = "Performance"; Risk = "Moderate"; SecurityImpact = $false; Reversible = $true; RequiresReboot = $false
            Description = "MapsBroker, lfsvc (Konum), WMPNetworkSvc, PcaSvc servislerini kapatır. Çevrimdışı harita indirme, 'Cihazımı Bul' veya konum tabanlı uygulama kullanıyorsanız bu tweak'i atlayın."
            Detect = { (Get-SvcStartType "MapsBroker") -eq "Disabled" }
            Apply  = {
                foreach ($svc in @("MapsBroker", "lfsvc", "WMPNetworkSvc", "PcaSvc")) {
                    Set-SvcState -Name $svc -StartupType Disabled
                }
            }
        },
        [PSCustomObject]@{
            Id = "services.print-spooler-off"; Name = "Yazdırma Biriktiricisini (Print Spooler) Kapatma"; Category = "Services"
            Tier = "Extreme"; Risk = "Aggressive"; SecurityImpact = $false; Reversible = $true; RequiresReboot = $false
            Description = "Yazıcı kullanılmıyorsa Spooler servisini kapatır. Kurulu yazıcı tespit edilirse otomatik olarak atlanır."
            Detect = { (Get-SvcStartType "Spooler") -eq "Disabled" }
            Apply  = {
                $printers = Get-Printer -ErrorAction SilentlyContinue
                if ($printers -and $printers.Count -gt 0) {
                    Write-Warn2 "Kurulu yazıcı tespit edildi; Print Spooler kapatılmadı."
                    return
                }
                Set-SvcState -Name "Spooler" -StartupType Disabled
            }
        },
        [PSCustomObject]@{
            Id = "tasks.telemetry-tasks-off"; Name = "Telemetri/CEIP Zamanlanmış Görevlerini Kapatma"; Category = "ScheduledTasks"
            Tier = "Balanced"; Risk = "Safe"; SecurityImpact = $false; Reversible = $true; RequiresReboot = $false
            Description = "Compatibility Appraiser, CEIP Consolidator/UsbCeip, DiskDiagnostic, Feedback ve WER kuyruğu görevlerini devre dışı bırakır. Windows Update/bakım/güvenlik görevlerine dokunmaz."
            Detect = { $null }
            Apply  = {
                $gorevler = @(
                    @{ Path = "\Microsoft\Windows\Application Experience\"; Name = "Microsoft Compatibility Appraiser" },
                    @{ Path = "\Microsoft\Windows\Application Experience\"; Name = "ProgramDataUpdater" },
                    @{ Path = "\Microsoft\Windows\Autochk\"; Name = "Proxy" },
                    @{ Path = "\Microsoft\Windows\Customer Experience Improvement Program\"; Name = "Consolidator" },
                    @{ Path = "\Microsoft\Windows\Customer Experience Improvement Program\"; Name = "UsbCeip" },
                    @{ Path = "\Microsoft\Windows\DiskDiagnostic\"; Name = "Microsoft-Windows-DiskDiagnosticDataCollector" },
                    @{ Path = "\Microsoft\Windows\Feedback\Siuf\"; Name = "DmClient" },
                    @{ Path = "\Microsoft\Windows\Feedback\Siuf\"; Name = "DmClientOnScenarioDownload" },
                    @{ Path = "\Microsoft\Windows\Windows Error Reporting\"; Name = "QueueReporting" }
                )
                foreach ($g in $gorevler) {
                    Set-ScheduledTaskState -TaskPath $g.Path -TaskName $g.Name -State Disabled | Out-Null
                }
            }
        },
        [PSCustomObject]@{
            Id = "ui.taskbar-left-align"; Name = "Görev Çubuğunu Sola Hizalama"; Category = "UI"
            Tier = "Safe"; Risk = "Safe"; SecurityImpact = $false; Reversible = $true; RequiresReboot = $false
            Description = "Windows 11 varsayılanı olan ortalanmış görev çubuğunu klasik sol hizaya döndürür (kozmetik)."
            Detect = { (Get-RegValue $script:expAdvPath "TaskbarAl") -eq 0 }
            Apply  = { Set-Reg $script:expAdvPath "TaskbarAl" 0 }
        },
        [PSCustomObject]@{
            Id = "ui.widgets-off"; Name = "Widget'ları Kapatma"; Category = "UI"
            Tier = "Safe"; Risk = "Safe"; SecurityImpact = $false; Reversible = $true; RequiresReboot = $false
            Description = "Görev çubuğundaki Widget düğmesini ve arka plan sürecini kapatır (kozmetik + hafif RAM kazancı)."
            Detect = { (Get-RegValue $script:expAdvPath "TaskbarDa") -eq 0 }
            Apply  = { Set-Reg $script:expAdvPath "TaskbarDa" 0 }
        },
        [PSCustomObject]@{
            Id = "ui.start-suggestions-off"; Name = "Başlat Menüsü Önerilerini Kapatma"; Category = "UI"
            Tier = "Safe"; Risk = "Safe"; SecurityImpact = $false; Reversible = $true; RequiresReboot = $false
            Description = "Başlat menüsündeki 'önerilen' uygulama/dosya blokunu kapatır (kozmetik + gizlilik)."
            Detect = { (Get-RegValue $script:expAdvPath "Start_IrisRecommendations") -eq 0 }
            Apply  = {
                Set-Reg $script:expAdvPath "Start_TrackDocs" 0
                Set-Reg $script:expAdvPath "Start_IrisRecommendations" 0
            }
        },
        [PSCustomObject]@{
            Id = "ui.web-search-off"; Name = "Görev Çubuğu Web Aramasını Kapatma"; Category = "UI"
            Tier = "Safe"; Risk = "Safe"; SecurityImpact = $false; Reversible = $true; RequiresReboot = $false
            Description = "Başlat/Arama'da yerel dosya aramasına web sonuçlarının karışmasını engeller."
            Detect = { (Get-RegValue "HKCU:\Software\Policies\Microsoft\Windows\Explorer" "DisableSearchBoxSuggestions") -eq 1 }
            Apply  = { Set-Reg "HKCU:\Software\Policies\Microsoft\Windows\Explorer" "DisableSearchBoxSuggestions" 1 }
        },
        [PSCustomObject]@{
            Id = "ui.taskbar-search-off"; Name = "Görev Çubuğu Arama Kutusunu Kapatma"; Category = "UI"
            Tier = "Safe"; Risk = "Safe"; SecurityImpact = $false; Reversible = $true; RequiresReboot = $false
            Description = "Görev çubuğundaki arama kutusunu/simgesini gizler (kozmetik)."
            Detect = { (Get-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "SearchboxTaskbarMode") -eq 0 }
            Apply  = { Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "SearchboxTaskbarMode" 0 }
        },
        [PSCustomObject]@{
            Id = "ui.numlock-on-boot"; Name = "Açılışta NumLock'u Etkinleştirme"; Category = "UI"
            Tier = "Safe"; Risk = "Safe"; SecurityImpact = $false; Reversible = "Partial"; RequiresReboot = $false
            Description = 'Oturum açma ekranından itibaren NumLock''un açık gelmesini sağlar. reg.exe kullanır (HKU: sürücüsü PowerShell''de otomatik bağlı değildir) - bu tek satır yedekleme motorundan geçmez, geri almak isterseniz aynı anahtarı elle "0" değerine döndürün: reg add "HKU\.DEFAULT\Control Panel\Keyboard" /v InitialKeyboardIndicators /t REG_SZ /d 0 /f'
            Detect = { $null }
            Apply  = { reg add "HKU\.DEFAULT\Control Panel\Keyboard" /v "InitialKeyboardIndicators" /t REG_SZ /d "2" /f | Out-Null }
        },
        [PSCustomObject]@{
            Id = "ui.menu-delay-off"; Name = "Menü Açılış Gecikmesini Sıfırlama"; Category = "UI"
            Tier = "Safe"; Risk = "Safe"; SecurityImpact = $false; Reversible = $true; RequiresReboot = $false
            Description = "Sağ tık/Başlat menülerinin varsayılan ~400ms açılış gecikmesini sıfırlar."
            Detect = { (Get-RegValue "HKCU:\Control Panel\Desktop" "MenuShowDelay") -eq "0" }
            Apply  = { Set-Reg "HKCU:\Control Panel\Desktop" "MenuShowDelay" "0" "String" }
        },
        [PSCustomObject]@{
            Id = "onedrive.remove"; Name = "OneDrive'ı Kaldırma"; Category = "Bloatware"
            Tier = "Extreme"; Risk = "Aggressive"; SecurityImpact = $false; Reversible = "Partial"; RequiresReboot = $false
            Description = "OneDrive istemcisini kaldırır. Geri almak için Microsoft Store/winget üzerinden yeniden kurulması gerekir; bu bir kayıt defteri geri almasıyla tam olarak tersine çevrilemez."
            Detect = {
                $p32 = Test-Path "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
                $p64 = Test-Path "$env:SystemRoot\System32\OneDriveSetup.exe"
                -not ($p32 -or $p64)
            }
            Apply  = {
                Stop-Process -Name "OneDrive" -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                $onedrive32 = "$env:SystemRoot\System32\OneDriveSetup.exe"
                $onedrive64 = "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
                if (Test-Path $onedrive64) { Start-Process $onedrive64 -ArgumentList "/uninstall" -Wait -NoNewWindow }
                elseif (Test-Path $onedrive32) { Start-Process $onedrive32 -ArgumentList "/uninstall" -Wait -NoNewWindow }
                reg add "HKCR\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}" /v "System.IsPinnedToNameSpaceTree" /t REG_DWORD /d 0 /f | Out-Null
            }
        },
        [PSCustomObject]@{
            Id = "security.uac-lowest"; Name = "UAC Seviyesini En Düşük Seviyeye Ayarlama"; Category = "Security"
            Tier = "Extreme"; Risk = "Aggressive"; SecurityImpact = $true; Reversible = $true; RequiresReboot = $false
            SecurityNote = "Yönetici onay istemlerini sessizce (masaüstünü karartmadan) geçer; kötü amaçlı yazılımların yükselmiş izin alma çabasını kolaylaştırabilir."
            Description = "ConsentPromptBehaviorAdmin=0 ve PromptOnSecureDesktop=0 yaparak UAC uyarılarını en aza indirir (UAC tamamen kapanmaz, EnableLUA=1 kalır)."
            Detect = { (Get-RegValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" "ConsentPromptBehaviorAdmin") -eq 0 }
            Apply  = {
                $uacPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
                Set-Reg $uacPath "ConsentPromptBehaviorAdmin" 0
                Set-Reg $uacPath "PromptOnSecureDesktop" 0
                Set-Reg $uacPath "EnableLUA" 1
            }
        },
        [PSCustomObject]@{
            Id = "security.system-restore-off"; Name = "Sistem Geri Yüklemeyi Kapatma"; Category = "Security"
            Tier = "Extreme"; Risk = "Aggressive"; SecurityImpact = $true; Reversible = $true; RequiresReboot = $false
            SecurityNote = "Sürücü/güncelleme sorunlarında veya fidye yazılımı sonrası geri dönüş imkanınızı kaldırır."
            Description = "Sistem Koruması'nı ve otomatik geri yükleme noktası oluşturmayı C sürücüsü için kapatır."
            Detect = { (Get-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\SystemRestore" "DisableSR") -eq 1 }
            Apply  = {
                $wasEnabled = -not ((Get-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\SystemRestore" "DisableSR" 0) -eq 1)
                Add-SimpleksBackupEntry -Type "SystemRestore" -Path "SystemRestore" -PreviousValue $wasEnabled -PreviousExisted $true -NewValue $false
                Disable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue | Out-Null
                Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\SystemRestore" "DisableSR" 1
            }
        },
        [PSCustomObject]@{
            Id = "security.vbs-off"; Name = "Bellenim Tabanlı Koruma / Çekirdek Yalıtımını (VBS) Kapatma"; Category = "Security"
            Tier = "Extreme"; Risk = "Experimental"; SecurityImpact = $true; Reversible = $true; RequiresReboot = $true
            SecurityNote = "Hypervisor tabanlı bellek bütünlüğü korumasını kapatır; bazı çekirdek-düzeyi kötü amaçlı yazılımlara karşı savunmasız kalırsınız. Bazı sistemlerde küçük FPS kazancı sağlar, bazılarında ölçülebilir fark yaratmaz."
            Description = "HypervisorEnforcedCodeIntegrity özelliğini kapatır."
            Detect = { (Get-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" "Enabled") -eq 0 }
            Apply  = { Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" "Enabled" 0 }
        },
        [PSCustomObject]@{
            Id = "security.cpu-mitigations-off"; Name = "CPU Spekülatif Yürütme Önlemlerini (Spectre/Meltdown) Kapatma"; Category = "Security"
            Tier = "Extreme"; Risk = "Experimental"; SecurityImpact = $true; Reversible = $true; RequiresReboot = $true
            SecurityNote = "Sisteminizi Spectre/Meltdown sınıfı yan kanal saldırılarına karşı savunmasız bırakır. Sadece izole/paylaşılmayan, internetten güvenilmeyen kod çalıştırmayan kişisel oyun sistemlerinde düşünülmelidir."
            Description = "FeatureSettingsOverride/FeatureSettingsOverrideMask=3 ile CPU mikro-kod tabanlı yan kanal önlemlerini kapatır (KB4073119'da belgelenen mekanizma). CPU-bound iş yüklerinde ölçülebilir ama donanıma bağlı değişken bir kazanç sağlar."
            Detect = { (Get-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "FeatureSettingsOverride") -eq 3 }
            Apply  = {
                $mmPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
                Set-Reg $mmPath "FeatureSettingsOverride" 3
                Set-Reg $mmPath "FeatureSettingsOverrideMask" 3
            }
        }
    )
}

# =========================================================================
# WPF ARAYÜZÜ
# =========================================================================

function Show-SimpleksGui {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xml

    $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Simpleks - Windows 11 Optimizasyon Aracı" Height="720" Width="920"
        Background="#1E1E1E" WindowStartupLocation="CenterScreen">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Background" Value="#3A3A3A"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="Padding" Value="10,4"/>
      <Setter Property="Margin" Value="4"/>
    </Style>
    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="Margin" Value="6,2"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>
    <Style TargetType="TextBlock">
      <Setter Property="Foreground" Value="White"/>
    </Style>
  </Window.Resources>
  <Grid Margin="10">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="150"/>
    </Grid.RowDefinitions>

    <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,6">
      <TextBlock Text="🚀 Simpleks" FontSize="20" FontWeight="Bold" Margin="0,0,10,0"/>
      <TextBlock x:Name="StatusText" VerticalAlignment="Center" Foreground="#AAAAAA"/>
    </StackPanel>

    <WrapPanel Grid.Row="1" Orientation="Horizontal" Margin="0,0,0,6">
      <TextBlock Text="Profil:" VerticalAlignment="Center" Margin="0,0,4,0"/>
      <ComboBox x:Name="PresetCombo" Width="140" Margin="0,0,10,0">
        <ComboBoxItem Content="Safe"/>
        <ComboBoxItem Content="Balanced" IsSelected="True"/>
        <ComboBoxItem Content="Performance"/>
        <ComboBoxItem Content="Extreme"/>
      </ComboBox>
      <CheckBox x:Name="RiskyCheck" Content="Riskli tweak'leri göster"/>
      <CheckBox x:Name="WhatIfCheck" Content="Sadece simüle et (WhatIf)"/>
      <Button x:Name="RefreshButton" Content="Durumu Yenile"/>
      <Button x:Name="RollbackButton" Content="Son Çalıştırmayı Geri Al"/>
    </WrapPanel>

    <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto">
      <StackPanel x:Name="TweaksPanel"/>
    </ScrollViewer>

    <WrapPanel Grid.Row="3" Orientation="Horizontal" Margin="0,6">
      <CheckBox x:Name="InstallPackagesCheck" Content="Chocolatey paketlerini kur"/>
      <CheckBox x:Name="RemoveAppsCheck" Content="İsteğe bağlı uygulamaları kaldır"/>
      <Button x:Name="ApplyButton" Content="UYGULA" FontWeight="Bold" Background="#2E7D32" Padding="18,6"/>
    </WrapPanel>

    <TextBox x:Name="LogBox" Grid.Row="4" Background="#101010" Foreground="#CCCCCC"
             FontFamily="Consolas" FontSize="12" IsReadOnly="True"
             VerticalScrollBarVisibility="Auto" TextWrapping="Wrap"/>
  </Grid>
</Window>
'@

    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $window = [Windows.Markup.XamlReader]::Load($reader)

    $presetCombo = $window.FindName("PresetCombo")
    $riskyCheck  = $window.FindName("RiskyCheck")
    $whatIfCheck = $window.FindName("WhatIfCheck")
    $refreshBtn  = $window.FindName("RefreshButton")
    $rollbackBtn = $window.FindName("RollbackButton")
    $tweaksPanel = $window.FindName("TweaksPanel")
    $installChk  = $window.FindName("InstallPackagesCheck")
    $removeChk   = $window.FindName("RemoveAppsCheck")
    $applyBtn    = $window.FindName("ApplyButton")
    $statusText  = $window.FindName("StatusText")

    $script:LogBox = $window.FindName("LogBox")

    $statusText.Text = " - $($script:BuildInfo.Caption) build $($script:BuildInfo.BuildNumber) - Yönetici: $(if (Test-SimpleksAdmin) { 'Evet' } else { 'HAYIR' })"

    $allTweaks = Get-SimpleksTweaks
    $checkboxMap = @{}

    foreach ($cat in ($allTweaks | Select-Object -ExpandProperty Category -Unique)) {
        $label = New-Object System.Windows.Controls.TextBlock
        $label.Text = $cat
        $label.FontWeight = "Bold"
        $label.Foreground = "#4FC3F7"
        $label.Margin = "0,10,0,2"
        [void]$tweaksPanel.Children.Add($label)

        foreach ($t in ($allTweaks | Where-Object { $_.Category -eq $cat })) {
            $cb = New-Object System.Windows.Controls.CheckBox
            $suffix = ""
            if ($t.RequiresReboot) { $suffix += " [yeniden başlatma]" }
            if ($t.SecurityImpact) { $suffix += " [GÜVENLİK]" }
            $cb.Content = "$($t.Name)$suffix"
            $cb.Tag = $t.Id
            $tooltip = $t.Description
            if ($t.SecurityNote) { $tooltip += "`r`n`r`nGÜVENLİK NOTU: $($t.SecurityNote)" }
            $cb.ToolTip = $tooltip
            $cb.Margin = "16,1,0,1"
            if ($t.SecurityImpact) {
                $cb.IsEnabled = $false
                $cb.Foreground = "#FF8A65"
            }
            [void]$tweaksPanel.Children.Add($cb)
            $checkboxMap[$t.Id] = $cb
        }
    }

    $updatePreset = {
        $preset = $presetCombo.SelectedItem.Content.ToString()
        $activeIds = @(Get-SimpleksActiveTweaks -Preset $preset | Select-Object -ExpandProperty Id)
        foreach ($id in $checkboxMap.Keys) {
            $checkboxMap[$id].IsChecked = ($activeIds -contains $id)
        }
    }
    $presetCombo.Add_SelectionChanged($updatePreset)
    & $updatePreset

    $riskyCheck.Add_Checked({
        foreach ($t in ($allTweaks | Where-Object { $_.SecurityImpact })) { $checkboxMap[$t.Id].IsEnabled = $true }
    }.GetNewClosure())
    $riskyCheck.Add_Unchecked({
        foreach ($t in ($allTweaks | Where-Object { $_.SecurityImpact })) {
            $checkboxMap[$t.Id].IsEnabled = $false
            $checkboxMap[$t.Id].IsChecked = $false
        }
    }.GetNewClosure())

    $refreshBtn.Add_Click({
        foreach ($t in $allTweaks) {
            $status = Get-SimpleksTweakStatus $t
            if ($status -eq "Applied") { $checkboxMap[$t.Id].IsChecked = $true }
            elseif ($status -eq "NotApplied") { $checkboxMap[$t.Id].IsChecked = $false }
        }
        Write-Ok "Durum yenilendi."
    }.GetNewClosure())

    $rollbackBtn.Add_Click({
        if (-not (Test-SimpleksAdmin)) { [System.Windows.MessageBox]::Show("Bu işlem Yönetici hakları gerektirir.", "Simpleks") | Out-Null; return }
        $latest = Get-ChildItem -Path $script:LogDir -Filter "backup-*.json" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $latest) { [System.Windows.MessageBox]::Show("Geri alınacak bir yedek bulunamadı.", "Simpleks") | Out-Null; return }
        $confirm = [System.Windows.MessageBox]::Show("Son çalıştırmadaki tüm değişiklikler geri alınacak ($($latest.Name)). Emin misiniz?", "Simpleks - Geri Al", "YesNo", "Warning")
        if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) { return }
        Restore-SimpleksBackupFile -Path $latest.FullName
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        [System.Windows.MessageBox]::Show("Geri alma tamamlandı.", "Simpleks") | Out-Null
    }.GetNewClosure())

    $applyBtn.Add_Click({
        if (-not (Test-SimpleksAdmin)) { [System.Windows.MessageBox]::Show("Bu işlem Yönetici hakları gerektirir.", "Simpleks") | Out-Null; return }

        $selectedTweaks = @($allTweaks | Where-Object { $checkboxMap[$_.Id].IsChecked -eq $true })
        if ($selectedTweaks.Count -eq 0) { [System.Windows.MessageBox]::Show("Hiçbir tweak seçilmedi.", "Simpleks") | Out-Null; return }

        $script:IncludeRisky = [bool]$riskyCheck.IsChecked
        $whatIf = [bool]$whatIfCheck.IsChecked

        $riskyChosen = @($selectedTweaks | Where-Object { $_.SecurityImpact })
        if ($riskyChosen.Count -gt 0 -and -not $whatIf) {
            $names = ($riskyChosen | ForEach-Object { "- $($_.Name): $($_.SecurityNote)" }) -join "`r`n"
            $confirm = [System.Windows.MessageBox]::Show("Aşağıdaki tweak'ler GÜVENLİK ETKİSİ taşır:`r`n`r`n$names`r`n`r`nDevam etmek istiyor musunuz?", "Simpleks - Güvenlik Uyarısı", "YesNo", "Warning")
            if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) { return }
        }

        $applyBtn.IsEnabled = $false
        try {
            $runStamp = Get-Date -Format "yyyyMMdd-HHmmss"
            $script:JsonLogPath  = Join-Path $script:LogDir "simpleks-$runStamp.jsonl"
            $script:TextLogPath  = Join-Path $script:LogDir "simpleks-$runStamp.log"
            $script:BackupEntries = [System.Collections.Generic.List[object]]::new()
            $backupFile = Join-Path $script:LogDir "backup-$runStamp.json"

            if (-not $whatIf) {
                Write-Step "Sistem Geri Yükleme noktası oluşturuluyor..."
                try {
                    Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
                    Checkpoint-Computer -Description "Simpleks Optimizasyon Öncesi" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
                    Write-Ok "Geri yükleme noktası oluşturuldu."
                } catch {
                    Write-Warn2 "Geri yükleme noktası oluşturulamadı: $($_.Exception.Message)"
                }
            }

            foreach ($t in $selectedTweaks) {
                Invoke-SimpleksTweak -Tweak $t -WhatIfOnly:$whatIf
                if (-not $whatIf) { Save-SimpleksBackupFile -Path $backupFile | Out-Null }
            }

            if ($installChk.IsChecked -and -not $whatIf) {
                Write-Step "Chocolatey paketleri kuruluyor..."
                if (!(Get-Command choco -ErrorAction SilentlyContinue)) {
                    Set-ExecutionPolicy Bypass -Scope Process -Force
                    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
                    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
                    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
                }
                foreach ($pkg in $script:ChocoPackages) {
                    choco install $pkg -y | Out-Null
                    if ($LASTEXITCODE -eq 0) { Write-Ok "$pkg kuruldu." } else { Write-Warn2 "$pkg kurulamadı." }
                }
            }

            if ($removeChk.IsChecked -and -not $whatIf) {
                Write-Step "İsteğe bağlı uygulamalar kaldırılıyor..."
                foreach ($pkgName in $script:OptionalAppxPackages) {
                    Get-AppxPackage -AllUsers -Name $pkgName -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
                    Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $pkgName } |
                        ForEach-Object { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null }
                }
            }

            if (-not $whatIf) {
                $saved = Save-SimpleksBackupFile -Path $backupFile
                if ($saved) { Write-Ok "Geri alma verisi kaydedildi: $saved" }
                Write-Ok "TÜM İŞLEMLER TAMAMLANDI ($($selectedTweaks.Count) tweak işlendi)."
                Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
                [System.Windows.MessageBox]::Show("Tamamlandı. Bazı ayarlar için yeniden başlatma gerekebilir.", "Simpleks") | Out-Null
            } else {
                Write-Ok "(-WhatIf: hiçbir değişiklik uygulanmadı.)"
            }
        } finally {
            $applyBtn.IsEnabled = $true
        }
    }.GetNewClosure())

    [void]$window.ShowDialog()
}

# =========================================================================
# BAŞLATMA
# =========================================================================

function Start-Simpleks {
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        $OutputEncoding = [System.Text.Encoding]::UTF8
        chcp 65001 | Out-Null
    } catch {}

    if (-not (Test-SimpleksAdmin)) {
        Write-Host "Simpleks, Yönetici olarak yeniden başlatılıyor (UAC onayı isteyecek)..." -ForegroundColor Yellow
        if ($PSCommandPath) {
            Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"")
        } else {
            $relaunchCommand = "irm $script:RepoRawBase/Simpleks.ps1 | iex"
            Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $relaunchCommand)
        }
        return
    }

    $script:BuildInfo     = Get-SimpleksBuildInfo
    $script:LogDir        = Join-Path $env:LOCALAPPDATA "Simpleks\logs"
    $script:BackupEntries = [System.Collections.Generic.List[object]]::new()
    $script:Silent        = $false
    $script:IncludeRisky  = $false
    $script:ChocoPackages = @("googlechrome", "nanazip", "sharex", "discord", "notepadplusplus", "vcredist140", "jre8", "sumatrapdf.install")
    $script:OptionalAppxPackages = @(
        "Microsoft.549981C3F5F10", "Microsoft.BingNews", "Microsoft.BingWeather", "Microsoft.GetHelp",
        "Microsoft.Getstarted", "Microsoft.MicrosoftOfficeHub", "Microsoft.MicrosoftSolitaireCollection",
        "Microsoft.People", "Microsoft.WindowsFeedbackHub", "Microsoft.YourPhone", "Microsoft.ZuneMusic",
        "Microsoft.ZuneVideo", "Clipchamp.Clipchamp", "MicrosoftTeams"
    )

    Show-SimpleksGui
}

# Dosya dot-source edildiğinde (ör. Pester) bu blok ÇALIŞMAZ - yalnızca
# doğrudan çalıştırıldığında (.\Simpleks.ps1) veya `irm ... | iex` ile
# değerlendirildiğinde çalışır.
if ($MyInvocation.InvocationName -ne '.') {
    Start-Simpleks
}

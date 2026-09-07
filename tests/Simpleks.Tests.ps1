#Requires -Modules Pester

<#
    Bu testler yalnızca Simpleks.Definitions.ps1 içindeki SAF MANTIĞI
    doğrular: tweak şeması, preset çözümleme, güvenlik kapısı.
    Hiçbir registry/servis/görev değişikliği YAPILMAZ - Detect/Apply
    scriptblock'ları burada çağrılmaz, sadece varlıkları ve alanları
    doğrulanır. Bu yüzden Windows dışı runner'larda da (CI dahil) güvenle
    çalışır.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot "..\Simpleks.Definitions.ps1")
    $script:AllTweaks = Get-SimpleksTweaks
}

Describe "Tweak şeması" {
    It "en az bir tweak tanımlıdır" {
        $script:AllTweaks.Count | Should -BeGreaterThan 0
    }

    It "tüm tweak Id değerleri benzersizdir" {
        $ids = $script:AllTweaks | ForEach-Object { $_.Id }
        ($ids | Select-Object -Unique).Count | Should -Be $ids.Count
    }

    It "her tweak zorunlu alanlara sahiptir" {
        foreach ($t in $script:AllTweaks) {
            $t.Id | Should -Not -BeNullOrEmpty
            $t.Name | Should -Not -BeNullOrEmpty
            $t.Category | Should -Not -BeNullOrEmpty
            $t.Tier | Should -BeIn @("Safe", "Balanced", "Performance", "Extreme")
            $t.Risk | Should -BeIn @("Safe", "Moderate", "Aggressive", "Experimental")
            $t.Apply | Should -BeOfType [scriptblock]
        }
    }

    It "güvenlik etkili (SecurityImpact) tweak'ler bir SecurityNote taşır" {
        $risky = $script:AllTweaks | Where-Object { $_.SecurityImpact }
        foreach ($t in $risky) {
            $t.SecurityNote | Should -Not -BeNullOrEmpty
        }
    }

    It "güvenlik etkili tweak'ler yalnızca Extreme seviyesindedir" {
        $risky = $script:AllTweaks | Where-Object { $_.SecurityImpact }
        foreach ($t in $risky) {
            $t.Tier | Should -Be "Extreme"
        }
    }
}

Describe "Preset çözümleme (Get-SimpleksActiveTweaks)" {
    It "Safe preset yalnızca Safe seviyeli tweak'leri döndürür" {
        $active = Get-SimpleksActiveTweaks -Preset "Safe"
        foreach ($t in $active) { $t.Tier | Should -Be "Safe" }
    }

    It "Balanced preset Safe+Balanced tweak'lerini içerir, Performance/Extreme'i içermez" {
        $active = Get-SimpleksActiveTweaks -Preset "Balanced"
        foreach ($t in $active) { $t.Tier | Should -BeIn @("Safe", "Balanced") }
    }

    It "Extreme preset -IncludeRisky olmadan güvenlik etkili tweak'leri HARİÇ TUTAR" {
        $active = Get-SimpleksActiveTweaks -Preset "Extreme"
        ($active | Where-Object { $_.SecurityImpact }).Count | Should -Be 0
    }

    It "Extreme preset -IncludeRisky ile güvenlik etkili tweak'leri İÇERİR" {
        $active = Get-SimpleksActiveTweaks -Preset "Extreme" -IncludeRisky
        $securityTweakCount = ($script:AllTweaks | Where-Object { $_.SecurityImpact }).Count
        ($active | Where-Object { $_.SecurityImpact }).Count | Should -Be $securityTweakCount
    }

    It "OnlyIds verildiğinde yalnızca o Id'ler döner (preset/tier'dan bağımsız)" {
        $oneId = $script:AllTweaks[0].Id
        $active = Get-SimpleksActiveTweaks -Preset "Safe" -OnlyIds @($oneId)
        $active.Count | Should -Be 1
        $active[0].Id | Should -Be $oneId
    }
}

Describe "Sürüm desteği (Test-SimpleksTweakSupported)" {
    BeforeAll {
        $script:BuildInfo = [PSCustomObject]@{ BuildNumber = 22631 }
    }

    It "MinBuild belirtilmemiş tweak her zaman desteklenir" {
        $t = [PSCustomObject]@{ MinBuild = $null }
        Test-SimpleksTweakSupported $t | Should -BeTrue
    }

    It "MinBuild mevcut build'den yüksekse tweak desteklenmez" {
        $t = [PSCustomObject]@{ MinBuild = 26100 }
        Test-SimpleksTweakSupported $t | Should -BeFalse
    }
}

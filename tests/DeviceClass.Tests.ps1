BeforeAll {
    $script:ModuleRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $script:ModuleRoot 'Quorum.psd1') -Force
}

Describe 'Windows Server device class' {
    It 'classifies an Intune preview server from skuNumber even when operatingSystem is Windows' {
        InModuleScope Quorum {
            $item = [pscustomobject]@{
                id                = '10000000-0000-4000-8000-0000000000c1'
                deviceName        = 'winsrv-sku.lab.example'
                azureADDeviceId   = '40000000-0000-4000-8000-0000000000c1'
                complianceState   = 'compliant'
                osVersion         = '10.0.29621.1000'
                operatingSystem   = 'Windows'
                skuNumber         = 8
            }
            $record = @(ConvertTo-QuorumIntuneRecord -Item $item)[0]
            Get-QuorumAttributeValue $record 'skuNumber' | Should -Be 8
            (Get-QuorumDeviceClass -Record $record) | Should -Be 'windows-server'
        }
    }

    It 'classifies an Intune record from the assignment-filter SKU name' {
        InModuleScope Quorum {
            $item = [pscustomobject]@{
                id                  = '10000000-0000-4000-8000-0000000000c2'
                deviceName          = 'winsrv-name.lab.example'
                azureADDeviceId     = '40000000-0000-4000-8000-0000000000c2'
                osVersion           = '10.0.29621.1000'
                operatingSystem     = 'Windows'
                operatingSystemSKU  = 'ServerStandard'
            }
            $record = @(ConvertTo-QuorumIntuneRecord -Item $item)[0]
            (Get-QuorumDeviceClass -Record $record) | Should -Be 'windows-server'
        }
    }

    It 'does not treat ServerRdsh (Windows Enterprise multi-session) as Windows Server' {
        InModuleScope Quorum {
            $item = [pscustomobject]@{
                id                = '10000000-0000-4000-8000-0000000000c3'
                deviceName        = 'multisession.lab.example'
                azureADDeviceId   = '40000000-0000-4000-8000-0000000000c3'
                osVersion         = '10.0.26100.1'
                operatingSystem   = 'Windows'
                skuNumber         = 175
                operatingSystemSKU = 'ServerRdsh'
            }
            $record = @(ConvertTo-QuorumIntuneRecord -Item $item)[0]
            (Get-QuorumDeviceClass -Record $record) | Should -Be 'windows'
        }
    }

    It 'treats a Windows Intune record without a server SKU as a Windows client' {
        InModuleScope Quorum {
            $item = [pscustomobject]@{
                id                = '10000000-0000-4000-8000-0000000000c4'
                deviceName        = 'win11-client.lab.example'
                azureADDeviceId   = '40000000-0000-4000-8000-0000000000c4'
                osVersion         = '10.0.26100.3775'
                operatingSystem   = 'Windows'
            }
            $record = @(ConvertTo-QuorumIntuneRecord -Item $item)[0]
            (Get-QuorumDeviceClass -Record $record) | Should -Be 'windows'
        }
    }

    It 'classifies Entra operatingSystem Windows Server and Defender Windows Server platforms' {
        InModuleScope Quorum {
            $entraItem = [pscustomobject]@{
                id                     = '20000000-0000-4000-8000-0000000000c5'
                deviceId               = '40000000-0000-4000-8000-0000000000c5'
                displayName            = 'entra-server.lab.example'
                operatingSystem        = 'Windows Server'
                operatingSystemVersion = '10.0.20348.2849'
                accountEnabled         = $true
            }
            $defenderItem = [pscustomobject]@{
                id              = '30000000-0000-4000-8000-0000000000c6'
                aadDeviceId     = '40000000-0000-4000-8000-0000000000c6'
                computerDnsName = 'mde-server.lab.example'
                osPlatform      = 'WindowsServer2022'
                osVersion       = '10.0.20348.2849'
                osBuild         = 20348
            }
            $entra = @(ConvertTo-QuorumEntraRecord -Item $entraItem)[0]
            $defender = @(ConvertTo-QuorumDefenderRecord -Item $defenderItem)[0]
            (Get-QuorumDeviceClass -Record $entra) | Should -Be 'windows-server'
            (Get-QuorumDeviceClass -Record $defender) | Should -Be 'windows-server'
        }
    }

    It 'lets a server SKU win when Intune still reports operatingSystem Windows' {
        InModuleScope Quorum {
            $id = '40000000-0000-4000-8000-0000000000c7'
            $intuneItem = [pscustomobject]@{
                id              = '10000000-0000-4000-8000-0000000000c7'
                deviceName      = 'winsrv-pilot.lab.example'
                azureADDeviceId = $id
                osVersion       = '10.0.29621.1000'
                operatingSystem = 'Windows'
                skuNumber       = 7
            }
            $entraItem = [pscustomobject]@{
                id                     = '20000000-0000-4000-8000-0000000000c7'
                deviceId               = $id
                displayName            = 'winsrv-pilot.lab.example'
                operatingSystem        = 'Windows Server'
                operatingSystemVersion = '10.0.29621.1000'
            }
            $intune = @(ConvertTo-QuorumIntuneRecord -Item $intuneItem)[0]
            $entra = @(ConvertTo-QuorumEntraRecord -Item $entraItem)[0]
            $devices = @(Merge-QuorumDevice -Record @($intune, $entra))
            $facts = Get-QuorumFact -Device $devices[0] -AsOf ([datetime]::new(2026, 4, 15, 12, 0, 0, [DateTimeKind]::Utc))
            $facts['device.class'] | Should -Be 'windows-server'
        }
    }

    It 'classifies the demo preview server as windows-server and keeps entra-only-04 out of Q002' {
        $out = Join-Path ([System.IO.Path]::GetTempPath()) ('quorum-class-' + [guid]::NewGuid().ToString('n'))
        try {
            $result = Invoke-Quorum -Demo -OutputPath $out
            $pilot = @($result.Devices | Where-Object { $_['hostname'] -eq 'winsrv-pilot-01' })
            $pilot.Count | Should -Be 1
            $pilot[0]['deviceClass'] | Should -Be 'windows-server'
            $server = @($result.Devices | Where-Object { $_['hostname'] -eq 'entra-only-04' })
            $server.Count | Should -Be 1
            $server[0]['deviceClass'] | Should -Be 'windows-server'
            @($result.Findings | Where-Object { $_['ruleId'] -eq 'Q002' -and $_['hostname'] -eq 'entra-only-04' }).Count | Should -Be 0
            @($result.Findings | Where-Object { $_['hostname'] -eq 'winsrv-pilot-01' }).Count | Should -Be 0
        }
        finally {
            if (Test-Path -LiteralPath $out) {
                Remove-Item -LiteralPath $out -Recurse -Force
            }
        }
    }
}

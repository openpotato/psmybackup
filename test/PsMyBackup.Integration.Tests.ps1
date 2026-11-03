# Copyright (c) STÜBER SYSTEMS GmbH. All rights reserved.
# Licensed under the MIT License.

#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

# Run from the repository root: 
# Invoke-Pester -Path ./test/PsMyBackup.Integration.Tests.ps1 -Output Detailed
BeforeAll {
    # Resolve the module manifest relative to the repository, not the current directory.
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path -Path $repositoryRoot -ChildPath 'src' -AdditionalChildPath @('PsMyBackup', 'PsMyBackup.psd1')
    Import-Module -Name $modulePath -Force -ErrorAction Stop

    function ConvertTo-PsMyBackupPsd1Literal([string] $Value) {
        return "'" + $Value.Replace("'", "''") + "'"
    }

    function Invoke-PsMyBackupTestLinkCreation {
        param(
            [string] $Link,
            [string] $Target
        )

        # Windows junctions do not require Developer Mode or symlink privileges.
        if ($IsWindows) {
            $null = New-Item -ItemType Junction -Path $Link -Target $Target -ErrorAction Stop
        }
        else {
            $null = New-Item -ItemType SymbolicLink -Path $Link -Target $Target -ErrorAction Stop
        }
    }

    function Write-PsMyBackupTestConfig {
        param(
            [string] $Path,
            [string] $Source,
            [string] $Target,
            [string] $Missing,
            [ValidateSet('fail', 'skip')]
            [string] $MissingPolicy = 'skip',
            [ValidateSet('None', 'Size', 'Sha256')]
            [string] $VerificationMode = 'Size',
            [string] $Extra = '',
            [bool] $PreserveAttributes = $false,
            [string[]] $SourceIgnore = @('*.tmp')
        )

        $sourceText = ConvertTo-PsMyBackupPsd1Literal $Source
        $targetText = ConvertTo-PsMyBackupPsd1Literal $Target
        $missingText = ConvertTo-PsMyBackupPsd1Literal $Missing
        $preserveAttributesText = if ($PreserveAttributes) { '$true' } else { '$false' }
        $sourceIgnoreText = ($SourceIgnore | ForEach-Object {
            ConvertTo-PsMyBackupPsd1Literal $_
        }) -join ', '
        $content = @"
@{
    Version = '1.0.0'
    TargetFolder = $targetText
    LogCopiedFiles = `$true
    Policies = @{
        MissingSource = 'fail'; ItemError = 'skip'; ExistingSnapshot = 'suffix'
        ExistingFile = 'fail'; RetryCount = 0; RetryDelayMilliseconds = 0
    }
    Verification = @{ Mode = '$VerificationMode' }
    Manifest = @{ Enabled = `$true; IncludeHashes = `$true }
    Metadata = @{ PreserveTimestamps = `$true; PreserveAttributes = $preserveAttributesText }
    $Extra
    Sources = @(
        @{ Name = 'Sample'; Path = $sourceText; Ignore = @($sourceIgnoreText) }
        @{ Name = 'Optional'; Path = $missingText; Policies = @{ MissingSource = '$MissingPolicy' } }
    )
}
"@
        [IO.File]::WriteAllText($Path, $content, [Text.UTF8Encoding]::new($false))
    }
}

AfterAll {
    Remove-Module -Name PsMyBackup -ErrorAction SilentlyContinue
}

Describe 'Backup-MyFiles end-to-end filesystem behavior' -Tag 'Integration' {
    BeforeEach {
        # Give each It a completely separate source, target, and configuration.
        $caseRoot = Join-Path $TestDrive ('PsMyBackup-' + [guid]::NewGuid().ToString('N'))
        $src = Join-Path $caseRoot 'src'
        $missing = Join-Path $caseRoot 'missing'
        $target = Join-Path $caseRoot 'backups'
        $configPath = Join-Path $caseRoot 'backup.psd1'
        $nested = Join-Path $src 'nested'

        [void][IO.Directory]::CreateDirectory($nested)
        [IO.File]::WriteAllText((Join-Path $src 'keep.txt'), 'keep')
        [IO.File]::WriteAllText((Join-Path $src 'ignore.tmp'), 'ignored')
        [IO.File]::WriteAllText((Join-Path $nested 'child.txt'), 'child')

        $stamp = [DateTime]::UtcNow.AddDays(-2)
        [IO.File]::SetLastWriteTimeUtc((Join-Path $src 'keep.txt'), $stamp)

        Write-PsMyBackupTestConfig -Path $configPath -Source $src -Target $target -Missing $missing
    }

    AfterEach {
        if ($caseRoot -and [IO.Directory]::Exists($caseRoot)) {
            [IO.Directory]::Delete($caseRoot, $true)
        }
    }

    Context 'Read-only execution and preflight' {
        It '-Test calculates planned files, applies ignore rules, and writes nothing' {
            $plan = Backup-MyFiles -ConfigPath $configPath -Test -WarningAction SilentlyContinue

            $plan.Status | Should -Be 'PARTIAL'
            $plan.IsTest | Should -BeTrue
            $plan.PSObject.TypeNames[0] | Should -Be 'PsMyBackup.Result'
            $plan.FilesPlanned | Should -Be 2
            $plan.BytesPlanned | Should -Be 9
            $plan.FilesCopied | Should -Be 0
            $plan.Ignored | Should -Be 1
            $plan.ReportPath | Should -BeNullOrEmpty
            $plan.ReportText | Should -Match 'PSMYBACKUP REPORT'
            $plan.ReportText | Should -Match 'TEST \(read-only\)'
            $plan.Sources[1].Policies.MissingSource | Should -Be 'skip'
            [IO.Directory]::Exists($target) | Should -BeFalse
        }

        It '-WhatIf also scans sources without creating a backup target' {
            $plan = Backup-MyFiles -ConfigPath $configPath -WhatIf -WarningAction SilentlyContinue

            $plan.IsTest | Should -BeTrue
            $plan.FilesPlanned | Should -Be 2
            $plan.FilesCopied | Should -Be 0
            [IO.Directory]::Exists($target) | Should -BeFalse
        }

        It 'runs optional disk-space preflight without creating files during -Test' {
            [void][IO.Directory]::CreateDirectory($missing)
            Write-PsMyBackupTestConfig -Path $configPath -Source $src -Target $target -Missing $missing `
                -MissingPolicy fail -VerificationMode Sha256 `
                -Extra 'Preflight = @{ CheckDiskSpace = $true; MinimumFreeBytes = 0; CheckTargetWrite = $true }'

            $plan = Backup-MyFiles -ConfigPath $configPath -Test

            $plan.Status | Should -Be 'SUCCESS'
            $plan.FilesPlanned | Should -Be 2
            $plan.Verified | Should -Be 0
            $plan.Events -join "`n" | Should -Match 'Preflight disk space'
            [IO.Directory]::Exists($target) | Should -BeFalse
        }

        It 'does not execute write probes or hashing during a dry run' {
            Write-PsMyBackupTestConfig -Path $configPath -Source $src -Target $target -Missing $missing `
                -VerificationMode Sha256 -Extra 'Preflight = @{ CheckTargetWrite = $true }'

            $plan = Backup-MyFiles -ConfigPath $configPath -Test -WarningAction SilentlyContinue

            $plan.FilesPlanned | Should -Be 2
            $plan.Verified | Should -Be 0
            [IO.Directory]::Exists($target) | Should -BeFalse
        }
    }

    Context 'Optional Windows sleep prevention' {
        It 'does not request sleep prevention in a -Test dry run' {
            $plan = Backup-MyFiles -ConfigPath $configPath -Test -PreventSleep `
                -WarningAction SilentlyContinue

            $plan.IsTest | Should -BeTrue
            [IO.Directory]::Exists($target) | Should -BeFalse
        }

        It 'does not request sleep prevention in a -WhatIf dry run' {
            $plan = Backup-MyFiles -ConfigPath $configPath -WhatIf -PreventSleep `
                -WarningAction SilentlyContinue

            $plan.IsTest | Should -BeTrue
            [IO.Directory]::Exists($target) | Should -BeFalse
        }

        It 'restores an existing execution state if a real backup throws' {
            Mock -ModuleName PsMyBackup -CommandName Enter-BackupSleepPrevention -MockWith {
                return [uint32]2147483648
            }
            Mock -ModuleName PsMyBackup -CommandName Exit-BackupSleepPrevention -MockWith {}
            Mock -ModuleName PsMyBackup -CommandName Enter-BackupLock -MockWith {
                throw 'Simulated lock acquisition failure.'
            }

            { Backup-MyFiles -ConfigPath $configPath -PreventSleep -Confirm:$false } |
                Should -Throw '*Simulated lock acquisition failure*'

            Should -Invoke -CommandName Enter-BackupSleepPrevention -ModuleName PsMyBackup `
                -Exactly -Times 1
            Should -Invoke -CommandName Exit-BackupSleepPrevention -ModuleName PsMyBackup `
                -Exactly -Times 1 -ParameterFilter {
                    $PreviousState -eq [uint32]2147483648
                }
        }

        It 'completes a real backup with sleep prevention on Windows' -Skip:(-not $IsWindows) {
            [void][IO.Directory]::CreateDirectory($missing)
            $result = Backup-MyFiles -ConfigPath $configPath -PreventSleep

            $result.Status | Should -Be 'SUCCESS'
            $result.FilesCopied | Should -Be 2
            [IO.File]::Exists((Join-Path $result.SnapshotPath 'Sample/keep.txt')) |
                Should -BeTrue
        }

        It 'rejects -PreventSleep for real backups on Linux before creating the target' `
            -Skip:$IsWindows {
            [void][IO.Directory]::CreateDirectory($missing)

            { Backup-MyFiles -ConfigPath $configPath -PreventSleep -ErrorAction Stop } |
                Should -Throw '*only on Windows*'
            [IO.Directory]::Exists($target) | Should -BeFalse
        }
    }

    Context 'Source-root ignore behavior' {
        It 'excludes only root Adobe when configured with /Adobe/' {
            $rootAdobe = Join-Path $src 'Adobe'
            $nestedAdobe = Join-Path $nested 'Adobe'
            [void][IO.Directory]::CreateDirectory($rootAdobe)
            [void][IO.Directory]::CreateDirectory($nestedAdobe)
            [IO.File]::WriteAllText((Join-Path $rootAdobe 'excluded.txt'), 'excluded')
            [IO.File]::WriteAllText((Join-Path $nestedAdobe 'included.txt'), 'included')
            [void][IO.Directory]::CreateDirectory($missing)
            Write-PsMyBackupTestConfig -Path $configPath -Source $src -Target $target `
                -Missing $missing -MissingPolicy fail -SourceIgnore @('*.tmp', '/Adobe/')

            $result = Backup-MyFiles -ConfigPath $configPath

            $result.Status | Should -Be 'SUCCESS'
            $result.FilesCopied | Should -Be 3
            [IO.File]::Exists((Join-Path $result.SnapshotPath 'Sample/Adobe/excluded.txt')) |
                Should -BeFalse
            [IO.File]::Exists((Join-Path $result.SnapshotPath 'Sample/nested/Adobe/included.txt')) |
                Should -BeTrue
            [IO.File]::Exists((Join-Path $result.SnapshotPath 'Sample/ignore.tmp')) |
                Should -BeFalse
        }
    }

    Context 'Backup output and verification' {
        It 'copies included files and writes a partial status, report, and hashed manifest' {
            $result = Backup-MyFiles -ConfigPath $configPath -WarningAction SilentlyContinue

            $result.Status | Should -Be 'PARTIAL'
            $result.FilesCopied | Should -Be 2
            [IO.File]::Exists($result.ReportPath) | Should -BeTrue
            [IO.File]::Exists($result.StatusPath) | Should -BeTrue
            [IO.File]::Exists($result.ManifestPath) | Should -BeTrue
            $status = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($result.StatusPath)) -DateKind String
            $status.status | Should -Be 'Partial'
            $status.format | Should -Be 'PsMyBackup.Snapshot'
            $status.schemaVersion | Should -Be '1.0.0'
            $status.finishedAt | Should -Not -BeNullOrEmpty
            $status.startedAt | Should -BeOfType [string]
            $status.finishedAt | Should -BeOfType [string]
            $status.filesCopied | Should -Be 2
            $status.bytesCopied | Should -BeGreaterThan 0
            $status.filesPlanned | Should -Be 2
            $status.errors | Should -BeGreaterThan -1
            $status.fatalError | Should -BeNullOrEmpty
            $manifest = ConvertFrom-Json -InputObject (
                [IO.File]::ReadAllText($result.ManifestPath)
            ) -AsHashtable
            $manifest.format | Should -Be 'PsMyBackup.Manifest'
            $manifest.schemaVersion | Should -Be '1.0.0'
            $manifest.schemaVersion | Should -BeOfType [string]
            @($manifest.entries) | Should -HaveCount 2
            $manifest.entries[0].sha256 | Should -Match '^[0-9A-F]{64}$'

            [IO.File]::Exists((Join-Path $result.SnapshotPath 'Sample/nested/child.txt')) | Should -BeTrue
            [IO.File]::Exists((Join-Path $result.SnapshotPath 'Sample/ignore.tmp')) | Should -BeFalse
            (@(Get-ChildItem -LiteralPath $result.SnapshotPath -Recurse -File -Filter '*.partial')).Count | Should -Be 0
            $copiedStamp = [IO.File]::GetLastWriteTimeUtc((Join-Path $result.SnapshotPath 'Sample/keep.txt'))
            [Math]::Abs(($copiedStamp - $stamp).TotalSeconds) | Should -BeLessThan 2
            [IO.File]::Exists((Join-Path $target '.psmybackup.lock')) | Should -BeTrue
        }

        It 'validates real status and hashed manifest files against their JSON Schemas' {
            $result = Backup-MyFiles -ConfigPath $configPath -WarningAction SilentlyContinue
            $result.Status | Should -Be 'PARTIAL'

            $statusSchema = Join-Path $repositoryRoot 'schemas/backup-status/v1.0/schema.json'
            $manifestSchema = Join-Path $repositoryRoot 'schemas/backup-manifest/v1.0/schema.json'
            Test-Json -Json ([IO.File]::ReadAllText($result.StatusPath)) `
                -SchemaFile $statusSchema | Should -BeTrue
            Test-Json -Json ([IO.File]::ReadAllText($result.ManifestPath)) `
                -SchemaFile $manifestSchema | Should -BeTrue
        }

        It 'performs SHA-256 verification and the optional target write probe' {
            [void][IO.Directory]::CreateDirectory($missing)
            Write-PsMyBackupTestConfig -Path $configPath -Source $src -Target $target -Missing $missing `
                -MissingPolicy fail -VerificationMode Sha256 `
                -Extra 'Preflight = @{ CheckTargetWrite = $true }'

            $result = Backup-MyFiles -ConfigPath $configPath

            $result.Status | Should -Be 'SUCCESS'
            $result.Verified | Should -Be 2
            $result.FilesCopied | Should -Be 2
            $result.Errors | Should -Be 0
            [IO.File]::Exists($result.ManifestPath) | Should -BeTrue
            $status = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($result.StatusPath)) -DateKind String
            $status.status | Should -Be 'Completed'
            $status.format | Should -Be 'PsMyBackup.Snapshot'
            $status.schemaVersion | Should -Be '1.0.0'
            (@(Get-ChildItem -LiteralPath $target -File -Filter '.psmybackup-probe-*')).Count | Should -Be 0
        }
    }

    Context 'Snapshot restoration' {
        It 'restores a complete snapshot into an empty folder with matching contents' {
            # Include a binary file and an empty directory to test more than text copies.
            $binaryPath = Join-Path $nested 'binary.dat'
            [IO.File]::WriteAllBytes($binaryPath, [byte[]]@(0, 1, 127, 128, 255))
            [void][IO.Directory]::CreateDirectory((Join-Path $src 'empty'))
            [void][IO.Directory]::CreateDirectory($missing)
            Write-PsMyBackupTestConfig -Path $configPath -Source $src -Target $target `
                -Missing $missing -MissingPolicy fail -VerificationMode Sha256

            $result = Backup-MyFiles -ConfigPath $configPath
            $result.Status | Should -Be 'SUCCESS'
            $result.FilesCopied | Should -Be 3
            $result.Errors | Should -Be 0

            # Restore only the backed-up source folders, not the snapshot's metadata files.
            $restoreRoot = Join-Path $caseRoot 'restored'
            [void][IO.Directory]::CreateDirectory($restoreRoot)
            foreach ($sourceName in @('Sample', 'Optional')) {
                Copy-Item -LiteralPath (Join-Path $result.SnapshotPath $sourceName) `
                    -Destination $restoreRoot -Recurse -ErrorAction Stop
            }

            $restoredSample = Join-Path $restoreRoot 'Sample'
            [IO.Directory]::Exists((Join-Path $restoreRoot 'Optional')) | Should -BeTrue
            [IO.Directory]::Exists((Join-Path $restoredSample 'empty')) | Should -BeTrue
            [IO.File]::Exists((Join-Path $restoredSample 'ignore.tmp')) | Should -BeFalse

            # Verify that no files are missing or added, then compare every file by SHA-256.
            $expectedFiles = @(
                Get-ChildItem -LiteralPath $src -Recurse -File |
                    Where-Object Name -ne 'ignore.tmp' |
                    ForEach-Object { [IO.Path]::GetRelativePath($src, $_.FullName) } |
                    Sort-Object
            )
            $restoredFiles = @(
                Get-ChildItem -LiteralPath $restoredSample -Recurse -File |
                    ForEach-Object { [IO.Path]::GetRelativePath($restoredSample, $_.FullName) } |
                    Sort-Object
            )
            $expectedFiles | Should -HaveCount 3
            @(Compare-Object -ReferenceObject $expectedFiles -DifferenceObject $restoredFiles).Count |
                Should -Be 0

            foreach ($relativePath in $expectedFiles) {
                $originalFile = Join-Path $src $relativePath
                $restoredFile = Join-Path $restoredSample $relativePath
                (Get-FileHash -LiteralPath $restoredFile -Algorithm SHA256).Hash |
                    Should -BeExactly (Get-FileHash -LiteralPath $originalFile -Algorithm SHA256).Hash
            }
        }
    }

    Context 'Configuration validation' {
        It 'accepts only a string Version 1.0.0 in configuration files' {
            # The fixture uses the supported string version and can be parsed.
            $result = Backup-MyFiles -ConfigPath $configPath -Test -WarningAction SilentlyContinue
            $result.IsTest | Should -BeTrue
            [IO.Directory]::Exists($target) | Should -BeFalse

            # An unquoted integer, a different version, and a missing Version
            # are all unsupported. No implicit upgrade or fallback is allowed.
            $validConfig = [IO.File]::ReadAllText($configPath)
            foreach ($versionEntry in @('Version = 1', "Version = '1.0.1'", '')) {
                $invalidConfig = $validConfig.Replace("Version = '1.0.0'", $versionEntry)
                [IO.File]::WriteAllText($configPath, $invalidConfig)

                { Backup-MyFiles -ConfigPath $configPath -Test } |
                    Should -Throw -ExpectedMessage "*Configuration requires Version = '1.0.0'*"
                [IO.Directory]::Exists($target) | Should -BeFalse
            }
        }

        It 'rejects unknown configuration keys without creating a target folder' {
            Write-PsMyBackupTestConfig -Path $configPath -Source $src -Target $target -Missing $missing `
                -Extra "UnknownSetting = 'not-allowed'"

            { Backup-MyFiles -ConfigPath $configPath -Test } | Should -Throw
            [IO.Directory]::Exists($target) | Should -BeFalse
        }

        It 'rejects overlapping source and destination paths' {
            $overlappingTarget = Join-Path $src 'nested-backups'
            Write-PsMyBackupTestConfig -Path $configPath -Source $src -Target $overlappingTarget -Missing $missing

            { Backup-MyFiles -ConfigPath $configPath -Test } | Should -Throw
            [IO.Directory]::Exists($overlappingTarget) | Should -BeFalse
        }
    }

    Context 'Failure reporting' {
        It 'reports a FAILED result when a required source is missing' {
            Write-PsMyBackupTestConfig -Path $configPath -Source $src -Target $target -Missing $missing -MissingPolicy fail

            $result = Backup-MyFiles -ConfigPath $configPath -ErrorAction Continue 2>$null

            $result.Status | Should -Be 'FAILED'
            $result.FatalError | Should -Not -BeNullOrEmpty
            [IO.File]::Exists($result.ReportPath) | Should -BeTrue
            (ConvertFrom-Json ([IO.File]::ReadAllText($result.StatusPath))).status | Should -Be 'Failed'
        }

        It '-ErrorAction Stop makes a FAILED result a terminating error' {
            Write-PsMyBackupTestConfig -Path $configPath -Source $src -Target $target -Missing $missing -MissingPolicy fail

            { $null = Backup-MyFiles -ConfigPath $configPath -ErrorAction Stop } | Should -Throw -ExpectedMessage '*PsMyBackup FAILED*'
        }
    }

    Context 'Retention and deletion safety' {
        It 'removes eligible old snapshots but never unmarked directories' {
            [void][IO.Directory]::CreateDirectory($missing)
            Write-PsMyBackupTestConfig -Path $configPath -Source $src -Target $target -Missing $missing `
                -MissingPolicy fail -Extra 'Retention = @{ Enabled = $true; KeepLast = 1; MaxAgeDays = 0 }'

            $first = Backup-MyFiles -ConfigPath $configPath
            $first.Status | Should -Be 'SUCCESS'

            $sentinel = Join-Path $target '2026-01-01_00-00-00-000'
            [void][IO.Directory]::CreateDirectory($sentinel)
            [IO.File]::WriteAllText((Join-Path $sentinel 'do-not-delete.txt'), 'unmarked')

            $dry = Backup-MyFiles -ConfigPath $configPath -Test
            $dry.IsTest | Should -BeTrue
            [IO.Directory]::Exists($first.SnapshotPath) | Should -BeTrue

            $second = Backup-MyFiles -ConfigPath $configPath
            $second.Status | Should -Be 'SUCCESS'
            $second.RetentionDeleted | Should -BeGreaterThan 0
            [IO.Directory]::Exists($first.SnapshotPath) | Should -BeFalse
            [IO.Directory]::Exists($sentinel) | Should -BeTrue
            [IO.File]::Exists((Join-Path $sentinel 'do-not-delete.txt')) | Should -BeTrue
        }

        It 'does not recognize old integer-version status markers for retention' {
            [void][IO.Directory]::CreateDirectory($missing)
            Write-PsMyBackupTestConfig -Path $configPath -Source $src -Target $target -Missing $missing `
                -MissingPolicy fail -Extra 'Retention = @{ Enabled = $true; KeepLast = 0; MaxAgeDays = 0 }'

            $legacy = Join-Path $target '2001-01-01_00-00-00-000'
            [void][IO.Directory]::CreateDirectory($legacy)
            $oldMarker = @{
                Format = 'PsMyBackup.Snapshot'
                SchemaVersion = 1
                SnapshotId = [guid]::NewGuid().ToString('D')
                SnapshotPath = $legacy
                Status = 'Completed'
                StartedAt = '2001-01-01T00:00:00+00:00'
            } | ConvertTo-Json
            [IO.File]::WriteAllText((Join-Path $legacy 'backup-status.json'), $oldMarker)

            $result = Backup-MyFiles -ConfigPath $configPath

            $result.Status | Should -Be 'SUCCESS'
            [IO.Directory]::Exists($legacy) | Should -BeTrue
            $result.RetentionPlanned | Should -Not -Contain $legacy
        }

        It 'does not delete a malformed or incomplete marker during a successful backup' {
            [void][IO.Directory]::CreateDirectory($missing)
            Write-PsMyBackupTestConfig -Path $configPath -Source $src -Target $target `
                -Missing $missing -MissingPolicy fail `
                -Extra 'Retention = @{ Enabled = $true; KeepLast = 0; MaxAgeDays = 0 }'

            $corrupt = Join-Path $target '2001-01-01_00-00-00-000'
            $incomplete = Join-Path $target '2002-01-01_00-00-00-000'
            foreach ($dir in @($corrupt, $incomplete)) {
                [void][IO.Directory]::CreateDirectory($dir)
                [IO.File]::WriteAllText((Join-Path $dir 'preserve.txt'), 'do not delete')
            }
            [IO.File]::WriteAllText((Join-Path $corrupt 'backup-status.json'), '{"format":')
            $marker = [ordered]@{
                format = 'PsMyBackup.Snapshot'
                schemaVersion = '1.0.0'
                snapshotId = [guid]::NewGuid().ToString('D')
                snapshotPath = $incomplete
                status = 'Completed'
                startedAt = '2002-01-01T00:00:00Z'
                finishedAt = '2002-01-01T00:01:00Z'
                bytesCopied = 0
                filesPlanned = 0
                errors = 0
                fatalError = $null
            }
            [IO.File]::WriteAllText((Join-Path $incomplete 'backup-status.json'),
                ($marker | ConvertTo-Json -Depth 5))

            $result = Backup-MyFiles -ConfigPath $configPath

            $result.Status | Should -Be 'SUCCESS'
            $result.RetentionPlanned | Should -Not -Contain $corrupt
            $result.RetentionPlanned | Should -Not -Contain $incomplete
            foreach ($dir in @($corrupt, $incomplete)) {
                [IO.Directory]::Exists($dir) | Should -BeTrue
                [IO.File]::ReadAllText((Join-Path $dir 'preserve.txt')) |
                    Should -BeExactly 'do not delete'
            }
        }

        It 'removes old snapshots containing preserved read-only files' -Skip:(-not $IsWindows) {
            # Reproduces Windows Directory.Delete failures with read-only files.
            [void][IO.Directory]::CreateDirectory($missing)
            Write-PsMyBackupTestConfig -Path $configPath -Source $src -Target $target -Missing $missing `
                -MissingPolicy fail -PreserveAttributes $true `
                -Extra 'Retention = @{ Enabled = $true; KeepLast = 1; MaxAgeDays = 0 }'

            $readOnlySource = Join-Path $src 'read-only.txt'
            [IO.File]::WriteAllText($readOnlySource, 'preserve this file')
            [IO.File]::SetAttributes($readOnlySource, [IO.FileAttributes]::ReadOnly)

            # Keep references for cleanup even if a backup or assertion fails.
            $first = $null
            $second = $null
            try {
                $first = Backup-MyFiles -ConfigPath $configPath
                $first.Status | Should -Be 'SUCCESS'

                $stored = Join-Path $first.SnapshotPath 'Sample/read-only.txt'
                [IO.File]::Exists($stored) | Should -BeTrue
                (([IO.File]::GetAttributes($stored) -band [IO.FileAttributes]::ReadOnly) -ne 0) | Should -BeTrue

                $second = Backup-MyFiles -ConfigPath $configPath
                $second.Status | Should -Be 'SUCCESS'
                $second.RetentionDeleted | Should -BeGreaterThan 0
                [IO.Directory]::Exists($first.SnapshotPath) | Should -BeFalse
                (([IO.File]::GetAttributes($readOnlySource) -band [IO.FileAttributes]::ReadOnly) -ne 0) | Should -BeTrue

                # The newest snapshot must retain the source's ReadOnly attribute.
                $latestCopy = Join-Path $second.SnapshotPath 'Sample/read-only.txt'
                (([IO.File]::GetAttributes($latestCopy) -band [IO.FileAttributes]::ReadOnly) -ne 0) | Should -BeTrue
            }
            finally {
                # The test's AfterEach recursively deletes $caseRoot. On Windows,
                # Directory.Delete(path, $true) cannot remove ReadOnly files. Reset
                # attributes on our test-owned source and both possible backup copies
                # so fixture cleanup cannot hide the real retention test result.
                $cleanupPaths = @($readOnlySource)
                foreach ($snapshot in @($first, $second)) {
                    if ($null -ne $snapshot) {
                        $cleanupPaths += Join-Path $snapshot.SnapshotPath 'Sample/read-only.txt'
                    }
                }
                foreach ($path in $cleanupPaths) {
                    if ([IO.File]::Exists($path)) {
                        $attributes = [IO.File]::GetAttributes($path)
                        if (($attributes -band [IO.FileAttributes]::ReadOnly) -ne 0) {
                            [IO.File]::SetAttributes(
                                $path,
                                ($attributes -band (-bnot [IO.FileAttributes]::ReadOnly))
                            )
                        }
                    }
                }
            }
        }

        It 'refuses to delete a snapshot containing a linked child directory' {
            [void][IO.Directory]::CreateDirectory($missing)
            Write-PsMyBackupTestConfig -Path $configPath -Source $src -Target $target -Missing $missing `
                -MissingPolicy fail -Extra 'Retention = @{ Enabled = $true; KeepLast = 1; MaxAgeDays = 0 }'

            $first = Backup-MyFiles -ConfigPath $configPath
            $first.Status | Should -Be 'SUCCESS'

            $outside = Join-Path $caseRoot 'external-data'
            [void][IO.Directory]::CreateDirectory($outside)
            $sentinel = Join-Path $outside 'important.txt'
            [IO.File]::WriteAllText($sentinel, 'must survive retention')
            $linkedChild = Join-Path $first.SnapshotPath 'linked-child'
            Invoke-PsMyBackupTestLinkCreation -Link $linkedChild -Target $outside
            try {
                $second = Backup-MyFiles -ConfigPath $configPath
                $second.Status | Should -Be 'PARTIAL'
                $second.RetentionDeleted | Should -Be 0
                [IO.Directory]::Exists($first.SnapshotPath) | Should -BeTrue
                [IO.File]::ReadAllText($sentinel) | Should -Be 'must survive retention'
            }
            finally {
                [IO.Directory]::Delete($linkedChild, $false)
            }
        }
    }

    Context 'Linked path safety' {
        It 'rejects a source path with a junction or symlink in its parent path' {
            $alias = Join-Path $caseRoot 'source-alias'
            Invoke-PsMyBackupTestLinkCreation -Link $alias -Target $src
            try {
                $linkedSource = Join-Path $alias 'nested'
                Write-PsMyBackupTestConfig -Path $configPath -Source $linkedSource -Target $target -Missing $missing
                { Backup-MyFiles -ConfigPath $configPath -Test } |
                    Should -Throw -ExpectedMessage '*symbolic link or junction*'
                [IO.Directory]::Exists($target) | Should -BeFalse
            }
            finally {
                # Remove the link itself, never recurse into its target.
                [IO.Directory]::Delete($alias, $false)
            }
        }

        It 'rejects a target path redirected into a source through a junction or symlink' {
            $alias = Join-Path $caseRoot 'target-alias'
            Invoke-PsMyBackupTestLinkCreation -Link $alias -Target $src
            try {
                $linkedTarget = Join-Path $alias 'backups'
                Write-PsMyBackupTestConfig -Path $configPath -Source $src -Target $linkedTarget -Missing $missing
                { Backup-MyFiles -ConfigPath $configPath -Test } |
                    Should -Throw -ExpectedMessage '*symbolic link or junction*'
                [IO.Directory]::Exists($linkedTarget) | Should -BeFalse
            }
            finally {
                [IO.Directory]::Delete($alias, $false)
            }
        }
    }

    Context 'Concurrency and locking' {
        It 'prevents a real backup under an exclusive lock while allowing -Test' {
            [void][IO.Directory]::CreateDirectory($target)
            $lockFile = Join-Path $target '.psmybackup.lock'
            $held = [IO.File]::Open($lockFile, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
            try {
                { Backup-MyFiles -ConfigPath $configPath -ErrorAction Stop } | Should -Throw
                $dry = Backup-MyFiles -ConfigPath $configPath -Test -WarningAction SilentlyContinue
                $dry.IsTest | Should -BeTrue
            }
            finally {
                $held.Dispose()
            }
        }
    }
}

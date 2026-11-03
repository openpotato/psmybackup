# Copyright (c) STÜBER SYSTEMS GmbH. All rights reserved.
# Licensed under the MIT License.

#Requires -Version 7.5
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

# Run from the repository root: 
# Invoke-Pester -Path ./test/PsMyBackup.Unit.Tests.ps1 -Output Detailed
# Private helpers are called through InModuleScope. No backup files are created.
BeforeAll {
    # Resolve the module manifest relative to the repository, not the current directory.
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path -Path $repositoryRoot -ChildPath 'src' -AdditionalChildPath @('PsMyBackup', 'PsMyBackup.psd1')
    Import-Module -Name $modulePath -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name PsMyBackup -ErrorAction SilentlyContinue
}

Describe 'PsMyBackup unit behavior' -Tag 'Unit' {
    Context 'Public API and execution state' {
        It 'exports Backup-MyFiles as its only public command' {
            $exported = @(Get-Command -Module PsMyBackup)
            $exported | Should -HaveCount 1
            $exported[0].Name | Should -Be 'Backup-MyFiles'
            $exported[0].CommandType | Should -Be 'Function'
        }

        It 'exposes optional PreventSleep as a switch without exporting an additional command' {
            $command = Get-Command Backup-MyFiles -Module PsMyBackup
            $command.Parameters.ContainsKey('PreventSleep') | Should -BeTrue
            $command.Parameters['PreventSleep'].ParameterType | Should -Be ([switch])
        }

        It 'initializes execution counters and lists without filesystem access' {
            InModuleScope PsMyBackup {
                $state = Get-BackupExecutionState -SnapshotPath 'unused-snapshot' -IsTest $true
                $state.IsTest | Should -BeTrue
                $state.SnapshotPath | Should -Be 'unused-snapshot'
                $state.FilesCopied | Should -Be 0
                $state.BytesPlanned | Should -Be 0
                $state.Events.Count | Should -Be 0
                $state.Sources.Count | Should -Be 0
                $state.ManifestEntries.Count | Should -Be 0
                [guid]::Parse($state.SnapshotId) | Should -Not -Be ([guid]::Empty)
            }
        }

        It 'creates source statistics without touching the filesystem' {
            InModuleScope PsMyBackup {
                $source = [pscustomobject]@{
                    Name = 'Documents'
                    Path = 'not-a-real-directory'
                    Policies = [pscustomobject]@{ ItemError = 'skip' }
                    Verification = [pscustomobject]@{ Mode = 'Size' }
                    Metadata = [pscustomobject]@{ PreserveTimestamps = $true }
                }

                $stats = Get-BackupSourceStatistic -Source $source

                $stats.Name | Should -Be 'Documents'
                $stats.Policies.ItemError | Should -Be 'skip'
                $stats.Verification.Mode | Should -Be 'Size'
                $stats.FilesCopied | Should -Be 0
                $stats.BytesCopied | Should -Be 0
                $stats.DirectoriesPlanned | Should -Be 0
                $stats.Errors | Should -Be 0
            }
        }

        It 'uses fatal error precedence over non-fatal error counts' {
            InModuleScope PsMyBackup {
                $state = [pscustomobject]@{ Errors = 0 }
                Get-BackupExecutionStatus -State $state -FatalError $null | Should -Be 'SUCCESS'
                $state.Errors = 2
                Get-BackupExecutionStatus -State $state -FatalError $null | Should -Be 'PARTIAL'
                Get-BackupExecutionStatus -State $state -FatalError 'failed' | Should -Be 'FAILED'
            }
        }
    }

    Context 'Configuration, policies, and validation' {
        It 'resolves inherited metadata and policy overrides' {
            InModuleScope PsMyBackup {
                $global = Resolve-BackupPolicySet -Overrides @{ RetryCount = 2; ItemError = 'skip' } -Defaults $null -Scope 'Global'
                $source = Resolve-BackupPolicySet -Overrides @{ ItemError = 'fail' } -Defaults $global -Scope 'Source' -ForSource
                $source.RetryCount | Should -Be 2
                $source.ItemError | Should -Be 'fail'
                $source.ExistingFile | Should -Be 'fail'

                $metadata = Resolve-BackupMetadataSetting -Overrides @{ PreserveAttributes = $true } -Defaults $null -Scope 'Global'
                $metadata.PreserveAttributes | Should -BeTrue
                $metadata.PreserveTimestamps | Should -BeTrue
            }
        }

        It 'rejects invalid policy values and source-level snapshot overrides' {
            InModuleScope PsMyBackup {
                { Resolve-BackupPolicySet -Overrides @{ RetryCount = -1 } -Defaults $null -Scope 'Global' } | Should -Throw
                { Resolve-BackupPolicySet -Overrides @{ ExistingSnapshot = 'suffix' } -Defaults $null -Scope 'Source' -ForSource } | Should -Throw
            }
        }

        It 'resolves Int64 preflight reserve bounds and defaults' {
            InModuleScope PsMyBackup {
                $defaults = Resolve-BackupPreflight -Raw $null
                $defaults.MinimumFreeBytes | Should -Be ([long]0)
                $defaults.CheckDiskSpace | Should -BeFalse
                $defaults.CheckTargetWrite | Should -BeFalse

                $max = Resolve-BackupPreflight -Raw @{ MinimumFreeBytes = [long]::MaxValue }
                $max.MinimumFreeBytes | Should -Be ([long]::MaxValue)

                { Resolve-BackupPreflight -Raw @{ MinimumFreeBytes = -1 } } | Should -Throw
            }
        }

        It 'rejects unsafe source names and accepts normal names' {
            InModuleScope PsMyBackup {
                { Assert-BackupSourceName 'Documents' } | Should -Not -Throw
                { Assert-BackupSourceName '../outside' } | Should -Throw
                { Assert-BackupSourceName 'CON' } | Should -Throw
            }
        }
    }

    Context 'Ignore pattern matching' {
        It 'applies ordered ignore and negation patterns' {
            InModuleScope PsMyBackup {
                $patterns = @(ConvertTo-BackupIgnorePatternSet @('*.tmp', '*.bak', '!important.bak', '**/bin/'))
                Test-BackupIgnored 'notes.tmp' $false $patterns | Should -BeTrue
                Test-BackupIgnored 'docs/important.bak' $false $patterns | Should -BeFalse
                Test-BackupIgnored 'project/bin' $true $patterns | Should -BeTrue
                Test-BackupIgnored 'project/keep.txt' $false $patterns | Should -BeFalse
            }
        }
    }

    Context 'Root-anchored ignore patterns' {
        It 'limits /Adobe/ to source-root directories and distinguishes files' {
            InModuleScope PsMyBackup {
                $rootOnly = @(ConvertTo-BackupIgnorePatternSet @('/Adobe/'))
                Test-BackupIgnored 'Adobe' $true $rootOnly | Should -BeTrue
                Test-BackupIgnored 'Adobe' $false $rootOnly | Should -BeFalse
                Test-BackupIgnored 'Projects/Adobe' $true $rootOnly | Should -BeFalse
                Test-BackupIgnored 'Projects/Adobe/readme.txt' $false $rootOnly | Should -BeFalse
                Test-BackupIgnored 'Adobe/readme.txt' $false $rootOnly | Should -BeFalse

                # Unanchored patterns can match at multiple directory levels.
                $anyDepth = @(ConvertTo-BackupIgnorePatternSet @('Adobe/'))
                Test-BackupIgnored 'Adobe' $true $anyDepth | Should -BeTrue
                Test-BackupIgnored 'Projects/Adobe' $true $anyDepth | Should -BeTrue
                Test-BackupIgnored 'Projects/Adobe' $false $anyDepth | Should -BeFalse

                # The matcher also normalizes backslashes in the relative input path.
                $oneLevel = @(ConvertTo-BackupIgnorePatternSet @('/*/Adobe/'))
                Test-BackupIgnored 'Projects\Adobe' $true $oneLevel | Should -BeTrue
                Test-BackupIgnored 'Projects/Deep/Adobe' $true $oneLevel | Should -BeFalse
            }
        }
    }

    Context 'JSON schema compatibility and snapshot status' {
        It 'recognizes only string JSON schema versions compatible with 1.0.x' {
            InModuleScope PsMyBackup {
                foreach ($version in @('1.0.0', '1.0.1', '1.0.7', '1.0.12', '1.0.001')) {
                    Test-BackupJsonSchemaVersion -Version $version | Should -BeTrue
                }

                foreach ($version in @('1.1.0', '2.0.0', '1.0', '1.0.x', '1.0.0-beta', '1.0.0.1')) {
                    Test-BackupJsonSchemaVersion -Version $version | Should -BeFalse
                }

                foreach ($version in @(1, 0, $true, $null)) {
                    Test-BackupJsonSchemaVersion -Version $version | Should -BeFalse
                }
            }
        }

        It 'reads compatible 1.0.x status JSON for retention but ignores incompatible versions' {
            InModuleScope PsMyBackup -Parameters @{ TestDirectory = $TestDrive } {
                param($TestDirectory)

                $target = Join-Path $TestDirectory ('versions-' + [guid]::NewGuid().ToString('N'))
                $snapshot = Join-Path $target '2001-01-01_00-00-00-000'
                [void][IO.Directory]::CreateDirectory($snapshot)
                $statusPath = Join-Path $snapshot 'backup-status.json'
                $config = [pscustomobject]@{
                    TargetFolder = $target
                    Retention = [pscustomobject]@{
                        Enabled = $true
                        KeepLast = 0
                        MaxAgeDays = 0
                        IncludeNonSuccessful = $false
                    }
                }
                $status = [ordered]@{
                    format = 'PsMyBackup.Snapshot'
                    schemaVersion = '1.0.0'
                    snapshotId = [guid]::NewGuid().ToString('D')
                    snapshotPath = $snapshot
                    status = 'Completed'
                    startedAt = '2001-01-01T00:00:00Z'
                    finishedAt = '2001-01-01T00:01:00Z'
                    filesCopied = 0
                    bytesCopied = 0
                    filesPlanned = 0
                    errors = 0
                    fatalError = $null
                }

                foreach ($version in @('1.0.0', '1.0.1', '1.0.12')) {
                    $status.schemaVersion = $version
                    [IO.File]::WriteAllText($statusPath, ($status | ConvertTo-Json -Depth 3))
                    $plan = @(Get-BackupRetentionPlan -Config $config -CurrentSnapshot '' -IncludeCurrent $false)
                    $plan | Should -HaveCount 1
                    $plan[0] | Should -BeExactly $snapshot
                }

                foreach ($version in @('1.1.0', '2.0.0', '1.0.x', '1.0.0-beta', 1, $null)) {
                    $status.schemaVersion = $version
                    [IO.File]::WriteAllText($statusPath, ($status | ConvertTo-Json -Depth 3))
                    $plan = @(Get-BackupRetentionPlan -Config $config -CurrentSnapshot '' -IncludeCurrent $false)
                    $plan | Should -HaveCount 0
                }
            }
        }

        It 'preserves RFC 3339 offset strings for retention and rejects numeric dates' {
            InModuleScope PsMyBackup -Parameters @{ TestDirectory = $TestDrive } {
                param($TestDirectory)

                $target = Join-Path $TestDirectory ('offsets-' + [guid]::NewGuid().ToString('N'))
                $snapshot = Join-Path $target '2001-01-01_00-00-00-000'
                [void][IO.Directory]::CreateDirectory($snapshot)
                $statusPath = Join-Path $snapshot 'backup-status.json'
                $config = [pscustomobject]@{
                    TargetFolder = $target
                    Retention = [pscustomobject]@{
                        Enabled = $true
                        KeepLast = 0
                        MaxAgeDays = 0
                        IncludeNonSuccessful = $false
                    }
                }
                $valid = [ordered]@{
                    format = 'PsMyBackup.Snapshot'
                    schemaVersion = '1.0.1'
                    snapshotId = [guid]::NewGuid().ToString('D')
                    snapshotPath = $snapshot
                    status = 'Completed'
                    startedAt = '2001-01-01T01:00:00+01:00'
                    finishedAt = '2001-01-01T01:01:00+01:00'
                    filesCopied = 0
                    bytesCopied = 0
                    filesPlanned = 0
                    errors = 0
                    fatalError = $null
                }

                # Default ConvertFrom-Json transforms date strings into DateTime objects.
                # The retention parser must explicitly preserve the original JSON strings.
                [IO.File]::WriteAllText($statusPath, ($valid | ConvertTo-Json -Depth 5))
                @(Get-BackupRetentionPlan -Config $config -CurrentSnapshot '' -IncludeCurrent $false) |
                    Should -HaveCount 1

                foreach ($field in @('startedAt', 'finishedAt')) {
                    $invalid = [ordered]@{}
                    foreach ($key in $valid.Keys) {
                        $invalid[$key] = $valid[$key]
                    }
                    $invalid[$field] = 946684800
                    [IO.File]::WriteAllText($statusPath, ($invalid | ConvertTo-Json -Depth 5))
                    @(Get-BackupRetentionPlan -Config $config -CurrentSnapshot '' -IncludeCurrent $false) |
                        Should -HaveCount 0 -Because "'$field' must be a JSON date-time string"
                }
            }
        }

        It 'preserves malformed, incomplete, and invalid status documents during retention' {
            InModuleScope PsMyBackup -Parameters @{ TestDirectory = $TestDrive } {
                param($TestDirectory)

                $target = Join-Path $TestDirectory ('retention-' + [guid]::NewGuid().ToString('N'))
                $snapshot = Join-Path $target '2001-01-01_00-00-00-000'
                [void][IO.Directory]::CreateDirectory($snapshot)
                $statusPath = Join-Path $snapshot 'backup-status.json'
                $config = [pscustomobject]@{
                    TargetFolder = $target
                    Retention = [pscustomobject]@{
                        Enabled = $true
                        KeepLast = 0
                        MaxAgeDays = 0
                        IncludeNonSuccessful = $false
                    }
                }
                $valid = [ordered]@{
                    format = 'PsMyBackup.Snapshot'
                    schemaVersion = '1.0.1'
                    snapshotId = [guid]::NewGuid().ToString('D')
                    snapshotPath = $snapshot
                    status = 'Completed'
                    startedAt = '2001-01-01T00:00:00Z'
                    finishedAt = '2001-01-01T00:01:00Z'
                    filesCopied = 1
                    bytesCopied = 42
                    filesPlanned = 1
                    errors = 0
                    fatalError = $null
                }

                # Confirm the baseline is actually deletion-eligible.
                [IO.File]::WriteAllText($statusPath, ($valid | ConvertTo-Json -Depth 5))
                @(Get-BackupRetentionPlan -Config $config -CurrentSnapshot '' -IncludeCurrent $false) |
                    Should -HaveCount 1

                # Invalid JSON and missing documents must not be considered snapshots.
                [IO.File]::WriteAllText($statusPath, '{"format":')
                @(Get-BackupRetentionPlan -Config $config -CurrentSnapshot '' -IncludeCurrent $false) |
                    Should -HaveCount 0
                [IO.File]::Delete($statusPath)
                @(Get-BackupRetentionPlan -Config $config -CurrentSnapshot '' -IncludeCurrent $false) |
                    Should -HaveCount 0

                foreach ($requiredKey in @($valid.Keys)) {
                    $marker = $valid | ConvertTo-Json -Depth 5 | ConvertFrom-Json -AsHashtable
                    $marker.Remove($requiredKey)
                    [IO.File]::WriteAllText($statusPath, ($marker | ConvertTo-Json -Depth 5))
                    @(Get-BackupRetentionPlan -Config $config -CurrentSnapshot '' -IncludeCurrent $false) |
                        Should -HaveCount 0 -Because "'$requiredKey' is required"
                }

                # Reject non-schema values and unknown properties as well as missing fields.
                $invalidFields = @(
                    @{ Name = 'finishedAt'; Value = $null }
                    @{ Name = 'filesCopied'; Value = -1 }
                    @{ Name = 'bytesCopied'; Value = '42' }
                    @{ Name = 'filesPlanned'; Value = 0.5 }
                    @{ Name = 'errors'; Value = -2 }
                    @{ Name = 'startedAt'; Value = 'not a timestamp' }
                    @{ Name = 'snapshotId'; Value = 'not-a-uuid' }
                    @{ Name = 'status'; Value = 'Running' }
                    @{ Name = 'status'; Value = 'completed' }
                    @{ Name = 'snapshotPath'; Value = 'another-directory' }
                )
                foreach ($case in $invalidFields) {
                    $marker = $valid | ConvertTo-Json -Depth 5 | ConvertFrom-Json -AsHashtable
                    $marker[$case.Name] = $case.Value
                    [IO.File]::WriteAllText($statusPath, ($marker | ConvertTo-Json -Depth 5))
                    @(Get-BackupRetentionPlan -Config $config -CurrentSnapshot '' -IncludeCurrent $false) |
                        Should -HaveCount 0 -Because "'$($case.Name)' is invalid"
                }
                $marker = $valid | ConvertTo-Json -Depth 5 | ConvertFrom-Json -AsHashtable
                $marker.unexpected = $true
                [IO.File]::WriteAllText($statusPath, ($marker | ConvertTo-Json -Depth 5))
                @(Get-BackupRetentionPlan -Config $config -CurrentSnapshot '' -IncludeCurrent $false) |
                    Should -HaveCount 0
                [IO.Directory]::Exists($snapshot) | Should -BeTrue
            }
        }

        It 'writes schema 1.0.0 status documents in camelCase for running and completed backups' {
            # Pass TestDrive explicitly because this script executes inside the module scope.
            InModuleScope PsMyBackup -Parameters @{ TestDirectory = $TestDrive } {
                param($TestDirectory)
                $snapshot = Join-Path $TestDirectory ('status-' + [guid]::NewGuid().ToString('N'))
                [void][IO.Directory]::CreateDirectory($snapshot)
                $state = Get-BackupExecutionState -SnapshotPath $snapshot -IsTest $false
                $statusPath = Join-Path $snapshot 'backup-status.json'
                $finishedAt = [DateTimeOffset]::Now

                Write-BackupStatus -State $state -Status 'Running' -FatalError $null -FinishedAt $finishedAt
                $running = Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json -AsHashtable
                $running.format | Should -Be 'PsMyBackup.Snapshot'
                $running.schemaVersion | Should -Be '1.0.0'
                $running.status | Should -Be 'Running'
                $running.finishedAt | Should -BeNullOrEmpty
                $running.Keys -ccontains 'Format' | Should -BeFalse
                $running.Keys -ccontains 'SchemaVersion' | Should -BeFalse
                $running.Keys -ccontains 'backupStatus' | Should -BeFalse

                Write-BackupStatus -State $state -Status 'Completed' -FatalError $null -FinishedAt $finishedAt
                $completed = Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json -AsHashtable
                $completed.status | Should -Be 'Completed'
                $completed.finishedAt | Should -Not -BeNullOrEmpty
                $completed.filesCopied | Should -Be 0
                $completed.bytesCopied | Should -Be 0
                $completed.errors | Should -Be 0
                $completed.fatalError | Should -BeNullOrEmpty
            }
        }
    }

    Context 'Draft 2020-12 JSON Schema validation' {
        It 'validates generated Running and Completed statuses against the complete schema' {
            $schemaFile = Join-Path $repositoryRoot 'schemas/backup-status/v1.0/schema.json'
            InModuleScope PsMyBackup -Parameters @{
                TestDirectory = $TestDrive
                SchemaFile = $schemaFile
            } {
                param($TestDirectory, $SchemaFile)
                $snapshot = Join-Path $TestDirectory ('schema-status-' + [guid]::NewGuid().ToString('N'))
                [void][IO.Directory]::CreateDirectory($snapshot)
                $state = Get-BackupExecutionState -SnapshotPath $snapshot -IsTest $false
                $file = Join-Path $snapshot 'backup-status.json'

                Write-BackupStatus -State $state -Status 'Running' -FatalError $null `
                    -FinishedAt ([DateTimeOffset]::UtcNow)
                Test-Json -Json ([IO.File]::ReadAllText($file)) -SchemaFile $SchemaFile |
                    Should -BeTrue

                Write-BackupStatus -State $state -Status 'Completed' -FatalError $null `
                    -FinishedAt ([DateTimeOffset]::UtcNow)
                $json = [IO.File]::ReadAllText($file)
                Test-Json -Json $json -SchemaFile $SchemaFile | Should -BeTrue

                $invalid = $json | ConvertFrom-Json -AsHashtable
                $invalid.Remove('filesCopied')
                Test-Json -Json ($invalid | ConvertTo-Json -Depth 6) -SchemaFile $SchemaFile `
                    -ErrorAction SilentlyContinue | Should -BeFalse

                $invalid = $json | ConvertFrom-Json -AsHashtable
                $invalid.filesCopied = -1
                Test-Json -Json ($invalid | ConvertTo-Json -Depth 6) -SchemaFile $SchemaFile `
                    -ErrorAction SilentlyContinue | Should -BeFalse

                $invalid = $json | ConvertFrom-Json -AsHashtable
                $invalid.unknownField = $true
                Test-Json -Json ($invalid | ConvertTo-Json -Depth 6) -SchemaFile $SchemaFile `
                    -ErrorAction SilentlyContinue | Should -BeFalse
            }
        }

        It 'validates generated manifests and rejects invalid nested entries' {
            $schemaFile = Join-Path $repositoryRoot 'schemas/backup-manifest/v1.0/schema.json'
            InModuleScope PsMyBackup -Parameters @{
                TestDirectory = $TestDrive
                SchemaFile = $schemaFile
            } {
                param($TestDirectory, $SchemaFile)
                $snapshot = Join-Path $TestDirectory ('schema-manifest-' + [guid]::NewGuid().ToString('N'))
                [void][IO.Directory]::CreateDirectory($snapshot)
                $state = Get-BackupExecutionState -SnapshotPath $snapshot -IsTest $false
                $state.ManifestEntries.Add([pscustomobject]@{
                    path = 'Documents/report.txt'
                    size = 42
                    lastWriteTimeUtc = '2026-10-29T08:00:00Z'
                    sha256 = $null
                })
                Write-BackupManifest -State $state
                $json = [IO.File]::ReadAllText((Join-Path $snapshot 'backup-manifest.json'))
                Test-Json -Json $json -SchemaFile $SchemaFile | Should -BeTrue

                $invalid = $json | ConvertFrom-Json -AsHashtable
                $invalid.entries[0].Remove('lastWriteTimeUtc')
                Test-Json -Json ($invalid | ConvertTo-Json -Depth 6) -SchemaFile $SchemaFile `
                    -ErrorAction SilentlyContinue | Should -BeFalse

                $invalid = $json | ConvertFrom-Json -AsHashtable
                $invalid.entries[0].sha256 = 'not-a-sha256-hash'
                Test-Json -Json ($invalid | ConvertTo-Json -Depth 6) -SchemaFile $SchemaFile `
                    -ErrorAction SilentlyContinue | Should -BeFalse

                $invalid = $json | ConvertFrom-Json -AsHashtable
                $invalid.entries[0].extraProperty = 'disallowed'
                Test-Json -Json ($invalid | ConvertTo-Json -Depth 6) -SchemaFile $SchemaFile `
                    -ErrorAction SilentlyContinue | Should -BeFalse
            }
        }
    }

    Context 'Manifest output' {
        It 'writes a schema 1.0.0 manifest with camelCase entries and optional null hashes' {
            # The private writer operates on the snapshot folder passed through InModuleScope.
            InModuleScope PsMyBackup -Parameters @{ TestDirectory = $TestDrive } {
                param($TestDirectory)
                $snapshot = Join-Path $TestDirectory ('manifest-' + [guid]::NewGuid().ToString('N'))
                [void][IO.Directory]::CreateDirectory($snapshot)
                $state = Get-BackupExecutionState -SnapshotPath $snapshot -IsTest $false
                $state.ManifestEntries.Add([pscustomobject]@{
                    path = 'Documents/report.txt'
                    size = 42
                    lastWriteTimeUtc = '2026-10-29T08:00:00Z'
                    sha256 = $null
                })

                Write-BackupManifest -State $state
                $manifest = Get-Content -LiteralPath (Join-Path $snapshot 'backup-manifest.json') -Raw |
                    ConvertFrom-Json -AsHashtable

                $manifest.format | Should -Be 'PsMyBackup.Manifest'
                $manifest.schemaVersion | Should -Be '1.0.0'
                $manifest.schemaVersion | Should -BeOfType [string]
                $manifest.snapshotId | Should -Be $state.SnapshotId
                @($manifest.entries) | Should -HaveCount 1
                $manifest.entries[0].path | Should -Be 'Documents/report.txt'
                $manifest.entries[0].size | Should -Be 42
                $manifest.entries[0].sha256 | Should -BeNullOrEmpty

                $manifest.Keys -ccontains 'Format' | Should -BeFalse
                $manifest.Keys -ccontains 'SchemaVersion' | Should -BeFalse
                $manifest.entries[0].Keys -ccontains 'LastWriteTimeUtc' | Should -BeFalse
                $manifest.entries[0].Keys -ccontains 'Sha256' | Should -BeFalse
            }
        }
    }
}

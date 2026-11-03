# Copyright (c) STÜBER SYSTEMS GmbH. All rights reserved.
# Licensed under the MIT License.

@{
    RootModule         = 'PsMyBackup.psm1'
    ModuleVersion      = '0.1.0'
    GUID               = '9f4c8863-e57f-4f81-b290-2d1a970134d0'
    Author             = 'STÜBER SYSTEMS GmbH'
    CompanyName        = 'STÜBER SYSTEMS GmbH'
    Copyright          = '(c) 2026 STÜBER SYSTEMS GmbH. All rights reserved.'
    Description        = 'Configuration-driven timestamped folder backups with global policies, ignore patterns, reporting, integrity checks, retry, retention, and read-only dry runs.'
    PowerShellVersion  = '7.5'
    FunctionsToExport  = @('Backup-MyFiles')
    CmdletsToExport    = @()
    VariablesToExport  = @()
    AliasesToExport    = @()
    PrivateData        = @{
        PSData = @{ 
            Tags       = @('backup', 'filesystem', 'powershell') 
            LicenseUri = 'https://github.com/openpotato/psmybackup/blob/main/LICENSE'
            ProjectUri = 'https://github.com/openpotato/psmybackup'
        }
    }
}

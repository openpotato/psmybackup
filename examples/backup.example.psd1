@{
    Version = '1.0.0'

    # Relative paths resolve from this config file. %ENVIRONMENT% variables expand.
    TargetFolder = 'D:\Backups'
    LogCopiedFiles = $false

    # Inherited by each source unless explicitly overridden.
    Policies = @{
        MissingSource = 'fail'         # fail | skip
        ItemError = 'skip'             # fail | skip
        ExistingSnapshot = 'suffix'    # fail | suffix (global only)
        ExistingFile = 'fail'          # fail | skip | overwrite
        RetryCount = 0                 # extra attempts; 0 = no retry
        RetryDelayMilliseconds = 250   # used only when RetryCount > 0
    }

    # Size uses file metadata, not full-file hashing. SHA-256 is opt-in.
    Verification = @{ Mode = 'Size' }  # None | Size | Sha256

    # Both expensive checks are OFF by default.
    Preflight = @{
        CheckDiskSpace = $false        # full additional source scan if enabled
        MinimumFreeBytes = 0           # reserve on target volume
        CheckTargetWrite = $false      # temporary write probe (never in -Test)
    }

    # Deletion is OFF by default. Only PsMyBackup-marked snapshots are eligible.
    Retention = @{
        Enabled = $false
        KeepLast = 10                  # keep at least this many
        MaxAgeDays = 30                # remove older than this AND beyond KeepLast
        IncludeNonSuccessful = $false  # completed backups only by default
    }

    # Optional machine-readable listing; hashes may trigger full file reads.
    Manifest = @{
        Enabled = $false
        IncludeHashes = $false
    }

    Metadata = @{
        PreserveTimestamps = $true
        PreserveAttributes = $false    # not ACLs/owner
    }

    Sources = @(
        @{
            Name = 'Documents'
            Path = 'C:\Users\%USERNAME%\Documents'
            Ignore = @(
                '*.tmp'
                '*.bak'
                '~$*'
                '**/.git/'
                '**/node_modules/'
                '!important.bak'
            )
        }
        @{
            Name = 'Projects'
            Path = 'C:\Work\Projects'
            Ignore = @('**/.git/', '**/bin/', '**/obj/', '**/*.log')

            # Only specified values override the global defaults.
            Policies = @{ ItemError = 'fail'; RetryCount = 2 }
            Verification = @{ Mode = 'Sha256' }
        }
    )
}

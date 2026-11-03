<div align="center">
  
# PsMyBackup

[![PowerShell](https://img.shields.io/badge/PowerShell-5C2D91?style=for-the-badge)](https://www.powershellgallery.com/packages/PsMyBackup)
[![GitHub License](https://img.shields.io/github/license/openpotato/psmybackup?style=for-the-badge)](./LICENSE)
[![Documentation](https://img.shields.io/badge/docs-available-brightgreen?style=for-the-badge)](https://github.com/openpotato/psmybackup/wiki)

</div>

A lightweight [PowerShell](https://learn.microsoft.com/powershell/) module for creating timestamped backups of local folders, with configurable file selection, integrity verification, reporting, and retention. Backup files remain directly accessible in their original formats.

+ Supports **PowerShell 7.5** and later on Windows and Linux.
+ Back up multiple source directories into timestamped snapshot folders.
+ Configure backups using PowerShell data files (`.psd1`), including per-source settings.
+ Exclude files and directories using glob-style ignore patterns.
+ Control missing sources, file conflicts, individual errors, and copy retries through configurable policies.
+ Verify copied files by size or SHA-256 checksum.
+ Optionally preserve file timestamps and supported filesystem attributes.
+ Generate backup status files, human-readable reports, and optional manifests with SHA-256 hashes.
+ Automatically remove eligible old snapshots using count- and age-based retention rules.
+ Preview planned operations without writing files using `-Test` or `-WhatIf`.
+ Optionally prevent automatic Windows sleep during a real backup with `-PreventSleep`.
+ Optional disk-space and target-write preflight checks, along with exclusive destination locking.
+ Zero additional runtime dependencies.

## Installation

``` powershell
Install-Module -Name PsMyBackup -Scope CurrentUser
```

## Getting started

Documentation is available in the [GitHub wiki](https://github.com/openpotato/psmybackup/wiki).

## Can I help?

Yes, that would be much appreciated. The best way to help is to post a response via the [Issue Tracker](https://github.com/openpotato/psmybackup/issues) and/or submit a [Pull Request](https://github.com/openpotato/psmybackup/pulls).

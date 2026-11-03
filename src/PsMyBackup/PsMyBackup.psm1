# Copyright (c) STÜBER SYSTEMS GmbH. All rights reserved.
# Licensed under the MIT License.

#Requires -Version 7.5
Set-StrictMode -Version Latest

#region Configuration value validation

<#
.SYNOPSIS
    Validates that a configuration value is a Boolean.

.DESCRIPTION
    Ensures that the supplied value is a Boolean ($true or $false).

    The function performs strict type validation and does not accept strings, numbers, or other
    values that could otherwise be implicitly converted to a Boolean.

    Throws an exception if the value is not a Boolean.

.PARAMETER Value
    The configuration value to validate.

.PARAMETER Name
    The name of the configuration setting. Used to produce a meaningful validation error message.

.OUTPUTS
    System.Boolean
    Returns the validated Boolean value.

.EXAMPLE
    Assert-BackupBoolean -Value $true -Name 'Retention.Enabled'

    Returns $true.

.EXAMPLE
    Assert-BackupBoolean -Value 'true' -Name 'Retention.Enabled'

    Throws an exception because the value is a string, not a Boolean.
#>
function Assert-BackupBoolean {
    param(
        [object] $Value,
        [string] $Name
    )

    # Require an actual Boolean value without implicit conversions.
    if ($Value -isnot [bool]) {
        throw "$Name must be `$true or `$false."
    }

    return [bool]$Value
}

<#
.SYNOPSIS
    Validates an integer configuration value against an allowed range.

.DESCRIPTION
    Ensures that the supplied configuration value is an integer of type System.Int32 or
    System.Int64 and falls within the specified inclusive minimum and maximum boundaries.

    The function performs strict type validation and does not implicitly convert strings,
    floating-point numbers, or other numeric types into integers.

    Throws an exception if the value is not a supported integer type or lies outside the permitted
    range.

.PARAMETER Value
    The configuration value to validate.

.PARAMETER Name
    The name of the configuration setting. Used to produce a meaningful validation error message.

.PARAMETER Min
    The minimum permitted value, inclusive.

.PARAMETER Max
    The maximum permitted value, inclusive.

.OUTPUTS
    System.Int64
    Returns the validated integer as a 64-bit signed integer.

.EXAMPLE
    Assert-BackupInteger -Value 5 -Name 'Policies.RetryCount' -Min 0 -Max 20

    Returns 5.

.EXAMPLE
    Assert-BackupInteger -Value -1 -Name 'Policies.RetryCount' -Min 0 -Max 20

    Throws an exception because the value is below the permitted minimum.

.EXAMPLE
    Assert-BackupInteger -Value '10' -Name 'Retention.KeepLast' -Min 0 -Max 1000

    Throws an exception because the supplied value is a string rather than an integer.
#>
function Assert-BackupInteger {
    param(
        [object] $Value,
        [string] $Name,
        [long] $Min,
        [long] $Max
    )

    # Accept only 32-bit or 64-bit signed integer values.
    if ($Value -isnot [int] -and $Value -isnot [long]) {
        throw "$Name must be an integer."
    }

    # Validate the inclusive minimum and maximum boundaries.
    if ($Value -lt $Min -or $Value -gt $Max) {
        throw "$Name must be between $Min and $Max."
    }

    # Normalize the result to a 64-bit integer.
    return [long]$Value
}

<#
.SYNOPSIS
    Validates the permitted keys of a configuration section.

.DESCRIPTION
    Ensures that a configuration section contains only recognized setting names.

    The configuration section must implement System.Collections.IDictionary, such as a PowerShell
    hashtable.

    Each key is checked against the supplied collection of allowed setting names.

    Throws an exception when:
    - The configuration section is not a dictionary.
    - A key is not a string.
    - A key is not included in the allowed names.

    A null configuration section is accepted and treated as an optional section that has not been
    specified.

    PowerShell's default string comparison is case-insensitive, so key validation is also
    case-insensitive.

.PARAMETER Map
    The configuration section to validate.

    Usually a hashtable imported from a PSD1 configuration file.

.PARAMETER Allowed
    The collection of permitted setting names.

.PARAMETER Scope
    The logical name of the configuration section. Included in validation error messages to
    identify the location of an invalid setting.

.OUTPUTS
    None.
    Throws an exception when validation fails.

.EXAMPLE
    $policies = @{
        MissingSource = 'fail'
        ItemError = 'skip'
    }

    Assert-BackupKeySet -Map $policies `
        -Allowed @('MissingSource', 'ItemError') `
        -Scope 'Policies'

    Successfully validates the configuration section.

.EXAMPLE
    $policies = @{
        UnknownPolicy = 'fail'
    }

    Assert-BackupKeySet -Map $policies `
        -Allowed @('MissingSource', 'ItemError') `
        -Scope 'Policies'

    Throws an exception identifying UnknownPolicy as an unrecognized setting.

.NOTES
    This function validates only the names of configuration settings, not their associated values.

    Value validation is performed separately by functions such as Assert-BackupBoolean,
    Assert-BackupInteger, and Resolve-BackupPolicySet.
#>
function Assert-BackupKeySet {
    param(
        [object] $Map,
        [string[]] $Allowed,
        [string] $Scope
    )

    # An omitted optional configuration section is valid.
    if ($null -eq $Map) {
        return
    }

    # Configuration sections must be dictionary-like objects.
    if ($Map -isnot [System.Collections.IDictionary]) {
        throw "$Scope must be a hashtable."
    }

    # Reject unknown or non-string configuration keys.
    foreach ($key in $Map.Keys) {
        if ($key -isnot [string] -or $key -notin $Allowed) {
            throw "Unknown setting '$key' in $Scope."
        }
    }
}

<#
.SYNOPSIS
    Validates a backup source name for use as a directory name.

.DESCRIPTION
    Ensures that the specified source name is a valid, safe, single directory name suitable for
    creating a folder within a backup snapshot.

    The validation rejects:
    - Null, empty, or whitespace-only names.
    - Current and parent directory references ('.' and '..').
    - Path separators and characters forbidden in Windows filenames.
    - Names ending with a period or space.
    - Characters considered invalid by the current operating system.
    - Reserved Windows device names such as CON, PRN, AUX, NUL, COM1-COM9, and LPT1-LPT9, 
      including names with extensions.

    Windows filename restrictions are enforced on all platforms to ensure consistent backup
    directory names across operating systems.

    Throws an exception if the name fails validation.

.PARAMETER Name
    The backup source name to validate.

    The name is used as the directory name under the timestamped backup snapshot.

.OUTPUTS
    None.
    Throws System.Management.Automation.RuntimeException if the supplied name is invalid.

.EXAMPLE
    Assert-BackupSourceName -Name 'Documents'

    Validates a normal source directory name.

.EXAMPLE
    Assert-BackupSourceName -Name 'CON'

    Throws an exception because CON is a reserved Windows device name.

.EXAMPLE
    Assert-BackupSourceName -Name 'My/Projects'

    Throws an exception because the name contains a directory separator.
#>
function Assert-BackupSourceName {
    param(
        [string] $Name
    )

    # Reject invalid directory names, including reserved Windows names.
    if (
        [string]::IsNullOrWhiteSpace($Name) -or
        $Name -in @('.', '..') -or
        $Name -match '[\\/:*?"<>|]' -or
        $Name -match '[\. ]$' -or
        $Name.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or
        $Name -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?$'
    ) {
        throw "Invalid source name '$Name'. Use a single safe folder name."
    }
}

#endregion

#region Configuration and filesystem path utilities

<#
.SYNOPSIS
    Retrieves a named configuration value from an object.

.DESCRIPTION
    Reads a configuration value from either a dictionary (such as a hashtable imported from a PSD1
    file) or a PowerShell object.

    Returns $null if the object is $null or the specified property or dictionary key does not
    exist.

.PARAMETER Object
    The configuration object containing the value.

.PARAMETER Name
    The name of the property or dictionary key to retrieve.

.OUTPUTS
    System.Object
    The configuration value, or $null if it cannot be found.
#>
function Get-BackupConfigValue {
    param(
        [object] $Object,
        [string] $Name
    )

    if ($null -eq $Object) { return $null }

    # Retrieve the value directly when the object is a dictionary.
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $null
    }

    # Otherwise, resolve the value through PowerShell object properties.
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }

    return $property.Value
}

<#
.SYNOPSIS
    Retrieves a configuration setting with a fallback default value.

.DESCRIPTION
    Looks up a named setting in a configuration dictionary and returns its value if the key
    exists.

    If the configuration dictionary is null or does not contain the specified key, the provided
    default value is returned instead.

    This function is primarily used to resolve optional settings from PsMyBackup PSD1
    configuration files.

    An explicitly configured null value is returned as null and does not trigger the fallback.

.PARAMETER Map
    The configuration dictionary containing the setting.

    Typically a hashtable imported from a PSD1 configuration file. May be null if the
    configuration section is optional.

.PARAMETER Key
    The name of the configuration setting to retrieve.

.PARAMETER Default
    The fallback value returned when the configuration dictionary is null or does not contain the
    specified key.

.OUTPUTS
    System.Object
    The configured value if the key exists; otherwise, the default value.

.EXAMPLE
    $policies = @{
        RetryCount = 3
    }

    Get-BackupSetting -Map $policies -Key 'RetryCount' -Default 0

    Returns 3 because RetryCount is explicitly configured.

.EXAMPLE
    $policies = @{}

    Get-BackupSetting -Map $policies -Key 'RetryCount' -Default 0

    Returns 0 because RetryCount is not configured.

.EXAMPLE
    Get-BackupSetting -Map $null -Key 'Enabled' -Default $false

    Returns $false because the configuration dictionary is null.

.NOTES
    The function distinguishes between missing settings and settings explicitly assigned a null
    value.

    It assumes that Map provides a Contains() method, such as System.Collections.IDictionary
    implementations.

    Configuration value types and allowed ranges must be validated separately using the
    appropriate Assert-Backup* functions.
#>
function Get-BackupSetting {
    param(
        [object] $Map,
        [string] $Key,
        [object] $Default
    )

    # Return the configured value when the dictionary contains the key.
    if ($null -ne $Map -and $Map.Contains($Key)) {
        return $Map[$Key]
    }

    # Use the fallback for missing keys or omitted configuration sections.
    return $Default
}

<#
.SYNOPSIS
    Resolves a source or target path to an absolute filesystem path.

.DESCRIPTION
    Expands environment variables in the specified path and converts relative paths into absolute
    paths using the provided base directory.

    The resulting path is normalized using .NET path handling.

    Throws an exception if the supplied path is null, empty, or contains only whitespace.

.PARAMETER Value
    The filesystem path to resolve. May contain environment variables and may be relative or
    absolute.

.PARAMETER BaseDirectory
    The base directory used to resolve relative paths. Should be an absolute filesystem path.

.OUTPUTS
    System.String
    The normalized, absolute filesystem path.

.EXAMPLE
    Resolve-BackupPath -Value '%USERPROFILE%\Documents' -BaseDirectory 'C:\Backup'

    Resolves the Documents directory of the current user.

.EXAMPLE
    Resolve-BackupPath -Value '.\Documents' -BaseDirectory 'C:\Data'

    Returns 'C:\Data\Documents'.
#>
function Resolve-BackupPath {
    param(
        [string] $Value,
        [string] $BaseDirectory
    )

    # Reject empty or whitespace-only paths.
    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw 'Source and target paths must not be empty.'
    }

    # Expand environment variables such as %USERPROFILE%.
    $expanded = [Environment]::ExpandEnvironmentVariables($Value)

    # Resolve relative paths against the specified base directory.
    if (-not [IO.Path]::IsPathFullyQualified($expanded)) {
        $expanded = [IO.Path]::Combine($BaseDirectory, $expanded)
    }

    # Normalize the path and return its absolute representation.
    return [IO.Path]::GetFullPath($expanded)
}

<#
.SYNOPSIS
    Rejects filesystem paths containing symbolic-link or junction ancestors.

.DESCRIPTION
    Inspects the supplied fully qualified path and each existing parent up to the volume root. A
    reparse point at any level is rejected. Nonexistent path components are permitted so that
    optional sources and not-yet-created backup destinations can be validated. Unexpected
    inspection errors fail closed rather than silently allowing potentially redirected paths.

    This check is performed during configuration validation and again before mutable operations
    where appropriate. It does not remove time-of-check / time-of-use races and is not a security
    boundary against a hostile local process that can replace path components during backup
    execution.

.PARAMETER Path
    Fully qualified source, destination, or snapshot path to inspect.

.OUTPUTS
    None. Throws if a link/junction or an unexpected filesystem error occurs.
#>
function Assert-BackupPathWithoutLink {
    param(
        [string] $Path
    )

    $current = [IO.Path]::GetFullPath($Path)

    while ($true) {
        try {
            $attributes = [IO.File]::GetAttributes($current)
            if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing path containing a symbolic link or junction: $current"
            }
        }
        catch [IO.FileNotFoundException] {
            # A source may be absent (MissingSource=skip), or a target uncreated.
            Write-Verbose "Skipping missing path component: $current"
        }
        catch [IO.DirectoryNotFoundException] {
            # Inspect higher ancestors even when this component does not exist.
            Write-Verbose "Skipping missing directory component: $current"
        }

        $parent = [IO.Directory]::GetParent($current)
        if ($null -eq $parent) {
            break
        }
        $current = $parent.FullName
    }
}

<#
.SYNOPSIS
    Determines whether two filesystem paths overlap.

.DESCRIPTION
    Checks whether two filesystem paths refer to the same directory or whether one path is located
    within the other.

    Path comparisons are case-insensitive on Windows and case-sensitive on other operating
    systems.

    Trailing directory separators are removed before comparison. Directory separators are
    considered when checking parent-child relationships to avoid false matches between similarly
    named directories.

    This function performs a lexical path comparison only. Linked paths are rejected separately by
    Assert-BackupPathWithoutLink during configuration validation; there is no guarantee against
    concurrent path replacement.

.PARAMETER Left
    The first filesystem path to compare.

.PARAMETER Right
    The second filesystem path to compare.

.OUTPUTS
    System.Boolean
    Returns $true if the paths are identical or one is a descendant of the other; otherwise,
    returns $false.

.EXAMPLE
    Test-BackupPathsOverlap -Left 'C:\Data' -Right 'C:\Data\Projects'

    Returns $true because the second path is within the first.

.EXAMPLE
    Test-BackupPathsOverlap -Left 'C:\Data' -Right 'C:\Database'

    Returns $false because the directories do not overlap.

.NOTES
    Both paths should already be absolute and normalized, for example using Resolve-BackupPath,
    before calling this function.
#>
function Test-BackupPathsOverlap {
    param(
        [string] $Left,
        [string] $Right
    )

    # Use the operating system's usual path comparison semantics.
    $comparison = if ($IsWindows) {
        [StringComparison]::OrdinalIgnoreCase
    } else {
        [StringComparison]::Ordinal
    }

    # Remove trailing directory separators while preserving root paths.
    $a = [IO.Path]::TrimEndingDirectorySeparator($Left)
    $b = [IO.Path]::TrimEndingDirectorySeparator($Right)

    # Determine the platform-specific directory separator.
    $separator = [string][IO.Path]::DirectorySeparatorChar

    # Ensure prefixes end with a separator to prevent partial directory-name matches (e.g. C:\Data
    # vs. C:\Database).
    $aPrefix = if ([IO.Path]::EndsInDirectorySeparator($a)) {
        $a
    } else {
        $a + $separator
    }

    $bPrefix = if ([IO.Path]::EndsInDirectorySeparator($b)) {
        $b
    } else {
        $b + $separator
    }

    # Paths overlap if they are identical or one is a descendant of the other.
    return (
        $a.Equals($b, $comparison) -or
        $a.StartsWith($bPrefix, $comparison) -or
        $b.StartsWith($aPrefix, $comparison)
    )
}

#endregion

#region Ignore pattern compilation and matching

<#
.SYNOPSIS
    Converts a glob pattern into a regular expression.

.DESCRIPTION
    Translates a simplified Git-style glob pattern into an equivalent regular expression for
    matching relative file and directory paths.

    The following wildcard expressions are supported:

    - *   Matches zero or more characters except path separators.
    - **  Matches zero or more characters, including path separators.
    - **/ Matches zero or more complete directory levels.
    - ?   Matches exactly one character except a path separator.

    All other characters are escaped using Regex.Escape() to prevent them from being interpreted
    as regular expression operators.

    The function expects forward slashes (/) as path separators, regardless of the operating
    system.

    The returned expression is not anchored with ^ or $. Anchoring and case sensitivity must be
    handled by the caller.

.PARAMETER Glob
    The glob pattern to convert into a regular expression.

.OUTPUTS
    System.String
    The regular expression corresponding to the supplied glob pattern.

.EXAMPLE
    Convert-BackupGlobToRegex -Glob '*.tmp'

    Returns '[^/]*\.tmp', matching filenames ending in .tmp.

.EXAMPLE
    Convert-BackupGlobToRegex -Glob '**/bin/'

    Returns '(?:.*/)?bin/', matching bin directories at any depth.

.EXAMPLE
    Convert-BackupGlobToRegex -Glob 'documents/?.txt'

    Returns 'documents/[^/]\.txt', matching single-character filenames such as documents/a.txt.

.NOTES
    This function implements a subset of Git-style glob syntax. It does not support character
    classes, brace expansion, or negation patterns.

    Negation patterns beginning with ! must be handled separately by the calling ignore-pattern
    implementation.
#>
function Convert-BackupGlobToRegex {
    param(
        [string] $Glob
    )

    # Build the regular expression incrementally.
    $result = [Text.StringBuilder]::new()

    # Process each character of the glob pattern.
    for ($i = 0; $i -lt $Glob.Length; $i++) {
        $ch = $Glob[$i]

        if ($ch -eq '*') {

            # Detect the double-star wildcard (**).
            if ($i + 1 -lt $Glob.Length -and $Glob[$i + 1] -eq '*') {

                # **/ matches zero or more directory levels.
                if ($i + 2 -lt $Glob.Length -and $Glob[$i + 2] -eq '/') {
                    [void] $result.Append('(?:.*/)?')
                    $i += 2
                }
                else {
                    # ** matches any characters, including separators.
                    [void] $result.Append('.*')
                    $i++
                }
            }
            else {
                # * matches any characters except a path separator.
                [void] $result.Append('[^/]*')
            }
        }
        elseif ($ch -eq '?') {

            # ? matches exactly one non-separator character.
            [void] $result.Append('[^/]')
        }
        else {

            # Escape literal characters to prevent regex interpretation.
            [void] $result.Append([regex]::Escape([string] $ch))
        }
    }

    # Return the generated regular expression without anchors.
    return $result.ToString()
}

<#
.SYNOPSIS
    Compiles backup ignore patterns into regular expressions.

.DESCRIPTION
    Converts a collection of Git-style ignore patterns into compiled regular expressions used to
    determine which files and directories should be excluded from a backup.

    Each pattern is processed according to the following rules:

    - Empty patterns and comment lines beginning with # are ignored.
    - Patterns beginning with ! negate a previous exclusion.
    - Patterns ending with / apply only to directories.
    - Patterns beginning with / are anchored to the source root.
    - Patterns without path separators can match at any directory level.
    - Patterns containing path separators are matched relative to
      the source root.

    Wildcard expressions are converted using Convert-BackupGlobToRegex.

    The resulting regular expressions use culture-invariant matching. Case-insensitive matching is
    enabled on Windows, while other operating systems use case-sensitive matching.

    The order of patterns is preserved because later matching patterns can override earlier ones.

    The function implements a simplified subset of .gitignore syntax, not the complete Git
    wildmatch specification.

.PARAMETER Patterns
    An array of ignore patterns defined in the backup configuration.

    Each element must be a string or null. Null elements, empty patterns, and comment lines are
    silently ignored.

.OUTPUTS
    System.Management.Automation.PSCustomObject[]
    A collection of compiled ignore-pattern objects.

    Each object contains the following properties:

    - Regex         The compiled System.Text.RegularExpressions.Regex.
    - Negated       Whether the pattern represents a negation rule.
    - DirectoryOnly Whether the pattern applies only to directories.

.EXAMPLE
    $patterns = ConvertTo-BackupIgnorePatternSet @(
        '*.tmp'
        '*.bak'
        '**/bin/'
        '**/obj/'
        '!important.bak'
    )

    Compiles common backup exclusions, including a negation rule that allows important.bak to
    override a matching *.bak exclusion.

.EXAMPLE
    $patterns = ConvertTo-BackupIgnorePatternSet @(
        '/temp/'
        '*.log'
    )

    Excludes the temp directory at the source root and matches log files at any directory level.

.NOTES
    This function only compiles ignore patterns. It does not evaluate filesystem paths or
    determine whether an entry should be excluded.

    Pattern evaluation is performed by Test-BackupIgnored.

    Directory traversal is handled separately by the backup engine. Once an excluded directory is
    skipped, its descendants cannot be re-included by a later negation rule unless traversal logic
    explicitly supports visiting excluded directories.
#>
function ConvertTo-BackupIgnorePatternSet {
    param(
        [object[]] $Patterns
    )

    # Create a collection for the compiled ignore patterns.
    $compiled = [Collections.Generic.List[object]]::new()

    # Use culture-invariant regular expression matching.
    $options = [Text.RegularExpressions.RegexOptions]::CultureInvariant

    # Windows filesystems generally use case-insensitive naming.
    if ($IsWindows) {
        $options = $options -bor [Text.RegularExpressions.RegexOptions]::IgnoreCase
    }

    # Process each ignore pattern in its original order.
    foreach ($raw in $Patterns) {

        # Ignore null entries.
        if ($null -eq $raw) {
            continue
        }

        # Only string patterns are supported.
        if ($raw -isnot [string]) {
            throw 'Ignore patterns must be strings.'
        }

        # Remove surrounding whitespace.
        $pattern = $raw.Trim()

        # Ignore empty patterns and comment lines.
        if ($pattern.Length -eq 0 -or $pattern.StartsWith('#')) {
            continue
        }

        # Detect negation rules beginning with '!'.
        $negated = $pattern.StartsWith('!')

        if ($negated) {
            $pattern = $pattern.Substring(1)
        }

        # Detect patterns that apply only to directories.
        $directoryOnly = $pattern.EndsWith('/')

        if ($directoryOnly) {
            $pattern = $pattern.TrimEnd('/')
        }

        # Detect patterns anchored to the source root.
        $anchored = $pattern.StartsWith('/')

        if ($anchored) {
            $pattern = $pattern.TrimStart('/')
        }

        # Reject patterns that become empty after removing modifiers.
        if ($pattern.Length -eq 0) {
            throw "Invalid ignore pattern '$raw'."
        }

        # Unanchored patterns without path separators may match at any directory level. Other
        # patterns begin at the source root.
        $prefix = if (-not $anchored -and -not $pattern.Contains('/')) {
            '(?:^|/)'
        }
        else {
            '^'
        }

        # Convert the glob expression and anchor it to the path end.
        $expression = $prefix + (Convert-BackupGlobToRegex $pattern) + '$'

        # Store the compiled regex together with its matching flags.
        $compiled.Add([pscustomobject]@{
            Regex         = [regex]::new($expression, $options)
            Negated       = $negated
            DirectoryOnly = $directoryOnly
        })
    }

    # Return the compiled patterns in their original order.
    return $compiled.ToArray()
}

<#
.SYNOPSIS
    Determines whether a backup file or directory should be ignored.

.DESCRIPTION
    Evaluates a relative filesystem path against a collection of previously compiled backup ignore
    patterns.

    The path is normalized to use forward slashes so that matching behaves consistently across
    operating systems.

    Patterns are evaluated sequentially in their original order.

    When a pattern matches:
    - A normal pattern marks the entry as ignored.
    - A negated pattern marks the entry as not ignored.

    Later matching patterns override earlier matching patterns.

    Patterns marked as DirectoryOnly are evaluated only when IsDirectory is true.

    If no pattern matches, the entry is not ignored.

    The function evaluates only the supplied entry. It does not inspect the filesystem or
    recursively evaluate descendants.

.PARAMETER RelativePath
    The path of the file or directory relative to the source root.

    Both Windows-style backslashes and forward slashes are accepted.

.PARAMETER IsDirectory
    Indicates whether the supplied path represents a directory.

    Directory-only ignore patterns are skipped when this value is false.

.PARAMETER Patterns
    The compiled ignore-pattern collection created by ConvertTo-BackupIgnorePatternSet.

.OUTPUTS
    System.Boolean
    Returns $true if the entry should be excluded from the backup.

    Returns $false if the entry should be included.

.EXAMPLE
    $patterns = ConvertTo-BackupIgnorePatternSet @(
        '*.tmp'
        '*.bak'
        '!important.bak'
    )

    Test-BackupIgnored -RelativePath 'docs/test.tmp' `
        -IsDirectory $false -Patterns $patterns

    Returns $true because the file matches *.tmp.

.EXAMPLE
    $patterns = ConvertTo-BackupIgnorePatternSet @(
        '*.bak'
        '!important.bak'
    )

    Test-BackupIgnored -RelativePath 'docs/important.bak' `
        -IsDirectory $false -Patterns $patterns

    Returns $false because the later negation rule overrides the earlier exclusion.

.EXAMPLE
    $patterns = ConvertTo-BackupIgnorePatternSet @(
        '**/bin/'
        '**/obj/'
    )

    Test-BackupIgnored -RelativePath 'Project/bin' `
        -IsDirectory $true -Patterns $patterns

    Returns $true because the path identifies a matching directory.

.NOTES
    The function implements last-matching-rule-wins behavior.

    It does not reproduce all .gitignore semantics. In particular, negation rules cannot
    automatically restore descendants of an excluded directory if the backup traversal has already
    skipped that directory.

    Regular expression matching options are defined when the patterns are compiled, not during
    their evaluation.
#>
function Test-BackupIgnored {
    param(
        [string] $RelativePath,
        [bool] $IsDirectory,
        [object[]] $Patterns
    )

    # Normalize path separators for cross-platform matching.
    $normalized = $RelativePath.Replace('\', '/')

    # Files and directories are included unless explicitly excluded.
    $ignored = $false

    # Evaluate patterns sequentially, preserving their precedence.
    foreach ($pattern in $Patterns) {

        # Directory-only rules cannot exclude individual files.
        if ($pattern.DirectoryOnly -and -not $IsDirectory) {
            continue
        }

        # Apply matching rules. Later rules override earlier ones.
        if ($pattern.Regex.IsMatch($normalized)) {

            # A normal rule excludes; a negated rule includes.
            $ignored = -not $pattern.Negated
        }
    }

    # Return the final exclusion decision.
    return $ignored
}

#endregion

#region Configuration resolution and loading

<#
.SYNOPSIS
    Resolves metadata preservation settings for a backup source.

.DESCRIPTION
    Combines built-in metadata preservation settings with optional global defaults and
    source-specific overrides.

    Configuration values are resolved in the following order:

    1. Built-in defaults.
    2. Global configuration defaults.
    3. Source-specific overrides.

    Later values take precedence over earlier ones.

    The following settings are supported:

    - PreserveTimestamps
      Preserves file and directory modification timestamps. Default: $true.

    - PreserveAttributes
      Preserves supported filesystem attributes. Default: $false.

    All explicitly configured values must be Boolean.

    Unknown configuration keys or invalid values cause an exception.

.PARAMETER Overrides
    Optional metadata settings that override the defaults.

    Typically represents the Metadata section of an individual backup source.

.PARAMETER Defaults
    Optional previously resolved metadata settings.

    Usually contains the global metadata configuration. May be null when resolving global
    settings.

.PARAMETER Scope
    Identifies the configuration scope, such as 'Global' or "Source 'Documents'".

    Used to generate meaningful validation error messages.

.OUTPUTS
    System.Management.Automation.PSCustomObject
    A resolved metadata configuration containing:

    - PreserveTimestamps
    - PreserveAttributes

.EXAMPLE
    $metadata = Resolve-BackupMetadataSetting `
        -Overrides $null `
        -Defaults $null `
        -Scope 'Global'

    Returns the built-in metadata defaults.

.EXAMPLE
    $global = Resolve-BackupMetadataSetting `
        -Overrides @{ PreserveAttributes = $true } `
        -Defaults $null `
        -Scope 'Global'

    $source = Resolve-BackupMetadataSetting `
        -Overrides @{ PreserveTimestamps = $false } `
        -Defaults $global `
        -Scope "Source 'Documents'"

    Returns metadata settings with timestamp preservation disabled and attribute preservation
    enabled.

.NOTES
    This function only resolves and validates configuration values.

    Actual metadata preservation is performed by the backup execution functions.
#>
function Resolve-BackupMetadataSetting {
    param(
        [object] $Overrides,
        [object] $Defaults,
        [string] $Scope
    )

    # Validate the names of explicitly configured metadata settings.
    Assert-BackupKeySet $Overrides @(
        'PreserveTimestamps',
        'PreserveAttributes'
    ) "$Scope.Metadata"

    # Initialize the built-in metadata defaults.
    $data = [ordered]@{
        PreserveTimestamps = $true
        PreserveAttributes = $false
    }

    # Apply inherited defaults, typically from the global configuration.
    if ($null -ne $Defaults) {
        foreach ($key in @($data.Keys)) {
            $data[$key] = $Defaults.$key
        }
    }

    # Apply explicitly configured overrides after validating their types.
    if ($null -ne $Overrides) {
        foreach ($key in $Overrides.Keys) {
            $data[$key] = Assert-BackupBoolean $Overrides[$key] "$Scope.Metadata.$key"
        }
    }

    # Return the fully resolved metadata configuration.
    return [pscustomobject]$data
}

<#
.SYNOPSIS
    Resolves backup error-handling and retry policies.

.DESCRIPTION
    Combines built-in policies, optional global defaults, and source-specific overrides into a
    single effective policy set.

    Policies are resolved in the following order:

    1. Built-in defaults.
    2. Global configuration defaults.
    3. Source-specific overrides.

    Later values take precedence over earlier values.

    Supported policies:

    MissingSource
        'fail' or 'skip'
        Determines how missing source directories are handled.
        Default: 'fail'.

    ItemError
        'fail' or 'skip'
        Determines how individual filesystem operation errors
        are handled.
        Default: 'skip'.

    ExistingSnapshot
        'fail' or 'suffix'
        Determines how timestamp collisions are handled.
        Default: 'suffix'.

        This policy is global and cannot be overridden per source.

    ExistingFile
        'fail', 'skip', or 'overwrite'
        Determines how existing destination files are handled.
        Default: 'fail'.

    RetryCount
        Number of additional attempts after a failed copy.
        Allowed range: 0 through 20.
        Default: 0.

    RetryDelayMilliseconds
        Delay between retry attempts.
        Allowed range: 0 through 60000.
        Default: 250.

    Unknown policies, invalid values, and disallowed source overrides cause an exception.

    String policy values are normalized to lowercase.

.PARAMETER Overrides
    Optional policy settings to apply over the defaults.

    Usually contains the Policies section of the global configuration or an individual source.

.PARAMETER Defaults
    Optional previously resolved policy configuration.

    Typically contains the global policies when resolving source-specific settings.

.PARAMETER Scope
    Identifies the configuration scope for validation errors.

    Examples include 'Global' and "Source 'Projects'".

.PARAMETER ForSource
    Indicates that source-specific policies are being resolved.

    When specified, ExistingSnapshot cannot be overridden because snapshot naming applies to the
    entire backup.

.OUTPUTS
    System.Management.Automation.PSCustomObject
    The effective policy configuration containing:

    - MissingSource
    - ItemError
    - ExistingSnapshot
    - ExistingFile
    - RetryCount
    - RetryDelayMilliseconds

.EXAMPLE
    $policies = Resolve-BackupPolicySet `
        -Overrides $null `
        -Defaults $null `
        -Scope 'Global'

    Returns the built-in backup policies.

.EXAMPLE
    $global = Resolve-BackupPolicySet `
        -Overrides @{
            ItemError = 'skip'
            RetryCount = 2
        } `
        -Defaults $null `
        -Scope 'Global'

    $source = Resolve-BackupPolicySet `
        -Overrides @{
            ItemError = 'fail'
        } `
        -Defaults $global `
        -Scope "Source 'Projects'" `
        -ForSource

    Returns source policies with ItemError set to 'fail'
    while inheriting RetryCount = 2.

.NOTES
    This function resolves configuration only.

    Actual retry behavior, error handling, and snapshot collision handling are implemented by the
    backup execution functions.

    ExistingSnapshot is inherited by sources but can only be configured globally.
#>
function Resolve-BackupPolicySet {
    param(
        [object] $Overrides,
        [object] $Defaults,
        [string] $Scope,
        [switch] $ForSource
    )

    # Initialize all policies with their built-in defaults.
    $values = [ordered]@{
        MissingSource         = 'fail'
        ItemError             = 'skip'
        ExistingSnapshot      = 'suffix'
        ExistingFile          = 'fail'
        RetryCount            = 0
        RetryDelayMilliseconds = 250
    }

    # Apply inherited policies, typically from the global configuration.
    if ($null -ne $Defaults) {
        foreach ($key in @($values.Keys)) {
            $values[$key] = $Defaults.$key
        }
    }

    # Reject unknown policy names before processing their values.
    Assert-BackupKeySet $Overrides @($values.Keys) "$Scope.Policies"

    # Process explicitly configured policy overrides.
    if ($null -ne $Overrides) {
        foreach ($key in $Overrides.Keys) {

            # Snapshot naming is controlled globally, not per source.
            if ($ForSource -and $key -eq 'ExistingSnapshot') {
                throw "$Scope.Policies.ExistingSnapshot is global only."
            }

            # Retrieve the configured policy value.
            $raw = $Overrides[$key]

            switch ($key) {

                # Validate the number of additional copy attempts.
                'RetryCount' {
                    $values[$key] = [int](Assert-BackupInteger $raw "$Scope.Policies.$key" 0 20)
                }

                # Validate the delay between retry attempts.
                'RetryDelayMilliseconds' {
                    $values[$key] = [int](Assert-BackupInteger $raw "$Scope.Policies.$key" 0 60000)
                }

                # Validate policies represented by predefined string values.
                default {

                    # Determine the permitted values for the current policy.
                    $allowed = switch ($key) {
                        'MissingSource' {
                            @('fail', 'skip')
                        }
                        'ItemError' {
                            @('fail', 'skip')
                        }
                        'ExistingSnapshot' {
                            @('fail', 'suffix')
                        }
                        'ExistingFile' {
                            @('fail', 'skip', 'overwrite')
                        }
                    }

                    # Require a supported string value.
                    if ($raw -isnot [string] -or $raw.ToLowerInvariant() -notin $allowed) {
                        throw "$Scope.Policies.$key must be one of: $($allowed -join ', ')."
                    }

                    # Normalize policy values to lowercase.
                    $values[$key] = $raw.ToLowerInvariant()
                }
            }
        }
    }

    # Return the effective policy set.
    return [pscustomobject]$values
}

<#
.SYNOPSIS
    Resolves file verification settings for a backup source.

.DESCRIPTION
    Combines built-in verification settings with optional global defaults and source-specific
    overrides.

    Settings are resolved in the following order:

    1. Built-in defaults.
    2. Global configuration defaults.
    3. Source-specific overrides.

    The following verification modes are supported:

    None
        Performs no additional content verification after copying.

    Size
        Compares the copied file size with the source file size.
        This is the built-in default.

    Sha256
        Computes and compares SHA-256 hashes of the source
        and copied files.

    SHA-256 verification performs additional disk reads and is therefore more expensive than size
    verification.

    An exception is thrown if an unsupported verification mode or unknown configuration setting is
    encountered.

.PARAMETER Overrides
    Optional verification settings that override inherited defaults.

    May contain a Mode setting.

.PARAMETER Defaults
    Optional previously resolved verification settings.

    Typically contains the global verification configuration. May be null when resolving global
    settings.

.PARAMETER Scope
    Identifies the configuration scope for validation errors.

.OUTPUTS
    System.Management.Automation.PSCustomObject
    A resolved verification configuration containing:

    - Mode

.EXAMPLE
    $verification = Resolve-BackupVerification `
        -Overrides $null `
        -Defaults $null `
        -Scope 'Global'

    Returns Mode = 'Size'.

.EXAMPLE
    $global = Resolve-BackupVerification `
        -Overrides @{ Mode = 'Size' } `
        -Defaults $null `
        -Scope 'Global'

    $source = Resolve-BackupVerification `
        -Overrides @{ Mode = 'Sha256' } `
        -Defaults $global `
        -Scope "Source 'Documents'"

    Enables SHA-256 verification for the Documents source
    while retaining size verification as the global default.

.NOTES
    Verification is configured independently for each source.

    This function only resolves configuration values. Actual verification is performed during file
    copying.
#>
function Resolve-BackupVerification {
    param(
        [object] $Overrides,
        [object] $Defaults,
        [string] $Scope
    )

    # Accept only the supported verification configuration keys.
    Assert-BackupKeySet $Overrides @('Mode') "$Scope.Verification"

    # Use the inherited mode or the built-in Size default.
    $mode = if ($null -ne $Defaults) {
        $Defaults.Mode
    }
    else {
        'Size'
    }

    # Override the inherited mode when explicitly configured.
    if ($null -ne $Overrides -and $Overrides.Contains('Mode')) {

        # Reject unsupported or non-string verification modes.
        if ($Overrides['Mode'] -isnot [string] -or
            $Overrides['Mode'] -notin @('None', 'Size', 'Sha256')) {

            throw "$Scope.Verification.Mode must be None, Size, or Sha256."
        }

        $mode = $Overrides['Mode']
    }

    # Return the effective verification configuration.
    return [pscustomobject]@{
        Mode = $mode
    }
}

<#
.SYNOPSIS
    Resolves and validates optional backup preflight settings.

.DESCRIPTION
    Applies the built-in preflight defaults and validates the supported settings. Checks requiring
    extra filesystem operations remain disabled unless explicitly enabled in the PSD1
    configuration.

    CheckDiskSpace defaults to $false, MinimumFreeBytes to 0, and CheckTargetWrite to $false.

.PARAMETER Raw
    The optional Preflight hashtable from the PSD1 configuration.

.OUTPUTS
    System.Management.Automation.PSCustomObject
    The resolved CheckDiskSpace, MinimumFreeBytes, and CheckTargetWrite values.

.EXAMPLE
    Resolve-BackupPreflight -Raw @{ CheckDiskSpace = $true }

.NOTES
    This function only validates settings; it does not probe the filesystem.
#>
function Resolve-BackupPreflight {
    param(
        [object] $Raw
    )

    Assert-BackupKeySet $Raw @(
        'CheckDiskSpace',
        'MinimumFreeBytes',
        'CheckTargetWrite'
    ) 'Preflight'

    # Expensive preflight operations are disabled by default.
    return [pscustomobject]@{
        CheckDiskSpace = $(
            Assert-BackupBoolean (
                Get-BackupSetting $Raw 'CheckDiskSpace' $false
            ) 'Preflight.CheckDiskSpace'
        )

        MinimumFreeBytes = $(
            Assert-BackupInteger (
                Get-BackupSetting $Raw 'MinimumFreeBytes' ([long]0)
            ) 'Preflight.MinimumFreeBytes' 0 ([long]::MaxValue)
        )

        CheckTargetWrite = $(
            Assert-BackupBoolean (
                Get-BackupSetting $Raw 'CheckTargetWrite' $false
            ) 'Preflight.CheckTargetWrite'
        )
    }
}

<#
.SYNOPSIS
    Resolves and validates optional snapshot retention settings.

.DESCRIPTION
    Applies built-in defaults and validates retention settings. Retention is disabled by default.
    KeepLast defaults to 10 and MaxAgeDays to 30; either limit may explicitly be set to $null to
    disable it.

    When retention is enabled, at least one limit must be non-null. IncludeNonSuccessful defaults
    to $false.

.PARAMETER Raw
    The optional Retention hashtable from the PSD1 configuration.

.OUTPUTS
    System.Management.Automation.PSCustomObject
    The resolved Enabled, KeepLast, MaxAgeDays, and IncludeNonSuccessful values.

.EXAMPLE
    Resolve-BackupRetention -Raw @{ Enabled = $true; KeepLast = 10; MaxAgeDays = $null }

.NOTES
    The function validates configuration only and never deletes snapshots.
#>
function Resolve-BackupRetention {
    param(
        [object] $Raw
    )

    Assert-BackupKeySet $Raw @(
        'Enabled',
        'KeepLast',
        'MaxAgeDays',
        'IncludeNonSuccessful'
    ) 'Retention'

    $keepLast = Get-BackupSetting $Raw 'KeepLast' 10
    $maxAgeDays = Get-BackupSetting $Raw 'MaxAgeDays' 30

    $retention = [pscustomobject]@{
        Enabled = $(
            Assert-BackupBoolean (
                Get-BackupSetting $Raw 'Enabled' $false
            ) 'Retention.Enabled'
        )

        KeepLast = $(
            if ($null -eq $keepLast) {
                $null
            }
            else {
                [int](Assert-BackupInteger $keepLast 'Retention.KeepLast' 0 1000000)
            }
        )

        MaxAgeDays = $(
            if ($null -eq $maxAgeDays) {
                $null
            }
            else {
                [int](Assert-BackupInteger $maxAgeDays 'Retention.MaxAgeDays' 0 365000)
            }
        )

        IncludeNonSuccessful = $(
            Assert-BackupBoolean (
                Get-BackupSetting $Raw 'IncludeNonSuccessful' $false
            ) 'Retention.IncludeNonSuccessful'
        )
    }

    # Retention requires at least one enabled limit.
    if ($retention.Enabled -and
        $null -eq $retention.KeepLast -and
        $null -eq $retention.MaxAgeDays) {

        throw 'Enabled retention requires KeepLast and/or MaxAgeDays.'
    }

    return $retention
}

<#
.SYNOPSIS
    Resolves and validates optional backup manifest settings.

.DESCRIPTION
    Validates the manifest options and applies built-in defaults. Both Enabled and IncludeHashes
    default to $false. Hash generation requires manifest output to be enabled.

.PARAMETER Raw
    The optional Manifest hashtable from the PSD1 configuration.

.OUTPUTS
    System.Management.Automation.PSCustomObject
    The resolved Enabled and IncludeHashes values.

.EXAMPLE
    Resolve-BackupManifest -Raw @{ Enabled = $true; IncludeHashes = $false }

.NOTES
    This function does not create a manifest or calculate hashes.
#>
function Resolve-BackupManifest {
    param(
        [object] $Raw
    )

    Assert-BackupKeySet $Raw @(
        'Enabled',
        'IncludeHashes'
    ) 'Manifest'

    $manifest = [pscustomobject]@{
        Enabled = $(
            Assert-BackupBoolean (
                Get-BackupSetting $Raw 'Enabled' $false
            ) 'Manifest.Enabled'
        )

        IncludeHashes = $(
            Assert-BackupBoolean (
                Get-BackupSetting $Raw 'IncludeHashes' $false
            ) 'Manifest.IncludeHashes'
        )
    }

    if ($manifest.IncludeHashes -and -not $manifest.Enabled) {
        throw 'Manifest.IncludeHashes requires Manifest.Enabled.'
    }

    return $manifest
}

<#
.SYNOPSIS
    Resolves and validates one backup source definition.

.DESCRIPTION
    Validates a PSD1 source entry, resolves its filesystem path and name, rejects duplicate source
    names and source/target path overlap, compiles its ignore rules, and inherits global Policies,
    Verification, and Metadata settings while applying source-specific overrides.

.PARAMETER RawSource
    The source entry from the PSD1 Sources array.

.PARAMETER BaseDirectory
    Directory containing the configuration file, used for relative paths.

.PARAMETER TargetFolder
    The normalized backup destination path to check for overlap.

.PARAMETER Policies
    Resolved global backup policies.

.PARAMETER Verification
    Resolved global verification settings.

.PARAMETER Metadata
    Resolved global metadata preservation settings.

.PARAMETER Names
    Per-configuration set of source names already encountered. Uses platform-specific casing rules
    provided by Resolve-BackupSourceCollection.

.OUTPUTS
    System.Management.Automation.PSCustomObject
    A normalized source with Name, Path, Patterns, Policies, Verification, and Metadata
    properties.

.NOTES
    Name uniqueness is checked before path overlap and ignore compilation, matching the validation
    order of the original configuration reader.
#>
function Resolve-BackupSource {
    param(
        [object] $RawSource,
        [string] $BaseDirectory,
        [string] $TargetFolder,
        [object] $Policies,
        [object] $Verification,
        [object] $Metadata,
        [Collections.Generic.HashSet[string]] $Names
    )

    Assert-BackupKeySet $RawSource @(
        'Name',
        'Path',
        'Ignore',
        'Policies',
        'Verification',
        'Metadata'
    ) 'Sources[]'

    # Relative paths are interpreted from the PSD1 file's directory.
    $path = Resolve-BackupPath (
        [string](Get-BackupConfigValue $RawSource 'Path')
    ) $BaseDirectory

    # Use the last path component when the source name is omitted.
    $rawName = Get-BackupConfigValue $RawSource 'Name'
    $name = if ([string]::IsNullOrWhiteSpace([string]$rawName)) {
        [IO.Path]::GetFileName(
            [IO.Path]::TrimEndingDirectorySeparator($path)
        )
    }
    else {
        [string]$rawName
    }

    Assert-BackupSourceName $name

    if (-not $Names.Add($name)) {
        throw "Duplicate source name '$name'."
    }

    # Reject source links and redirected ancestor paths (including missing sources). This
    # complements, rather than replaces, the lexical overlap check.
    Assert-BackupPathWithoutLink $path

    # Avoid recursive copies when source and destination overlap.
    if (Test-BackupPathsOverlap $path $TargetFolder) {
        throw "Source '$path' overlaps target '$TargetFolder'."
    }

    $rawIgnore = Get-BackupConfigValue $RawSource 'Ignore'
    if ($null -ne $rawIgnore -and $rawIgnore -is [string]) {
        $rawIgnore = @($rawIgnore)
    }
    $patterns = @(ConvertTo-BackupIgnorePatternSet @($rawIgnore))

    # Apply per-source overrides to the fully resolved global settings.
    return [pscustomobject]@{
        Name = $name
        Path = $path
        Patterns = $patterns
        Policies = $(
            Resolve-BackupPolicySet `
                (Get-BackupConfigValue $RawSource 'Policies') `
                $Policies "Source '$name'" -ForSource
        )
        Verification = $(
            Resolve-BackupVerification `
                (Get-BackupConfigValue $RawSource 'Verification') `
                $Verification "Source '$name'"
        )
        Metadata = $(
            Resolve-BackupMetadataSetting `
                (Get-BackupConfigValue $RawSource 'Metadata') `
                $Metadata "Source '$name'"
        )
    }
}

<#
.SYNOPSIS
    Resolves all configured backup sources.

.DESCRIPTION
    Ensures that at least one source is defined, sets up platform-specific duplicate-name
    detection, and delegates each entry to Resolve-BackupSource. Returns a single array even when
    only one source is configured.

.PARAMETER RawSources
    The Sources entry from the PSD1 configuration.

.PARAMETER BaseDirectory
    Directory containing the configuration file.

.PARAMETER TargetFolder
    Normalized destination directory.

.PARAMETER Policies
    Resolved global policies.

.PARAMETER Verification
    Resolved global verification configuration.

.PARAMETER Metadata
    Resolved global metadata settings.

.OUTPUTS
    System.Object[]
    Normalized source entries, including effective per-source settings.
#>
function Resolve-BackupSourceCollection {
    param(
        [object] $RawSources,
        [string] $BaseDirectory,
        [string] $TargetFolder,
        [object] $Policies,
        [object] $Verification,
        [object] $Metadata
    )

    if ($null -eq $RawSources -or @($RawSources).Count -eq 0) {
        throw 'Sources must contain at least one source.'
    }

    $comparer = if ($IsWindows) {
        [StringComparer]::OrdinalIgnoreCase
    }
    else {
        [StringComparer]::Ordinal
    }

    $names = [Collections.Generic.HashSet[string]]::new($comparer)
    $sources = [Collections.Generic.List[object]]::new()

    foreach ($rawSource in $RawSources) {
        $source = Resolve-BackupSource `
            -RawSource $rawSource `
            -BaseDirectory $BaseDirectory `
            -TargetFolder $TargetFolder `
            -Policies $Policies `
            -Verification $Verification `
            -Metadata $Metadata `
            -Names $names

        $sources.Add($source)
    }

    # A unary comma avoids unrolling one-item arrays on the PowerShell pipeline.
    return ,$sources.ToArray()
}

<#
.SYNOPSIS
    Loads and validates a PsMyBackup PSD1 configuration file.

.DESCRIPTION
    Reads a PowerShell Data File (.psd1), validates its structure, resolves configuration defaults
    and source-specific overrides, and returns a normalized backup configuration object.

    The following top-level configuration sections are supported:

    - Version
    - TargetFolder
    - LogCopiedFiles
    - Policies
    - Sources
    - Verification
    - Preflight
    - Retention
    - Manifest
    - Metadata

    Processing consists of several stages:

    1. Resolve and load the PSD1 configuration file.
    2. Validate top-level configuration keys and format version.
    3. Resolve the target directory.
    4. Resolve global policies, verification, and metadata settings.
    5. Delegate preflight, retention, and manifest validation.
    6. Resolve sources with inherited defaults and per-source overrides.
    7. Return the fully resolved configuration.

    Relative source and target paths are resolved against the directory containing the
    configuration file.

    Environment variables in paths are expanded.

    Source definitions are validated to prevent duplicate names and lexical overlaps between
    source and target directories. Existing path ancestors are inspected for symbolic links and
    junctions, which are rejected in both sources and backup destinations.

    Ignore patterns are compiled into regular expressions.

    The function throws an exception for invalid configuration settings or unsupported values. The
    individual configuration sections are resolved by private Resolve-Backup* helper functions.

.PARAMETER ConfigPath
    Path to an existing PsMyBackup PSD1 configuration file.

    The path may contain environment variables.

.OUTPUTS
    System.Management.Automation.PSCustomObject
    The fully resolved backup configuration containing:

    - FilePath
    - TargetFolder
    - Policies
    - Verification
    - Metadata
    - Preflight
    - Retention
    - Manifest
    - Sources
    - LogCopiedFiles

    Each source contains its resolved path, name, compiled ignore patterns, effective policies,
    verification, and metadata settings.

.EXAMPLE
    $config = Read-BackupConfiguration -ConfigPath './backup.psd1'

    Loads and validates the configuration file.

.EXAMPLE
    $config = Read-BackupConfiguration -ConfigPath './backup.psd1'

    $config.TargetFolder
    $config.Policies.RetryCount
    $config.Sources[0].Verification.Mode

    Reads individual values from the resolved configuration.

.NOTES
    The function requires configuration Version = '1.0.0' (a string).

    Import-PowerShellDataFile is used instead of executing the configuration as an ordinary
    PowerShell script.

    This function validates configuration structure and path relationships but does not copy files
    or create backups.

    Only path-attribute safety checks occur during configuration loading; optional write and
    disk-space preflight checks and backup execution are performed separately. A concurrent
    filesystem mutation can still race with validation.
#>
function Read-BackupConfiguration {
    param(
        [string] $ConfigPath
    )

    # Resolve and load the PSD1 configuration without executing a script.
    $expanded = [Environment]::ExpandEnvironmentVariables($ConfigPath)
    $file = Get-Item -LiteralPath $expanded -ErrorAction Stop

    if ($file -isnot [IO.FileInfo] -or $file.Extension -ine '.psd1') {
        throw 'ConfigPath must identify an existing .psd1 file.'
    }

    $config = Import-PowerShellDataFile -LiteralPath $file.FullName -ErrorAction Stop

    # Validate the top-level schema and configuration format version.
    Assert-BackupKeySet $config @(
        'Version',
        'TargetFolder',
        'LogCopiedFiles',
        'Policies',
        'Sources',
        'Verification',
        'Preflight',
        'Retention',
        'Manifest',
        'Metadata'
    ) 'Configuration'

    # Require the exact string-valued PSD1 format version; future schema versions must not be
    # accepted implicitly.
    $configVersion = Get-BackupConfigValue $config 'Version'
    if ($configVersion -isnot [string] -or $configVersion -cne '1.0.0') {
        throw "Configuration requires Version = '1.0.0' (string)."
    }

    $target = Resolve-BackupPath (
        [string](Get-BackupConfigValue $config 'TargetFolder')
    ) $file.DirectoryName

    # Reject linked destination paths (including redirected parent directories).
    Assert-BackupPathWithoutLink $target

    # Resolve global defaults before resolving individual sources.
    $policies = Resolve-BackupPolicySet (Get-BackupConfigValue $config 'Policies') $null 'Global'

    $verification = Resolve-BackupVerification (Get-BackupConfigValue $config 'Verification') $null 'Global'

    $metadata = Resolve-BackupMetadataSetting (Get-BackupConfigValue $config 'Metadata') $null 'Global'

    # Delegate the optional configuration sections to their own validators.
    $preflight = Resolve-BackupPreflight (Get-BackupConfigValue $config 'Preflight')
    $retention = Resolve-BackupRetention (Get-BackupConfigValue $config 'Retention')
    $manifest = Resolve-BackupManifest (Get-BackupConfigValue $config 'Manifest')

    # LogCopiedFiles is a top-level optional Boolean, not a subsection.
    $rawLogging = Get-BackupConfigValue $config 'LogCopiedFiles'
    if ($null -ne $rawLogging) {
        [void](Assert-BackupBoolean $rawLogging 'LogCopiedFiles')
    }

    # Resolve sources using the global defaults and the PSD1 file directory.
    $sources = Resolve-BackupSourceCollection `
        -RawSources (Get-BackupConfigValue $config 'Sources') `
        -BaseDirectory $file.DirectoryName `
        -TargetFolder $target `
        -Policies $policies `
        -Verification $verification `
        -Metadata $metadata

    # Preserve the existing shape expected by all downstream commands.
    return [pscustomobject]@{
        FilePath       = $file.FullName
        TargetFolder   = $target
        Policies       = $policies
        Verification   = $verification
        Metadata       = $metadata
        Preflight      = $preflight
        Retention      = $retention
        Manifest       = $manifest
        Sources        = $sources
        LogCopiedFiles = ($rawLogging -eq $true)
    }
}

#endregion

#region Snapshot paths and preflight checks

<#
.SYNOPSIS
    Generates a unique timestamped directory path for a backup snapshot.

.DESCRIPTION
    Constructs a backup snapshot directory path beneath the specified target folder using the
    current local date and time.

    Snapshot directories use the following naming format:

        yyyy-MM-dd_HH-mm-ss-fff

    The timestamp includes milliseconds to reduce the likelihood of collisions between consecutive
    backup operations.

    If a file or directory with the generated name already exists, the ExistingSnapshot policy
    determines how the collision is handled:

    - fail
      Throws an exception if the snapshot path already exists.

    - suffix
      Appends a four-digit numeric suffix to generate a unique name. Suffixes range from _0001
      through _9999.

    The function also rejects a target folder path that already exists as a regular file.

    If no available snapshot name can be found, an exception is thrown.

    The function only determines the snapshot path. It does not create directories or modify the
    filesystem.

.PARAMETER TargetFolder
    The absolute path of the backup destination directory.

    The generated snapshot path will be located directly beneath this directory.

.PARAMETER Policies
    The resolved global backup policies.

    The following property is required:

    - ExistingSnapshot
      Determines how snapshot name collisions are handled. Supported values: 'fail' and 'suffix'.

.OUTPUTS
    System.String
    The absolute path of an available snapshot directory.

.EXAMPLE
    $path = Get-BackupSnapshotPath `
        -TargetFolder 'D:\Backups' `
        -Policies $policies

    Returns a timestamped path similar to:

        D:\Backups\2026-10-26_21-30-15-123

.EXAMPLE
    $policies = [pscustomobject]@{
        ExistingSnapshot = 'suffix'
    }

    Get-BackupSnapshotPath `
        -TargetFolder 'D:\Backups' `
        -Policies $policies

    If the timestamped directory already exists, returns a path with a numeric suffix, such as:

        D:\Backups\2026-10-26_21-30-15-123_0001

.NOTES
    The function uses the local system clock.

    Snapshot names are generated with millisecond precision. The configured collision policy
    provides additional protection against duplicate names.

    The function does not reserve the generated path. Another process could create it between
    validation and actual directory creation.

    PsMyBackup uses an exclusive destination lock to prevent concurrent backup operations using
    the same target folder.

    The function assumes that Policies.ExistingSnapshot has already been validated by
    Resolve-BackupPolicySet.
#>
function Get-BackupSnapshotPath {
    param(
        [string] $TargetFolder,
        [object] $Policies
    )

    # Reject a destination path that already exists as a regular file.
    if ([IO.File]::Exists($TargetFolder)) {
        throw "Target folder is a file: $TargetFolder"
    }

    # Generate a timestamp using the current local date and time.
    $timestamp = [DateTimeOffset]::Now.ToString('yyyy-MM-dd_HH-mm-ss-fff')

    # Construct the initial snapshot path.
    $path = [IO.Path]::Combine($TargetFolder, $timestamp)

    # Return the path immediately if neither a file nor a directory exists.
    if (-not [IO.Directory]::Exists($path) -and
        -not [IO.File]::Exists($path)) {

        return $path
    }

    # Abort when the configured policy does not allow name collisions.
    if ($Policies.ExistingSnapshot -eq 'fail') {
        throw "Snapshot already exists: $path"
    }

    # Try numeric suffixes from _0001 through _9999.
    for ($index = 1; $index -le 9999; $index++) {

        # Append a zero-padded numeric suffix to the timestamp.
        $candidate = [IO.Path]::Combine(
            $TargetFolder,
            ('{0}_{1:D4}' -f $timestamp, $index)
        )

        # Return the first candidate that does not already exist.
        if (-not [IO.Directory]::Exists($candidate) -and
            -not [IO.File]::Exists($candidate)) {

            return $candidate
        }
    }

    # All supported suffixes are already occupied.
    throw 'No free snapshot suffix is available.'
}

<#
.SYNOPSIS
    Calculates the estimated disk space required for a backup.

.DESCRIPTION
    Performs a complete preflight scan of all configured source directories and calculates the
    combined size of files that would be included in the backup.

    The function traverses each source directory recursively, applying the configured ignore
    patterns to files and directories.

    The following rules are applied:

    - Missing source directories are handled according to the
      source's MissingSource policy.
    - Files and directories matching ignore patterns are skipped.
    - Symbolic links, junctions, and other reparse points are skipped.
    - Directories are traversed recursively unless excluded.
    - File sizes are accumulated using 64-bit integers.

    Directory traversal is implemented iteratively using a stack to avoid recursive PowerShell
    function calls.

    The function reads filesystem metadata but does not open files for content inspection or
    hashing.

    If a required source is missing or the filesystem cannot be enumerated reliably, an exception
    is thrown.

    The resulting estimate is intended for use with Assert-BackupFreeSpace before starting a
    backup.

.PARAMETER Config
    The fully resolved backup configuration returned by Read-BackupConfiguration.

    The following properties are required:

    - Sources
      Collection of configured backup sources.

    Each source must contain:

    - Path
      Absolute path of the source directory.

    - Policies.MissingSource
      Determines whether a missing source causes an error or is skipped.

    - Patterns
      Compiled ignore patterns used to exclude files and directories from the size calculation.

.OUTPUTS
    System.Int64
    The estimated total number of bytes required to store all included source files.

.EXAMPLE
    $config = Read-BackupConfiguration -ConfigPath './backup.psd1'

    $requiredBytes = Get-BackupRequiredByteCount -Config $config

    Calculates the total size of all files that would be included in the backup.

.EXAMPLE
    $requiredBytes = Get-BackupRequiredByteCount -Config $config

    Assert-BackupFreeSpace `
        -Config $config `
        -RequiredBytes $requiredBytes `
        -State $state

    Calculates the required storage space and validates that sufficient disk space is available on
    the target volume.

.NOTES
    This function performs a complete scan of all configured source directories and may be
    expensive for large directory trees or network-based filesystems.

    In PsMyBackup, this prescan is optional and is controlled by:

        Preflight.CheckDiskSpace = $true

    The size calculation is an estimate, not an exact prediction of the final disk space consumed.

    It does not account for:
    - Filesystem metadata and directory storage overhead.
    - Files added, removed, or modified after the scan.
    - Filesystem allocation units or compression.
    - Temporary files created during copying.
    - Snapshot metadata, reports, and manifests.

    The function follows a fail-closed approach. Filesystem enumeration and metadata errors
    propagate to the caller rather than producing a potentially incomplete estimate.

    No filesystem modifications are performed.
#>
function Get-BackupRequiredByteCount {
    param(
        [object] $Config
    )

    # Accumulate the estimated total using a 64-bit integer.
    $total = [long]0

    # Process every configured backup source independently.
    foreach ($source in $Config.Sources) {

        # Apply the configured policy when a source directory is missing.
        if (-not [IO.Directory]::Exists($source.Path)) {

            if ($source.Policies.MissingSource -eq 'fail') {
                throw "Preflight: missing source '$($source.Path)'."
            }

            # Skip missing sources when permitted by the policy.
            continue
        }

        # Use an explicit stack for iterative directory traversal. Each entry contains the
        # physical path and its relative path.
        $stack = [Collections.Generic.Stack[object]]::new()

        # Start traversal at the source root.
        $stack.Push([pscustomobject]@{
            Path     = $source.Path
            Relative = ''
        })

        # Continue until all included directories have been processed.
        while ($stack.Count -gt 0) {

            # Retrieve the next directory to inspect.
            $node = $stack.Pop()

            # Enumerate immediate filesystem entries.
            foreach ($entry in [IO.Directory]::GetFileSystemEntries($node.Path)) {

                # Extract the name of the current file or directory.
                $name = [IO.Path]::GetFileName($entry)

                # Build a path relative to the source root. Forward slashes are used for
                # ignore-pattern matching.
                $relative = if ($node.Relative) {
                    "$($node.Relative)/$name"
                }
                else {
                    $name
                }

                # Retrieve filesystem attributes.
                $attrs = [IO.File]::GetAttributes($entry)

                # Do not follow symbolic links, junctions, or reparse points.
                if (($attrs -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                    continue
                }

                # Determine whether the current entry is a directory.
                $dir = ($attrs -band [IO.FileAttributes]::Directory) -ne 0

                # Apply the source-specific ignore patterns.
                if (Test-BackupIgnored $relative $dir $source.Patterns) {
                    continue
                }

                if ($dir) {

                    # Queue included directories for further traversal.
                    $stack.Push([pscustomobject]@{
                        Path     = $entry
                        Relative = $relative
                    })
                }
                else {

                    # Add the file size to the estimated backup size.
                    $total = [long](
                        $total + ([IO.FileInfo]::new($entry)).Length
                    )
                }
            }
        }
    }

    # Return the combined size of all included files in bytes.
    return $total
}

<#
.SYNOPSIS
    Verifies that the backup target directory is writable.

.DESCRIPTION
    Performs an optional preflight check to determine whether the current process can create and
    delete files in the specified backup target directory.

    The function creates a temporary probe file with a unique name using a GUID to avoid
    collisions with existing files.

    The probe file is opened with:

    - FileMode.CreateNew
      Ensures that an existing file is never overwritten.

    - FileAccess.Write
      Requests write access to the newly created file.

    - FileShare.None
      Prevents other processes from accessing the file while its handle remains open.

    After successful creation, the file handle is closed and the temporary file is deleted.

    Cleanup is performed in a finally block to ensure that the probe file is removed even when an
    exception occurs.

    The function throws an exception if the probe file cannot be created or deleted.

    This check modifies the filesystem temporarily and must never be executed during a dry run
    (-Test or -WhatIf).

.PARAMETER TargetFolder
    The absolute path of the backup destination directory.

    The directory must already exist.

    The function attempts to create and delete a temporary file directly within this directory.

.OUTPUTS
    None.
    Throws an exception if the write-permission check fails.

.EXAMPLE
    Test-BackupTargetWrite -TargetFolder 'D:\Backups'

    Verifies that the current process can create and delete files in the D:\Backups directory.

.EXAMPLE
    if ($config.Preflight.CheckTargetWrite -and -not $state.IsTest) {
        Test-BackupTargetWrite -TargetFolder $config.TargetFolder
    }

    Performs the optional write-permission check only during a real backup operation.

.NOTES
    This preflight check is controlled by the configuration setting:

        Preflight.CheckTargetWrite = $true

    It is disabled by default.

    The function verifies the ability to create and delete a regular file at the time of
    execution.

    It does not guarantee that:
    - Sufficient disk space is available.
    - Files can be created in newly created subdirectories.
    - Filesystem permissions will remain unchanged.
    - Large file-copy operations will succeed.
    - Existing files can be overwritten.

    The probe filename uses the prefix '.psmybackup-probe-' followed by a randomly generated GUID.

    If deletion fails, the function throws and the temporary probe file may remain in the target
    directory.
#>
function Test-BackupTargetWrite {
    param(
        [string] $TargetFolder
    )

    # Generate a unique temporary filename within the target directory.
    $path = [IO.Path]::Combine(
        $TargetFolder,
        ".psmybackup-probe-$([Guid]::NewGuid().ToString('N'))"
    )

    try {

        # Attempt to create a new file without overwriting existing files. Request exclusive write
        # access to the probe file.
        $stream = [IO.File]::Open(
            $path,
            [IO.FileMode]::CreateNew,
            [IO.FileAccess]::Write,
            [IO.FileShare]::None
        )

        # Release the file handle so the probe file can be deleted.
        $stream.Dispose()
    }
    finally {

        # Remove the temporary probe file if it was successfully created. Cleanup is attempted
        # even if the write operation fails.
        if ([IO.File]::Exists($path)) {
            [IO.File]::Delete($path)
        }
    }
}

<#
.SYNOPSIS
    Validates that sufficient disk space is available for a backup.

.DESCRIPTION
    Checks whether the destination volume has enough available disk space to store the estimated
    backup data while preserving the configured minimum free-space reserve.

    The check is performed only when the configuration setting Preflight.CheckDiskSpace is
    enabled.

    The required number of bytes is typically calculated by scanning the source directories before
    starting the backup.

    The function determines the destination volume using the root of the configured target folder
    and retrieves its available disk space through System.IO.DriveInfo.

    Throws an exception when:
    - The destination volume cannot be determined.
    - The destination volume is not ready.
    - Available disk space cannot be retrieved.
    - Available disk space is insufficient.

    On success, an informational event is added to the backup state.

    The check is an estimate and does not reserve disk space. Other processes may consume space
    after validation.

.PARAMETER Config
    The resolved backup configuration.

    The following properties are required:
    - TargetFolder
    - Preflight.CheckDiskSpace
    - Preflight.MinimumFreeBytes

.PARAMETER RequiredBytes
    The estimated number of bytes required for the backup.

.PARAMETER State
    The current backup execution state.

    Used to record the result of the disk-space validation through Add-BackupEvent.

.OUTPUTS
    None.
    Throws an exception when validation fails.

.EXAMPLE
    Assert-BackupFreeSpace -Config $config -RequiredBytes 1073741824 -State $state

    Checks whether the destination volume has sufficient disk space for approximately 1 GiB of
    backup data, including the configured minimum free-space reserve.

.NOTES
    This optional preflight check requires a scan of all source files to calculate the estimated
    backup size.

    It is therefore disabled by default to avoid unnecessary filesystem operations.

    The estimate does not include filesystem metadata overhead or account for concurrent changes
    to source files.
#>
function Assert-BackupFreeSpace {
    param(
        [object] $Config,
        [long] $RequiredBytes,
        [object] $State
    )

    # Skip validation when disk-space preflight is disabled.
    if (-not $Config.Preflight.CheckDiskSpace) {
        return
    }

    # Determine the root volume of the backup destination.
    $root = [IO.Path]::GetPathRoot($Config.TargetFolder)

    if ([string]::IsNullOrEmpty($root)) {
        throw 'Cannot identify destination volume for disk-space check.'
    }

    # Retrieve the available disk space on the destination volume.
    try {
        $drive = [IO.DriveInfo]::new($root)

        if (-not $drive.IsReady) {
            throw "Destination volume is not ready: $root"
        }

        $available = $drive.AvailableFreeSpace
    }
    catch {
        throw "Unable to check available space on '$root': $($_.Exception.Message)"
    }

    # Read the minimum free-space reserve from the configuration.
    $reserve = [long]$Config.Preflight.MinimumFreeBytes

    # Ensure that the backup fits without consuming the reserve.
    if ($RequiredBytes -gt ($available - $reserve)) {
        throw "Insufficient disk space: need $RequiredBytes bytes plus $reserve bytes reserve; $available bytes available on '$root'."
    }

    # Record the successful disk-space validation.
    Add-BackupEvent $State 'INFO' "Preflight disk space | required=$RequiredBytes available=$available reserve=$reserve"
}

#endregion

#region Backup locking

<#
.SYNOPSIS
    Acquires an exclusive lock for a backup destination.

.DESCRIPTION
    Opens or creates a persistent lock file in the specified backup target directory to prevent
    concurrent PsMyBackup operations from using the same destination.

    The lock file is named:

        .psmybackup.lock

    The function opens the lock file using:

    - FileMode.OpenOrCreate
      Opens the existing lock file or creates it if necessary.

    - FileAccess.ReadWrite
      Requests read and write access to the lock file.

    - FileShare.None
      Requests exclusive access, preventing other processes from opening the file while the handle
      remains active.

    The returned FileStream represents the acquired lock.

    The caller must keep the stream open for the entire backup operation and dispose of it when
    the operation finishes.

    If another process holds an incompatible lock or the file cannot be opened, an exception is
    thrown.

    The lock file is intentionally persistent and must not be deleted when the lock is released.

.PARAMETER TargetFolder
    The absolute path of the backup destination directory.

    The directory must already exist.

    The lock file is created or opened directly within this directory.

.OUTPUTS
    System.IO.FileStream
    An open file stream representing the exclusive backup lock.

    The caller is responsible for disposing of the stream to release the lock.

.EXAMPLE
    $lock = Enter-BackupLock -TargetFolder 'D:\Backups'

    try {
        # Perform the backup while holding the exclusive lock.
    }
    finally {
        $lock.Dispose()
    }

    Acquires an exclusive lock and releases it when the backup operation finishes.

.EXAMPLE
    $lock = $null

    try {
        $lock = Enter-BackupLock -TargetFolder $config.TargetFolder

        # Create the snapshot and perform backup operations.
    }
    finally {
        if ($null -ne $lock) {
            $lock.Dispose()
        }
    }

    Demonstrates safe lock management when the backup operation may fail.

.NOTES
    The lock is implemented using filesystem sharing semantics rather than a named mutex or
    operating-system-specific API.

    It is intended to coordinate PsMyBackup processes that use the same target directory and lock
    file.

    The lock file must remain in place after the stream is closed.

    On Unix-like systems, deleting an open lock file can allow another process to create and lock
    a different file with the same name, potentially bypassing the existing lock.

    For this reason, the lock file is never deleted automatically.

    The lock is released when the FileStream is disposed or when the operating system closes the
    process's file handles.

    The lock file uses a PsMyBackup-specific name.

    The function modifies the filesystem if the lock file does not already exist. It must
    therefore not be called during dry runs (-Test or -WhatIf).

    The function assumes that the target directory has already been created and is accessible to
    the current process.
#>
function Enter-BackupLock {
    param(
        [string] $TargetFolder
    )

    # Construct the path of the persistent lock file.
    $path = [IO.Path]::Combine(
        $TargetFolder,
        '.psmybackup.lock'
    )

    try {

        # Open or create the lock file with exclusive access.
        #
        # FileShare.None prevents another cooperating process from acquiring an incompatible
        # handle to the same file.
        #
        # The returned stream must remain open throughout the backup.
        return [IO.File]::Open(
            $path,
            [IO.FileMode]::OpenOrCreate,
            [IO.FileAccess]::ReadWrite,
            [IO.FileShare]::None
        )
    }
    catch {

        # Convert filesystem errors into a meaningful backup-specific exception while preserving
        # the underlying error message.
        throw "Cannot acquire exclusive PsMyBackup lock at '$path': $($_.Exception.Message)"
    }
}

#endregion

#region File hashing and atomic copying

<#
.SYNOPSIS
    Computes the SHA-256 hash of a file.

.DESCRIPTION
    Calculates the SHA-256 cryptographic hash of the contents of the specified file.

    The file is opened as a read-only stream and processed using
    System.Security.Cryptography.SHA256.

    The file is opened with the following options:

    - FileMode.Open
      Opens an existing file without creating or modifying it.

    - FileAccess.Read
      Requests read-only access to the file.

    - FileShare.Read
      Allows other processes to open the file for reading while the hash is being calculated.

    The SHA-256 algorithm processes the file incrementally through a stream, avoiding the need to
    load the entire file into memory.

    The resulting 256-bit hash is converted into an uppercase hexadecimal string without
    separators.

    Both the SHA-256 algorithm instance and the file stream are disposed of using finally blocks,
    ensuring that their resources are released even when an exception occurs.

    The function throws an exception if the file cannot be opened, read, or hashed.

.PARAMETER Path
    The path of the file whose SHA-256 hash should be calculated.

    The file must exist and be readable by the current process.

.OUTPUTS
    System.String
    The SHA-256 hash represented as a 64-character uppercase hexadecimal string without
    separators.

.EXAMPLE
    $hash = Get-BackupHash -Path 'C:\Documents\report.pdf'

    Calculates the SHA-256 hash of report.pdf.

.EXAMPLE
    $sourceHash = Get-BackupHash -Path 'C:\Documents\report.pdf'
    $backupHash = Get-BackupHash -Path 'D:\Backups\Documents\report.pdf'

    if ($sourceHash -cne $backupHash) {
        throw 'Backup integrity verification failed.'
    }

    Compares the hashes of the original and copied files to verify that their contents are
    identical.

.NOTES
    SHA-256 produces a 256-bit (32-byte) cryptographic digest.

    This function is used by PsMyBackup for optional file integrity verification and manifest hash
    generation.

    Hash calculation requires reading the complete file contents and can therefore be expensive
    for large files or files located on network storage.

    In PsMyBackup, SHA-256 verification is optional and can be enabled through:

        Verification = @{
            Mode = 'Sha256'
        }

    The function does not modify the source file.

    It does not guarantee that the file remains unchanged during or after hashing.
    Filesystem-level consistency must be handled separately.

    Hash comparison verifies content equality with extremely high confidence but does not
    authenticate the origin of a file unless the expected hash is independently trusted.
#>
function Get-BackupHash {
    param(
        [string] $Path
    )

    # Open the file for reading without modifying its contents. Other processes may open it for
    # reading simultaneously.
    $stream = [IO.File]::Open(
        $Path,
        [IO.FileMode]::Open,
        [IO.FileAccess]::Read,
        [IO.FileShare]::Read
    )

    try {

        # Create the SHA-256 cryptographic hash algorithm.
        $sha256 = [Security.Cryptography.SHA256]::Create()

        try {

            # Compute the hash by reading the file through the stream.
            $hash = $sha256.ComputeHash($stream)

            # Convert the binary hash into an uppercase hexadecimal string and remove the hyphen
            # separators.
            return [BitConverter]::ToString($hash).Replace('-', '')
        }
        finally {

            # Release the cryptographic algorithm resources.
            $sha256.Dispose()
        }
    }
    finally {

        # Always close the file stream, including when hashing fails.
        $stream.Dispose()
    }
}

<#
.SYNOPSIS
    Copies a single file into a backup snapshot with optional verification.

.DESCRIPTION
    Copies a source file to its destination using a temporary file to prevent incomplete copies
    from appearing under the final destination filename.

    The operation consists of the following steps:

    1. Read the source file's size and modification timestamp.
    2. Copy the source file into a uniquely named temporary file.
    3. Perform the configured integrity verification.
    4. Optionally preserve timestamps and filesystem attributes.
    5. Check whether the source file changed during the operation.
    6. Optionally calculate a SHA-256 hash for the backup manifest.
    7. Move the temporary file to its final destination.
    8. Remove any remaining temporary file.

    Temporary files are created in the destination directory using the following naming
    convention:

        .psmybackup-<GUID>.partial

    Creating the temporary file in the destination directory allows the final rename to occur
    within the same filesystem.

    The following verification modes are supported:

    - None
      Performs no explicit size or content verification. Source modification checks are also
      skipped.

    - Size
      Compares the copied file's size with the original source size and checks whether the source
      file's size or modification timestamp changed during copying.

    - Sha256
      Performs size verification and compares SHA-256 hashes of the source file and its temporary
      copy.

    When manifest hashing is enabled, a SHA-256 hash of the copied file is calculated even if the
    selected verification mode does not require hashing.

    The ExistingFile policy determines whether an existing destination file may be replaced.

    Any copying, verification, metadata, or rename error causes an exception. The caller is
    responsible for retrying the operation according to the configured retry policy.

.PARAMETER Source
    The absolute path of the source file to copy.

    The file must exist and be readable by the current process.

.PARAMETER Destination
    The absolute path of the destination file.

    The parent directory must already exist.

    The destination file is created only after the temporary copy has been completed and verified
    according to the configured verification mode.

.PARAMETER SourceConfig
    The resolved configuration of the current backup source.

    The following settings are used:

    - Verification.Mode
      Specifies None, Size, or Sha256 verification.

    - Metadata.PreserveTimestamps
      Determines whether the original modification timestamp is applied to the copied file.

    - Metadata.PreserveAttributes
      Determines whether supported filesystem attributes are preserved.

    - Policies.ExistingFile
      Determines whether an existing destination file may be overwritten.

.PARAMETER Config
    The fully resolved global backup configuration.

    The following properties are used:

    - Manifest.Enabled
      Determines whether manifest generation is enabled.

    - Manifest.IncludeHashes
      Determines whether copied files require SHA-256 hashes for inclusion in the manifest.

.OUTPUTS
    System.Management.Automation.PSCustomObject
    Returns an object containing:

    - Size
      The size of the destination file in bytes.

    - Hash
      The SHA-256 hash of the copied file as an uppercase hexadecimal string, or $null when no
      hash was calculated.

    - LastWriteTimeUtc
      The source file's original modification timestamp, represented as an ISO 8601 string.

.EXAMPLE
    $result = Invoke-BackupCopyOnce `
        -Source 'C:\Documents\report.pdf' `
        -Destination 'D:\Backups\Documents\report.pdf' `
        -SourceConfig $sourceConfig `
        -Config $config

    Copies report.pdf into the backup snapshot, applies the configured verification and metadata
    settings, and returns information about the copied file.

.EXAMPLE
    $result = Invoke-BackupCopyOnce `
        -Source $sourcePath `
        -Destination $destinationPath `
        -SourceConfig $source `
        -Config $config

    $result.Size
    $result.Hash
    $result.LastWriteTimeUtc

    Copies the file and retrieves its resulting metadata.

.NOTES
    The function performs exactly one copy attempt.

    Retry handling and retry delays are implemented by Invoke-BackupFileWithRetry.

    SHA-256 verification requires reading the complete source and destination contents and can be
    expensive for large files.

    Only file modification timestamps and optional supported filesystem attributes are preserved.
    Filesystem permissions, ACLs, ownership, and alternate data streams are not explicitly
    preserved by this function.

    The function does not use filesystem snapshots or volume shadow copies. Therefore, it cannot
    guarantee a consistent copy of a file modified concurrently by another process.

    Source modification detection compares file size and modification timestamp. Changes that
    preserve both values may remain undetected unless SHA-256 verification catches them.

    The final rename normally provides an atomic publication operation when supported by the
    destination filesystem.

    Temporary files are removed in a finally block. If cleanup fails, a warning is emitted and the
    temporary file may remain.

    The function must not be called during a dry run.
#>
function Invoke-BackupCopyOnce {
    param(
        [string] $Source,
        [string] $Destination,
        [object] $SourceConfig,
        [object] $Config
    )

    # Determine the destination directory.
    $folder = [IO.Path]::GetDirectoryName($Destination)

    # Generate a unique temporary filename in the destination directory. The temporary file will
    # be renamed only after successful copying.
    $temporary = [IO.Path]::Combine(
        $folder,
        ".psmybackup-$([Guid]::NewGuid().ToString('N')).partial"
    )

    try {

        # Capture the original source file metadata before copying.
        $before = [IO.FileInfo]::new($Source)

        $beforeSize = $before.Length
        $beforeModified = $before.LastWriteTimeUtc

        # Copy the source file to a temporary destination. The final destination remains untouched
        # at this stage.
        [IO.File]::Copy($Source, $temporary, $false)

        # File.Copy may carry over the source ReadOnly flag. Remove it from this disposable
        # staging copy so timestamp updates and cleanup work. The original attributes are restored
        # below when requested.
        $temporaryAttributes = [IO.File]::GetAttributes($temporary)
        if (($temporaryAttributes -band [IO.FileAttributes]::ReadOnly) -ne 0) {
            [IO.File]::SetAttributes(
                $temporary,
                ($temporaryAttributes -band (-bnot [IO.FileAttributes]::ReadOnly))
            )
        }

        # Retrieve the effective verification mode.
        $mode = $SourceConfig.Verification.Mode

        # Initialize the optional SHA-256 hash result.
        $hash = $null

        # Unless verification is disabled, compare the copied file size with the original source
        # file size.
        if ($mode -ne 'None') {

            $size = ([IO.FileInfo]::new($temporary)).Length

            if ($size -ne $beforeSize) {
                throw "Size verification failed ($beforeSize != $size) for '$Source'."
            }
        }

        # Perform cryptographic integrity verification when requested.
        if ($mode -eq 'Sha256') {

            # Calculate the source file's SHA-256 hash.
            $sourceHash = Get-BackupHash $Source

            # Calculate the temporary copy's SHA-256 hash.
            $targetHash = Get-BackupHash $temporary

            # Require both files to have identical content hashes.
            if ($sourceHash -cne $targetHash) {
                throw "SHA-256 verification failed for '$Source'."
            }

            # Reuse the calculated hash for the optional manifest.
            $hash = $targetHash
        }

        # Restore the original modification timestamp when enabled.
        if ($SourceConfig.Metadata.PreserveTimestamps) {
            [IO.File]::SetLastWriteTimeUtc(
                $temporary,
                $beforeModified
            )
        }

        # Preserve supported filesystem attributes when enabled.
        if ($SourceConfig.Metadata.PreserveAttributes) {

            # Exclude the ReparsePoint flag. ACLs and ownership are not explicitly copied.
            [IO.File]::SetAttributes(
                $temporary,
                $before.Attributes -band (-bnot [IO.FileAttributes]::ReparsePoint)
            )
        }

        # Detect source changes that occurred during copying or verification by comparing metadata
        # captured before and after the operation.
        if ($mode -ne 'None') {

            # Refresh the source file metadata.
            $after = [IO.FileInfo]::new($Source)

            # Reject the copy if its source changed in size or modification timestamp.
            if ($after.Length -ne $beforeSize -or
                $after.LastWriteTimeUtc -ne $beforeModified) {

                throw "Source changed while copying or verifying: $Source"
            }
        }

        # Generate a SHA-256 hash when required by the manifest and no hash was calculated during
        # verification.
        if ($Config.Manifest.Enabled -and
            $Config.Manifest.IncludeHashes -and
            $null -eq $hash) {

            $hash = Get-BackupHash $temporary
        }

        # Publish the completed temporary file under its final name.
        #
        # Existing destination files are replaced only when the source's ExistingFile policy
        # explicitly permits overwriting.
        [IO.File]::Move(
            $temporary,
            $Destination,
            ($SourceConfig.Policies.ExistingFile -eq 'overwrite')
        )

        # Return metadata about the successfully copied file.
        return [pscustomobject]@{
            Size             = ([IO.FileInfo]::new($Destination)).Length
            Hash             = $hash
            LastWriteTimeUtc = $beforeModified.ToString('o')
        }
    }
    finally {

        # Remove the temporary file if it still exists.
        #
        # After a successful rename, the temporary path no longer exists, so no cleanup is
        # necessary.
        #
        # If copying or verification failed, this removes the incomplete temporary copy.
        if ([IO.File]::Exists($temporary)) {

            try {
                # A failed publication can leave a ReadOnly staging copy.
                $attributes = [IO.File]::GetAttributes($temporary)
                if (($attributes -band [IO.FileAttributes]::ReadOnly) -ne 0) {
                    [IO.File]::SetAttributes(
                        $temporary,
                        ($attributes -band (-bnot [IO.FileAttributes]::ReadOnly))
                    )
                }
                [IO.File]::Delete($temporary)
            }
            catch {

                # Cleanup failure must not hide the original copy or verification exception.
                Write-Warning "Failed to delete temporary file '$temporary': $($_.Exception.Message)"
            }
        }
    }
}

#endregion

#region Events and source error handling

<#
.SYNOPSIS
    Adds a timestamped event to the backup execution log.

.DESCRIPTION
    Creates a formatted log entry containing the current timestamp, an event severity level, and a
    descriptive message.

    Events use the following format:

        <timestamp> [<level>] <message>

    The timestamp is generated using the current local date and time with its UTC offset and
    formatted according to ISO 8601.

    The resulting event is appended to the Events collection of the current backup execution
    state.

    This function is used throughout PsMyBackup to record informational messages, warnings,
    errors, and fatal failures.

    Events are kept in memory during execution and subsequently included in the backup report.

    The function does not write directly to a log file or produce console output.

.PARAMETER State
    The current backup execution state.

    The object must contain an Events property representing a mutable collection that supports an
    Add() method.

.PARAMETER Level
    The severity level of the event.

    Common values used by PsMyBackup include:

    - INFO
    - WARN
    - ERROR
    - FATAL

    The function does not validate or normalize the level.

.PARAMETER Message
    The descriptive event message to record.

.OUTPUTS
    None.
    The event is added directly to State.Events.

.EXAMPLE
    Add-BackupEvent `
        -State $state `
        -Level 'INFO' `
        -Message 'Backup started'

    Adds an informational event to the execution log.

.EXAMPLE
    Add-BackupEvent `
        -State $state `
        -Level 'ERROR' `
        -Message "Cannot read file: $path"

    Records an error associated with a specific file.

.NOTES
    Event timestamps are generated independently of the backup's start and completion timestamps.

    Events are stored in their insertion order.

    The function does not modify error counters, determine backup status, or apply error-handling
    policies.

    These responsibilities belong to the calling functions.
#>
function Add-BackupEvent {
    param(
        [object] $State,
        [string] $Level,
        [string] $Message
    )

    # Generate a timestamped event containing the severity and message.
    $eventLine = "$([DateTimeOffset]::Now.ToString('o')) [$Level] $Message"

    # Append the event to the current backup execution log.
    $State.Events.Add($eventLine)
}

<#
.SYNOPSIS
    Handles an existing destination file according to the backup policy.

.DESCRIPTION
    Registers a destination-file conflict that occurs when a file already exists at the intended
    backup destination.

    The function updates both the overall backup execution state and the statistics of the current
    backup source.

    Every invocation increments the error counters.

    The behavior depends on the effective ExistingFile policy of the current source:

    - fail
      Records an error event and immediately throws an exception, terminating the current
      operation.

    - skip
      Increments the skipped-on-error counters and records a warning event. Processing may
      continue with other files.

    The overwrite policy is not handled directly by this function. Overwriting is performed by the
    file-copy implementation.

    The function does not create, modify, or delete files.

.PARAMETER State
    The current backup execution state.

    The following properties are modified:

    - Errors
    - SkippedOnError
    - Events

.PARAMETER Stats
    The statistics object of the current backup source.

    The following properties are used or modified:

    - Policies.ExistingFile
    - Errors
    - SkippedOnError

.PARAMETER Path
    The absolute path of the destination file that already exists.

    The path is included in the event log and exception messages.

.OUTPUTS
    None.
    Throws an exception when ExistingFile is set to 'fail'.

.EXAMPLE
    Register-BackupExistingFile `
        -State $state `
        -Stats $stats `
        -Path 'D:\Backups\Documents\report.pdf'

    Applies the current source's ExistingFile policy to the destination-file conflict.

.EXAMPLE
    if ([IO.File]::Exists($destination)) {
        Register-BackupExistingFile `
            -State $state `
            -Stats $stats `
            -Path $destination
    }

    Registers an existing destination file and either aborts or skips it according to the
    configured policy.

.NOTES
    The function assumes that the caller has already detected a destination conflict.

    It is intended to be called only when the ExistingFile policy does not permit overwriting.

    Both 'fail' and 'skip' increase the error counters. Consequently, even a skipped conflict
    contributes to a PARTIAL backup result.

    The function records a warning event for skipped files but does not call Write-Warning.

    The caller is responsible for continuing with the next file when the function returns without
    throwing.
#>
function Register-BackupExistingFile {
    param(
        [object] $State,
        [object] $Stats,
        [string] $Path
    )

    # Count the destination conflict as an error in the overall backup and in the statistics of
    # the affected source.
    $State.Errors++
    $Stats.Errors++

    # Abort immediately when existing destination files are forbidden.
    if ($Stats.Policies.ExistingFile -eq 'fail') {

        # Record the conflict before terminating the operation.
        Add-BackupEvent `
            $State `
            'ERROR' `
            "Destination exists | $Path | ExistingFile=fail"

        # Stop processing regardless of the separate ItemError policy.
        throw "Stopped by ExistingFile=fail: $Path"
    }

    # The conflict is permitted to be skipped. Track the skipped file in both statistics objects.
    $State.SkippedOnError++
    $Stats.SkippedOnError++

    # Record the skipped destination conflict.
    Add-BackupEvent `
        $State `
        'WARN' `
        "Destination exists; skipped | $Path"
}

<#
.SYNOPSIS
    Registers a filesystem operation error during backup execution.

.DESCRIPTION
    Handles an error associated with an individual filesystem operation performed during a backup.

    The function records the error in both the overall backup execution state and the statistics
    of the affected source.

    Each error is:
    
    - Counted in the overall backup error statistics.
    - Counted in the affected source's error statistics.
    - Recorded as an ERROR event in the backup event log.
    - Reported through PowerShell's Write-Warning mechanism.

    After recording the error, the function applies the effective ItemError policy of the current
    source.

    Supported policies:

    - fail
      Throws an exception and terminates the current operation.

    - skip
      Increments the skipped-on-error counters and returns, allowing the caller to continue
      processing.

    The function is used for errors such as:

    - Directory enumeration failures.
    - File metadata access failures.
    - File copying or verification failures.
    - Directory creation failures.
    - Metadata preservation failures.

    The function does not retry failed operations. Retry handling is implemented by the calling
    backup functions.

.PARAMETER State
    The current backup execution state.

    The following properties are modified:

    - Errors
    - SkippedOnError
    - Events

.PARAMETER Stats
    The statistics object of the current backup source.

    The following properties are used or modified:

    - Policies.ItemError
    - Errors
    - SkippedOnError

.PARAMETER Operation
    A short description of the filesystem operation that failed.

    Examples:

    - 'Copy/verify failed'
    - 'Listing directory'
    - 'Reading attributes'
    - 'Creating directory'

.PARAMETER Item
    The filesystem path associated with the failed operation.

.PARAMETER Reason
    A description of the failure.

    Typically contains the message of the original exception.

.OUTPUTS
    None.
    Throws an exception when ItemError is set to 'fail'.

.EXAMPLE
    Register-BackupItemProblem `
        -State $state `
        -Stats $stats `
        -Operation 'Copy/verify failed' `
        -Item 'C:\Documents\report.pdf' `
        -Reason 'Access denied'

    Records the file-copy failure and applies the source's configured ItemError policy.

.EXAMPLE
    try {
        [IO.Directory]::CreateDirectory($destination)
    }
    catch {
        Register-BackupItemProblem `
            -State $state `
            -Stats $stats `
            -Operation 'Creating directory' `
            -Item $destination `
            -Reason $_.Exception.Message
    }

    Handles a directory-creation failure and either aborts or allows processing to continue.

.NOTES
    The function always increments the error counters, regardless of the configured ItemError
    policy.

    The skipped-on-error counters are incremented only when the policy permits skipping.

    A skipped error contributes to the backup's PARTIAL status.

    When ItemError is 'fail', the function throws an exception after recording the error and
    emitting a warning.

    The caller is responsible for deciding whether to continue processing after the function
    returns.

    The function does not directly determine the final backup status or write the backup report.
#>
function Register-BackupItemProblem {
    param(
        [object] $State,
        [object] $Stats,
        [string] $Operation,
        [string] $Item,
        [string] $Reason
    )

    # Count the problem in the overall backup statistics.
    $State.Errors++

    # Count the problem in the affected source statistics.
    $Stats.Errors++

    # Record a detailed error event containing the operation, affected item, and failure reason.
    Add-BackupEvent `
        $State `
        'ERROR' `
        "$Operation | $Item | $Reason"

    # Emit a PowerShell warning for immediate diagnostic visibility.
    Write-Warning "$Operation | $Item | $Reason"

    # Abort processing when the source policy requires failures to terminate the backup operation.
    if ($Stats.Policies.ItemError -eq 'fail') {
        throw "Stopped by ItemError=fail ($Operation): $Item. $Reason"
    }

    # Otherwise, register that the affected item was skipped and allow the calling function to
    # continue.
    $State.SkippedOnError++
    $Stats.SkippedOnError++
}

#endregion

#region Snapshot JSON files, manifests, and reporting

<#
.SYNOPSIS
    Writes a JSON document to a file using an atomic replacement operation.

.DESCRIPTION
    Serializes an object into JSON and writes the resulting document to the specified destination
    path.

    To prevent incomplete JSON documents from appearing under the final filename, the function
    uses a temporary file.

    The operation consists of the following steps:

    1. Determine the destination directory.
    2. Generate a unique temporary filename in that directory.
    3. Serialize the supplied object into JSON.
    4. Write the JSON document to the temporary file.
    5. Move the temporary file to the final destination.
    6. Remove any remaining temporary file.

    Temporary files use the following naming convention:

        .psmybackup-<GUID>.tmp

    JSON serialization uses a maximum depth of 15.

    The generated JSON is encoded as UTF-8 without a byte order mark (BOM) and ends with a
    platform-specific newline.

    An existing destination file is replaced by the completed temporary file.

    Creating the temporary file in the destination directory allows the final move to use a
    filesystem rename operation.

    The function throws an exception if serialization, writing, renaming, or cleanup fails.

.PARAMETER Path
    The absolute path of the destination JSON file.

    The parent directory must already exist.

    If the destination file exists, it will be replaced.

.PARAMETER Data
    The object to serialize into JSON.

    Supports PowerShell objects, hashtables, arrays, and other values supported by ConvertTo-Json.

.OUTPUTS
    None.
    Throws an exception if the JSON document cannot be written.

.EXAMPLE
    $data = @{
        Status = 'Completed'
        FilesCopied = 150
        Errors = 0
    }

    Write-BackupJsonAtomic `
        -Path 'D:\Backups\backup-status.json' `
        -Data $data

    Serializes the supplied object and writes the resulting JSON document to the specified file.

.EXAMPLE
    Write-BackupJsonAtomic `
        -Path $manifestPath `
        -Data $manifest

    Writes a backup manifest, replacing an existing manifest only after the temporary JSON
    document has been written.

.NOTES
    This function is used by PsMyBackup to write structured snapshot metadata, including:

    - backup-status.json
    - backup-manifest.json

    The final rename is intended to provide atomic publication when supported by the destination
    filesystem.

    Atomic publication does not guarantee crash durability. The function does not explicitly flush
    data or filesystem metadata to durable storage.

    The operation is not intended for concurrent writers modifying the same destination file.

    Temporary files are removed in a finally block.

    Because the function modifies the filesystem, it must not be called during dry runs (-Test or
    -WhatIf).
#>
function Write-BackupJsonAtomic {
    param(
        [string] $Path,
        [object] $Data
    )

    # Determine the directory containing the destination JSON file.
    $folder = [IO.Path]::GetDirectoryName($Path)

    # Generate a unique temporary filename in the same directory. This keeps the final move on the
    # same filesystem.
    $temporary = [IO.Path]::Combine(
        $folder,
        ".psmybackup-$([Guid]::NewGuid().ToString('N')).tmp"
    )

    try {

        # Serialize the supplied object into JSON. A depth of 15 supports nested configuration and
        # manifest objects.
        $json = ConvertTo-Json -InputObject $Data -Depth 15

        # Write the complete JSON document to the temporary file.
        #
        # UTF-8 without BOM is used for compatibility with standard JSON consumers.
        #
        # Append a newline to keep the resulting file text-friendly.
        [IO.File]::WriteAllText(
            $temporary,
            $json + [Environment]::NewLine,
            [Text.UTF8Encoding]::new($false)
        )

        # Publish the completed JSON document.
        #
        # The overwrite flag permits replacing an existing file, which is necessary when updating
        # snapshot status.
        [IO.File]::Move(
            $temporary,
            $Path,
            $true
        )
    }
    finally {

        # Remove the temporary file if it still exists.
        #
        # After a successful move, the temporary path no longer exists. If serialization or
        # writing fails, cleanup removes the incomplete temporary document.
        if ([IO.File]::Exists($temporary)) {
            [IO.File]::Delete($temporary)
        }
    }
}

<#
.SYNOPSIS
    Writes the current backup snapshot status to a JSON file.

.DESCRIPTION
    Creates a structured status document describing the current state and progress of a backup
    snapshot.

    The status document contains:

    - format
      Identifies the document as a PsMyBackup snapshot.

    - schemaVersion
      Version of the status document structure.

    - snapshotId
      Unique identifier of the backup snapshot.

    - snapshotPath
      Absolute path of the snapshot directory.

    - status
      Current lifecycle status of the snapshot.

    - startedAt
      Timestamp when the backup operation started.

    - finishedAt
      Timestamp when the backup operation finished, or null while the backup is running.

    - filesCopied
      Number of files successfully copied.

    - bytesCopied
      Total number of bytes successfully copied.

    - filesPlanned
      Number of files identified for copying.

    - errors
      Number of errors encountered during execution.

    - fatalError
      Description of a fatal error, if available.

    Supported lifecycle states used by PsMyBackup include:

    - Running
      The backup operation is in progress.

    - Completed
      The backup finished successfully.

    - Partial
      The backup finished with one or more non-fatal errors.

    - Failed
      The backup operation encountered a fatal error.

    The status document is written to:

        <SnapshotPath>/backup-status.json

    Writing is delegated to Write-BackupJsonAtomic to avoid publishing partially written JSON
    documents.

    Existing status documents are replaced.

.PARAMETER State
    The current backup execution state.

    Must contain the snapshot identity, path, timestamps, and execution counters used in the
    status document.

.PARAMETER Status
    The lifecycle status to record.

    Expected values are Running, Completed, Partial, and Failed.

    The function does not explicitly validate this value.

.PARAMETER FatalError
    An optional description of the fatal error responsible for terminating the backup.

    Typically null for successful or running backups.

.PARAMETER FinishedAt
    The timestamp at which the backup operation finished.

    When status is Running, the resulting finishedAt property in the JSON document is set to null.

.OUTPUTS
    None.
    Throws an exception if the status document cannot be written.

.EXAMPLE
    Write-BackupStatus `
        -State $state `
        -Status 'Running' `
        -FatalError $null `
        -FinishedAt $state.StartedAt

    Creates the initial status document for a running backup.

.EXAMPLE
    Write-BackupStatus `
        -State $state `
        -Status 'Completed' `
        -FatalError $null `
        -FinishedAt ([DateTimeOffset]::Now)

    Updates the snapshot status after successful completion.

.EXAMPLE
    Write-BackupStatus `
        -State $state `
        -Status 'Failed' `
        -FatalError 'Source directory is inaccessible.' `
        -FinishedAt ([DateTimeOffset]::Now)

    Records a failed backup together with its fatal error.

.NOTES
    The status document uses the following identifiers:

        format        = PsMyBackup.Snapshot
        schemaVersion = 1.0.0

    Older status document layouts and schema versions are not supported. Retention never selects
    unrecognized documents for deletion.

    A status document is not sufficient by itself to authorize deletion. Retention applies
    additional validation.

    A snapshot may remain in the Running state when execution is interrupted before its final
    status can be written.

    The status file is intended for machine-readable reporting. Human-readable reporting is
    handled separately by Format-BackupReport.
#>
function Write-BackupStatus {
    param(
        [object] $State,
        [string] $Status,
        [string] $FatalError,
        [DateTimeOffset] $FinishedAt
    )

    # Construct the machine-readable snapshot status document.
    $document = [ordered]@{

        # Identify the document format and schema version. PsMyBackup-specific status marker used
        # for retention recognition.
        format = 'PsMyBackup.Snapshot'
        schemaVersion = '1.0.0'

        # Identify the snapshot.
        snapshotId = $State.SnapshotId
        snapshotPath = $State.SnapshotPath

        # Record the current lifecycle status.
        status = $Status

        # Record the backup start timestamp.
        startedAt = $State.StartedAt.ToString('o')

        # A running backup has no completion timestamp.
        finishedAt = $(
            if ($Status -eq 'Running') {
                $null
            }
            else {
                $FinishedAt.ToString('o')
            }
        )

        # Record file-copy statistics.
        filesCopied = $State.FilesCopied
        bytesCopied = $State.BytesCopied
        filesPlanned = $State.FilesPlanned

        # Record error information.
        errors = $State.Errors
        fatalError = $FatalError
    }

    # Write or replace the status document using the atomic JSON writer.
    Write-BackupJsonAtomic `
        ([IO.Path]::Combine($State.SnapshotPath, 'backup-status.json')) `
        $document
}

<#
.SYNOPSIS
    Writes a JSON manifest for a completed source-processing phase.

.DESCRIPTION
    Constructs a PsMyBackup manifest using schema version 1.0.0 and camelCase property names.
    Includes entries collected during copying and writes the document atomically into the snapshot
    directory. The caller controls when manifest writing is permitted and handles errors.

.PARAMETER State
    Execution state with SnapshotPath, SnapshotId, and ManifestEntries.

.OUTPUTS
    None. Throws if writing the manifest fails.
#>
function Write-BackupManifest {
    param(
        [object] $State
    )

    $manifest = [ordered]@{
        format = 'PsMyBackup.Manifest'
        schemaVersion = '1.0.0'
        snapshotId = $State.SnapshotId
        entries = $State.ManifestEntries.ToArray()
    }

    Write-BackupJsonAtomic `
        ([IO.Path]::Combine($State.SnapshotPath, 'backup-manifest.json')) `
        $manifest
}

<#
.SYNOPSIS
    Generates a human-readable backup execution report.

.DESCRIPTION
    Formats the current backup execution state into a structured text report containing summary
    statistics, source-specific results, retention information, and recorded events.

    The report consists of the following sections:

    1. General backup summary
       Includes execution mode, status, timestamps, configuration, snapshot path, file statistics,
       verification, retries, and error counts.

    2. Per-source summary
       Lists each configured source together with its effective policies, verification mode, and
       execution statistics.

    3. Retention candidates
       Lists snapshot directories selected for retention deletion, when applicable.

    4. Event log
       Contains timestamped informational messages, warnings, errors, and fatal events recorded
       during execution.

    The function supports both regular backups and dry runs.

    During a dry run, the report identifies the execution mode as TEST and includes a note
    explaining that no filesystem modifications were performed by the backup operation.

    Report lines are collected in memory and joined using the platform-specific newline sequence.

    The resulting report ends with a newline.

    The function does not create or modify any files. Writing the report to disk is handled by the
    caller.

.PARAMETER State
    The current backup execution state.

    Contains execution timestamps, snapshot information, counters, source statistics, retention
    information, and the event collection.

.PARAMETER Config
    The fully resolved backup configuration.

    The FilePath property is used to identify the configuration file associated with the backup.

.PARAMETER Status
    The overall backup result.

    Expected values are SUCCESS, PARTIAL, and FAILED.

.PARAMETER FatalError
    An optional description of the fatal error that caused the backup to fail.

    When provided, the message is included in the report.

.PARAMETER FinishedAt
    The timestamp when backup execution finished.

.OUTPUTS
    System.String
    A complete human-readable backup report.

.EXAMPLE
    $report = Format-BackupReport `
        -State $state `
        -Config $config `
        -Status 'SUCCESS' `
        -FatalError $null `
        -FinishedAt ([DateTimeOffset]::Now)

    Generates a text report for a successful backup.

.EXAMPLE
    $report = Format-BackupReport `
        -State $state `
        -Config $config `
        -Status 'FAILED' `
        -FatalError 'Cannot access source directory.' `
        -FinishedAt ([DateTimeOffset]::Now)

    Generates a report that includes the fatal error.

.EXAMPLE
    $report = Format-BackupReport `
        -State $state `
        -Config $config `
        -Status 'SUCCESS' `
        -FatalError $null `
        -FinishedAt ([DateTimeOffset]::Now)

    [IO.File]::WriteAllText(
        $reportPath,
        $report,
        [Text.UTF8Encoding]::new($false)
    )

    Generates and persists the report as a UTF-8 text file.

.NOTES
    This function is responsible only for report formatting.

    It does not:
    - Determine the final backup status.
    - Perform backup operations.
    - Delete snapshots.
    - Write files.
    - Modify execution statistics.

    The event log is included in its original insertion order.

    The report is normally stored as:

        backup-report.txt

    inside the timestamped snapshot directory.

    During dry runs, the formatted text is returned through the ReportText property of the
    Backup-MyFiles result.
#>
function Format-BackupReport {
    param(
        [object] $State,
        [object] $Config,
        [string] $Status,
        [string] $FatalError,
        [DateTimeOffset] $FinishedAt
    )

    # Collect report lines before joining them into a single string.
    $lines = [Collections.Generic.List[string]]::new()

    # Add the report title and separator.
    $lines.Add('PSMYBACKUP REPORT')
    $lines.Add(('=' * 72))

    # Identify whether the operation was a real backup or a dry run.
    $lines.Add("Mode                : $(if ($State.IsTest) { 'TEST (read-only)' } else { 'BACKUP' })")

    # Record the overall execution status.
    $lines.Add("Status              : $Status")

    # Record execution timestamps.
    $lines.Add("Started             : $($State.StartedAt.ToString('o'))")
    $lines.Add("Finished            : $($FinishedAt.ToString('o'))")

    # Identify the configuration and snapshot paths.
    $lines.Add("Configuration       : $($Config.FilePath)")
    $lines.Add("Snapshot            : $($State.SnapshotPath)")

    # Record the number and size of planned files.
    $lines.Add("Files planned       : $($State.FilesPlanned)")
    $lines.Add("Bytes planned       : $($State.BytesPlanned)")

    # Record successfully copied files.
    $lines.Add("Files copied        : $($State.FilesCopied)")
    $lines.Add("Bytes copied        : $($State.BytesCopied)")

    # Record created directories and excluded entries.
    $lines.Add("Directories created : $($State.DirectoriesCopied)")
    $lines.Add("Ignored entries     : $($State.Ignored)")
    $lines.Add("Links skipped       : $($State.LinksSkipped)")

    # Record verification and retry statistics.
    $lines.Add("Verified files      : $($State.Verified)")
    $lines.Add("Copy retries        : $($State.Retries)")

    # Record errors and skipped items.
    $lines.Add("Errors              : $($State.Errors)")
    $lines.Add("Skipped on error    : $($State.SkippedOnError)")

    # Record retention statistics.
    $lines.Add("Retention planned   : $($State.RetentionPlanned.Count)")
    $lines.Add("Retention deleted   : $($State.RetentionDeleted)")

    # Include the fatal error when one occurred.
    if ($FatalError) {
        $lines.Add("Fatal error         : $FatalError")
    }

    # Explain the limitations of dry-run execution.
    if ($State.IsTest) {
        $lines.Add(
            'Note: TEST reads metadata only. It never writes, deletes, opens files for hashing, or probes target write permissions.'
        )
    }

    # Separate the source summary from the general statistics.
    $lines.Add('')
    $lines.Add('PER-SOURCE SUMMARY')

    # Add execution statistics for every processed source.
    foreach ($source in $State.Sources) {

        # Identify the source by name and absolute path.
        $lines.Add("$($source.Name) | $($source.Path)")

        # Record the effective error-handling and retry policies.
        $lines.Add(
            "  policies: MissingSource=$($source.Policies.MissingSource), ItemError=$($source.Policies.ItemError), ExistingFile=$($source.Policies.ExistingFile), RetryCount=$($source.Policies.RetryCount), RetryDelayMilliseconds=$($source.Policies.RetryDelayMilliseconds)"
        )

        # Record the verification mode and source-specific statistics.
        $lines.Add(
            "  verification=$($source.Verification.Mode), copied=$($source.FilesCopied), planned=$($source.FilesPlanned), ignored=$($source.Ignored), retries=$($source.Retries), errors=$($source.Errors)"
        )
    }

    # Include the retention section only when candidates exist.
    if ($State.RetentionPlanned.Count -gt 0) {

        $lines.Add('')
        $lines.Add('RETENTION CANDIDATES')

        # List all snapshot directories selected for retention.
        foreach ($path in $State.RetentionPlanned) {
            $lines.Add("  $path")
        }
    }

    # Separate the chronological event log from the summaries.
    $lines.Add('')
    $lines.Add('EVENT LOG')

    # Append events in the order they were recorded.
    foreach ($eventLine in $State.Events) {
        $lines.Add($eventLine)
    }

    # Join all report lines and append a final newline.
    return ($lines -join [Environment]::NewLine) + [Environment]::NewLine
}

#endregion

#region Retention recognition and deletion safety

<#
.SYNOPSIS
    Tests whether a JSON document uses a supported PsMyBackup schema version.

.DESCRIPTION
    Accepts string versions in the 1.0.x series, where x contains one or more decimal digits.
    Other major/minor versions, prerelease suffixes, and non-string values are rejected.

    Both backup-status.json and backup-manifest.json use this version convention. Both writers
    emit 1.0.0; The status reader uses this check when evaluating retention.

.PARAMETER Version
    The schemaVersion value as deserialized from JSON.

.OUTPUTS
    System.Boolean
    True only for a string matching the schema's 1.0.x version pattern.
#>
function Test-BackupJsonSchemaVersion {
    param([object] $Version)

    # Do not convert numbers or other JSON value types into version strings.
    return ($Version -is [string] -and $Version -cmatch '^1\.0\.\d+$')
}

<#
.SYNOPSIS
    Validates a snapshot directory before retention deletion.

.DESCRIPTION
    Recursively examines a backup snapshot directory and ensures that it contains no symbolic
    links, junctions, or other filesystem entries marked with the ReparsePoint attribute.

    This validation is a safety precaution performed before a snapshot is deleted by the retention
    subsystem.

    Directory traversal is implemented iteratively using a stack to avoid recursive PowerShell
    function calls.

    For each directory and filesystem entry, the function retrieves its attributes and checks for
    the ReparsePoint flag.

    If a reparse point is encountered, the function immediately throws an exception and prevents
    the caller from proceeding with deletion.

    The function also throws if a directory cannot be enumerated or its filesystem attributes
    cannot be retrieved.

    The function does not modify or delete any files or directories.

.PARAMETER Path
    The absolute path of the snapshot directory to validate.

.OUTPUTS
    None.
    Throws an exception if a reparse point is encountered or the filesystem cannot be inspected.

.EXAMPLE
    Assert-BackupSafeRetentionTree -Path 'D:\Backups\2026-10-24_21-30-00-000'

    Validates the snapshot directory and all of its descendants before the retention subsystem
    attempts to delete it.

.NOTES
    The validation is performed only when retention is enabled.

    The function follows a fail-closed approach: if the directory tree cannot be inspected safely,
    the snapshot must not be deleted.

    This is a best-effort safety check, not a security boundary. The filesystem could change
    between validation and deletion.

    The caller must separately verify that the directory is a recognized PsMyBackup snapshot and
    that it is eligible for retention deletion.
#>
function Assert-BackupSafeRetentionTree {
    param(
        [string] $Path
    )

    # Use an explicit stack to traverse the directory tree.
    $stack = [Collections.Generic.Stack[string]]::new()
    $stack.Push($Path)

    # Process directories until the entire tree has been inspected.
    while ($stack.Count -gt 0) {
        $directory = $stack.Pop()

        # Reject directories that are themselves links or junctions.
        if (([IO.File]::GetAttributes($directory) -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing to delete a snapshot containing a link/junction: $directory"
        }

        # Enumerate all immediate children of the current directory.
        foreach ($entry in [IO.Directory]::GetFileSystemEntries($directory)) {

            # Read filesystem attributes to identify links and directories.
            $attributes = [IO.File]::GetAttributes($entry)

            # Never allow retention deletion when a reparse point is found.
            if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing to delete a snapshot containing a link/junction: $entry"
            }

            # Queue subdirectories for further inspection.
            if (($attributes -band [IO.FileAttributes]::Directory) -ne 0) {
                $stack.Push($entry)
            }
        }
    }
}

<#
.SYNOPSIS
    Determines which backup snapshots are eligible for retention deletion.

.DESCRIPTION
    Evaluates existing backup snapshots in the configured target directory and creates a retention
    deletion plan.

    The function supports two retention constraints:

    - KeepLast
      Protects the specified number of newest eligible snapshots from deletion.

    - MaxAgeDays
      Protects snapshots that are newer than the configured age threshold.

    When both constraints are configured, a snapshot is selected for deletion only when both
    conditions are satisfied:

    - It is outside the KeepLast protection window.
    - It is older than the MaxAgeDays threshold.

    This ensures that the minimum number of retained snapshots is preserved even when those
    snapshots exceed the age limit.

    Only directories recognized as PsMyBackup snapshots are considered for retention.

    A directory must satisfy all of the following conditions:

    - Its name matches the PsMyBackup timestamp naming convention.
    - It is not the current snapshot.
    - It is not a symbolic link or junction.
    - It contains a backup-status.json file.
    - The status document identifies the PsMyBackup.Snapshot format
      using the camelCase format property.
    - The status document uses schema version 1.0.x (string).
    - It contains a valid, non-empty snapshot GUID.
    - Its recorded snapshot path matches the directory path.
    - Its status is Completed, Partial, or Failed.

    By default, only Completed snapshots are eligible. Partial and Failed snapshots are included
    only when Retention.IncludeNonSuccessful is enabled.

    Recognized snapshots are sorted by their recorded start timestamps in descending order, with
    the path used as an additional sorting property.

    The current snapshot may optionally be included as a virtual candidate when calculating the
    KeepLast window. It is never selected for deletion.

    The function returns only a list of directory paths. It does not delete files or modify the
    filesystem.

.PARAMETER Config
    The fully resolved backup configuration returned by Read-BackupConfiguration.

    The following properties are required:

    - TargetFolder
      Directory containing the backup snapshots.

    - Retention.Enabled
      Determines whether retention is active.

    - Retention.KeepLast
      Minimum number of newest eligible snapshots to protect. May be null to disable the count
      constraint.

    - Retention.MaxAgeDays
      Maximum snapshot age in days. May be null to disable the age constraint.

    - Retention.IncludeNonSuccessful
      Determines whether Partial and Failed snapshots are included in retention evaluation.

.PARAMETER CurrentSnapshot
    The absolute path of the snapshot associated with the current backup operation.

    This snapshot is always excluded from deletion.

.PARAMETER IncludeCurrent
    Determines whether the current snapshot participates in the retention ranking.

    When true, the current snapshot is added as a virtual candidate with the current timestamp.

    This is useful when calculating retention after a successful backup, because the newly created
    snapshot should count toward KeepLast.

    When false, the current snapshot is excluded from both retention ranking and deletion.

.OUTPUTS
    System.String[]
    An array containing the absolute paths of snapshots selected for retention deletion.

    Returns an empty array when retention is disabled, the target directory does not exist, or no
    snapshots satisfy the deletion criteria.

.EXAMPLE
    $plan = Get-BackupRetentionPlan `
        -Config $config `
        -CurrentSnapshot $snapshotPath `
        -IncludeCurrent $true

    Calculates the retention plan after a successful backup.

    The current snapshot participates in retention ranking but cannot be selected for deletion.

.EXAMPLE
    $plan = Get-BackupRetentionPlan `
        -Config $config `
        -CurrentSnapshot $snapshotPath `
        -IncludeCurrent $false

    Calculates retention candidates without counting the current snapshot toward the KeepLast
    constraint.

.EXAMPLE
    $plan = Get-BackupRetentionPlan `
        -Config $config `
        -CurrentSnapshot $snapshotPath `
        -IncludeCurrent $true

    foreach ($path in $plan) {
        Write-Host "Retention candidate: $path"
    }

    Displays the snapshots that would be selected for deletion without modifying the filesystem.

.NOTES
    Retention is disabled by default in PsMyBackup.

    The function performs directory enumeration and reads status documents, so its cost depends on
    the number of snapshots present in the target directory.

    Malformed or unreadable status documents are ignored. A directory that cannot be positively
    recognized as a PsMyBackup snapshot is not selected for deletion.

    The function does not independently verify that the snapshot contents are complete or
    internally consistent.

    Snapshot timestamps are obtained from backup-status.json rather than filesystem creation or
    modification times.

    Recognition of a PsMyBackup status document is an ownership check, not cryptographic
    authentication.

    Actual deletion is coordinated by Invoke-BackupRetention and performed by
    Invoke-BackupRetentionRemoval after validation of the complete tree.

    The function does not acquire an exclusive backup lock. The caller is responsible for
    concurrency protection.

    The current time is evaluated when the plan is generated. Results may therefore differ between
    consecutive executions.
#>
function Get-BackupRetentionPlan {
    param(
        [object] $Config,
        [string] $CurrentSnapshot,
        [bool] $IncludeCurrent
    )

    # Create a collection for snapshot paths selected for deletion.
    $plan = [Collections.Generic.List[object]]::new()

    # Retention must be enabled and the destination directory must exist.
    if (-not $Config.Retention.Enabled -or
        -not [IO.Directory]::Exists($Config.TargetFolder)) {

        return $plan.ToArray()
    }

    # Collect recognized snapshots before applying retention constraints.
    $candidates = [Collections.Generic.List[object]]::new()

    # Require the complete schema 1.0 status document before considering destructive retention.
    # Property names are case-sensitive; unknown and missing properties fail closed.
    $requiredStatusKeys = @(
        'format', 'schemaVersion', 'snapshotId', 'snapshotPath', 'status', 'startedAt',
        'finishedAt', 'filesCopied', 'bytesCopied', 'filesPlanned', 'errors', 'fatalError'
    )
    $timestampPattern = '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$'

    # Enumerate immediate subdirectories of the backup destination.
    foreach ($dir in [IO.Directory]::EnumerateDirectories($Config.TargetFolder)) {

        # Never consider the current snapshot for deletion.
        if ($dir -eq $CurrentSnapshot) {
            continue
        }

        # Only consider directories matching PsMyBackup's timestamp format. Optional four-digit
        # suffixes are supported for name collisions.
        if (-not (
            [IO.Path]::GetFileName($dir) -match
            '^\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}-\d{3}(?:_\d{4})?$'
        )) {
            continue
        }

        try {

            # Inspect the candidate directory.
            $info = [IO.DirectoryInfo]::new($dir)

            # Do not process directory links or junctions.
            if (($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                continue
            }

            # Locate the machine-readable PsMyBackup status document.
            $statusFile = [IO.Path]::Combine(
                $dir,
                'backup-status.json'
            )

            # A status document is required to recognize a snapshot.
            if (-not [IO.File]::Exists($statusFile)) {
                continue
            }

            # Preserve JSON timestamp strings for strict RFC 3339 validation and snapshot
            # recognition. The default parser converts them into DateTime objects.
            $marker = ConvertFrom-Json `
                -InputObject ([IO.File]::ReadAllText($statusFile)) `
                -DateKind String `
                -ErrorAction Stop

            # Require the exact set of status properties defined by the JSON Schema.
            $markerKeys = @($marker.PSObject.Properties.Name)
            if ($markerKeys.Count -ne $requiredStatusKeys.Count -or
                @($requiredStatusKeys | Where-Object { $markerKeys -cnotcontains $_ }).Count -gt 0) {
                continue
            }

            # Retention cannot rely on shape alone: check value types and supported versions.
            if ($marker.format -cne 'PsMyBackup.Snapshot' -or
                -not (Test-BackupJsonSchemaVersion -Version $marker.schemaVersion) -or
                $marker.snapshotId -isnot [string] -or
                $marker.snapshotPath -isnot [string] -or
                $marker.status -isnot [string] -or
                $marker.startedAt -isnot [string] -or
                $marker.finishedAt -isnot [string] -or
                ($null -ne $marker.fatalError -and $marker.fatalError -isnot [string])) {
                continue
            }

            # Completed, Partial, and Failed snapshots must carry valid RFC 3339 timestamps.
            if ($marker.startedAt -cnotmatch $timestampPattern -or
                $marker.finishedAt -cnotmatch $timestampPattern) {
                continue
            }
            $null = [DateTimeOffset]::Parse(
                $marker.finishedAt,
                [Globalization.CultureInfo]::InvariantCulture
            )

            # Counters must be JSON integers and non-negative. Never coerce strings or decimals.
            $invalidCounter = $false
            foreach ($counter in @($marker.filesCopied, $marker.bytesCopied,
                    $marker.filesPlanned, $marker.errors)) {
                if (($counter -isnot [int] -and $counter -isnot [long] -and
                        $counter -isnot [bigint]) -or $counter -lt 0) {
                    $invalidCounter = $true
                    break
                }
            }
            if ($invalidCounter) {
                continue
            }

            # The schema requires the canonical hyphenated GUID form.
            if ($marker.snapshotId -cnotmatch
                '^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') {
                continue
            }

            # Require a valid, non-empty snapshot identifier.
            $id = [guid]::Empty

            if (-not [guid]::TryParse(
                    [string]$marker.snapshotId,
                    [ref]$id
                ) -or $id -eq [guid]::Empty) {

                continue
            }

            # Ensure that the recorded path matches the directory.
            if ($marker.snapshotPath -cne $dir) {
                continue
            }

            # Only finalized snapshots qualify for retention. Running or otherwise unrecognized
            # states are excluded.
            if ($marker.status -cnotin @(
                    'Completed',
                    'Partial',
                    'Failed'
                )) {

                continue
            }

            # By default, protect unsuccessful snapshots from retention.
            if (-not $Config.Retention.IncludeNonSuccessful -and
                $marker.status -cne 'Completed') {

                continue
            }

            # Parse the snapshot start timestamp using invariant culture.
            $started = [DateTimeOffset]::Parse(
                [string]$marker.startedAt,
                [Globalization.CultureInfo]::InvariantCulture
            )

            # Register the validated snapshot for retention evaluation.
            $candidates.Add([pscustomobject]@{
                Path      = $dir
                StartedAt = $started
                IsCurrent = $false
            })
        }
        catch {

            # Fail closed for malformed or unreadable snapshot metadata. Such directories are not
            # considered for deletion.
            Write-Verbose "Retention skipped unrecognized snapshot '$dir': $($_.Exception.Message)"
        }
    }

    # Optionally count the current snapshot toward the KeepLast limit. It is represented as a
    # virtual candidate and is never deleted.
    if ($IncludeCurrent) {

        $candidates.Add([pscustomobject]@{
            Path      = $CurrentSnapshot
            StartedAt = [DateTimeOffset]::Now
            IsCurrent = $true
        })
    }

    # Sort snapshots by their recorded start timestamps and paths. Newest snapshots appear first.
    $sorted = @(
        $candidates |
            Sort-Object -Property StartedAt, Path -Descending
    )

    # Retrieve the configured retention constraints.
    $keepLast = $Config.Retention.KeepLast
    $maxAge = $Config.Retention.MaxAgeDays

    # Calculate the minimum permitted snapshot timestamp. A null cutoff means age-based retention
    # is disabled.
    $cutoff = if ($null -ne $maxAge) {
        [DateTimeOffset]::Now.AddDays(-$maxAge)
    }
    else {
        $null
    }

    # Evaluate every snapshot in descending chronological order.
    for ($i = 0; $i -lt $sorted.Count; $i++) {

        $candidate = $sorted[$i]

        # Never select the current snapshot for deletion.
        if ($candidate.IsCurrent) {
            continue
        }

        # Protect the newest KeepLast snapshots. A null value disables count-based protection.
        if ($null -ne $keepLast -and $i -lt $keepLast) {
            continue
        }

        # Protect snapshots newer than the configured age threshold. A null cutoff disables
        # age-based protection.
        if ($null -ne $cutoff -and $candidate.StartedAt -ge $cutoff) {
            continue
        }

        # The snapshot satisfies all applicable deletion conditions.
        $plan.Add($candidate.Path)
    }

    # Return the snapshot paths selected for deletion.
    return $plan.ToArray()
}

#endregion

#region Retention execution

<#
.SYNOPSIS
    Deletes an eligible snapshot, including preserved read-only files.

.DESCRIPTION
    Validates the snapshot and its existing ancestors for reparse points before modifying
    anything. Deletes files and directories in leaf-first order, clearing only the ReadOnly
    attribute when necessary for Windows deletion semantics. Each entry is checked again for
    reparse points immediately before use; links and junctions are never intentionally traversed
    or deleted.

    The caller MUST first select the directory using Get-BackupRetentionPlan and hold the
    exclusive destination lock. This function must never be called on source folders or arbitrary
    paths. The existing validation is best-effort; concurrent hostile filesystem mutation can
    still create a race.

.PARAMETER Path
    Previously validated, retention-eligible snapshot directory.

.OUTPUTS
    None. Throws on unsafe entries or filesystem deletion failures.
#>
function Invoke-BackupRetentionRemoval {
    param(
        [string] $Path
    )

    # Validate the complete tree before any destructive action.
    Assert-BackupPathWithoutLink $Path
    Assert-BackupSafeRetentionTree $Path

    $stack = [Collections.Generic.Stack[object]]::new()
    $stack.Push([pscustomobject]@{ Path = $Path; PostOrder = $false })

    while ($stack.Count -gt 0) {
        $node = $stack.Pop()
        $attributes = [IO.File]::GetAttributes($node.Path)
        if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing to delete a linked snapshot entry: $($node.Path)"
        }

        if ($node.PostOrder) {
            # Delete the directory only after its descendants are gone.
            if (($attributes -band [IO.FileAttributes]::ReadOnly) -ne 0) {
                [IO.File]::SetAttributes(
                    $node.Path,
                    ($attributes -band (-bnot [IO.FileAttributes]::ReadOnly))
                )
            }
            [IO.Directory]::Delete($node.Path, $false)
            continue
        }

        $stack.Push([pscustomobject]@{ Path = $node.Path; PostOrder = $true })
        foreach ($entry in [IO.Directory]::GetFileSystemEntries($node.Path)) {
            $entryAttributes = [IO.File]::GetAttributes($entry)
            if (($entryAttributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing to delete a linked snapshot entry: $entry"
            }

            if (($entryAttributes -band [IO.FileAttributes]::Directory) -ne 0) {
                $stack.Push([pscustomobject]@{ Path = $entry; PostOrder = $false })
                continue
            }

            # Only touch the copy inside this eligible snapshot, never the source.
            if (($entryAttributes -band [IO.FileAttributes]::ReadOnly) -ne 0) {
                [IO.File]::SetAttributes(
                    $entry,
                    ($entryAttributes -band (-bnot [IO.FileAttributes]::ReadOnly))
                )
            }
            [IO.File]::Delete($entry)
        }
    }
}

<#
.SYNOPSIS
    Plans and, when permitted, applies snapshot retention.

.DESCRIPTION
    For a successful real backup, writes a Completed status and preliminary report before any
    destructive deletion. It then calculates retention candidates. Only successful real backups
    delete candidates; dry runs produce a plan without changing the filesystem. Failed individual
    deletions and retention scans are recorded as non-fatal errors.

.PARAMETER Config
    Resolved configuration containing Retention settings and TargetFolder.

.PARAMETER State
    Mutable execution state with snapshot path, counters, and event log.

.PARAMETER Status
    Status determined immediately before retention (SUCCESS/PARTIAL/FAILED).

.OUTPUTS
    None. Throws when pre-deletion snapshot finalization fails.

.NOTES
    The caller must hold the exclusive target lock during real backups. The current snapshot is
    never deleted. Invoke-BackupRetentionRemoval validates all entries and removes read-only
    snapshots in leaf-first order.
#>
function Invoke-BackupRetention {
    param(
        [object] $Config,
        [object] $State,
        [string] $Status
    )

    if (-not $Config.Retention.Enabled) {
        return
    }

    $snapshotPath = $State.SnapshotPath

    # Document the successful new snapshot BEFORE deleting older snapshots.
    if (-not $State.IsTest -and $Status -eq 'SUCCESS') {
        try {
            Write-BackupStatus $State 'Completed' $null ([DateTimeOffset]::Now)
            $initialReport = Format-BackupReport $State $Config $Status $null ([DateTimeOffset]::Now)
            [IO.File]::WriteAllText(
                ([IO.Path]::Combine($snapshotPath, 'backup-report.txt')),
                $initialReport,
                [Text.UTF8Encoding]::new($false)
            )
        }
        catch {
            throw "Could not finalize snapshot before retention: $($_.Exception.Message)"
        }
    }

    try {
        # Count the newly created snapshot only when the run succeeded.
        $planned = @(Get-BackupRetentionPlan $Config $snapshotPath ($Status -eq 'SUCCESS'))
        foreach ($path in $planned) {
            $State.RetentionPlanned.Add($path)
        }

        if (-not $State.IsTest -and $Status -eq 'SUCCESS') {
            foreach ($path in $State.RetentionPlanned) {
                try {
                    # Retain the same lock and never delete the current snapshot.
                    if ($path -eq $snapshotPath) { continue }

                    Invoke-BackupRetentionRemoval $path
                    $State.RetentionDeleted++
                    Add-BackupEvent $State 'INFO' "Retention deleted | $path"
                }
                catch {
                    $State.Errors++
                    Add-BackupEvent $State 'ERROR' "Retention failed | $path | $($_.Exception.Message)"
                    Write-Warning "Retention failed for '$path': $($_.Exception.Message)"
                }
            }
        }
    }
    catch {
        $State.Errors++
        Add-BackupEvent $State 'ERROR' "Retention scan failed | $($_.Exception.Message)"
        Write-Warning "Retention could not be evaluated: $($_.Exception.Message)"
    }
}

#endregion

#region Source preparation and traversal

<#
.SYNOPSIS
    Initializes execution statistics for one backup source.

.DESCRIPTION
    Constructs the source-specific counters and retains the effective source policies,
    verification settings, and metadata options. The returned object is registered with the
    overall execution state by Invoke-BackupSource.

.PARAMETER Source
    Fully resolved source configuration.

.OUTPUTS
    System.Management.Automation.PSCustomObject
    Mutable source statistics with the established PsMyBackup field names.

.NOTES
    Does not access the filesystem or mutate the overall execution state.
#>
function Get-BackupSourceStatistic {
    param([object] $Source)

    return [pscustomobject]@{
        Name = $Source.Name
        Path = $Source.Path
        Policies = $Source.Policies
        Verification = $Source.Verification
        Metadata = $Source.Metadata

        FilesCopied = 0
        BytesCopied = [long]0
        FilesPlanned = 0
        BytesPlanned = [long]0
        DirectoriesCopied = 0
        DirectoriesPlanned = 0
        Ignored = 0
        LinksSkipped = 0
        SkippedOnError = 0
        Errors = 0
        Retries = 0
        Verified = 0
    }
}

<#
.SYNOPSIS
    Validates and prepares one source for backup traversal.

.DESCRIPTION
    Records the source configuration, checks the source directory, applies MissingSource policy,
    rejects linked source roots, and creates the destination root for real backups. Updates
    directory counters on success.

.PARAMETER Source
    Fully resolved source configuration.

.PARAMETER State
    Mutable overall execution state.

.PARAMETER Stats
    Mutable source-specific statistics.

.PARAMETER DestinationRoot
    Destination path beneath the current snapshot.

.OUTPUTS
    System.Boolean
    True when traversal may begin; false when the source is skipped. Throws when the applicable
    source policy requires failure.

.NOTES
    During dry runs this function performs metadata inspection only and never creates the
    destination root. State.Sources is populated by the caller before this function is invoked.
#>
function Initialize-BackupSource {
    param(
        [object] $Source,
        [object] $State,
        [object] $Stats,
        [string] $DestinationRoot
    )

    Add-BackupEvent $State 'INFO' "Source $($Source.Name) | $($Source.Path) | MissingSource=$($Source.Policies.MissingSource) ItemError=$($Source.Policies.ItemError) ExistingFile=$($Source.Policies.ExistingFile) RetryCount=$($Source.Policies.RetryCount) Verification=$($Source.Verification.Mode)"
    Write-Verbose "Scanning source '$($Source.Name)': $($Source.Path)"

    if (-not [IO.Directory]::Exists($Source.Path)) {
        $State.Errors++
        $Stats.Errors++

        if ($Source.Policies.MissingSource -eq 'fail') {
            Add-BackupEvent $State 'ERROR' "Missing or inaccessible source | $($Source.Path)"
            throw "Stopped by MissingSource=fail: $($Source.Path)"
        }

        $State.SkippedOnError++
        $Stats.SkippedOnError++
        Add-BackupEvent $State 'WARN' "Missing source skipped | $($Source.Path)"
        Write-Warning "Missing source skipped: $($Source.Path)"
        return $false
    }

    try {
        # Recheck the source and existing ancestor directories immediately before processing. An
        # alias introduced since parsing must not be used.
        Assert-BackupPathWithoutLink $Source.Path

        # Never traverse a linked root, regardless of dry-run mode.
        if (([IO.File]::GetAttributes($Source.Path) -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'A source root cannot be a symbolic link or junction.'
        }

        if (-not $State.IsTest) {
            [void][IO.Directory]::CreateDirectory($DestinationRoot)
            $State.DirectoriesCopied++
            $Stats.DirectoriesCopied++
        }

        $State.DirectoriesPlanned++
        $Stats.DirectoriesPlanned++
    }
    catch {
        Register-BackupItemProblem $State $Stats 'Preparing source' $Source.Path $_.Exception.Message
        return $false
    }

    return $true
}

<#
.SYNOPSIS
    Creates and schedules an included subdirectory.

.DESCRIPTION
    Creates the destination directory for real backups, records planned directory counts, tracks
    it for later metadata preservation, and queues its children for iterative traversal. Creation
    errors are passed to the source-specific ItemError policy handler.

.PARAMETER Entry
    Original source directory path.

.PARAMETER Destination
    Corresponding destination directory path.

.PARAMETER Relative
    Path relative to the source root using forward slashes.

.PARAMETER State
    Overall execution state.

.PARAMETER Stats
    Current source statistics.

.PARAMETER Stack
    Pending traversal nodes.

.PARAMETER Directories
    Source/destination pairs used for directory metadata restoration.

.OUTPUTS
    None. Throws only when the ItemError policy requires failure.
#>
function Invoke-BackupDirectory {
    param(
        [string] $Entry,
        [string] $Destination,
        [string] $Relative,
        [object] $State,
        [object] $Stats,
        [Collections.Generic.Stack[object]] $Stack,
        [Collections.Generic.List[object]] $Directories
    )

    try {
        if (-not $State.IsTest) {
            [void][IO.Directory]::CreateDirectory($Destination)
            $State.DirectoriesCopied++
            $Stats.DirectoriesCopied++
        }

        $State.DirectoriesPlanned++
        $Stats.DirectoriesPlanned++

        $Directories.Add([pscustomobject]@{ From = $Entry; To = $Destination })
        $Stack.Push([pscustomobject]@{ Input = $Entry; Output = $Destination; Relative = $Relative })
    }
    catch {
        Register-BackupItemProblem $State $Stats 'Creating directory' $Destination $_.Exception.Message
    }
}

<#
.SYNOPSIS
    Restores metadata for included backup directories.

.DESCRIPTION
    Applies configured modification timestamps and filesystem attributes to backup directories
    after all children have been processed. Works from descendant directories to their parents and
    applies the source's ItemError policy if reading or writing metadata fails.

.PARAMETER Source
    Resolved source configuration with metadata preservation settings.

.PARAMETER State
    Overall state containing the dry-run flag.

.PARAMETER Stats
    Current source statistics for error reporting.

.PARAMETER Directories
    Source and destination directory pairs registered during traversal.

.OUTPUTS
    None. Throws only when ItemError=fail requires it.

.NOTES
    Skipped during dry runs or when neither metadata option is enabled. ReparsePoint attributes
    are never copied.
#>
function Restore-BackupDirectoryMetadataEntry {
    param(
        [object] $Source,
        [object] $State,
        [object] $Stats,
        [Collections.Generic.List[object]] $Directories
    )

    if ($State.IsTest -or
        -not ($Source.Metadata.PreserveTimestamps -or $Source.Metadata.PreserveAttributes)) {
        return
    }

    # Descendants first: creating children can change parent timestamps.
    for ($i = $Directories.Count - 1; $i -ge 0; $i--) {
        $dir = $Directories[$i]
        try {
            if ($Source.Metadata.PreserveTimestamps) {
                [IO.Directory]::SetLastWriteTimeUtc($dir.To, [IO.Directory]::GetLastWriteTimeUtc($dir.From))
            }
            if ($Source.Metadata.PreserveAttributes) {
                $attrs = [IO.File]::GetAttributes($dir.From)
                [IO.File]::SetAttributes($dir.To, $attrs -band (-bnot [IO.FileAttributes]::ReparsePoint))
            }
        }
        catch {
            Register-BackupItemProblem $State $Stats 'Preserving directory metadata' $dir.To $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Copies a file with the source-specific retry policy.

.DESCRIPTION
    Invokes the single-attempt atomic copy routine. On success, updates copy and verification
    counters, appends an optional manifest entry, and records per-file events. On failure, retries
    with the configured delay; after the final attempt, applies the ItemError policy.

.PARAMETER Entry
    Source file path.

.PARAMETER Destination
    Final destination file path.

.PARAMETER Relative
    Source-relative path for the manifest.

.PARAMETER Source
    Resolved source configuration and retry policy.

.PARAMETER Config
    Resolved global configuration, including manifest and logging options.

.PARAMETER State
    Overall execution state.

.PARAMETER Stats
    Current source statistics.

.OUTPUTS
    System.Boolean
    True when the copy succeeds, otherwise false if ItemError=skip. Throws when ItemError=fail.

.NOTES
    RetryCount is the number of additional attempts after the first. This helper is never invoked
    during -Test or -WhatIf.
#>
function Invoke-BackupFileWithRetry {
    param(
        [string] $Entry,
        [string] $Destination,
        [string] $Relative,
        [object] $Source,
        [object] $Config,
        [object] $State,
        [object] $Stats
    )

    for ($attempt = 0; $attempt -le $Source.Policies.RetryCount; $attempt++) {
        try {
            $copied = Invoke-BackupCopyOnce $Entry $Destination $Source $Config
            $State.FilesCopied++
            $Stats.FilesCopied++
            $State.BytesCopied += $copied.Size
            $Stats.BytesCopied += $copied.Size

            if ($Source.Verification.Mode -ne 'None') {
                $State.Verified++
                $Stats.Verified++
            }

            if ($Config.Manifest.Enabled) {
                $State.ManifestEntries.Add([pscustomobject]@{
                    path = ($Source.Name + '/' + $Relative)
                    size = $copied.Size
                    lastWriteTimeUtc = $copied.LastWriteTimeUtc
                    sha256 = $(if ($Config.Manifest.IncludeHashes) { $copied.Hash } else { $null })
                })
            }

            if ($Config.LogCopiedFiles) {
                Add-BackupEvent $State 'INFO' "Copied ($($copied.Size) bytes) | $Entry -> $Destination"
            }

            return $true
        }
        catch {
            if ($attempt -ge $Source.Policies.RetryCount) {
                Register-BackupItemProblem $State $Stats 'Copy/verify failed' $Entry $_.Exception.Message
            }
            else {
                $State.Retries++
                $Stats.Retries++
                Add-BackupEvent $State 'WARN' "Retry $($attempt + 1)/$($Source.Policies.RetryCount) | $Entry | $($_.Exception.Message)"
                Write-Verbose "Retry for '$Entry': $($_.Exception.Message)"
                if ($Source.Policies.RetryDelayMilliseconds -gt 0) {
                    Start-Sleep -Milliseconds $Source.Policies.RetryDelayMilliseconds
                }
            }
        }
    }

    return $false
}

<#
.SYNOPSIS
    Plans and optionally copies one included source file.

.DESCRIPTION
    Applies ExistingFile policy, reads source file size, and increments planned counters. A dry
    run only logs the planned copy. A real backup delegates copying and retries to
    Invoke-BackupFileWithRetry. Progress is updated once after each successful hundredth copy.

.PARAMETER Entry
    Source file path.

.PARAMETER Destination
    Final snapshot file path.

.PARAMETER Relative
    Source-relative path for manifest generation.

.PARAMETER Source
    Resolved source configuration.

.PARAMETER Config
    Resolved global configuration.

.PARAMETER State
    Overall execution state.

.PARAMETER Stats
    Current source statistics.

.OUTPUTS
    None. File statistics and events are stored in State and Stats.

.NOTES
    Existing destination conflicts are checked before planned counters, preserving the original
    behavior for -Test and real backups.
#>
function Invoke-BackupFile {
    param(
        [string] $Entry,
        [string] $Destination,
        [string] $Relative,
        [object] $Source,
        [object] $Config,
        [object] $State,
        [object] $Stats
    )

    if (([IO.File]::Exists($Destination) -or [IO.Directory]::Exists($Destination)) -and
        $Source.Policies.ExistingFile -ne 'overwrite') {
        Register-BackupExistingFile $State $Stats $Destination
        return
    }

    try {
        $expected = ([IO.FileInfo]::new($Entry)).Length
        $State.FilesPlanned++
        $Stats.FilesPlanned++
        $State.BytesPlanned += $expected
        $Stats.BytesPlanned += $expected
    }
    catch {
        Register-BackupItemProblem $State $Stats 'Reading file metadata' $Entry $_.Exception.Message
        return
    }

    if ($State.IsTest) {
        if ($Config.LogCopiedFiles) {
            Add-BackupEvent $State 'INFO' "Would copy ($expected bytes) | $Entry -> $Destination"
        }
        return
    }

    $copied = Invoke-BackupFileWithRetry `
        -Entry $Entry -Destination $Destination -Relative $Relative `
        -Source $Source -Config $Config -State $State -Stats $Stats

    # Update progress only for the copy that reaches a 100-file boundary. Avoid repeated progress
    # messages when subsequent files are skipped.
    if ($copied -and $State.FilesCopied -gt 0 -and ($State.FilesCopied % 100) -eq 0) {
        Write-Progress -Id 1 -Activity 'PsMyBackup' -Status "$($Source.Name): $($State.FilesCopied) files copied"
    }
}

<#
.SYNOPSIS
    Traverses a backup source directory and dispatches included entries.

.DESCRIPTION
    Performs iterative depth-first traversal from the source root. It enumerates entries, skips
    links and ignore matches, and delegates directories to Invoke-BackupDirectory and files to
    Invoke-BackupFile. Enumeration and attribute errors obey ItemError policy.

.PARAMETER Source
    Resolved source configuration containing Path and Patterns.

.PARAMETER Config
    Resolved global configuration for logging and manifests.

.PARAMETER State
    Overall execution state.

.PARAMETER Stats
    Current source statistics.

.PARAMETER DestinationRoot
    Destination directory belonging to this source.

.PARAMETER Directories
    Source/destination directory pairs to restore metadata later.

.OUTPUTS
    None. Changes are recorded in State and Stats.

.NOTES
    Ignored directories are not traversed, so descendants cannot be re-included by later negated
    ignore patterns. Reparse points are skipped rather than dereferenced.
#>
function Invoke-BackupDirectoryTraversal {
    param(
        [object] $Source,
        [object] $Config,
        [object] $State,
        [object] $Stats,
        [string] $DestinationRoot,
        [Collections.Generic.List[object]] $Directories
    )

    $stack = [Collections.Generic.Stack[object]]::new()
    $stack.Push([pscustomobject]@{ Input = $Source.Path; Output = $DestinationRoot; Relative = '' })

    while ($stack.Count -gt 0) {
        $current = $stack.Pop()
        try {
            $entries = [IO.Directory]::GetFileSystemEntries($current.Input)
        }
        catch {
            Register-BackupItemProblem $State $Stats 'Listing directory' $current.Input $_.Exception.Message
            continue
        }

        foreach ($entry in $entries) {
            $leaf = [IO.Path]::GetFileName($entry)
            $relative = if ($current.Relative) { "$($current.Relative)/$leaf" } else { $leaf }
            $destination = [IO.Path]::Combine($current.Output, $leaf)

            try {
                $attributes = [IO.File]::GetAttributes($entry)
            }
            catch {
                Register-BackupItemProblem $State $Stats 'Reading attributes' $entry $_.Exception.Message
                continue
            }

            if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                $State.LinksSkipped++
                $Stats.LinksSkipped++
                Add-BackupEvent $State 'INFO' "Link or junction skipped | $entry"
                continue
            }

            $isDir = ($attributes -band [IO.FileAttributes]::Directory) -ne 0
            if (Test-BackupIgnored $relative $isDir $Source.Patterns) {
                $State.Ignored++
                $Stats.Ignored++
                if ($Config.LogCopiedFiles) { Add-BackupEvent $State 'INFO' "Ignored | $entry" }
                continue
            }

            if ($isDir) {
                Invoke-BackupDirectory `
                    -Entry $entry -Destination $destination -Relative $relative `
                    -State $State -Stats $Stats -Stack $stack -Directories $Directories
                continue
            }

            Invoke-BackupFile `
                -Entry $entry -Destination $destination -Relative $relative `
                -Source $Source -Config $Config -State $State -Stats $Stats
        }
    }
}

<#
.SYNOPSIS
    Processes one configured backup source.

.DESCRIPTION
    Registers source statistics, validates and prepares the source, traverses all included
    entries, and restores directory metadata after processing. Each task is delegated to a private
    helper to keep this coordinator small. Supports read-only dry runs and source-specific error
    and retry policies.

.PARAMETER Source
    Resolved source configuration, including name, path, ignore patterns, policies, verification,
    and metadata options.

.PARAMETER Config
    Resolved global configuration for logging, manifests, and other settings.

.PARAMETER State
    Mutable execution state collecting counters, events, and source results.

.OUTPUTS
    None. Updates State.Sources, aggregate counters, events, and manifests.

.EXAMPLE
    Invoke-BackupSource -Source $config.Sources[0] -Config $config -State $state

.NOTES
    This private function is called by Invoke-BackupSourceCollection. The caller holds the
    target lock during real backups. The function never follows reparse points or hashes files
    during a dry
    run.
#>
function Invoke-BackupSource {
    param(
        [object] $Source,
        [object] $Config,
        [object] $State
    )

    $stats = Get-BackupSourceStatistic -Source $Source
    $State.Sources.Add($stats)

    $root = [IO.Path]::Combine($State.SnapshotPath, $Source.Name)
    if (-not (Initialize-BackupSource -Source $Source -State $State -Stats $stats -DestinationRoot $root)) {
        return
    }

    # Keep source root and descendants for post-copy metadata restoration.
    $directories = [Collections.Generic.List[object]]::new()
    $directories.Add([pscustomobject]@{ From = $Source.Path; To = $root })

    Invoke-BackupDirectoryTraversal `
        -Source $Source -Config $Config -State $State -Stats $stats `
        -DestinationRoot $root -Directories $directories

    Restore-BackupDirectoryMetadataEntry -Source $Source -State $State -Stats $stats -Directories $directories
}

#endregion

#region Windows sleep prevention

<#
.SYNOPSIS
    Requests that Windows prevent automatic idle sleep during a real backup.

.DESCRIPTION
    Records the current thread's execution state, then enables ES_SYSTEM_REQUIRED together
    with ES_CONTINUOUS. The saved state must be restored from the same thread in a finally block.

    The native API is loaded on demand, only when the optional PreventSleep switch is used.

.OUTPUTS
    System.UInt32

    Returns the previous thread execution state to be restored after the backup.
#>
function Enter-BackupSleepPrevention {
    [CmdletBinding()]
    param()

    if (-not $IsWindows) {
        throw '-PreventSleep is supported only on Windows.'
    }

    if (-not ('PsMyBackup.SleepPreventionNative' -as [type])) {
        $definition = @'
using System.Runtime.InteropServices;

namespace PsMyBackup
{
    public static class SleepPreventionNative
    {
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern uint SetThreadExecutionState(uint flags);
    }
}
'@
        Add-Type -TypeDefinition $definition -ErrorAction Stop
    }

    $esContinuous = [uint32]2147483648
    $esSystemRequired = [uint32]1
    $flags = [uint32]($esContinuous -bor $esSystemRequired)

    $previousState = [PsMyBackup.SleepPreventionNative]::SetThreadExecutionState($flags)
    if ($previousState -eq 0) {
        $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "Unable to prevent automatic sleep. Windows error: $errorCode"
    }

    return [uint32]$previousState
}

<#
.SYNOPSIS
    Restores the execution state saved before enabling Windows sleep prevention.

.DESCRIPTION
    Retains any execution-state requests that were present before the backup, including requests
    from an outer caller. Restoration must take place on the same thread as the initial request.

.PARAMETER PreviousState
    Execution state returned by Enter-BackupSleepPrevention.
#>
function Exit-BackupSleepPrevention {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [uint32] $PreviousState
    )

    $esContinuous = [uint32]2147483648
    $flags = [uint32]($PreviousState -bor $esContinuous)
    $result = [PsMyBackup.SleepPreventionNative]::SetThreadExecutionState($flags)

    if ($result -eq 0) {
        $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        Write-Warning "Unable to restore the previous Windows execution state. Error: $errorCode"
    }
}

#endregion

#region Backup workflow orchestration

<#
.SYNOPSIS
    Creates the mutable execution state for one backup run.

.DESCRIPTION
    Initializes snapshot identity, execution timestamps, counters, and collections used by source
    processing, reporting, manifests, and retention. This operation does not access or modify the
    filesystem.

.PARAMETER SnapshotPath
    Selected absolute path for the new snapshot.

.PARAMETER IsTest
    Indicates a read-only dry run.

.OUTPUTS
    System.Management.Automation.PSCustomObject
    The initialized execution state.

.EXAMPLE
    $state = Get-BackupExecutionState -SnapshotPath $path -IsTest $true
#>
function Get-BackupExecutionState {
    param(
        [string] $SnapshotPath,
        [bool] $IsTest
    )

    return [pscustomobject]@{
        StartedAt = [DateTimeOffset]::Now
        SnapshotId = [Guid]::NewGuid().ToString('D')
        SnapshotPath = $SnapshotPath
        IsTest = $IsTest

        FilesCopied = 0
        BytesCopied = [long]0
        FilesPlanned = 0
        BytesPlanned = [long]0
        DirectoriesCopied = 0
        DirectoriesPlanned = 0
        Ignored = 0
        LinksSkipped = 0
        SkippedOnError = 0
        Errors = 0
        Retries = 0
        Verified = 0
        RetentionDeleted = 0

        RetentionPlanned = [Collections.Generic.List[string]]::new()
        Events = [Collections.Generic.List[string]]::new()
        Sources = [Collections.Generic.List[object]]::new()
        ManifestEntries = [Collections.Generic.List[object]]::new()
    }
}

<#
.SYNOPSIS
    Runs the optional disk-space and target-write preflight checks.

.DESCRIPTION
    Before source processing, real backups may scan source sizes and perform a temporary target
    write probe. During dry runs, the disk-space check is deferred until after source processing
    so it can use BytesPlanned without an additional source scan. A dry run never writes probe
    files.

.PARAMETER Config
    The resolved backup configuration.

.PARAMETER State
    Mutable state containing IsTest and BytesPlanned.

.PARAMETER AfterSources
    Runs the post-scan dry-run disk-space check instead of the initial checks.

.OUTPUTS
    None. Throws when a required preflight check fails.

.EXAMPLE
    Invoke-BackupPreflight -Config $config -State $state
    Invoke-BackupPreflight -Config $config -State $state -AfterSources
#>
function Invoke-BackupPreflight {
    param(
        [object] $Config,
        [object] $State,
        [switch] $AfterSources
    )

    if ($AfterSources) {
        # Dry runs use the sizes collected by Invoke-BackupSource.
        if ($State.IsTest -and $Config.Preflight.CheckDiskSpace) {
            Assert-BackupFreeSpace $Config $State.BytesPlanned $State
        }
        return
    }

    # A real backup may perform an optional additional full scan.
    if ($Config.Preflight.CheckDiskSpace -and -not $State.IsTest) {
        Write-Verbose 'Optional preflight: scanning all sources to estimate required space.'
        $required = Get-BackupRequiredByteCount $Config
        Assert-BackupFreeSpace $Config $required $State
    }

    # Never create a probe file during -Test or -WhatIf.
    if ($Config.Preflight.CheckTargetWrite -and -not $State.IsTest) {
        Test-BackupTargetWrite $Config.TargetFolder
        Add-BackupEvent $State 'INFO' 'Preflight write probe passed'
    }
}

<#
.SYNOPSIS
    Processes configured sources with top-level PowerShell progress reporting.

.DESCRIPTION
    Calls Invoke-BackupSource for each source in configuration order and displays source-level
    progress. It does not decide error policy or catch failures; those responsibilities remain
    with Invoke-BackupWork.

.PARAMETER Config
    Resolved configuration containing the Sources collection.

.PARAMETER State
    Mutable execution state.

.OUTPUTS
    None.
#>
function Invoke-BackupSourceCollection {
    param(
        [object] $Config,
        [object] $State
    )

    $totalSources = $Config.Sources.Count

    for ($i = 0; $i -lt $totalSources; $i++) {
        $source = $Config.Sources[$i]

        Write-Progress `
            -Id 1 `
            -Activity 'PsMyBackup' `
            -Status "$($source.Name) ($($i + 1)/$totalSources)" `
            -PercentComplete ([int](100 * $i / $totalSources))

        Invoke-BackupSource $source $Config $State
    }
}

<#
.SYNOPSIS
    Executes preflight and source processing while recording fatal errors.

.DESCRIPTION
    Runs the initial preflight, all sources, and the optional post-scan dry-run disk-space check.
    An execution error is logged as FATAL and returned as text so final reporting can still
    proceed. The PowerShell progress display is always completed, even if an operation fails.

.PARAMETER Config
    Resolved backup configuration.

.PARAMETER State
    Mutable execution state.

.OUTPUTS
    System.String
    Fatal error message, or null when source processing succeeds.
#>
function Invoke-BackupWork {
    param(
        [object] $Config,
        [object] $State
    )

    try {
        Invoke-BackupPreflight -Config $Config -State $State
        Invoke-BackupSourceCollection -Config $Config -State $State
        Invoke-BackupPreflight -Config $Config -State $State -AfterSources
    }
    catch {
        # Keep operational failures reportable rather than abandoning the run.
        $fatalError = $_.Exception.Message
        Add-BackupEvent $State 'FATAL' $fatalError
        return $fatalError
    }
    finally {
        Write-Progress -Id 1 -Activity 'PsMyBackup' -Completed
    }

    return $null
}

#endregion

#region Snapshot completion and public result

<#
.SYNOPSIS
    Calculates the overall backup execution status.

.DESCRIPTION
    Returns FAILED when a fatal error is present, PARTIAL when non-fatal errors are recorded, and
    SUCCESS otherwise. Used both before and after retention because retention may add errors.

.PARAMETER State
    Execution state containing the Errors counter.

.PARAMETER FatalError
    Fatal error message, if any.

.OUTPUTS
    System.String
    SUCCESS, PARTIAL, or FAILED.
#>
function Get-BackupExecutionStatus {
    param(
        [object] $State,
        [string] $FatalError
    )

    if ($FatalError) { return 'FAILED' }
    if ($State.Errors -gt 0) { return 'PARTIAL' }
    return 'SUCCESS'
}

<#
.SYNOPSIS
    Finalizes a backup snapshot and creates the final report.

.DESCRIPTION
    Recalculates the final status after retention, formats the report, and writes the final status
    JSON and report text for real backups. During dry runs, the formatted report is returned
    without filesystem changes.

.PARAMETER Config
    Resolved backup configuration.

.PARAMETER State
    Mutable execution state.

.PARAMETER FatalError
    Fatal error from source processing or manifest creation, if any.

.OUTPUTS
    System.Management.Automation.PSCustomObject
    Final status, completion time, report text, and optional report path.
#>
function Complete-BackupSnapshot {
    param(
        [object] $Config,
        [object] $State,
        [string] $FatalError
    )

    $finishedAt = [DateTimeOffset]::Now
    $status = Get-BackupExecutionStatus $State $FatalError
    $markerStatus = switch ($status) {
        'SUCCESS' { 'Completed' }
        'PARTIAL' { 'Partial' }
        default   { 'Failed' }
    }

    $reportText = Format-BackupReport $State $Config $status $FatalError $finishedAt
    $reportPath = $null

    if (-not $State.IsTest) {
        $reportPath = [IO.Path]::Combine($State.SnapshotPath, 'backup-report.txt')
        try {
            Write-BackupStatus $State $markerStatus $FatalError $finishedAt
            [IO.File]::WriteAllText(
                $reportPath,
                $reportText,
                [Text.UTF8Encoding]::new($false)
            )
        }
        catch {
            throw "Snapshot '$($State.SnapshotPath)' may be incomplete. Failed writing status/report: $($_.Exception.Message)"
        }
    }

    return [pscustomobject]@{
        Status = $status
        FinishedAt = $finishedAt
        ReportText = $reportText
        ReportPath = $reportPath
    }
}

<#
.SYNOPSIS
    Builds the public PsMyBackup.Result object.

.DESCRIPTION
    Projects the execution state and finalization information into the established public result
    shape. Paths to persisted files are null for dry runs. ManifestPath is populated only when its
    file exists.

.PARAMETER Config
    Resolved backup configuration.

.PARAMETER State
    Execution state with counters, events, and per-source results.

.PARAMETER Completion
    Object returned by Complete-BackupSnapshot.

.PARAMETER FatalError
    Optional fatal error message.

.OUTPUTS
    PsMyBackup.Result Structured result returned from Backup-MyFiles.
#>
function Get-BackupResult {
    param(
        [object] $Config,
        [object] $State,
        [object] $Completion,
        [string] $FatalError
    )

    $snapshotPath = $State.SnapshotPath
    $isTest = $State.IsTest
    $finishedAt = $Completion.FinishedAt

    return [pscustomobject]@{
        PSTypeName = 'PsMyBackup.Result'

        Status = $Completion.Status
        IsTest = $isTest

        ConfigPath = $Config.FilePath
        SnapshotPath = $snapshotPath
        ReportPath = $Completion.ReportPath

        StatusPath = $(
            if ($isTest) {
                $null
            }
            else {
                [IO.Path]::Combine($snapshotPath, 'backup-status.json')
            }
        )

        ManifestPath = $(
            if ($isTest -or
                -not $Config.Manifest.Enabled -or
                -not [IO.File]::Exists(
                    [IO.Path]::Combine($snapshotPath, 'backup-manifest.json')
                )) {
                $null
            }
            else {
                [IO.Path]::Combine($snapshotPath, 'backup-manifest.json')
            }
        )

        StartedAt = $State.StartedAt
        FinishedAt = $finishedAt
        Duration = $finishedAt - $State.StartedAt

        FilesCopied = $State.FilesCopied
        BytesCopied = $State.BytesCopied
        FilesPlanned = $State.FilesPlanned
        BytesPlanned = $State.BytesPlanned
        DirectoriesCopied = $State.DirectoriesCopied
        DirectoriesPlanned = $State.DirectoriesPlanned
        Ignored = $State.Ignored
        LinksSkipped = $State.LinksSkipped
        Verified = $State.Verified
        Retries = $State.Retries
        SkippedOnError = $State.SkippedOnError
        Errors = $State.Errors
        FatalError = $FatalError
        RetentionPlanned = $State.RetentionPlanned.ToArray()
        RetentionDeleted = $State.RetentionDeleted
        Sources = $State.Sources.ToArray()
        Events = $State.Events.ToArray()
        ReportText = $Completion.ReportText
    }
}

#endregion

#region Public commands

function Backup-MyFiles {
    <#
    .SYNOPSIS
        Creates a timestamped backup of configured files and folders.

    .DESCRIPTION
        Executes a backup operation using a PowerShell Data File (.psd1) containing source 
        directories, a target directory, and optional backup policies.

        Each backup creates a new timestamped snapshot directory beneath the configured target 
        directory.

        The function supports:

        - Multiple source directories.
        - Global and source-specific backup policies.
        - File and directory exclusion patterns.
        - Optional file integrity verification.
        - Optional disk-space and target write-permission checks.
        - Atomic file copying using temporary files.
        - Configurable retry policies.
        - File metadata preservation.
        - Optional JSON manifest generation.
        - Configurable snapshot retention.
        - Exclusive destination locking.
        - Optional prevention of automatic Windows sleep during real backups.
        - PowerShell progress reporting and verbose output.
        - Structured results and detailed execution reports.

        Backup execution consists of the following stages:

        1. Load and validate the configuration.
        2. Determine whether the operation is a dry run.
        3. Optionally prevent Windows idle sleep and acquire an exclusive destination lock.
        4. Generate a unique timestamped snapshot path.
        5. Initialize the backup execution state.
        6. Create the snapshot and initial status document.
        7. Perform optional preflight checks.
        8. Process all configured source directories.
        9. Optionally generate a JSON manifest.
        10. Calculate and apply snapshot retention.
        11. Finalize the snapshot status and execution report.
        12. Return a structured backup result.
        13. Release the destination lock and restore the previous execution state if requested.

        Dry-run execution is supported through the Test switch or PowerShell's standard WhatIf 
        functionality.

        Dry runs scan source directories and calculate planned backup statistics without creating, 
        copying, modifying, or deleting filesystem entries.

        The function distinguishes three execution results:

        SUCCESS
            The backup completed without reported errors.

        PARTIAL
            The backup completed with one or more non-fatal errors.

        FAILED
            The backup encountered a fatal error.

        Operational failures are represented by a structured result and a PowerShell error record.

        Invalid configurations and certain initialization or reporting failures cause terminating 
        exceptions.

    .PARAMETER ConfigPath
        Path to the PsMyBackup PSD1 configuration file.

        Defaults to:

            ./backup.psd1

        The configuration defines the backup sources, target directory, global policies, 
        source-specific overrides, and optional features.

    .PARAMETER Test
        Performs a read-only dry run.

        Source directories are scanned and planned file counts and sizes are calculated.

        No snapshot directories, lock files, manifests, reports, or temporary probe files are 
        created.

        No files are copied or deleted.

        Expensive content hashing is not performed.

        When disk-space preflight is enabled, available disk space may still be queried without 
        modifying the filesystem.

        The generated report is returned through the ReportText property of the result object.

    .PARAMETER PreventSleep
        Prevents automatic Windows idle sleep while a real backup runs. Uses the native Windows
        SetThreadExecutionState API; no change to Windows power-plan settings is required.

        Does not keep the display on. Does not prevent explicit sleep, shutdown, or necessarily
        closing a laptop lid. The previous execution state is restored in a finally block.

        This switch is ignored for -Test and -WhatIf dry runs. On Linux, requesting it for a
        real backup causes a terminating error; normal backups remain supported on Linux.

    .PARAMETER WhatIf
        Displays the intended backup operation without applying filesystem modifications.

        This is a standard PowerShell common parameter provided through SupportsShouldProcess.

        When the operation is declined by ShouldProcess, the function executes in dry-run mode.

    .OUTPUTS
        PsMyBackup.Result

        Returns a structured PowerShell object containing:

        - Status
        - IsTest
        - ConfigPath
        - SnapshotPath
        - ReportPath
        - StatusPath
        - ManifestPath
        - StartedAt
        - FinishedAt
        - Duration
        - FilesCopied
        - BytesCopied
        - FilesPlanned
        - BytesPlanned
        - DirectoriesCopied
        - DirectoriesPlanned
        - Ignored
        - LinksSkipped
        - Verified
        - Retries
        - SkippedOnError
        - Errors
        - FatalError
        - RetentionPlanned
        - RetentionDeleted
        - Sources
        - Events
        - ReportText

    .EXAMPLE
        Backup-MyFiles -ConfigPath './backup.psd1'

        Executes a backup using the specified configuration.

    .EXAMPLE
        $result = Backup-MyFiles -ConfigPath './backup.psd1' -Test

        $result.Status
        $result.FilesPlanned
        $result.BytesPlanned
        $result.ReportText

        Performs a dry run and inspects the planned backup.

    .EXAMPLE
        Backup-MyFiles -ConfigPath './backup.psd1' -WhatIf

        Uses PowerShell's native WhatIf functionality to perform a read-only preview.

    .EXAMPLE
        Backup-MyFiles -ConfigPath './backup.psd1' -PreventSleep

        Runs a Windows backup while preventing automatic idle sleep until the operation finishes.

    .EXAMPLE
        $result = Backup-MyFiles -ConfigPath './backup.psd1' -Verbose

        Executes the backup with additional diagnostic output.

    .EXAMPLE
        $result = Backup-MyFiles `
            -ConfigPath './backup.psd1' `
            -ErrorAction Stop

        Executes the backup and converts a reported FAILED result into a terminating error.

    .NOTES
        The function is the public entry point of the PsMyBackup module.

        Configuration parsing and validation are delegated to Read-BackupConfiguration.

        Individual sources are processed by Invoke-BackupSource.

        The function coordinates backup execution but delegates file copying, hashing, reporting, 
        and retention planning to specialized private functions.

        An exclusive destination lock is held throughout a normal backup operation, including 
        retention processing.

        Dry runs do not acquire this lock.

        Snapshot status documents use the PsMyBackup.Snapshot format and are written to 
        backup-status.json.

        Human-readable reports are written to backup-report.txt.

        Retention deletion is performed only after a successful backup. Retention candidates can 
        also be calculated during dry runs.

        The function does not implement restore operations.
    #>

    [CmdletBinding(
        SupportsShouldProcess = $true,
        ConfirmImpact = 'Medium'
    )]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseSingularNouns', '',
        Justification = 'We want to use the name Backup-MyFiles as our established public command name. Basta!'
    )]
    param(
        [Parameter(Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $ConfigPath = './backup.psd1',

        [switch] $Test,

        [switch] $PreventSleep
    )

    # Resolve configuration first; invalid configurations must still throw.
    $config = Read-BackupConfiguration $ConfigPath

    $isTest = [bool]$Test
    if (-not $isTest -and
        -not $PSCmdlet.ShouldProcess(
            $config.TargetFolder,
            'Create timestamped snapshot and apply configured retention'
        )) {
        $isTest = $true
    }

    $lock = $null
    $snapshotPath = $null
    $previousSleepState = $null

    try {
        # Keep the request active through final reporting and lock disposal. Dry runs do not
        # change the Windows execution state, even when -PreventSleep is specified.
        if ($PreventSleep -and -not $isTest) {
            $previousSleepState = Enter-BackupSleepPrevention
        }

        if (-not $isTest) {
            # Revalidate existing target ancestors before creating directories.
            Assert-BackupPathWithoutLink $config.TargetFolder
            [void][IO.Directory]::CreateDirectory($config.TargetFolder)
            $lock = Enter-BackupLock $config.TargetFolder
        }

        $snapshotPath = Get-BackupSnapshotPath $config.TargetFolder $config.Policies
        $state = Get-BackupExecutionState -SnapshotPath $snapshotPath -IsTest $isTest

        Add-BackupEvent `
            $state 'INFO' `
            "$(if ($isTest) { 'Dry run' } else { 'Backup' }) started | $snapshotPath"

        if (-not $isTest) {
            [void][IO.Directory]::CreateDirectory($snapshotPath)
            Write-BackupStatus $state 'Running' $null $state.StartedAt
        }

        # Record execution failures so the final report can still be written.
        $fatalError = Invoke-BackupWork -Config $config -State $state

        # A manifest failure is fatal when manifest output was requested.
        if (-not $isTest -and $null -eq $fatalError -and $config.Manifest.Enabled) {
            try {
                Write-BackupManifest -State $state
            }
            catch {
                $fatalError = "Unable to write manifest: $($_.Exception.Message)"
                Add-BackupEvent $state 'FATAL' $fatalError
            }
        }

        $status = Get-BackupExecutionStatus -State $state -FatalError $fatalError
        Invoke-BackupRetention -Config $config -State $state -Status $status

        # Retention may add non-fatal errors, so calculate status again.
        $completion = Complete-BackupSnapshot `
            -Config $config `
            -State $state `
            -FatalError $fatalError

        $result = Get-BackupResult `
            -Config $config `
            -State $state `
            -Completion $completion `
            -FatalError $fatalError

        Write-Verbose "PsMyBackup $($completion.Status) | dry-run=$isTest | copied=$($state.FilesCopied) | planned=$($state.FilesPlanned) | errors=$($state.Errors)"

        # Preserve the public behavior: a FAILED result also emits an error. -ErrorAction Stop
        # makes this terminating AFTER reporting is complete.
        if ($completion.Status -eq 'FAILED') {
            $record = [Management.Automation.ErrorRecord]::new(
                [InvalidOperationException]::new("PsMyBackup FAILED: $fatalError"),
                'PsMyBackupFailed',
                [Management.Automation.ErrorCategory]::InvalidOperation,
                $result
            )
            $PSCmdlet.WriteError($record)
        }

        return $result

    }
    finally {
        try {
            # Keep the persistent lock file; dispose only the acquired handle.
            if ($null -ne $lock) {
                $lock.Dispose()
            }
        }
        finally {
            # Windows execution-state requests are thread-specific. Restore the exact state
            # saved before this backup; do not clear an outer caller's existing request.
            if ($null -ne $previousSleepState) {
                Exit-BackupSleepPrevention -PreviousState $previousSleepState
            }
        }
    }
}

#endregion

Export-ModuleMember -Function Backup-MyFiles

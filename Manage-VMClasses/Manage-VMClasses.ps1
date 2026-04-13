# Copyright (c) 2026 Broadcom. All Rights Reserved.
# Broadcom Confidential. The term "Broadcom" refers to Broadcom Inc.
# and/or its subsidiaries.
#
# =============================================================================
#
# SOFTWARE LICENSE AGREEMENT
#
# Copyright (c) CA, Inc. All rights reserved.
#
# You are hereby granted a non-exclusive, worldwide, royalty-free license
# under CA, Inc.'s copyrights to use, copy, modify, and distribute this
# software in source code or binary form for use in connection with CA, Inc.
# products.
#
# This copyright notice shall be included in all copies or substantial
# portions of the software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
# DEALINGS IN THE SOFTWARE.
#
# =============================================================================
#
# Manage-VMClasses.ps1 — Backup, discover, apply, list, and delete vCenter Supervisor VM classes.
#
# PowerShell script: Manage-VMClasses
# Last modified: 2026-04-08

#Requires -Version 7.4
# Requires VCF PowerCLI 9.0 or later (VMware.VimAutomation.Core). The module is loaded lazily on
# first vCenter connection so the menu appears immediately on startup.

<#
    .SYNOPSIS
    Manages vCenter Supervisor VM classes: discovers configurations from live VMs, applies class
    definitions from JSON, lists current classes, or deletes named classes.

    .DESCRIPTION
    Connects to vCenter using -VcenterServer and -VcenterUser (prompts when omitted). Five
    actions are available via -Action; prompts interactively when omitted:

    Backup: Queries every VM class currently defined on vCenter and writes the definitions
    to a JSON file in the same format as vmClasses.json. The backup file can be used directly
    with -Action Update to restore or re-apply classes. The default output path is
    vmClasses-backup.json next to this script; pass -JsonPath to override. Pass -Force to
    overwrite an existing file without prompting. Classes with DynamicDirectPathIO devices are
    included in the backup without that configuration, and a warning is logged for each.

    Update: Reads the JSON class definition file and applies it to vCenter as a true
    upsert — classes not present on vCenter are created (POST), classes that differ from the file
    are patched (PATCH), and classes that already match are skipped. Use -VmClassName to target a
    single class by name, or pass "all" to process every entry in the file. When -VmClassName is
    omitted in an interactive session, the script prompts for a name.

    Discover: Connects to vCenter, enumerates all VMs, and groups them by unique CPU/memory/GPU
    configuration. An interactive selection table lets you choose which groups to export. The
    selected configurations are written to -JsonPath (default: vmClasses.json) as a JSON array
    ready for use with -Action Update. If the output file already exists, the script prompts
    to overwrite or enter a different path. Pass -Force to overwrite without prompting. Pass
    -SaveAll to skip the selection table and save every discovered configuration automatically.

    List: Prints a table of all VM classes on vCenter (Name, CpuCount, MemoryMB, Gpu). No JSON
    file is required.

    Delete: Queries vCenter for all VM classes, filters out the 16 built-in defaults, and
    removes the remaining custom classes. Pass -VmClassName with a specific name to delete a
    single class, or "all" to delete every custom class. An interactive session presents a
    multi-select TUI when -VmClassName is omitted. A missing class is reported and the script
    exits without calling the delete API. Built-in default class names are never deleted.

    JSON file: Defaults to vmClasses.json next to this script for all actions. Pass -JsonPath
    to override. When the file is required and missing, an interactive session prompts for a path
    with Y/N retry. The file must be a JSON array; each object requires name, cpuCount, memoryMB,
    cpuCommitment, and memoryCommitment. The description field is optional.

    Non-interactive runs: set VCENTER_PASSWORD and pass -VcenterServer and -VcenterUser.

    .PARAMETER Force
    Suppress the overwrite prompt for Discover or Backup when the output file already exists.
    Useful for automation and scheduled runs where the output file should be refreshed silently.

    .PARAMETER JsonPath
    Path to the JSON class definition file. For Update and Delete, defaults to vmClasses.json
    next to this script. For Discover, defaults to vmClasses.json. For Backup, defaults to
    vmClasses-backup-<VcenterServer>.json next to this script.

    .PARAMETER LogLevel
    Minimum level for console output (DEBUG, INFO, ADVISORY, WARNING, ERROR). All levels are
    written to the log file. Default: INFO.

    .PARAMETER Action
    The action to perform: Discover, List, Update, or Delete. Prompts interactively when omitted.

    .PARAMETER SaveAll
    Skip the interactive configuration selection for Discover and save every discovered VM
    configuration to the output file automatically. Combine with -Force for fully non-interactive
    Discover runs.

    .PARAMETER VcenterServer
    vCenter Server FQDN or IP. Prompts interactively when omitted. In interactive menu mode, a
    value passed on the command line (or VCENTER_SERVER when set) is used as the default for each
    workflow connection prompt.

    .PARAMETER VcenterUser
    vCenter sign-in name (for example administrator@vsphere.local). Prompts interactively when
    omitted.

    .PARAMETER VmClassName
    VM class name to target for Update or Delete, or "all" to process every entry in the JSON
    file. Required for non-interactive Update and Delete; prompts when omitted in an interactive
    session.

    .EXAMPLE
    .\Manage-VMClasses.ps1 -Action Discover -VcenterServer vcenter.example.com -VcenterUser administrator@vsphere.local

    Scans vCenter VMs and writes vmClasses.json (prompts to overwrite if the file already exists).

    .EXAMPLE
    .\Manage-VMClasses.ps1 -Action Discover -VcenterServer vcenter.example.com -VcenterUser administrator@vsphere.local -Force

    Same as above but overwrites an existing vmClasses.json without prompting.

    .EXAMPLE
    .\Manage-VMClasses.ps1 -Action Backup -VcenterServer vcenter.example.com -VcenterUser administrator@vsphere.local

    Saves all VM classes from vCenter to vmClasses-backup-vcenter.example.com.json.

    .EXAMPLE
    .\Manage-VMClasses.ps1 -Action Backup -VcenterServer vcenter.example.com -VcenterUser administrator@vsphere.local -JsonPath .\backup-$(Get-Date -Format yyyyMMdd).json -Force

    Saves a dated backup file and overwrites it if it already exists.

    .EXAMPLE
    .\Manage-VMClasses.ps1 -Action Discover -VcenterServer vcenter.example.com -VcenterUser administrator@vsphere.local -SaveAll -Force

    Saves all discovered VM configurations non-interactively, overwriting any existing output file.

    .EXAMPLE
    .\Manage-VMClasses.ps1 -Action Update -VcenterServer vcenter.example.com -VcenterUser administrator@vsphere.local -VmClassName all

    Applies all classes from vmClasses.json to vCenter.

    .EXAMPLE
    .\Manage-VMClasses.ps1 -Action Update -JsonPath .\vmClasses-inventory-20260327-154027.json -VcenterServer vcenter.example.com -VmClassName all

    Applies all classes from the specified file to vCenter.

    .EXAMPLE
    .\Manage-VMClasses.ps1 -Action List -VcenterServer vcenter.example.com

    Lists all VM classes on vCenter.

    .EXAMPLE
    .\Manage-VMClasses.ps1 -Action Delete -VmClassName my-vm-class -VcenterServer vcenter.example.com

    Deletes a single named VM class from vCenter.

    .NOTES
    Requires PowerShell 7.4+ and VCF.PowerCLI 9.0+.
    Non-interactive authentication: export VCENTER_PASSWORD before calling this script. Optional
    defaults for interactive menu mode: VCENTER_SERVER and VCENTER_USER when -VcenterServer /
    -VcenterUser are omitted.

    .LINK
    https://developer.broadcom.com/xapis/vsphere-automation-api/latest/vcenter/namespace-management/virtual-machine-classes/
#>

[CmdletBinding(ConfirmImpact = "None", DefaultParameterSetName = "Execute", SupportsShouldProcess = $true)]
Param (
    [Parameter(Mandatory = $false, ParameterSetName = "Help")] [Switch]$Detailed,
    [Parameter(Mandatory = $false, ParameterSetName = "Help")] [Switch]$Examples,
    [Parameter(Mandatory = $false, ParameterSetName = "Help")] [Switch]$Full,
    [Parameter(Mandatory = $false, ParameterSetName = "Execute")] [ValidateSet("Backup", "Delete", "Discover", "List", "Update")] [String]$Action,
    [Parameter(Mandatory = $false, ParameterSetName = "Execute")] [Switch]$Force,
    [Parameter(Mandatory = $false, ParameterSetName = "Execute")] [String]$JsonPath,
    [Parameter(Mandatory = $false, ParameterSetName = "Execute")] [ValidateSet("ADVISORY", "DEBUG", "ERROR", "INFO", "WARNING")] [String]$LogLevel = "INFO",
    [Parameter(Mandatory = $false, ParameterSetName = "Execute")] [Switch]$SaveAll,
    [Parameter(Mandatory = $false, ParameterSetName = "Execute")] [String]$VcenterServer,
    [Parameter(Mandatory = $false, ParameterSetName = "Execute")] [String]$VcenterUser,
    [Parameter(Mandatory = $false, ParameterSetName = "Execute")] [String]$VmClassName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($PSCmdlet.ParameterSetName -eq "Help") {
    $helpArgs = @{ Name = $PSCommandPath }
    if ($Detailed) { $helpArgs["Detailed"] = $true }
    if ($Examples) { $helpArgs["Examples"] = $true }
    if ($Full) { $helpArgs["Full"] = $true }
    Get-Help @helpArgs | Out-Host
    exit 0
}

# =============================================================================
# Script-level constants
# =============================================================================
$SCRIPT:DEFAULT_VM_CLASS_NAMES = [string[]]@(
    "best-effort-2xlarge",  "best-effort-4xlarge",  "best-effort-8xlarge",
    "best-effort-large",    "best-effort-medium",   "best-effort-small",
    "best-effort-xlarge",   "best-effort-xsmall",
    "guaranteed-2xlarge",   "guaranteed-4xlarge",   "guaranteed-8xlarge",
    "guaranteed-large",     "guaranteed-medium",    "guaranteed-small",
    "guaranteed-xlarge",    "guaranteed-xsmall"
)
$SCRIPT:DEFAULT_VM_CLASSES_JSON_FILENAME = "vmClasses.json"
$SCRIPT:CONNECT_VCENTER_RETRY_VCENTER_ADDRESS = "RetryVcenterAddress"
$SCRIPT:VmClassInteractiveAffirmativeResponseRegexPattern = "^y(es)?$"
$SCRIPT:VmClassJsonMaximumCpuCount = 960
$SCRIPT:VmClassJsonMaximumMemoryMb = 25165824
$SCRIPT:VmClassJsonMaximumVgpuProfileNamesPerDeviceObject = 4
$SCRIPT:VmClassJsonMinimumVgpuProfileNamesPerDeviceObject = 1
$SCRIPT:VmClassJsonVmClassNameRegexPattern = "^(?=.{1,63}$)[a-z0-9]([-a-z0-9]*[a-z0-9])?$"
$SCRIPT:VmClassJsonValidNamePreviewMaximumCount = 20
$SCRIPT:VmClassFullReservationPercent = 100
$SCRIPT:VmClassJsonPreflightCacheEntries = $null
$SCRIPT:VmClassJsonPreflightCachePath = $null
$SCRIPT:VM_CLASS_NAME_MAX_LENGTH = 63

# =============================================================================
# Script-level setup: resolved JSON path
# =============================================================================
$resolvedJsonPath = if ([string]::IsNullOrWhiteSpace($JsonPath)) {
    Join-Path -Path $PSScriptRoot -ChildPath $SCRIPT:DEFAULT_VM_CLASSES_JSON_FILENAME
} else {
    $JsonPath.Trim()
}

$jsonFileRequired = $false

# Holds names selected via the post-connection TUI when -VmClassName is not passed.
$resolvedVmClassNames = [string[]]@()

# =============================================================================
# Script-level variables: log level hierarchy and logger state (Set-StrictMode safe)
# =============================================================================
$SCRIPT:LogLevelHierarchy = @{
    "DEBUG"     = 0
    "INFO"      = 1
    "ADVISORY"  = 2
    "WARNING"   = 3
    "EXCEPTION" = 4
    "ERROR"     = 5
}
$SCRIPT:LogMessagePending = $null
$SCRIPT:LogMessagePendingType = $null
$SCRIPT:LogMessagePendingTimestamp = $null
$SCRIPT:LogOnly = $null

# =============================================================================
# VM class classification helpers
# =============================================================================
Function Test-VmClassIsDefaultName {

    <#
        .SYNOPSIS
        Returns $true when the given name matches one of the built-in vCenter default VM class names.

        .PARAMETER Name
        VM class name to test (case-insensitive comparison).

        .OUTPUTS
        Boolean
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Name
    )

    return $SCRIPT:DEFAULT_VM_CLASS_NAMES -icontains $Name
}

# =============================================================================
# Logging helpers
# =============================================================================
Function Test-LogLevel {

    <#
        .SYNOPSIS
        Determines whether a message meets the configured log level threshold for console output.

        .PARAMETER ConfiguredLevel
        The minimum log level configured for screen output.

        .PARAMETER MessageType
        The severity of the log message to check.

        .OUTPUTS
        Boolean
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$ConfiguredLevel,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$MessageType
    )

    if (-not $SCRIPT:LogLevelHierarchy.ContainsKey($MessageType)) {
        throw "Unsupported MessageType `"$MessageType`" for Test-LogLevel."
    }
    if (-not $SCRIPT:LogLevelHierarchy.ContainsKey($ConfiguredLevel)) {
        throw "Unsupported ConfiguredLevel `"$ConfiguredLevel`" for Test-LogLevel."
    }

    $messageLevel = $SCRIPT:LogLevelHierarchy[$MessageType]
    $configuredLevelValue = $SCRIPT:LogLevelHierarchy[$ConfiguredLevel]

    return ($messageLevel -ge $configuredLevelValue)
}
Function Get-EnvironmentSetup {

    <#
        .SYNOPSIS
        Collects and logs system environment information for troubleshooting purposes.

        .NOTES
        Called automatically by New-LogFile when a new log file is created.
    #>

    $macOsVersion = $null
    $windowsVersion = $null

    Write-LogMessage -Type DEBUG -Message "Entered Get-EnvironmentSetup function..."

    $powerShellRelease = $PSVersionTable.PSVersion.ToString()

    $vcfModuleInfo = $null
    $vcfModuleList = @(Get-Module -ListAvailable -Name VCF.PowerCLI -ErrorAction SilentlyContinue)
    if ($vcfModuleList.Count -gt 0) {
        $vcfModuleInfo = $vcfModuleList | Sort-Object -Property Version -Descending | Select-Object -First 1
    }
    $vcfPowerCliRelease = if (
        $null -ne $vcfModuleInfo -and
        ($vcfModuleInfo.PSObject.Properties.Name -contains "Version")
    ) {
        $vcfModuleInfo.Version.ToString()
    } else {
        "N/A"
    }

    $vmwareModuleInfo = $null
    $vmwareModuleList = @(Get-Module -ListAvailable -Name VMware.PowerCLI -ErrorAction SilentlyContinue)
    if ($vmwareModuleList.Count -gt 0) {
        $vmwareModuleInfo = $vmwareModuleList | Sort-Object -Property Version -Descending | Select-Object -First 1
    }
    $vmwarePowerCliRelease = if (
        $null -ne $vmwareModuleInfo -and
        ($vmwareModuleInfo.PSObject.Properties.Name -contains "Version")
    ) {
        $vmwareModuleInfo.Version.ToString()
    } else {
        "N/A"
    }

    $operatingSystem = $PSVersionTable.OS

    if ($IsMacOS) {
        try {
            $macOsVersion = "$(sw_vers --productName) $(sw_vers --productVersion)"
        } catch [Exception] {
            Write-LogMessage -Type DEBUG -Message "sw_vers failed; using fallback OS info. $($_.Exception.Message)"
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($macOsVersion)) {
        $operatingSystem = $macOsVersion
    }

    if ($IsWindows) {
        try {
            $winInfo = (Get-ComputerInfo -ProgressAction SilentlyContinue) | Select-Object OSName, OSVersion
            $windowsVersion = "$($winInfo.OSName) $($winInfo.OSVersion)"
        } catch [Exception] {
            Write-LogMessage -Type DEBUG -Message "Get-ComputerInfo failed; using fallback OS info. $($_.Exception.Message)"
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($windowsVersion)) {
        $operatingSystem = $windowsVersion
    }

    Write-LogMessage -Type DEBUG -Message "Client PowerShell version is $powerShellRelease."
    if ($vcfPowerCliRelease) {
        Write-LogMessage -Type DEBUG -Message "Client VCF.PowerCLI version is $vcfPowerCliRelease."
    }
    if ($vmwarePowerCliRelease) {
        Write-LogMessage -Type DEBUG -Message "Client VMware.PowerCLI version is $vmwarePowerCliRelease."
    }
    Write-LogMessage -Type DEBUG -Message "Client Operating System is $operatingSystem."

    if ($vcfPowerCliRelease -eq "N/A") {
        Write-LogMessage -Type ERROR -Message "VCF.PowerCLI is not installed. Please install the VCF.PowerCLI module."
        throw "Manage-VMClasses cannot continue. Check logs for details."
    }
}
Function New-LogFile {

    <#
        .SYNOPSIS
        Creates a daily log file for this script run.

        .PARAMETER Directory
        Subdirectory under the script root to hold log files. Defaults to "logs".

        .PARAMETER Prefix
        Prefix for the log file name. Final file is named {Prefix}-yyyy-MM-dd.log.
    #>

    [CmdletBinding(SupportsShouldProcess = $true)]
    Param (
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$Directory = "logs",
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$Prefix = "Manage-VMClasses"
    )

    $fileTimeStamp = Get-Date -Format "yyyy-MM-dd"
    $SCRIPT:LogFolder = Join-Path -Path $PSScriptRoot -ChildPath $Directory
    $SCRIPT:LogFile = Join-Path -Path $SCRIPT:LogFolder -ChildPath "$Prefix-$fileTimeStamp.log"

    if (-not (Test-Path -LiteralPath $SCRIPT:LogFolder -PathType Container)) {
        if ($PSCmdlet.ShouldProcess($SCRIPT:LogFolder, "Create directory")) {
            try {
                New-Item -ItemType Directory -Path $SCRIPT:LogFolder -ErrorAction Stop | Out-Null
            } catch {
                throw "Failed to create log directory `"$SCRIPT:LogFolder`". Manage-VMClasses cannot continue."
            }
        }
    }

    if (-not (Test-Path -LiteralPath $SCRIPT:LogFile -PathType Leaf)) {
        if ($PSCmdlet.ShouldProcess($SCRIPT:LogFile, "Create log file")) {
            New-Item -ItemType File -Path $SCRIPT:LogFile | Out-Null
            Get-EnvironmentSetup
        }
    }
}
Function Write-LogMessage {

    <#
        .SYNOPSIS
        Writes a severity-based, color-coded message to the console and log file.

        .DESCRIPTION
        Supports DEBUG, INFO, ADVISORY, WARNING, EXCEPTION, and ERROR levels with color-coded
        console output and timestamped log file entries. Screen output is filtered by the
        configured log level; all levels are always written to the log file.

        Supports -NoNewline / -CompletePending for attempt/result line pairs such as
        "Creating VM class... Succeeded".

        .PARAMETER AppendNewLine
        Adds a blank line after the message on the console.

        .PARAMETER CompletePending
        Appends Message to the stored -NoNewline message and writes the combined line to the log.

        .PARAMETER Message
        The message to log and/or display.

        .PARAMETER NoNewline
        Displays the message without a trailing newline and stores it for -CompletePending.

        .PARAMETER PrependNewLine
        Adds a blank line before the message on the console.

        .PARAMETER SuppressOutputToFile
        Prevents the message from being written to the log file.

        .PARAMETER SuppressOutputToScreen
        Prevents the message from being displayed on the console.

        .PARAMETER Type
        Severity level: DEBUG, INFO, ADVISORY, WARNING, EXCEPTION, or ERROR. Defaults to INFO.

        .NOTES
        Write-Host is used here by design for severity-based color output. Do not use Write-Host
        elsewhere; use Write-LogMessage or Write-Output as appropriate.
    #>

    Param (
        [Parameter(Mandatory = $false)] [Switch]$AppendNewLine,
        [Parameter(Mandatory = $false)] [Switch]$CompletePending,
        [Parameter(Mandatory = $true)] [AllowEmptyString()] [String]$Message,
        [Parameter(Mandatory = $false)] [Switch]$NoNewline,
        [Parameter(Mandatory = $false)] [Switch]$PrependNewLine,
        [Parameter(Mandatory = $false)] [Switch]$SuppressOutputToFile,
        [Parameter(Mandatory = $false)] [Switch]$SuppressOutputToScreen,
        [Parameter(Mandatory = $false)] [ValidateSet("ADVISORY", "DEBUG", "ERROR", "EXCEPTION", "INFO", "WARNING")] [String]$Type = "INFO"
    )

    $colorMap = @{
        "INFO"      = "Green"
        "ERROR"     = "Red"
        "WARNING"   = "Yellow"
        "ADVISORY"  = "Yellow"
        "EXCEPTION" = "Cyan"
        "DEBUG"     = "Gray"
    }
    $messageColor = $colorMap.$Type
    $timeStamp = Get-Date -Format "yyyy-MM-dd_HH:mm:ss"
    $shouldDisplay = Test-LogLevel -ConfiguredLevel $SCRIPT:ConfiguredLogLevel -MessageType $Type

    if ($CompletePending) {
        if ($null -ne $SCRIPT:LogMessagePending) {
            $fullMessage = $SCRIPT:LogMessagePending + $Message
            $pendingType = $SCRIPT:LogMessagePendingType
            $pendingTimestamp = $SCRIPT:LogMessagePendingTimestamp
            $pendingColor = $colorMap.$pendingType
            $SCRIPT:LogMessagePending = $null
            $SCRIPT:LogMessagePendingType = $null
            $SCRIPT:LogMessagePendingTimestamp = $null
            if (-not $SuppressOutputToScreen -and $SCRIPT:LogOnly -ne "enabled" -and (Test-LogLevel -ConfiguredLevel $SCRIPT:ConfiguredLogLevel -MessageType $pendingType)) {
                Write-Host -ForegroundColor $pendingColor $Message
                [Console]::Out.Flush()
            }
            if (-not $SuppressOutputToFile -and $SCRIPT:LogFile -and -not [string]::IsNullOrWhiteSpace($SCRIPT:LogFile)) {
                $logContent = "[$pendingTimestamp] ($pendingType) $fullMessage"
                try {
                    $logDir = Split-Path -Path $SCRIPT:LogFile -Parent -ErrorAction SilentlyContinue
                    if ($logDir -and -not (Test-Path -LiteralPath $logDir -PathType Container -ErrorAction SilentlyContinue)) {
                        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
                    }
                    Add-Content -Encoding utf8 -Path $SCRIPT:LogFile -Value $logContent -ErrorAction Stop
                } catch {
                    Write-LogMessage -Type DEBUG -SuppressOutputToScreen -Message "Log write failed: $($_.Exception.Message)"
                }
            }
        } else {
            if (-not $SuppressOutputToScreen -and $SCRIPT:LogOnly -ne "enabled" -and $shouldDisplay) {
                Write-Host -ForegroundColor $messageColor "[$Type] $Message"
                [Console]::Out.Flush()
            }
            if (-not $SuppressOutputToFile -and $SCRIPT:LogFile -and -not [string]::IsNullOrWhiteSpace($SCRIPT:LogFile)) {
                $logContent = "[$timeStamp] ($Type) $Message"
                try {
                    Add-Content -Encoding utf8 -Path $SCRIPT:LogFile -Value $logContent -ErrorAction Stop
                } catch {
                    Write-LogMessage -Type DEBUG -SuppressOutputToScreen -Message "Log write failed: $($_.Exception.Message)"
                }
            }
        }
        return
    }

    if ($NoNewline) {
        if ($PrependNewLine -and $SCRIPT:LogOnly -ne "enabled" -and $shouldDisplay) {
            Write-Host ""
        }
        $SCRIPT:LogMessagePending = $Message
        $SCRIPT:LogMessagePendingType = $Type
        $SCRIPT:LogMessagePendingTimestamp = $timeStamp
        if (-not $SuppressOutputToScreen -and $SCRIPT:LogOnly -ne "enabled" -and $shouldDisplay) {
            Write-Host -ForegroundColor $messageColor "[$Type] $Message" -NoNewline
            [Console]::Out.Flush()
        }
        if ($AppendNewLine -and $SCRIPT:LogOnly -ne "enabled" -and $shouldDisplay) {
            Write-Host ""
        }
        return
    }

    if ($PrependNewLine -and $SCRIPT:LogOnly -ne "enabled" -and $shouldDisplay) {
        Write-Host ""
    }

    if (-not $SuppressOutputToScreen -and $SCRIPT:LogOnly -ne "enabled" -and $shouldDisplay -and $null -eq $SCRIPT:LogMessagePending) {
        Write-Host -ForegroundColor $messageColor "[$Type] $Message"
        [Console]::Out.Flush()
    }

    if ($AppendNewLine -and $SCRIPT:LogOnly -ne "enabled" -and $shouldDisplay) {
        Write-Host ""
    }

    if (-not $SuppressOutputToFile -and $SCRIPT:LogFile -and -not [string]::IsNullOrWhiteSpace($SCRIPT:LogFile)) {
        $logContent = "[$timeStamp] ($Type) $Message"
        try {
            $logDir = Split-Path -Path $SCRIPT:LogFile -Parent -ErrorAction SilentlyContinue
            if ($logDir -and -not (Test-Path -LiteralPath $logDir -PathType Container -ErrorAction SilentlyContinue)) {
                New-Item -ItemType Directory -Path $logDir -Force | Out-Null
            }
            Add-Content -Encoding utf8 -Path $SCRIPT:LogFile -Value $logContent -ErrorAction Stop
        } catch {
            Write-LogMessage -Type DEBUG -SuppressOutputToScreen -Message "Log write failed: $($_.Exception.Message)"
        }
    }
}

# =============================================================================
# Interactive prompts and vCenter connection helpers
# =============================================================================
Function Get-InteractiveInput {

    <#
        .SYNOPSIS
        Prompts until non-empty input is provided, with optional cancel via the letter c.

        .PARAMETER AsSecureString
        Reads masked input and returns a SecureString.

        .PARAMETER PromptMessage
        Base prompt text. A cancel hint is appended automatically.

        .OUTPUTS
        System.String or System.Security.SecureString
    #>

    Param (
        [Parameter(Mandatory = $false)] [Switch]$AsSecureString,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$PromptMessage
    )

    Write-LogMessage -Type DEBUG -Message "Entered Get-InteractiveInput function..."

    $fullPrompt = "$PromptMessage (or press 'c' to cancel)"

    do {
        try {
            if ($AsSecureString.IsPresent) {
                $value = Read-Host -Prompt $fullPrompt -AsSecureString
                if ($value.Length -eq 1) {
                    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($value)
                    try {
                        $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
                        if ($plain -eq "c" -or $plain -eq "C") {
                            throw [System.OperationCanceledException]::new("User cancelled input.")
                        }
                    } finally {
                        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
                    }
                }
            } else {
                $value = Read-Host -Prompt $fullPrompt
                if ($value -eq "c" -or $value -eq "C") {
                    throw [System.OperationCanceledException]::new("User cancelled input.")
                }
            }
        } catch {
            if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) {
                throw [System.OperationCanceledException]::new("User cancelled input (Control-C).")
            }
            if ($_.Exception -is [System.OperationCanceledException]) {
                throw
            }
            throw
        }
    } while ($null -eq $value -or $value.Length -eq 0)

    return $value
}
Function Test-ValidVcenterAddress {

    <#
        .SYNOPSIS
        Returns $true when the input is a plausible vCenter FQDN or dotted-quad IPv4 address.

        .DESCRIPTION
        Rejects strings containing a URL scheme (://), path separator (/), or port separator (:).
        Validates the remainder against the RFC-compliant hostname label pattern: alphanumerics and
        hyphens, where each label does not start or end with a hyphen, separated by dots. IPv4
        addresses pass because digit-only labels are valid hostname characters. IPv6 is not supported.

        .PARAMETER Address
        The address string to validate.

        .OUTPUTS
        System.Boolean
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Address
    )

    Write-LogMessage -Type DEBUG -Message "Entered Test-ValidVcenterAddress function..."

    if ($Address -match '://' -or $Address -match '/' -or $Address -match ':') {
        return $false
    }

    return [bool]($Address -match '^(?:[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)*[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?$')
}
Function Get-InteractiveVcenterServerFqdn {

    <#
        .SYNOPSIS
        Prompts for a vCenter FQDN or IPv4 address, validates format and DNS, and returns the trimmed value.

        .DESCRIPTION
        Validates format first (rejects URL schemes, path separators, and port suffixes), then confirms
        the address is DNS-resolvable before returning. Re-prompts the user on any failure.

        .PARAMETER ReturnToMenuOnCancel
        When set, a cancel ('c') rethrows OperationCanceledException so interactive menu callers can
        return to the main menu instead of exiting the script.

        .OUTPUTS
        System.String
    #>

    Param (
        [Parameter(Mandatory = $false)] [Switch]$ReturnToMenuOnCancel
    )

    Write-LogMessage -Type DEBUG -Message "Entered Get-InteractiveVcenterServerFqdn function..."

    while ($true) {
        try {
            $entered = Get-InteractiveInput -PromptMessage "Enter your vCenter Server FQDN or IP address"
        } catch [System.OperationCanceledException] {
            Write-LogMessage -Type INFO -Message "vCenter server entry cancelled by user."
            Write-Host ""
            if ($ReturnToMenuOnCancel.IsPresent) {
                throw
            }

            exit 0
        }

        if ([string]::IsNullOrWhiteSpace($entered)) {
            throw "vCenter Server address is required."
        }

        $trimmed = [string]$entered.Trim()

        if (-not (Test-ValidVcenterAddress -Address $trimmed)) {
            Write-LogMessage -Type ERROR -Message "`"$trimmed`" is not a valid FQDN or IPv4 address. Omit any scheme (https://), path, or port."
            continue
        }

        try {
            $null = [System.Net.Dns]::GetHostAddresses($trimmed)
        } catch {
            Write-LogMessage -Type ERROR -Message "Cannot resolve `"$trimmed`". Check the address and DNS connectivity."
            continue
        }

        return $trimmed
    }
}
Function Get-InteractiveVcenterUsername {

    <#
        .SYNOPSIS
        Prompts for a vCenter username when stdin is interactive.

        .OUTPUTS
        System.String
    #>

    Param ()

    Write-LogMessage -Type DEBUG -Message "Entered Get-InteractiveVcenterUsername function..."

    if ([Console]::IsInputRedirected) {
        throw "vCenter username is required. Pass -VcenterUser or run in an interactive session to be prompted."
    }

    Write-Host ""
    do {
        $enteredUser = Read-Host -Prompt "Enter your vCenter username"
    } while ([string]::IsNullOrWhiteSpace($enteredUser))

    return [string]$enteredUser.Trim()
}
Function Show-InteractiveHelpPager {

    <#
        .SYNOPSIS
        Scrollable TUI pager for displaying help text below the current cursor position.

        .DESCRIPTION
        Renders a fixed-height viewport of text lines. UpArrow and DownArrow scroll one line;
        PageUp and PageDown scroll by one full viewport. Escape returns to the caller.
        Only the content and footer lines are redrawn on each keypress; the header is written
        once and stays in place above the scrolling region.

        .PARAMETER Lines
        Array of text lines to display.

        .NOTES
        Write-Host is used here by design for the interactive TUI pager.
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNull()] [String[]]$Lines
    )

    $normalizedPagerLines = @(
        foreach ($line in @($Lines)) {
            if ($null -eq $line) {
                continue
            }

            $lineString = [string]$line
            if (-not [string]::IsNullOrWhiteSpace($lineString)) {
                $lineString
            }
        }
    )
    if ($normalizedPagerLines.Count -eq 0) {
        $normalizedPagerLines = @("(No help content to display.)")
    }

    $Lines = $normalizedPagerLines
    $viewportHeight = [Math]::Max(5, [Console]::WindowHeight - 6)
    $totalLines = $Lines.Count
    $maxOffset = [Math]::Max(0, $totalLines - $viewportHeight)
    $scrollOffset = 0
    $windowWidth = [Console]::WindowWidth - 1

    $renderViewport = {
        for ($i = 0; $i -lt $viewportHeight; $i++) {
            $lineIndex = $scrollOffset + $i
            $displayLine = if ($lineIndex -lt $totalLines) { $Lines[$lineIndex] } else { "" }
            if ($displayLine.Length -gt $windowWidth) {
                $displayLine = $displayLine.Substring(0, $windowWidth)
            }
            Write-Host $displayLine.PadRight($windowWidth)
        }
        $end = [Math]::Min($scrollOffset + $viewportHeight, $totalLines)
        $footer = "  Line $($scrollOffset + 1)-$end of $totalLines  |  Esc=back to menu"
        Write-Host $footer.PadRight($windowWidth) -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "  Help — Arrow keys=scroll  Page Up/Down=page  Esc=back to menu" -ForegroundColor Cyan
    Write-Host ""
    & $renderViewport

    while ($true) {
        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            "UpArrow" {
                if ($scrollOffset -gt 0) { $scrollOffset-- }
                break
            }
            "DownArrow" {
                if ($scrollOffset -lt $maxOffset) { $scrollOffset++ }
                break
            }
            "PageUp" {
                $scrollOffset = [Math]::Max(0, $scrollOffset - $viewportHeight)
                break
            }
            "PageDown" {
                $scrollOffset = [Math]::Min($maxOffset, $scrollOffset + $viewportHeight)
                break
            }
            "Escape" {
                return
            }
        }
        Write-Host -NoNewline "`e[$($viewportHeight + 1)F"
        & $renderViewport
    }
}
Function Get-InteractiveAction {

    <#
        .SYNOPSIS
        Arrow-key single-select menu for choosing an action (Backup, Discover, Update, List, Delete, Help, Quit).

        .OUTPUTS
        System.String — the selected action name, or "Quit" when the user exits. "Help" is handled
        internally: it displays Get-Help output and re-renders the menu without returning to the caller.

        .NOTES
        Write-Host is used here by design for the interactive TUI menu.
    #>

    Param (
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$JsonFileName = "vmClasses.json"
    )

    if ([Console]::IsInputRedirected) {
        throw "Non-interactive session: pass -Action (Backup, Discover, Update, List, or Delete)."
    }

    $options = @(
        [PSCustomObject]@{ Name = "Discover"; Description = "Scan live VMs and generate $JsonFileName" }
        [PSCustomObject]@{ Name = "List";     Description = "Show all VM classes on vCenter" }
        [PSCustomObject]@{ Name = "Backup";   Description = "Save all VM classes from vCenter to a JSON file" }
        [PSCustomObject]@{ Name = "Update";   Description = "Apply $JsonFileName to vCenter" }
        [PSCustomObject]@{ Name = "Delete";   Description = "Remove VM classes from vCenter" }
        [PSCustomObject]@{ Name = "Help";     Description = "Show usage documentation for this script" }
        [PSCustomObject]@{ Name = "Quit";     Description = "Exit without making any changes" }
    )
    $currentIndex = 0

    $renderMenu = {
        for ($i = 0; $i -lt $options.Count; $i++) {
            $cursor = if ($i -eq $currentIndex) { ">" } else { " " }
            $line = ("  $cursor {0,-10} {1}" -f $options[$i].Name, $options[$i].Description).PadRight([Console]::WindowWidth - 1)
            if ($i -eq $currentIndex) {
                Write-Host $line -ForegroundColor Cyan
            } else {
                Write-Host $line
            }
        }
    }

    Write-Host ""
    Write-Host "  Select an action below" -ForegroundColor Cyan
    Write-Host "  Arrow keys=navigate  Enter=confirm  Esc=quit" -ForegroundColor Gray
    Write-Host ""
    & $renderMenu

    while ($true) {
        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            "UpArrow" {
                if ($currentIndex -gt 0) { $currentIndex-- }
                break
            }
            "DownArrow" {
                if ($currentIndex -lt ($options.Count - 1)) { $currentIndex++ }
                break
            }
            "Escape" {
                Write-Host ""
                return "Quit"
            }
            "Enter" {
                if ($options[$currentIndex].Name -eq "Help") {
                    $rawHelp = ""
                    try {
                        $rawHelp = [string]((Get-Help $PSCommandPath -Detailed | Out-String))
                    } catch {
                        $rawHelp = ""
                    }

                    $helpLines = @(
                        foreach ($segment in ($rawHelp -split "`r?`n")) {
                            if (-not [string]::IsNullOrWhiteSpace($segment)) {
                                $segment
                            }
                        }
                    )
                    if ($helpLines.Count -eq 0) {
                        $helpLines = @(
                            "Help content could not be loaded in this session.",
                            "Run the following command outside the script to view documentation:",
                            "  Get-Help `"$PSCommandPath`" -Detailed"
                        )
                    }

                    Show-InteractiveHelpPager -Lines ([string[]]$helpLines)
                    [Console]::Clear()
                    Write-Host ""
                    Write-Host "  Select an action below" -ForegroundColor Cyan
                    Write-Host "  Arrow keys=navigate  Enter=confirm  Esc=quit" -ForegroundColor Gray
                    Write-Host ""
                    & $renderMenu
                    continue
                }
                Write-Host ""
                return $options[$currentIndex].Name
            }
        }
        Write-Host -NoNewline "`e[$($options.Count)F"
        & $renderMenu
    }
}
Function Get-InteractiveJsonPath {

    <#
        .SYNOPSIS
        Prompts until a VM classes JSON file path exists, or exits when the user declines to retry.

        .DESCRIPTION
        When -TreatInitialPathAsOptionalDefault is set (caller did not pass -JsonPath), a missing
        default path next to the script is not logged as ERROR before the first prompt. ERROR is
        still logged when -JsonPath was used and is missing, or after the user enters a path that
        does not exist. Y/N retry matches the vCenter FQDN pattern; N calls exit 0.

        .PARAMETER ForcePrompt
        When present, always prompts for a new path on the first iteration even if the initial file
        exists. Use this when the caller requires a new path rather than the pre-existing default
        (e.g. the user explicitly chose to use a different file).

        .PARAMETER InitialResolvedPath
        First path to validate.

        .PARAMETER TreatInitialPathAsOptionalDefault
        When present, suppresses ERROR while the path to try is still the initial default and the
        file is absent.

        .OUTPUTS
        System.String — resolved path to an existing file.
    #>

    Param (
        [Parameter(Mandatory = $false)] [Switch]$ForcePrompt,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$InitialResolvedPath,
        [Parameter(Mandatory = $false)] [Switch]$TreatInitialPathAsOptionalDefault
    )

    Write-LogMessage -Type DEBUG -Message "Entered Get-InteractiveJsonPath function..."

    if ([Console]::IsInputRedirected) {
        throw "VM classes JSON file not found: `"$InitialResolvedPath`". Provide -JsonPath or place $($SCRIPT:DEFAULT_VM_CLASSES_JSON_FILENAME) next to this script. A non-interactive session cannot prompt for a path."
    }

    $initialTrim = $InitialResolvedPath.Trim()
    $pathToTry = $initialTrim
    $isFirstIteration = $true

    while ($true) {
        if (-not ($isFirstIteration -and $ForcePrompt) -and (Test-Path -LiteralPath $pathToTry -PathType Leaf)) {
            Write-LogMessage -Type INFO -Message "Using VM classes JSON file `"$pathToTry`"."
            return $pathToTry
        }
        $isFirstIteration = $false

        $suppressErrorBeforePrompt = $TreatInitialPathAsOptionalDefault.IsPresent -and ($pathToTry -ceq $initialTrim)
        if (-not $suppressErrorBeforePrompt) {
            Write-LogMessage -Type ERROR -Message "VM classes JSON file not found: `"$pathToTry`"."
        }

        Write-Host ""
        $entered = Read-Host -Prompt "Enter the path to your VM classes JSON file"
        if (-not [string]::IsNullOrWhiteSpace($entered)) {
            $pathToTry = $entered.Trim()
        }

        if (Test-Path -LiteralPath $pathToTry -PathType Leaf) {
            Write-LogMessage -Type INFO -Message "Using VM classes JSON file `"$pathToTry`"."
            return $pathToTry
        }

        $suppressErrorAfterInput = $TreatInitialPathAsOptionalDefault.IsPresent -and ($pathToTry -ceq $initialTrim) -and [string]::IsNullOrWhiteSpace($entered)
        if (-not $suppressErrorAfterInput) {
            Write-LogMessage -Type ERROR -Message "VM classes JSON file not found: `"$pathToTry`"."
        }

        $retryResponse = $null
        while ($retryResponse -ne "Y" -and $retryResponse -ne "N") {
            $retryResponse = Read-Host "Would you like to enter a different path? (Y/N)"
            $retryResponse = $retryResponse.Trim().ToUpper()
        }

        if ($retryResponse -eq "N") {
            Write-LogMessage -Type INFO -Message "Exiting; VM classes JSON file is required for this action."
            exit 0
        }
    }
}
Function Get-ConfirmedDiscoverOutputPath {

    <#
        .SYNOPSIS
        Resolves the output path for Discover or Backup, prompting to overwrite or rename when the file exists.

        .DESCRIPTION
        When the target file does not exist, returns the path immediately. When the file exists and
        stdin is interactive, prompts the user to overwrite (Y), enter a new path (N), or cancel (C).
        When N is chosen, re-prompts until the user supplies a path whose parent directory exists and
        to which a probe write succeeds. Non-interactive sessions throw so the caller can require an
        explicit -JsonPath. Pass -Force to skip the overwrite prompt and always return the path as-is.
        Used by both -Action Discover and -Action Backup.

        .PARAMETER ActionName
        Display name of the calling action used in user-facing messages (e.g. "Discover" or "Backup").
        Defaults to "Discover".

        .PARAMETER Force
        When set, an existing file is accepted without prompting. Useful for non-interactive runs.

        .PARAMETER InitialPath
        The initial resolved path for the output JSON file.

        .OUTPUTS
        System.String — confirmed output path, or $null when the user cancelled.
    #>

    Param (
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$ActionName = "Discover",
        [Parameter(Mandatory = $false)] [Switch]$Force,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$InitialPath
    )

    Write-LogMessage -Type DEBUG -Message "Entered Get-ConfirmedDiscoverOutputPath function..."

    $pathToUse = $InitialPath.Trim()

    while ($true) {
        if (-not (Test-Path -LiteralPath $pathToUse -PathType Leaf)) {
            return $pathToUse
        }

        if ($Force) {
            Write-LogMessage -Type WARNING -Message "Output file `"$pathToUse`" already exists; overwriting (-Force)."
            return $pathToUse
        }

        if ([Console]::IsInputRedirected) {
            throw "$ActionName output file `"$pathToUse`" already exists. Pass -Force to overwrite, -JsonPath with a different path, or delete the existing file before running $ActionName in a non-interactive session."
        }

        Write-Host ""
        Write-LogMessage -Type WARNING -Message "Output file `"$pathToUse`" already exists."
        $response = $null
        while ($response -ne "Y" -and $response -ne "N" -and $response -ne "C") {
            $response = (Read-Host "Overwrite? Y=overwrite, N=enter new path, C=cancel").Trim().ToUpper()
        }

        switch ($response) {
            "Y" { return $pathToUse }
            "C" {
                Write-LogMessage -Type INFO -Message "$ActionName cancelled by user."
                return $null
            }
            "N" {
                Write-Host ""
                $pathToUse = $null
                while (-not $pathToUse) {
                    $candidate = (Read-Host "Enter a new output file path").Trim()
                    if ([string]::IsNullOrWhiteSpace($candidate)) {
                        continue
                    }
                    $resolvedCandidate = $null
                    try {
                        $resolvedCandidate = [System.IO.Path]::GetFullPath($candidate)
                    }
                    catch {
                        Write-LogMessage -Type ERROR -Message "Path `"$candidate`" is not a valid path: $($_.Exception.Message)"
                        $retryResponse = $null
                        while ($retryResponse -ne "Y" -and $retryResponse -ne "N") {
                            $retryResponse = (Read-Host "Would you like to enter a different path? (Y/N)").Trim().ToUpper()
                        }
                        if ($retryResponse -eq "N") {
                            Write-LogMessage -Type INFO -Message "$ActionName cancelled by user."
                            return $null
                        }
                        continue
                    }
                    $parentDir = Split-Path -Parent $resolvedCandidate
                    if (-not (Test-Path -LiteralPath $parentDir -PathType Container)) {
                        Write-LogMessage -Type ERROR -Message "Directory `"$parentDir`" does not exist."
                        $retryResponse = $null
                        while ($retryResponse -ne "Y" -and $retryResponse -ne "N") {
                            $retryResponse = (Read-Host "Would you like to enter a different path? (Y/N)").Trim().ToUpper()
                        }
                        if ($retryResponse -eq "N") {
                            Write-LogMessage -Type INFO -Message "$ActionName cancelled by user."
                            return $null
                        }
                        continue
                    }
                    $candidateExisted = Test-Path -LiteralPath $resolvedCandidate -PathType Leaf
                    try {
                        [System.IO.File]::Open($resolvedCandidate, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::Write).Close()
                        if (-not $candidateExisted) {
                            Remove-Item -LiteralPath $resolvedCandidate -Force -ErrorAction SilentlyContinue
                        }
                    }
                    catch {
                        Write-LogMessage -Type ERROR -Message "Cannot write to `"$resolvedCandidate`": $($_.Exception.Message)"
                        $retryResponse = $null
                        while ($retryResponse -ne "Y" -and $retryResponse -ne "N") {
                            $retryResponse = (Read-Host "Would you like to enter a different path? (Y/N)").Trim().ToUpper()
                        }
                        if ($retryResponse -eq "N") {
                            Write-LogMessage -Type INFO -Message "$ActionName cancelled by user."
                            return $null
                        }
                        continue
                    }
                    $pathToUse = $resolvedCandidate
                }
            }
        }
    }
}
Function Get-VmClassScriptVcenterPasswordSecureString {

    <#
        .SYNOPSIS
        Returns a SecureString for the vCenter password from environment variables or Read-Host.

        .DESCRIPTION
        Uses VCENTER_PASSWORD when set and non-empty. When not set and stdin is interactive,
        prompts until a non-empty password is entered. Throws when stdin is redirected and
        VCENTER_PASSWORD is not set.

        .OUTPUTS
        System.Security.SecureString
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("Microsoft.PowerShell.Security", "PSAvoidUsingConvertToSecureStringWithPlainText", Justification = "Password from VCENTER_PASSWORD environment variable for non-interactive runs.")]
    [CmdletBinding()]
    Param ()

    if (-not [string]::IsNullOrWhiteSpace($env:VCENTER_PASSWORD)) {
        Write-LogMessage -Type ADVISORY -Message "Using vCenter password from `$env:VCENTER_PASSWORD. Unset the variable to be prompted interactively."
        return ConvertTo-SecureString -String $env:VCENTER_PASSWORD -AsPlainText -Force
    }

    if ([Console]::IsInputRedirected) {
        throw "Non-interactive session: set VCENTER_PASSWORD and pass -VcenterServer and -VcenterUser."
    }

    do {
        $secureFromPrompt = Read-Host -Prompt "Enter your vCenter password" -AsSecureString
        $plainProbe = (New-Object System.Management.Automation.PSCredential("user", $secureFromPrompt)).GetNetworkCredential().Password
    } while ([string]::IsNullOrWhiteSpace($plainProbe))

    return $secureFromPrompt
}
Function Get-PowerCliDefaultViServer {

    <#
        .SYNOPSIS
        Returns Global:DefaultVIServer in a StrictMode-safe way, or $null when undefined.
    #>

    if (-not (Get-Variable -Name DefaultVIServer -Scope Global -ErrorAction SilentlyContinue)) {
        return $null
    }

    return (Get-Variable -Name DefaultVIServer -Scope Global -ErrorAction Stop).Value
}
Function Get-PowerCliDefaultViServerList {

    <#
        .SYNOPSIS
        Returns Global:DefaultVIServers as an array in a StrictMode-safe way.
    #>

    if (-not (Get-Variable -Name DefaultVIServers -Scope Global -ErrorAction SilentlyContinue)) {
        return @()
    }

    return @((Get-Variable -Name DefaultVIServers -Scope Global -ErrorAction Stop).Value)
}
Function Test-IsAlreadyConnectedToVcenterServer {

    <#
        .SYNOPSIS
        Returns whether PowerCLI reports an active connection to the given vCenter Server name.

        .PARAMETER ServerName
        vCenter FQDN or IP to match against connected sessions (case-insensitive).

        .OUTPUTS
        System.Boolean
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$ServerName
    )

    $trimmed = $ServerName.Trim()
    foreach ($viServer in @(Get-PowerCliDefaultViServerList)) {
        if ($viServer.IsConnected -and ($viServer.Name -ieq $trimmed)) {
            return $true
        }
    }

    return $false
}
Function Import-VcfPowerCLI {

    <#
        .SYNOPSIS
        Loads VMware.VimAutomation.Core on first use; returns immediately if already loaded.

        .DESCRIPTION
        Defers the module load until the first vCenter connection is required, keeping script
        startup fast. After loading, verifies that Connect-VIServer is available as a sanity
        check. Throws with an actionable message on any failure.

        Checking individual cmdlets at startup is not useful: the module either loads correctly
        (all cmdlets present) or it fails to load. One post-load check is sufficient.
    #>

    [CmdletBinding()]
    Param ()

    if (Get-Module -Name VMware.VimAutomation.Core) {
        return
    }

    Write-LogMessage -Type INFO -Message "Loading VCF PowerCLI module (this may take a moment)..."
    try {
        Import-Module -Name VMware.VimAutomation.Core -ErrorAction Stop
    } catch {
        throw "Failed to load VCF PowerCLI module 'VMware.VimAutomation.Core'. Ensure VCF PowerCLI 9.0 or later is installed: $($_.Exception.Message)"
    }

    if (-not (Get-Command -Name Connect-VIServer -ErrorAction SilentlyContinue)) {
        throw "VCF PowerCLI module loaded but 'Connect-VIServer' cmdlet was not found. Reinstall VCF PowerCLI 9.0 or later."
    }

    Write-LogMessage -Type DEBUG -Message "VCF PowerCLI module loaded successfully."
}
Function Connect-Vcenter {

    <#
        .SYNOPSIS
        Establishes a secure connection to a vCenter Server instance.

        .DESCRIPTION
        Connects using the supplied PSCredential, with intelligent duplicate-connection detection,
        SSL error guidance, auth-failure re-prompt, and optional DNS-retry signaling.

        .PARAMETER AllowVcenterAddressRetry
        When set, DNS failures prompt the user to re-enter the FQDN or IP. On Y, returns
        $SCRIPT:CONNECT_VCENTER_RETRY_VCENTER_ADDRESS so the caller can restart the prompt loop.

        .PARAMETER ServerCredential
        PSCredential for vCenter authentication.

        .PARAMETER ServerName
        vCenter FQDN or IP.

        .PARAMETER SkipRetryPrompt
        When set, authentication failures throw immediately without prompting.

        .OUTPUTS
        System.String — $SCRIPT:CONNECT_VCENTER_RETRY_VCENTER_ADDRESS when a DNS retry is requested.
    #>

    Param (
        [Parameter(Mandatory = $false)] [Switch]$AllowVcenterAddressRetry,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [PSCredential]$ServerCredential,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$ServerName,
        [Parameter(Mandatory = $false)] [Switch]$SkipRetryPrompt
    )

    Write-LogMessage -Type DEBUG -Message "Entered Connect-Vcenter function..."
    Import-VcfPowerCLI

    $defaultViServers = Get-PowerCliDefaultViServerList
    $connectedVcenter = $defaultViServers | Where-Object { $_.Name -eq $ServerName -and $_.IsConnected }

    if (-not $connectedVcenter) {
        $connectionSuccessful = $false
        $currentCredential = $ServerCredential

        while (-not $connectionSuccessful) {
            try {
                Write-LogMessage -Type DEBUG -Message "Connecting to vCenter `"$ServerName`" as `"$($currentCredential.UserName)`"."
                $null = Connect-VIServer -Server $ServerName -Credential $currentCredential -ErrorAction Stop
                $connectionSuccessful = $true
                Write-LogMessage -Type DEBUG -Message "Successfully connected to vCenter `"$ServerName`"."
            } catch [System.TimeoutException] {
                Write-LogMessage -Type ERROR -Message "Cannot connect to vCenter `"$ServerName`" due to a network timeout: $_."
                throw "Manage-VMClasses cannot continue. Check logs for details."
            } catch {
                $errorMessage = $_.Exception.Message

                switch -Regex ($errorMessage) {
                    "SSL connection could not be established|SSL|certificate" {
                        Write-LogMessage -Type ERROR -Message "Failed to establish an SSL connection to vCenter `"$ServerName`"."
                        Write-LogMessage -Type ERROR -Message "Common solutions:"
                        Write-LogMessage -Type ERROR -Message "  1. Run: Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:`$false"
                        Write-LogMessage -Type ERROR -Message "  2. Run: [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12"
                        Write-LogMessage -Type ERROR -Message "  3. Verify network connectivity to port 443 on `"$ServerName`"."
                        Write-LogMessage -Type ERROR -Message "Full error: $errorMessage."
                        throw "Manage-VMClasses cannot continue. Check logs for details."
                    }
                    "incorrect user name or password|authentication|credentials" {
                        Write-LogMessage -Type ERROR -PrependNewLine -Message "Authentication failed for vCenter `"$ServerName`"."
                        if ($SkipRetryPrompt.IsPresent) {
                            throw "Authentication failed."
                        }
                        if ([Console]::IsInputRedirected) {
                            throw "Authentication failed. Non-interactive session cannot re-prompt; verify VCENTER_PASSWORD and -VcenterUser."
                        }
                        Write-Host ""
                        $retryResponse = $null
                        while ($retryResponse -ne "Y" -and $retryResponse -ne "N") {
                            $retryResponse = (Read-Host "Would you like to re-enter your credentials? (Y/N)").Trim().ToUpper()
                        }
                        if ($retryResponse -eq "Y") {
                            Write-LogMessage -Type INFO -AppendNewLine -Message "Please enter your vCenter sign-in at the prompts."
                            do {
                                $retryUsername = Read-Host -Prompt "Enter your vCenter username"
                            } while ([string]::IsNullOrWhiteSpace($retryUsername))
                            Write-Host ""
                            do {
                                $newPassword = Read-Host -Prompt "Enter your vCenter password" -AsSecureString
                                $plainRetryProbe = (New-Object System.Management.Automation.PSCredential("user", $newPassword)).GetNetworkCredential().Password
                            } while ([string]::IsNullOrWhiteSpace($plainRetryProbe))
                            Write-Host ""
                            $currentCredential = New-Object System.Management.Automation.PSCredential($retryUsername.Trim(), $newPassword)
                        } else {
                            throw "Authentication failed. User chose not to retry."
                        }
                    }
                    "nodename nor servname provided|No such host is known" {
                        Write-LogMessage -Type ERROR -Message "Cannot resolve vCenter `"$ServerName`". Check DNS or specify an IP address."
                        if ($AllowVcenterAddressRetry.IsPresent -and -not [Console]::IsInputRedirected) {
                            Write-Host ""
                            $dnsRetry = $null
                            while ($dnsRetry -ne "Y" -and $dnsRetry -ne "N") {
                                $dnsRetry = (Read-Host "Would you like to re-enter your vCenter FQDN or IP address? (Y/N)").Trim().ToUpper()
                            }
                            if ($dnsRetry -eq "Y") {
                                return $SCRIPT:CONNECT_VCENTER_RETRY_VCENTER_ADDRESS
                            }
                            Write-LogMessage -Type INFO -Message "Exiting."
                            exit 0
                        }
                        throw "Manage-VMClasses cannot continue. Check logs for details."
                    }
                    default {
                        Write-LogMessage -Type DEBUG -Message "Connection error details: $errorMessage."
                        switch -Regex ($errorMessage) {
                            "Network is unreachable|unreachable\s*\(.*:443\)" {
                                Write-LogMessage -Type ERROR -Message "Cannot reach vCenter `"$ServerName`" on the network. Check that port 443 is reachable."
                            }
                            "did not properly respond|connection.*failed|timed out|host has failed to respond" {
                                Write-LogMessage -Type ERROR -Message "Connection to vCenter `"$ServerName`" timed out or the host did not respond."
                            }
                            default {
                                Write-LogMessage -Type ERROR -Message "Failed to connect to vCenter `"$ServerName`": $errorMessage"
                            }
                        }
                        throw "Manage-VMClasses cannot continue. Check logs for details."
                    }
                }
            }
        }
    } else {
        $existingUsername = ($defaultViServers | Where-Object { $_.Name -eq $ServerName }).User
        if (-not [string]::IsNullOrWhiteSpace([string]$existingUsername)) {
            Write-LogMessage -Type WARNING -Message "Already connected to vCenter `"$ServerName`" as `"$existingUsername`"."
        } else {
            Write-LogMessage -Type WARNING -Message "Already connected to vCenter `"$ServerName`"."
        }
    }
}
Function Test-VcenterReachability {

    <#
        .SYNOPSIS
        Checks that a vCenter address is DNS-resolvable and has TCP port 443 open.

        .DESCRIPTION
        First resolves the hostname via DNS (succeeds trivially for IP addresses). If resolution
        succeeds, opens a TCP connection to port 443 and waits up to -TimeoutMilliseconds. Returns
        a PSCustomObject with Success and ErrorMessage properties; never throws.

        .PARAMETER Server
        vCenter FQDN or IP address to test.

        .PARAMETER TimeoutMilliseconds
        Maximum wait time for the TCP connection attempt. Default: 3000.

        .OUTPUTS
        PSCustomObject — { Success: [Bool]; ErrorMessage: [String] }
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Server,
        [Parameter(Mandatory = $false)] [ValidateRange(100, 30000)] [Int]$TimeoutMilliseconds = 3000
    )

    Write-LogMessage -Type DEBUG -Message "Entered Test-VcenterReachability function..."

    $serverTrimmed = $Server.Trim()

    try {
        $null = [System.Net.Dns]::GetHostAddresses($serverTrimmed)
    } catch {
        return [PSCustomObject]@{
            Success      = $false
            ErrorMessage = "Cannot resolve `"$serverTrimmed`". Check DNS or specify an IP address."
        }
    }

    $tcpClient = [System.Net.Sockets.TcpClient]::new()
    try {
        $connectTask = $tcpClient.ConnectAsync($serverTrimmed, 443)
        if (-not $connectTask.Wait($TimeoutMilliseconds)) {
            return [PSCustomObject]@{
                Success      = $false
                ErrorMessage = "Cannot reach `"$serverTrimmed`" on port 443 (timed out after $($TimeoutMilliseconds)ms). Check network connectivity and firewall."
            }
        }
        if (-not $tcpClient.Connected) {
            return [PSCustomObject]@{
                Success      = $false
                ErrorMessage = "TCP connection to port 443 on `"$serverTrimmed`" failed. Verify the vCenter service is running."
            }
        }
    } catch {
        $innerMsg = if ($null -ne $_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
        return [PSCustomObject]@{
            Success      = $false
            ErrorMessage = "Cannot reach `"$serverTrimmed`" on port 443: $innerMsg"
        }
    } finally {
        $tcpClient.Dispose()
    }

    return [PSCustomObject]@{
        Success      = $true
        ErrorMessage = ""
    }
}
Function Disconnect-Vcenter {

    <#
        .SYNOPSIS
        Disconnects from one or all active vCenter sessions.

        .PARAMETER AllServers
        Disconnects all active PowerCLI sessions.

        .PARAMETER ServerName
        vCenter FQDN or IP to disconnect from. Required when -AllServers is not specified.

        .PARAMETER Silence
        Suppresses success messages from the console (still written to the log file).
    #>

    [CmdletBinding(DefaultParameterSetName = "Single")]
    Param (
        [Parameter(Mandatory = $true, ParameterSetName = "All")] [Switch]$AllServers,
        [Parameter(Mandatory = $true, ParameterSetName = "Single")] [ValidateNotNullOrEmpty()] [String]$ServerName,
        [Parameter(Mandatory = $false)] [Switch]$Silence
    )

    Write-LogMessage -Type DEBUG -Message "Entered Disconnect-Vcenter function..."

    if ($AllServers) {
        try {
            Disconnect-VIServer -Server * -Force -Confirm:$false -ErrorAction Stop | Out-Null
        } catch {
            if ($_.Exception.Message -notmatch "Could not find any of the servers") {
                Write-LogMessage -Type DEBUG -Message "Bulk disconnect failed; trying individual: $($_.Exception.Message)"
                $defaultViServer = Get-PowerCliDefaultViServer
                if ($null -ne $defaultViServer) {
                    foreach ($srv in @($defaultViServer)) {
                        Disconnect-VIServer -Server $srv.Name -Force -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
                    }
                }
            }
        }

        $defaultViServer = Get-PowerCliDefaultViServer
        $activeConnections = @(if ($null -ne $defaultViServer) { @($defaultViServer) | Where-Object { $_.IsConnected } } else { @() })

        if ($activeConnections.Count -eq 0) {
            if ($Silence) {
                Write-LogMessage -Type INFO -SuppressOutputToScreen -Message "Successfully disconnected from all vCenter connections."
            } else {
                Write-LogMessage -Type INFO -Message "Successfully disconnected from all vCenter connections."
            }
        } else {
            $names = $activeConnections | Select-Object -ExpandProperty Name
            Write-LogMessage -Type ERROR -Message "Failed to disconnect from all servers. Still active: $($names -join ', ')"
        }
    } else {
        try {
            Write-LogMessage -Type DEBUG -Message "Disconnecting from vCenter `"$ServerName`"..."
            Disconnect-VIServer -Server $ServerName -Force -Confirm:$false -ErrorAction Stop | Out-Null
        } catch {
            Write-LogMessage -Type DEBUG -Message "Disconnect error (non-critical): $($_.Exception.Message)"
        }
    }
}

# =============================================================================
# Discover action helpers (VM inventory scan)
# =============================================================================
Function Get-VmVgpuProfiles {

    <#
        .SYNOPSIS
        Returns the sorted, unique set of vGPU profile names attached to a VM.

        .DESCRIPTION
        Iterates the VM's virtual devices and checks for PCI-passthrough backing that carries a
        non-empty Vgpu profile name. All names are lowercased to match the DNS-style requirement.
        Returns an empty array when the VM has no vGPU devices or when the data is unavailable.

        .PARAMETER Vm
        A VM object returned by Get-VM.

        .OUTPUTS
        System.String[] — sorted unique profile name strings, or an empty array.
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNull()] [Object]$Vm
    )

    $profiles = [System.Collections.Generic.List[string]]::new()

    try {
        foreach ($device in @($Vm.ExtensionData.Config.Hardware.Device)) {
            if ($null -eq $device -or $null -eq $device.Backing) {
                continue
            }

            $vgpuProp = $device.Backing.PSObject.Properties.Match("Vgpu")
            if ($null -eq $vgpuProp -or $vgpuProp.Count -eq 0) {
                continue
            }

            $profileName = [string]$device.Backing.Vgpu
            if (-not [string]::IsNullOrWhiteSpace($profileName)) {
                [void]$profiles.Add($profileName.ToLowerInvariant().Trim())
            }
        }
    } catch {
        Write-LogMessage -Type DEBUG -Message "Could not read vGPU configuration for VM `"$($Vm.Name)`": $($_.Exception.Message)"
    }

    $sortedProfiles = @($profiles | Sort-Object -Unique)
    if ($sortedProfiles.Count -gt 0) {
        Write-LogMessage -Type DEBUG -Message "VM `"$($Vm.Name)`" has vGPU profile(s): $($sortedProfiles -join ', ')."
    }

    return $sortedProfiles
}
Function Get-VmInventoryData {

    <#
        .SYNOPSIS
        Retrieves all VMs from vCenter and records their CPU count, memory, and reservation flags.

        .DESCRIPTION
        Uses Get-VM to enumerate all VMs. For each VM, reads NumCpu (aggregate cores), MemoryMB,
        CPU/memory reservation values from ExtensionData.ResourceConfig, and vGPU profile names
        via Get-VmVgpuProfiles. A non-zero reservation results in HasCpuReservation or
        HasMemReservation being $true.

        .PARAMETER Server
        vCenter FQDN or IP to query.

        .OUTPUTS
        PSCustomObject[] — one entry per VM with VmName, NumCpu, MemoryMB, HasCpuReservation,
        HasMemReservation, VgpuProfiles.
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Server
    )

    Write-LogMessage -Type DEBUG -Message "Entered Get-VmInventoryData function..."

    $vms = @(Get-VM -Server $Server -ErrorAction Stop)
    Write-LogMessage -Type DEBUG -Message "Retrieved $($vms.Count) VM(s) from vCenter `"$Server`"."

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($vm in $vms) {
        $cpuReservationMhz = 0
        $memReservationMB = 0

        try {
            if ($null -ne $vm.ExtensionData -and $null -ne $vm.ExtensionData.ResourceConfig) {
                if ($null -ne $vm.ExtensionData.ResourceConfig.CpuAllocation) {
                    $cpuReservationMhz = $vm.ExtensionData.ResourceConfig.CpuAllocation.Reservation
                }
                if ($null -ne $vm.ExtensionData.ResourceConfig.MemoryAllocation) {
                    $memReservationMB = $vm.ExtensionData.ResourceConfig.MemoryAllocation.Reservation
                }
            }
        } catch {
            Write-LogMessage -Type DEBUG -Message "Could not read resource configuration for VM `"$($vm.Name)`": $($_.Exception.Message)"
        }

        $vgpuProfiles = @(Get-VmVgpuProfiles -Vm $vm)

        [void]$results.Add([PSCustomObject]@{
            VmName            = $vm.Name
            NumCpu            = [int]$vm.NumCpu
            MemoryMB          = [int64]$vm.MemoryMB
            HasCpuReservation = ($cpuReservationMhz -gt 0)
            HasMemReservation = ($memReservationMB -gt 0)
            VgpuProfiles      = $vgpuProfiles
        })
    }

    return @($results)
}
Function Get-VmConfigurationGroups {

    <#
        .SYNOPSIS
        Groups VM inventory records by unique configuration and returns one summary row per group.

        .DESCRIPTION
        Groups by NumCpu, MemoryMB, HasCpuReservation, HasMemReservation, and the sorted set of
        vGPU profile names. Results are sorted by VmCount descending.

        .PARAMETER InventoryData
        Output of Get-VmInventoryData.

        .OUTPUTS
        PSCustomObject[] — one entry per unique configuration with NumCpu, MemoryMB,
        HasCpuReservation, HasMemReservation, VgpuProfiles, and VmCount.
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNull()] [Object[]]$InventoryData
    )

    Write-LogMessage -Type DEBUG -Message "Entered Get-VmConfigurationGroups function..."

    $groups = $InventoryData |
        Group-Object -Property NumCpu, MemoryMB, HasCpuReservation, HasMemReservation,
            { ($_.VgpuProfiles | Sort-Object) -join "|" } |
        Sort-Object -Property @{ Expression = { $_.Count }; Descending = $true }

    $result = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($group in $groups) {
        $sample = $group.Group[0]
        [void]$result.Add([PSCustomObject]@{
            NumCpu            = $sample.NumCpu
            MemoryMB          = $sample.MemoryMB
            HasCpuReservation = $sample.HasCpuReservation
            HasMemReservation = $sample.HasMemReservation
            VgpuProfiles      = @($sample.VgpuProfiles)
            VmCount           = $group.Count
        })
    }

    return @($result)
}
Function ConvertTo-TruncatedVmClassJsonName {

    <#
        .SYNOPSIS
        Produces a VM class name that includes the GPU segment and fits within the DNS label limit.

        .DESCRIPTION
        Applies a progressive truncation chain so the name never exceeds MaxLength characters.
        Steps: (1) remove vowels from GPU segment, (2) collapse "nvd" to "nv", (3) abbreviate
        commitment words to "gt" / "bt", (4) auto-generate a stable 10-char SHA-256 hash name.

        .PARAMETER BaseName
        The CPU/memory portion of the class name.

        .PARAMETER GpuSegment
        The GPU profile portion to append.

        .PARAMETER MaxLength
        Maximum character length. Defaults to $SCRIPT:VM_CLASS_NAME_MAX_LENGTH (63).

        .OUTPUTS
        System.String
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$BaseName,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$GpuSegment,
        [Parameter(Mandatory = $false)] [ValidateRange(10, 253)] [Int]$MaxLength = $SCRIPT:VM_CLASS_NAME_MAX_LENGTH
    )

    $fullName = "$BaseName-$GpuSegment"
    if ($fullName.Length -le $MaxLength) {
        return $fullName
    }

    $gpuV1 = ($GpuSegment -replace "[aeiou]", "") -replace "-{2,}", "-"
    $gpuV1 = $gpuV1.Trim("-")
    $candidate = "$BaseName-$gpuV1"
    if ($candidate.Length -le $MaxLength) {
        Write-LogMessage -Type INFO -Message "Class name `"$fullName`" ($($fullName.Length) chars) exceeds $MaxLength; removed vowels from GPU segment → `"$candidate`"."
        return $candidate
    }

    $gpuV2 = $gpuV1 -replace "nvd", "nv"
    $candidate = "$BaseName-$gpuV2"
    if ($candidate.Length -le $MaxLength) {
        Write-LogMessage -Type INFO -Message "Class name `"$fullName`" ($($fullName.Length) chars) exceeds $MaxLength; collapsed nvidia abbreviation → `"$candidate`"."
        return $candidate
    }

    $shortBase = $BaseName -replace "guaranteed", "gt" -replace "besteffort", "bt"
    $candidate = "$shortBase-$gpuV2"
    if ($candidate.Length -le $MaxLength) {
        Write-LogMessage -Type INFO -Message "Class name `"$fullName`" ($($fullName.Length) chars) exceeds $MaxLength; abbreviated commitments → `"$candidate`"."
        return $candidate
    }

    $hashBytes = [System.Security.Cryptography.SHA256]::Create().ComputeHash(
        [System.Text.Encoding]::UTF8.GetBytes($fullName)
    )
    $shortHash = ([System.BitConverter]::ToString($hashBytes) -replace "-", "").ToLower().Substring(0, 10)
    $autoName = "vmclass-$shortHash"

    Write-LogMessage -Type WARNING -Message "Class name `"$fullName`" ($($fullName.Length) chars) cannot be shortened to $MaxLength chars or fewer; using auto-generated name `"$autoName`"."
    return $autoName
}
Function ConvertTo-VmClassJsonName {

    <#
        .SYNOPSIS
        Generates the DNS-style VM class name for a configuration group.

        .DESCRIPTION
        Returns a name in the format {N}cpu-{cpuCommitment}-{M}mb-{memCommitment} for non-GPU
        classes, or appends the GPU profile segment and applies truncation via
        ConvertTo-TruncatedVmClassJsonName when vGPU profiles are present.

        .PARAMETER ConfigGroup
        A configuration group as returned by Get-VmConfigurationGroups.

        .OUTPUTS
        System.String
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNull()] [PSCustomObject]$ConfigGroup
    )

    $cpuPart  = if ($ConfigGroup.HasCpuReservation) { "guaranteed" } else { "besteffort" }
    $memPart  = if ($ConfigGroup.HasMemReservation) { "guaranteed" } else { "besteffort" }
    $baseName = "$($ConfigGroup.NumCpu)cpu-$cpuPart-$($ConfigGroup.MemoryMB)mb-$memPart"

    $vgpuProfiles = @(if ($null -ne $ConfigGroup.VgpuProfiles) { $ConfigGroup.VgpuProfiles } else { @() })
    if ($vgpuProfiles.Count -eq 0) {
        return $baseName
    }

    $gpuSegment = $vgpuProfiles -join "-"
    return ConvertTo-TruncatedVmClassJsonName -BaseName $baseName -GpuSegment $gpuSegment
}
Function Get-TuiConfigurationSelection {

    <#
        .SYNOPSIS
        Interactive space-bar selection TUI for VM configuration groups.

        .DESCRIPTION
        Renders a checkbox table driven entirely by keyboard. Arrow keys move the cursor, Space
        toggles the checkbox on the highlighted row, A toggles all rows on or off, and Enter
        confirms the selection. Redraws use the ANSI ESC[NF sequence for relative cursor movement
        so the table overwrites itself correctly even when the terminal scrolls.

        Requires stdout to be a console (not redirected). Call Get-UserConfigurationSelection
        which automatically falls back to text-based input when output is redirected.

        .PARAMETER ClassNames
        Pre-computed class name strings, one per ConfigGroup entry (same index order).

        .PARAMETER ConfigGroups
        Configuration groups from Get-VmConfigurationGroups.

        .PARAMETER MaxNameLength
        Width of the Class Name column.

        .OUTPUTS
        PSCustomObject[] — the selected subset of ConfigGroups.

        .NOTES
        Write-Host is used here by design for color-coded interactive table rows and prompts.
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNull()] [String[]]$ClassNames,
        [Parameter(Mandatory = $true)] [ValidateNotNull()] [Object[]]$ConfigGroups,
        [Parameter(Mandatory = $true)] [ValidateRange(1, 200)] [Int]$MaxNameLength
    )

    $selectedFlags = [bool[]]::new($ConfigGroups.Count)
    $currentIndex = 0
    $showNoSelectionWarning = $false

    $hasAnyVgpu = @($ConfigGroups | Where-Object { $null -ne $_.VgpuProfiles -and $_.VgpuProfiles.Count -gt 0 }).Count -gt 0
    $maxVgpuWidth = 0
    if ($hasAnyVgpu) {
        $maxVgpuWidth = [Math]::Max(
            13,
            ($ConfigGroups | ForEach-Object {
                if ($null -ne $_.VgpuProfiles -and $_.VgpuProfiles.Count -gt 0) {
                    ($_.VgpuProfiles -join ", ").Length
                } else {
                    3
                }
            } | Measure-Object -Maximum).Maximum
        )
    }

    $renderSelectAllRow = {
        $allSelected = $selectedFlags -notcontains $false
        $cursor   = if ($currentIndex -eq -1) { ">" } else { " " }
        $checkbox = if ($allSelected) { "[x]" } else { "[ ]" }
        $line     = ("$cursor $checkbox {0,-$MaxNameLength}" -f "Select All").PadRight([Console]::WindowWidth - 1)
        if ($currentIndex -eq -1) {
            Write-Host $line -ForegroundColor Cyan
        } else {
            Write-Host $line -ForegroundColor Gray
        }
    }

    $renderRow = {
        Param ([int]$RowIndex, [bool]$IsActive)
        $group = $ConfigGroups[$RowIndex]
        $cursor = if ($IsActive) { ">" } else { " " }
        $checkbox = if ($selectedFlags[$RowIndex]) { "[x]" } else { "[ ]" }
        $cpuRes = if ($group.HasCpuReservation) { "Yes" } else { "No" }
        $memRes = if ($group.HasMemReservation) { "Yes" } else { "No" }
        $memDisplay = $group.MemoryMB.ToString("N0")
        if ($hasAnyVgpu) {
            $vgpuDisplay = if ($null -ne $group.VgpuProfiles -and $group.VgpuProfiles.Count -gt 0) {
                $group.VgpuProfiles -join ", "
            } else {
                "N/A"
            }
            $line = ("$cursor $checkbox {0,-$MaxNameLength} {1,5} {2,11}  {3,-12} {4,-12} {5,-$maxVgpuWidth}  {6,9}" -f
                $ClassNames[$RowIndex], $group.NumCpu, $memDisplay, $cpuRes, $memRes, $vgpuDisplay, $group.VmCount
            ).PadRight([Console]::WindowWidth - 1)
        } else {
            $line = ("$cursor $checkbox {0,-$MaxNameLength} {1,5} {2,11}  {3,-12} {4,-12} {5,9}" -f
                $ClassNames[$RowIndex], $group.NumCpu, $memDisplay, $cpuRes, $memRes, $group.VmCount
            ).PadRight([Console]::WindowWidth - 1)
        }
        if ($IsActive) {
            Write-Host $line -ForegroundColor Cyan
        } else {
            Write-Host $line
        }
    }

    $headerLine = if ($hasAnyVgpu) {
        "      {0,-$MaxNameLength} {1,5} {2,11}  {3,-12} {4,-12} {5,-$maxVgpuWidth}  {6,9}" -f
            "Class Name", "CPUs", "Memory (MB)", "CPU Reserved", "Mem Reserved", "vGPU Profiles", "VM Count"
    } else {
        "      {0,-$MaxNameLength} {1,5} {2,11}  {3,-12} {4,-12} {5,9}" -f
            "Class Name", "CPUs", "Memory (MB)", "CPU Reserved", "Mem Reserved", "VM Count"
    }
    Write-Host $headerLine -ForegroundColor Cyan
    Write-Host ("  " + "-" * ($headerLine.Length - 2)) -ForegroundColor Cyan
    Write-Host "  Space=toggle  Arrow keys=navigate  A=select all / none  Enter=confirm" -ForegroundColor Gray
    Write-Host ""

    & $renderSelectAllRow
    for ($i = 0; $i -lt $ConfigGroups.Count; $i++) {
        & $renderRow $i ($i -eq $currentIndex)
    }
    Write-Host "".PadRight([Console]::WindowWidth - 1) -NoNewline

    while ($true) {
        $key = [Console]::ReadKey($true)

        switch ($key.Key) {
            "UpArrow" {
                if ($currentIndex -gt 0) { $currentIndex-- }
                elseif ($currentIndex -eq 0) { $currentIndex = -1 }
                $showNoSelectionWarning = $false
                break
            }
            "DownArrow" {
                if ($currentIndex -eq -1) { $currentIndex = 0 }
                elseif ($currentIndex -lt ($ConfigGroups.Count - 1)) { $currentIndex++ }
                $showNoSelectionWarning = $false
                break
            }
            "Spacebar" {
                if ($currentIndex -eq -1) {
                    $allSelected = $selectedFlags -notcontains $false
                    for ($i = 0; $i -lt $selectedFlags.Count; $i++) {
                        $selectedFlags[$i] = -not $allSelected
                    }
                } else {
                    $selectedFlags[$currentIndex] = -not $selectedFlags[$currentIndex]
                }
                $showNoSelectionWarning = $false
                break
            }
            "Enter" {
                $result = @(0..($ConfigGroups.Count - 1) | Where-Object { $selectedFlags[$_] } | ForEach-Object { $ConfigGroups[$_] })
                if ($result.Count -eq 0) {
                    $showNoSelectionWarning = $true
                } else {
                    Write-Host ""
                    return $result
                }
                break
            }
        }

        if ($key.KeyChar -eq 'a' -or $key.KeyChar -eq 'A') {
            $allSelected = ($selectedFlags -notcontains $false)
            for ($i = 0; $i -lt $selectedFlags.Count; $i++) {
                $selectedFlags[$i] = -not $allSelected
            }
            $showNoSelectionWarning = $false
        }

        Write-Host -NoNewline "`e[$($ConfigGroups.Count + 1)F"
        & $renderSelectAllRow
        for ($i = 0; $i -lt $ConfigGroups.Count; $i++) {
            & $renderRow $i ($i -eq $currentIndex)
        }
        $warningText = if ($showNoSelectionWarning) { "  Select at least one row (Space) before pressing Enter." } else { "" }
        Write-Host $warningText.PadRight([Console]::WindowWidth - 1) -NoNewline
    }
}
Function Write-VmConfigurationSummaryTable {

    <#
        .SYNOPSIS
        Prints a read-only summary table of VM configuration groups (no selection prompt).

        .DESCRIPTION
        Outputs the class-name legend and a formatted table of all configuration groups.
        Used by the -SaveAll path in Discover to show what will be written to the output
        file without launching the interactive TUI or prompting for row selection.

        .PARAMETER ClassNames
        Pre-computed class name strings, one per ConfigGroups entry (same index order).

        .PARAMETER ConfigGroups
        Configuration groups from Get-VmConfigurationGroups.
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNull()] [String[]]$ClassNames,
        [Parameter(Mandatory = $true)] [ValidateNotNull()] [Object[]]$ConfigGroups
    )

    $hasAnyVgpu = @($ConfigGroups | Where-Object { $null -ne $_.VgpuProfiles -and $_.VgpuProfiles.Count -gt 0 }).Count -gt 0

    Write-Host ""
    Write-Host "Class name format: {N}cpu-{cpu-commitment}-{M}mb-{mem-commitment}[-{gpu-profile}]" -ForegroundColor Cyan
    Write-Host "  `"guaranteed`" = VMs in this group have a non-zero reservation; `"besteffort`" = no reservation." -ForegroundColor Gray
    if ($hasAnyVgpu) {
        Write-Host "  GPU profile names are embedded in the class name; long names are truncated automatically." -ForegroundColor Gray
    }
    Write-Host ""

    $rowIndex = 0
    $tableRows = foreach ($group in $ConfigGroups) {
        $rowProps = [ordered]@{
            "Class Name"   = $ClassNames[$rowIndex]
            "CPUs"         = $group.NumCpu
            "Memory (MB)"  = $group.MemoryMB.ToString("N0")
            "CPU Reserved" = if ($group.HasCpuReservation) { "Yes" } else { "No" }
            "Mem Reserved" = if ($group.HasMemReservation) { "Yes" } else { "No" }
        }
        if ($hasAnyVgpu) {
            $rowProps["vGPU Profiles"] = if ($null -ne $group.VgpuProfiles -and $group.VgpuProfiles.Count -gt 0) {
                $group.VgpuProfiles -join ", "
            } else {
                "N/A"
            }
        }
        $rowProps["VM Count"] = $group.VmCount
        [PSCustomObject]$rowProps
        $rowIndex++
    }

    $tableRows | Format-Table -AutoSize | Out-Host
}
Function Get-UserConfigurationSelection {

    <#
        .SYNOPSIS
        Displays VM configurations and lets the user select which to export as JSON.

        .DESCRIPTION
        Prints a naming-convention note then presents the configuration table. When stdout is a
        console, uses an interactive TUI (arrow keys, Space, A, Enter). When stdout is redirected,
        falls back to a numbered table with comma-separated row number input.

        .PARAMETER ConfigGroups
        Array of configuration groups from Get-VmConfigurationGroups.

        .OUTPUTS
        PSCustomObject[] — the selected subset of ConfigGroups.

        .NOTES
        Write-Host is used here by design for interactive tables and prompts.
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNull()] [Object[]]$ConfigGroups
    )

    Write-LogMessage -Type DEBUG -Message "Entered Get-UserConfigurationSelection function..."

    $classNames = @($ConfigGroups | ForEach-Object { ConvertTo-VmClassJsonName -ConfigGroup $_ })
    $maxNameLength = [Math]::Max(10, ($classNames | Measure-Object -Property Length -Maximum).Maximum)
    $hasAnyVgpu = @($ConfigGroups | Where-Object { $null -ne $_.VgpuProfiles -and $_.VgpuProfiles.Count -gt 0 }).Count -gt 0

    Write-Host ""
    Write-Host "Class name format: {N}cpu-{cpu-commitment}-{M}mb-{mem-commitment}[-{gpu-profile}]" -ForegroundColor Cyan
    Write-Host "  `"guaranteed`" = VMs in this group have a non-zero reservation; `"besteffort`" = no reservation." -ForegroundColor Gray
    if ($hasAnyVgpu) {
        Write-Host "  GPU profile names are embedded in the class name; long names are truncated automatically." -ForegroundColor Gray
    }
    Write-Host ""

    $canUseTui = (-not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected)

    if ($canUseTui) {
        return Get-TuiConfigurationSelection -ClassNames $classNames -ConfigGroups $ConfigGroups -MaxNameLength $maxNameLength
    }

    $rowIndex = 1
    $tableRows = foreach ($group in $ConfigGroups) {
        $rowProps = [ordered]@{
            "#"            = $rowIndex
            "Class Name"   = $classNames[$rowIndex - 1]
            "CPUs"         = $group.NumCpu
            "Memory (MB)"  = $group.MemoryMB.ToString("N0")
            "CPU Reserved" = if ($group.HasCpuReservation) { "Yes" } else { "No" }
            "Mem Reserved" = if ($group.HasMemReservation) { "Yes" } else { "No" }
        }
        if ($hasAnyVgpu) {
            $rowProps["vGPU Profiles"] = if ($null -ne $group.VgpuProfiles -and $group.VgpuProfiles.Count -gt 0) {
                $group.VgpuProfiles -join ", "
            } else {
                "N/A"
            }
        }
        $rowProps["VM Count"] = $group.VmCount
        [PSCustomObject]$rowProps
        $rowIndex++
    }
    $tableRows | Format-Table -AutoSize | Out-Host

    $selectedGroups = $null
    while ($null -eq $selectedGroups) {
        $rawInput = (Read-Host "Enter row number(s) to include in output JSON (comma-separated or 'all')").Trim()

        if ([string]::IsNullOrWhiteSpace($rawInput)) {
            Write-Host -ForegroundColor Yellow "Please enter one or more row numbers or 'all'."
            continue
        }

        if ($rawInput -ieq "all") {
            $selectedGroups = $ConfigGroups
            break
        }

        $valid = $true
        $selectedIndices = [System.Collections.Generic.List[int]]::new()

        foreach ($token in ($rawInput -split ',')) {
            $token = $token.Trim()
            $parsed = 0
            if (-not [int]::TryParse($token, [ref]$parsed)) {
                Write-Host -ForegroundColor Yellow "Invalid entry: `"$token`" is not an integer. Enter comma-separated row numbers or 'all'."
                $valid = $false
                break
            }
            if ($parsed -lt 1 -or $parsed -gt $ConfigGroups.Count) {
                Write-Host -ForegroundColor Yellow "Row $parsed is out of range (valid: 1 to $($ConfigGroups.Count)). Please try again."
                $valid = $false
                break
            }
            [void]$selectedIndices.Add($parsed)
        }

        if ($valid) {
            $selectedGroups = @($selectedIndices | Sort-Object -Unique | ForEach-Object { $ConfigGroups[$_ - 1] })
        }
    }

    return $selectedGroups
}
Function Get-TuiVmClassSelection {

    <#
        .SYNOPSIS
        Interactive multi-select TUI for choosing VM class names from a list.

        .DESCRIPTION
        Renders a checkbox list driven by keyboard. Arrow keys navigate, Space toggles a row,
        A toggles all rows on or off, Enter confirms, and Escape cancels. At least one selection
        is required before Enter is accepted.

        Requires stdout to be a console (not redirected). Call Get-UserVmClassSelection which
        handles the non-interactive fallback.

        .PARAMETER ClassNames
        List of VM class names to display as selectable rows.

        .PARAMETER DefaultSelectAll
        When set, all rows are pre-selected and the cursor starts on the "Select All" row,
        so the user can press Enter immediately to import every class.

        .OUTPUTS
        System.String[] — selected class names (never empty).

        .NOTES
        Write-Host is used here by design for color-coded interactive table rows and prompts.
        Throws OperationCanceledException when the user presses Escape.
    #>

    Param (
        [Parameter(Mandatory = $true)]  [ValidateNotNull()] [String[]]$ClassNames,
        [Parameter(Mandatory = $false)] [Switch]$DefaultSelectAll
    )

    $selectedFlags = [bool[]]::new($ClassNames.Count)
    $currentIndex = if ($DefaultSelectAll) { -1 } else { 0 }
    if ($DefaultSelectAll) {
        for ($i = 0; $i -lt $selectedFlags.Count; $i++) { $selectedFlags[$i] = $true }
    }
    $showNoSelectionWarning = $false
    $maxNameLength = [Math]::Max(10, ($ClassNames | Measure-Object -Property Length -Maximum).Maximum)

    $renderSelectAllRow = {
        $allSelected = $selectedFlags -notcontains $false
        $cursor   = if ($currentIndex -eq -1) { ">" } else { " " }
        $checkbox = if ($allSelected) { "[x]" } else { "[ ]" }
        $line = ("$cursor $checkbox {0,-$maxNameLength}" -f "Select All").PadRight([Console]::WindowWidth - 1)
        if ($currentIndex -eq -1) {
            Write-Host $line -ForegroundColor Cyan
        } else {
            Write-Host $line -ForegroundColor Gray
        }
    }

    $renderRow = {
        Param ([int]$RowIndex, [bool]$IsActive)
        $cursor   = if ($IsActive) { ">" } else { " " }
        $checkbox = if ($selectedFlags[$RowIndex]) { "[x]" } else { "[ ]" }
        $line = ("$cursor $checkbox {0,-$maxNameLength}" -f $ClassNames[$RowIndex]).PadRight([Console]::WindowWidth - 1)
        if ($IsActive) {
            Write-Host $line -ForegroundColor Cyan
        } else {
            Write-Host $line
        }
    }

    $headerLine = "      {0,-$maxNameLength}" -f "Class Name"
    Write-Host $headerLine -ForegroundColor Cyan
    Write-Host ("  " + "-" * ($maxNameLength + 4)) -ForegroundColor Cyan
    Write-Host "  Space=toggle  Arrow keys=navigate  A=select all / none  Enter=confirm  Esc=cancel" -ForegroundColor Gray
    Write-Host ""

    & $renderSelectAllRow
    for ($i = 0; $i -lt $ClassNames.Count; $i++) {
        & $renderRow $i ($i -eq $currentIndex)
    }
    Write-Host "".PadRight([Console]::WindowWidth - 1) -NoNewline

    while ($true) {
        $key = [Console]::ReadKey($true)

        switch ($key.Key) {
            "UpArrow" {
                if ($currentIndex -gt 0) { $currentIndex-- }
                elseif ($currentIndex -eq 0) { $currentIndex = -1 }
                $showNoSelectionWarning = $false
                break
            }
            "DownArrow" {
                if ($currentIndex -eq -1) { $currentIndex = 0 }
                elseif ($currentIndex -lt ($ClassNames.Count - 1)) { $currentIndex++ }
                $showNoSelectionWarning = $false
                break
            }
            "Spacebar" {
                if ($currentIndex -eq -1) {
                    $allSelected = $selectedFlags -notcontains $false
                    for ($i = 0; $i -lt $selectedFlags.Count; $i++) {
                        $selectedFlags[$i] = -not $allSelected
                    }
                } else {
                    $selectedFlags[$currentIndex] = -not $selectedFlags[$currentIndex]
                }
                $showNoSelectionWarning = $false
                break
            }
            "Enter" {
                $result = @(0..($ClassNames.Count - 1) | Where-Object { $selectedFlags[$_] } | ForEach-Object { $ClassNames[$_] })
                if ($result.Count -eq 0) {
                    $showNoSelectionWarning = $true
                } else {
                    Write-Host ""
                    return $result
                }
                break
            }
            "Escape" {
                Write-Host ""
                throw [System.OperationCanceledException]::new("VM class selection cancelled by user.")
            }
        }

        if ($key.KeyChar -eq 'a' -or $key.KeyChar -eq 'A') {
            $allSelected = ($selectedFlags -notcontains $false)
            for ($i = 0; $i -lt $selectedFlags.Count; $i++) {
                $selectedFlags[$i] = -not $allSelected
            }
            $showNoSelectionWarning = $false
        }

        Write-Host -NoNewline "`e[$($ClassNames.Count + 1)F"
        & $renderSelectAllRow
        for ($i = 0; $i -lt $ClassNames.Count; $i++) {
            & $renderRow $i ($i -eq $currentIndex)
        }
        $warningText = if ($showNoSelectionWarning) { "  Select at least one row (Space) before pressing Enter." } else { "" }
        Write-Host $warningText.PadRight([Console]::WindowWidth - 1) -NoNewline
    }
}
Function Get-UserVmClassSelection {

    <#
        .SYNOPSIS
        Presents a multi-select VM class menu and returns the selected class names.

        .DESCRIPTION
        Loads class names from the JSON file and, when stdout is a console, shows the interactive
        TUI (Get-TuiVmClassSelection). Non-interactive sessions throw because they require
        -VmClassName to be passed explicitly.

        .PARAMETER DefaultSelectAll
        When set, all rows are pre-selected and the cursor starts on the "Select All" row.
        Use for the import workflow where the intent is to apply every class.

        .PARAMETER JsonFilePath
        Path to the VM classes JSON file (must exist).

        .PARAMETER Action
        Update — used in error messaging.

        .OUTPUTS
        System.String[] — selected class names (never empty).

        .NOTES
        Write-Host is used here by design for interactive tables and prompts.
    #>

    Param (
        [Parameter(Mandatory = $false)] [Switch]$DefaultSelectAll,
        [Parameter(Mandatory = $true)]  [ValidateNotNullOrEmpty()] [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })] [String]$JsonFilePath,
        [Parameter(Mandatory = $true)]  [ValidateSet("Update")] [String]$Action
    )

    Write-LogMessage -Type DEBUG -Message "Entered Get-UserVmClassSelection function..."

    if ([Console]::IsInputRedirected) {
        throw "Non-interactive session: pass -Action with a class name or `"all`" to run $Action without a prompt."
    }

    $entries = Get-VmClassJsonValidatedEntryList -JsonFilePath $JsonFilePath
    if ($entries.Count -eq 0) {
        throw "No VM class entries found in `"$JsonFilePath`". Add entries to the file before running $Action."
    }

    $classNames = @($entries | ForEach-Object { Get-VmClassJsonEntryName -Entry $_ })

    Write-Host ""
    Write-LogMessage -Type INFO -Message "Select VM class(es) to $($Action.ToLowerInvariant()):"
    Write-LogMessage -Type INFO -Message "Source file: `"$JsonFilePath`""
    Write-Host ""

    try {
        return @(Get-TuiVmClassSelection -ClassNames $classNames -DefaultSelectAll:$DefaultSelectAll)
    } catch [System.OperationCanceledException] {
        Write-LogMessage -Type INFO -Message "Selection cancelled by user. Exiting."
        exit 0
    }
}
Function Get-UserCustomVmClassSelectionFromServer {

    <#
        .SYNOPSIS
        Queries vCenter for custom VM classes, filters out built-in defaults, and presents a
        multi-select TUI for the user to choose which ones to delete.

        .DESCRIPTION
        Retrieves all VM class IDs from vCenter, removes the 16 built-in default class names from
        consideration, and shows the remaining custom classes in the interactive TUI. When there are
        no custom classes, logs an informational message and returns an empty array (no TUI). Throws
        when running non-interactively without -VmClassName (use -VmClassName with a name or `"all`").

        .PARAMETER Server
        vCenter Server passed to Invoke-ListNamespaceManagementVirtualMachineClasses.

        .OUTPUTS
        System.String[] — selected custom class names, or an empty array when no custom classes exist.

        .NOTES
        Write-Host is used here by design for interactive tables and prompts.
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Server
    )

    if ([Console]::IsInputRedirected) {
        throw "Non-interactive session: pass -VmClassName with a class name or `"all`" to delete without a prompt."
    }

    Write-LogMessage -Type DEBUG -Message "Entered Get-UserCustomVmClassSelectionFromServer function..."

    $allIds = Get-ExistingVmClassIdSet -Server $Server
    $customIds = @($allIds | Where-Object { -not (Test-VmClassIsDefaultName -Name $_) } | Sort-Object)
    $defaultCount = $allIds.Count - $customIds.Count

    Write-LogMessage -Type INFO -Message "Found $($customIds.Count) custom VM class(es) on vCenter (ignoring $defaultCount built-in default(s))."

    if ($customIds.Count -eq 0) {
        Write-LogMessage -Type INFO -Message "There are no custom VM classes to delete on vCenter `"$Server`"; all class definitions are built-in defaults. Skipping delete selection."
        return @()
    }

    Write-Host ""
    Write-LogMessage -Type INFO -Message "Select VM class(es) to delete:"
    Write-Host ""

    try {
        return @(Get-TuiVmClassSelection -ClassNames $customIds)
    } catch [System.OperationCanceledException] {
        Write-LogMessage -Type INFO -Message "Selection cancelled by user. Exiting."
        exit 0
    }
}
Function Write-VmClassOutputJson {

    <#
        .SYNOPSIS
        Converts selected configuration groups to vmClasses.json-format entries and writes the file.

        .DESCRIPTION
        For each configuration group, generates a JSON object with name, cpuCount, cpuCommitment,
        memoryMB, and memoryCommitment. The file is written as a UTF-8 JSON array. The output
        directory is created if it does not already exist.

        .PARAMETER OutputFilePath
        Absolute or relative path for the output JSON file.

        .PARAMETER SelectedGroups
        Configuration groups to serialize, as returned by Get-UserConfigurationSelection.
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$OutputFilePath,
        [Parameter(Mandatory = $true)] [ValidateNotNull()] [Object[]]$SelectedGroups
    )

    Write-LogMessage -Type DEBUG -Message "Entered Write-VmClassOutputJson function..."

    $jsonEntries = foreach ($group in $SelectedGroups) {
        $cpuCommitment = if ($group.HasCpuReservation) { "guaranteed" } else { "bestEffort" }
        $memCommitment = if ($group.HasMemReservation) { "guaranteed" } else { "bestEffort" }
        $vgpuProfiles  = @(if ($null -ne $group.VgpuProfiles) { $group.VgpuProfiles } else { @() })

        if ($vgpuProfiles.Count -gt 0 -and $memCommitment -ne "guaranteed") {
            Write-LogMessage -Type INFO -Message "Class `"$(ConvertTo-VmClassJsonName -ConfigGroup $group)`": memoryCommitment forced to `"guaranteed`" because vGPU devices are present."
            $memCommitment = "guaranteed"
        }

        $entry = [ordered]@{
            name             = ConvertTo-VmClassJsonName -ConfigGroup $group
            cpuCount         = [string]$group.NumCpu
            cpuCommitment    = $cpuCommitment
            memoryMB         = [string]$group.MemoryMB
            memoryCommitment = $memCommitment
        }

        if ($vgpuProfiles.Count -gt 0) {
            $entry["vgpuDevices"] = @([PSCustomObject]@{ profileNames = @($vgpuProfiles) })
        }

        [PSCustomObject]$entry
    }

    $outputDir = Split-Path -Path $OutputFilePath -Parent
    if (-not [string]::IsNullOrWhiteSpace($outputDir) -and -not (Test-Path -LiteralPath $outputDir -PathType Container)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        Write-LogMessage -Type DEBUG -Message "Created output directory `"$outputDir`"."
    }

    $jsonContent = ConvertTo-Json -InputObject @($jsonEntries) -Depth 5
    Set-Content -Path $OutputFilePath -Value $jsonContent -Encoding UTF8

    Write-LogMessage -Type INFO -Message "Wrote $($SelectedGroups.Count) VM class definition(s) to `"$OutputFilePath`"."
}

# =============================================================================
# VM class JSON validation, REST, spec comparison, and PowerCLI queries
# =============================================================================
Function Get-VmClassJsonWholeNumberInt64Result {

    <#
        .SYNOPSIS
        Validates a cpuCount or memoryMb JSON value is a whole number representable as Int64.

        .PARAMETER FieldName
        Canonical field label for error text (cpuCount or memoryMb).

        .PARAMETER LogContext
        Prefix for error messages.

        .PARAMETER RawValue
        Property value from ConvertFrom-Json.

        .OUTPUTS
        PSCustomObject with FailureMessage ([string] or $null) and ParsedInt64 ([nullable long]).
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$FieldName,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$LogContext,
        [Parameter(Mandatory = $true)] [AllowNull()] $RawValue
    )

    switch ($true) {
        { $null -eq $RawValue } {
            return [PSCustomObject]@{
                FailureMessage = "${LogContext} : ${FieldName} value is null (required-field validation should have reported this)."
                ParsedInt64    = $null
            }
        }
        { $RawValue -is [string] } {
            $trimmed = $RawValue.Trim()
            if ($trimmed -eq "") {
                return [PSCustomObject]@{
                    FailureMessage = "${LogContext} : ${FieldName} must be a JSON integer or a string of digits (optional leading minus); got `"$RawValue`"."
                    ParsedInt64    = $null
                }
            }
            if ($trimmed -notmatch '^-?\d+$') {
                return [PSCustomObject]@{
                    FailureMessage = "${LogContext} : ${FieldName} must be a JSON integer or a digit-only string (no decimal point or exponent); got `"$RawValue`"."
                    ParsedInt64    = $null
                }
            }
            $parsedLong = 0L
            if (-not [int64]::TryParse($trimmed, [ref]$parsedLong)) {
                return [PSCustomObject]@{
                    FailureMessage = "${LogContext} : ${FieldName} must fit in a 64-bit signed integer; got `"$RawValue`"."
                    ParsedInt64    = $null
                }
            }
            return [PSCustomObject]@{ FailureMessage = $null; ParsedInt64 = $parsedLong }
        }
        { $RawValue -is [double] -or $RawValue -is [float] -or $RawValue -is [decimal] } {
            $asDec = [decimal]$RawValue
            if ($asDec -ne [System.Decimal]::Truncate($asDec)) {
                return [PSCustomObject]@{
                    FailureMessage = "${LogContext} : ${FieldName} must be a whole number (integer); got $RawValue."
                    ParsedInt64    = $null
                }
            }
            if ($asDec -lt [decimal][int64]::MinValue -or $asDec -gt [decimal][int64]::MaxValue) {
                return [PSCustomObject]@{
                    FailureMessage = "${LogContext} : ${FieldName} must fit in a 64-bit signed integer; got $RawValue."
                    ParsedInt64    = $null
                }
            }
            return [PSCustomObject]@{ FailureMessage = $null; ParsedInt64 = [int64]$asDec }
        }
        { $RawValue -is [byte] -or $RawValue -is [sbyte] -or $RawValue -is [int16] -or $RawValue -is [uint16] -or $RawValue -is [int] -or $RawValue -is [uint32] -or $RawValue -is [long] -or $RawValue -is [uint64] } {
            if ($RawValue -is [uint64] -and $RawValue -gt [uint64][int64]::MaxValue) {
                return [PSCustomObject]@{
                    FailureMessage = "${LogContext} : ${FieldName} must fit in a 64-bit signed integer; got $RawValue."
                    ParsedInt64    = $null
                }
            }
            return [PSCustomObject]@{ FailureMessage = $null; ParsedInt64 = [int64]$RawValue }
        }
        default {
            $typeName = $RawValue.GetType().FullName
            return [PSCustomObject]@{
                FailureMessage = "${LogContext} : ${FieldName} must be a JSON integer; got type $typeName (value: $RawValue)."
                ParsedInt64    = $null
            }
        }
    }
}
Function Get-VmClassJsonPropertyByInsensitiveName {

    <#
        .SYNOPSIS
        Returns the first PSObject property on a JSON-derived object whose name matches case-insensitively.

        .PARAMETER Entry
        PSCustomObject from ConvertFrom-Json.

        .PARAMETER PropertyName
        Canonical property name to find.

        .OUTPUTS
        Property descriptor, or $null.
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNull()] [PSCustomObject]$Entry,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$PropertyName
    )

    foreach ($property in $Entry.PSObject.Properties) {
        if ($property.Name -ieq $PropertyName) {
            return $property
        }
    }

    return $null
}
Function Get-VmClassJsonPropertyRawValueInsensitive {

    <#
        .SYNOPSIS
        Returns the value of a property matched case-insensitively on a JSON-derived object.

        .PARAMETER Entry
        PSCustomObject from ConvertFrom-Json.

        .PARAMETER PropertyName
        Canonical property name.

        .OUTPUTS
        The property value, or $null when absent.
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNull()] [PSCustomObject]$Entry,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$PropertyName
    )

    $matched = Get-VmClassJsonPropertyByInsensitiveName -Entry $Entry -PropertyName $PropertyName
    if ($null -eq $matched) {
        return $null
    }

    return $matched.Value
}
Function Get-VmClassJsonEntryName {

    <#
        .SYNOPSIS
        Returns the vmClasses.json name field for one array entry (case-insensitive property match).

        .PARAMETER Entry
        One object from the validated JSON array.

        .OUTPUTS
        System.String — empty string when the property is missing or null.
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNull()] [PSCustomObject]$Entry
    )

    $raw = Get-VmClassJsonPropertyRawValueInsensitive -Entry $Entry -PropertyName "name"
    if ($null -eq $raw) {
        return ""
    }

    return [string]$raw
}
Function Get-VmClassesJsonStrictSyntaxFailureMessage {

    <#
        .SYNOPSIS
        Returns validation messages for vmClasses JSON text (non-throwing; empty list when valid).

        .PARAMETER JsonText
        Full file content (UTF-8).

        .PARAMETER SourceLabel
        Label for messages (typically the file path).

        .OUTPUTS
        System.Collections.Generic.List[string]
    #>

    Param (
        [Parameter(Mandatory = $true)] [AllowEmptyString()] [String]$JsonText,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$SourceLabel
    )

    $failures = [System.Collections.Generic.List[string]]::new()
    if ([string]::IsNullOrWhiteSpace($JsonText)) {
        [void]$failures.Add("vmClasses JSON is empty or whitespace: $SourceLabel")
        return $failures
    }

        $document = $null
    try {
        $document = [System.Text.Json.JsonDocument]::Parse($JsonText)
        $rootKind = $document.RootElement.ValueKind
        if ($rootKind -ne [System.Text.Json.JsonValueKind]::Array) {
            [void]$failures.Add("vmClasses JSON root must be a JSON array ([]); $SourceLabel has root kind $rootKind.")
        }
    } catch {
        $parseErrorMessage = $_.Exception.Message
        [void]$failures.Add("Invalid vmClasses JSON in ${SourceLabel}: $parseErrorMessage")
        if ($parseErrorMessage -match 'LineNumber: (\d+) \| BytePositionInLine: (\d+)') {
            $jsonLines = $JsonText -split "`n"
            $problemLineIndex = [int]$matches[1]
            if ($problemLineIndex -ge 0 -and $problemLineIndex -lt $jsonLines.Count) {
                $problemLine = $jsonLines[$problemLineIndex].TrimEnd("`r")
                [void]$failures.Add("  Offending line $($problemLineIndex + 1): $problemLine")
            }
        }
    } finally {
        if ($null -ne $document) {
            $document.Dispose()
        }
    }

    return $failures
}
Function Test-VmClassJsonVmClassDnsStyleName {

    <#
        .SYNOPSIS
        Returns whether a string matches the vmClasses name/profile pattern (lowercase DNS-style, 63-char cap).

        .PARAMETER Value
        Candidate name string.

        .OUTPUTS
        System.Boolean
    #>

    Param (
        [Parameter(Mandatory = $true)] [AllowEmptyString()] [String]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    return $Value -cmatch $SCRIPT:VmClassJsonVmClassNameRegexPattern
}
Function Get-VmClassJsonEntryValidationMessage {

    <#
        .SYNOPSIS
        Collects human-readable vmClasses.json validation failures for one array element (no throw).

        .PARAMETER Entry
        Deserialized JSON element.

        .PARAMETER EntryIndex
        Zero-based index for messages.

        .PARAMETER MaximumCpuCount
        Inclusive upper bound for cpuCount.

        .PARAMETER MaximumMemoryMb
        Inclusive upper bound for memoryMB.

        .PARAMETER MinimumCpuCount
        Inclusive lower bound for cpuCount.

        .PARAMETER MinimumMemoryMb
        Inclusive lower bound for memoryMB.

        .OUTPUTS
        System.Collections.Generic.List[string]
    #>

    Param (
        [Parameter(Mandatory = $true)] [AllowNull()] $Entry,
        [Parameter(Mandatory = $true)] [ValidateRange(0, [int]::MaxValue)] [Int]$EntryIndex,
        [Parameter(Mandatory = $true)] [ValidateRange(1, [int]::MaxValue)] [Int]$MaximumCpuCount,
        [Parameter(Mandatory = $true)] [ValidateRange(1, [int]::MaxValue)] [Int]$MaximumMemoryMb,
        [Parameter(Mandatory = $false)] [ValidateRange(1, [int]::MaxValue)] [Int]$MinimumCpuCount = 1,
        [Parameter(Mandatory = $false)] [ValidateRange(1, [int]::MaxValue)] [Int]$MinimumMemoryMb = 1
    )

    $contextBase = "VM class at index $EntryIndex (the JSON file)"
    $messages = [System.Collections.Generic.List[string]]::new()

    if ($null -eq $Entry) {
        [void]$messages.Add("$contextBase : entry is JSON null; omit the element or provide an object.")
        return $messages
    }

    if ($Entry -isnot [PSCustomObject]) {
        [void]$messages.Add("$contextBase : entry must be a JSON object; got $($Entry.GetType().FullName).")
        return $messages
    }

    $nameLabelForContext = $null
    $namePropForContext = Get-VmClassJsonPropertyByInsensitiveName -Entry $Entry -PropertyName "name"
    if ($null -ne $namePropForContext -and $null -ne $namePropForContext.Value) {
        $nameLabelCandidate = [string]$namePropForContext.Value
        if (-not [string]::IsNullOrWhiteSpace($nameLabelCandidate)) {
            $nameLabelForContext = $nameLabelCandidate
        }
    }

    $contextNonName = if ($null -ne $nameLabelForContext) {
        "VM class `"$nameLabelForContext`" at index $EntryIndex (the JSON file)"
    } else {
        $contextBase
    }

    $allowedPropertyNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($allowedName in @("cpuCount", "cpuCommitment", "description", "memoryCommitment", "memoryMB", "name", "vgpuDevices")) {
        [void]$allowedPropertyNames.Add($allowedName)
    }

    foreach ($property in $Entry.PSObject.Properties) {
        if (-not $allowedPropertyNames.Contains($property.Name)) {
            Write-LogMessage -Type DEBUG -Message "$contextNonName : unknown property `"$($property.Name)`" (ignored by this script)."
        }
    }

    $requiredCanonicalNames = @("name", "cpuCommitment", "memoryCommitment", "cpuCount", "memoryMB")
    foreach ($canonical in $requiredCanonicalNames) {
        $propInfo = Get-VmClassJsonPropertyByInsensitiveName -Entry $Entry -PropertyName $canonical
        $msgContext = if ($canonical -ieq "name") { $contextBase } else { $contextNonName }

        if ($null -eq $propInfo) {
            [void]$messages.Add("$msgContext : missing required property `"$canonical`" (any JSON key casing is accepted, for example memoryMB).")
            continue
        }

        if ($null -eq $propInfo.Value) {
            [void]$messages.Add("$msgContext : required property `"$($propInfo.Name)`" must not be JSON null.")
        }
    }

    $nameValue = Get-VmClassJsonEntryName -Entry $Entry
    if ([string]::IsNullOrWhiteSpace($nameValue)) {
        [void]$messages.Add("$contextBase : name must be a non-empty string.")
    } elseif (-not (Test-VmClassJsonVmClassDnsStyleName -Value $nameValue)) {
        [void]$messages.Add("$contextBase : name `"$nameValue`" must match lowercase DNS-style rules (1-63 chars, a-z 0-9, internal hyphens only) as required by Kubernetes.")
    }

    $cpuCommitmentRaw = Get-VmClassJsonPropertyRawValueInsensitive -Entry $Entry -PropertyName "cpuCommitment"
    $memoryCommitmentRaw = Get-VmClassJsonPropertyRawValueInsensitive -Entry $Entry -PropertyName "memoryCommitment"
    $cpuCommitmentNormalized = ([string]$cpuCommitmentRaw).Trim().ToLowerInvariant()
    $memoryCommitmentNormalized = ([string]$memoryCommitmentRaw).Trim().ToLowerInvariant()
    $allowedCommitmentsInvariant = @("besteffort", "guaranteed")
    if ($allowedCommitmentsInvariant -notcontains $cpuCommitmentNormalized) {
        [void]$messages.Add("$contextNonName : cpuCommitment must be `"bestEffort`" or `"guaranteed`" (case-insensitive); got `"$([string]$cpuCommitmentRaw)`".")
    }

    if ($allowedCommitmentsInvariant -notcontains $memoryCommitmentNormalized) {
        [void]$messages.Add("$contextNonName : memoryCommitment must be `"bestEffort`" or `"guaranteed`" (case-insensitive); got `"$([string]$memoryCommitmentRaw)`".")
    }

    $descriptionProp = Get-VmClassJsonPropertyByInsensitiveName -Entry $Entry -PropertyName "description"
    if ($null -ne $descriptionProp -and $null -ne $descriptionProp.Value -and $descriptionProp.Value -isnot [string]) {
        [void]$messages.Add("$contextNonName : description must be a string or omitted; got $($descriptionProp.Value.GetType().FullName).")
    }

    $cpuRaw = Get-VmClassJsonPropertyRawValueInsensitive -Entry $Entry -PropertyName "cpuCount"
    $memoryRaw = Get-VmClassJsonPropertyRawValueInsensitive -Entry $Entry -PropertyName "memoryMB"
    $cpuCountParsed = $null
    $memoryMbParsed = $null

    if ($null -ne $cpuRaw) {
        $cpuNumericResult = Get-VmClassJsonWholeNumberInt64Result -FieldName "cpuCount" -LogContext $contextNonName -RawValue $cpuRaw
        if ($null -ne $cpuNumericResult.FailureMessage) {
            [void]$messages.Add($cpuNumericResult.FailureMessage)
        } else {
            $cpuCountParsed = $cpuNumericResult.ParsedInt64
        }
    }

    if ($null -ne $memoryRaw) {
        $memoryNumericResult = Get-VmClassJsonWholeNumberInt64Result -FieldName "memoryMB" -LogContext $contextNonName -RawValue $memoryRaw
        if ($null -ne $memoryNumericResult.FailureMessage) {
            [void]$messages.Add($memoryNumericResult.FailureMessage)
        } else {
            $memoryMbParsed = $memoryNumericResult.ParsedInt64
        }
    }

    if ($null -ne $cpuCountParsed) {
        if ($cpuCountParsed -lt $MinimumCpuCount -or $cpuCountParsed -gt $MaximumCpuCount) {
            [void]$messages.Add("$contextNonName : cpuCount must be between $MinimumCpuCount and $MaximumCpuCount inclusive; got $cpuCountParsed.")
        }
    }

    if ($null -ne $memoryMbParsed) {
        if ($memoryMbParsed -lt $MinimumMemoryMb -or $memoryMbParsed -gt $MaximumMemoryMb) {
            [void]$messages.Add("$contextNonName : memoryMB must be between $MinimumMemoryMb and $MaximumMemoryMb inclusive; got $memoryMbParsed.")
        }
    }

    $vgpuProp = Get-VmClassJsonPropertyByInsensitiveName -Entry $Entry -PropertyName "vgpuDevices"
    if ($null -ne $vgpuProp) {
        $vgpuRoot = $vgpuProp.Value
        if ($null -eq $vgpuRoot) {
            [void]$messages.Add("$contextNonName : vgpuDevices is present and must not be JSON null; omit the key or provide a non-empty array of objects.")
        } else {
            $invalidScalarTypes = @(
                [string], [bool], [byte], [sbyte], [int], [long], [short], [ushort], [uint], [ulong], [float], [double], [decimal]
            )
            $vgpuRootIsInvalidScalar = $false
            foreach ($scalarType in $invalidScalarTypes) {
                if ($vgpuRoot -is $scalarType) {
                    [void]$messages.Add("$contextNonName : vgpuDevices must be a JSON array or object, not $($scalarType.Name).")
                    $vgpuRootIsInvalidScalar = $true
                }
            }

            if (-not $vgpuRootIsInvalidScalar) {
                $deviceGroups = @($vgpuRoot)
                if ($deviceGroups.Count -eq 0) {
                    [void]$messages.Add("$contextNonName : vgpuDevices must contain at least one object when the key is present.")
                }

                $groupIndex = 0
                foreach ($deviceGroup in $deviceGroups) {
                    if ($null -eq $deviceGroup) {
                        [void]$messages.Add("$contextNonName : vgpuDevices[$groupIndex] must not be null.")
                        $groupIndex++
                        continue
                    }

                    if ($deviceGroup -isnot [PSCustomObject]) {
                        [void]$messages.Add("$contextNonName : vgpuDevices[$groupIndex] must be a JSON object.")
                        $groupIndex++
                        continue
                    }

                    $profileProp = Get-VmClassJsonPropertyByInsensitiveName -Entry $deviceGroup -PropertyName "profileNames"
                    if ($null -eq $profileProp) {
                        [void]$messages.Add("$contextNonName : vgpuDevices[$groupIndex] must include profileNames (array of 1 to $($SCRIPT:VmClassJsonMaximumVgpuProfileNamesPerDeviceObject) names).")
                        $groupIndex++
                        continue
                    }

                    if ($null -eq $profileProp.Value) {
                        [void]$messages.Add("$contextNonName : vgpuDevices[$groupIndex].profileNames must not be JSON null.")
                        $groupIndex++
                        continue
                    }

                    $profileNamesValue = $profileProp.Value
                    $profileNamesHasInvalidScalarType = $false
                    foreach ($scalarType in $invalidScalarTypes) {
                        if ($profileNamesValue -is $scalarType -and $profileNamesValue -isnot [string]) {
                            [void]$messages.Add("$contextNonName : vgpuDevices[$groupIndex].profileNames must be a JSON array or string, not $($scalarType.Name).")
                            $profileNamesHasInvalidScalarType = $true
                        }
                    }

                    if ($profileNamesHasInvalidScalarType) {
                        $groupIndex++
                        continue
                    }

                    $profileList = @($profileNamesValue)
                    $nonNullProfiles = [System.Collections.Generic.List[string]]::new()
                    foreach ($profileEntry in $profileList) {
                        if ($null -eq $profileEntry) {
                            [void]$messages.Add("$contextNonName : vgpuDevices[$groupIndex].profileNames must not contain JSON null entries.")
                            continue
                        }

                        if ($profileEntry -is [PSCustomObject] -or $profileEntry -is [System.Collections.IDictionary]) {
                            [void]$messages.Add("$contextNonName : vgpuDevices[$groupIndex].profileNames entries must be scalar strings, not objects.")
                            continue
                        }

                        $profileString = [string]$profileEntry
                        if ([string]::IsNullOrWhiteSpace($profileString)) {
                            [void]$messages.Add("$contextNonName : vgpuDevices[$groupIndex].profileNames entries must be non-empty strings.")
                            continue
                        }

                        [void]$nonNullProfiles.Add($profileString)
                    }

                    if ($nonNullProfiles.Count -lt $SCRIPT:VmClassJsonMinimumVgpuProfileNamesPerDeviceObject -or $nonNullProfiles.Count -gt $SCRIPT:VmClassJsonMaximumVgpuProfileNamesPerDeviceObject) {
                        [void]$messages.Add("$contextNonName : vgpuDevices[$groupIndex].profileNames must list between $($SCRIPT:VmClassJsonMinimumVgpuProfileNamesPerDeviceObject) and $($SCRIPT:VmClassJsonMaximumVgpuProfileNamesPerDeviceObject) profiles; found $($nonNullProfiles.Count).")
                    }

                    foreach ($profileString in $nonNullProfiles) {
                        if (-not (Test-VmClassJsonVmClassDnsStyleName -Value $profileString)) {
                            [void]$messages.Add("$contextNonName : vgpuDevices[$groupIndex] profile name `"$profileString`" must match the same lowercase DNS-style pattern as name (1-63 chars, a-z 0-9, internal hyphens).")
                        }
                    }

                    $groupIndex++
                }
            }
        }
    }

    return $messages
}
Function Get-VmClassJsonValidatedEntryList {

    <#
        .SYNOPSIS
        Loads vmClasses.json with strict syntax checks, validates every array element, then logs
        errors and exits on failure.

        .DESCRIPTION
        On validation failure, writes one Write-LogMessage ERROR per issue and exits with code 1.
        Successful results are cached for the same JsonFilePath so a pre-flight pass before
        Connect-Vcenter does not force a second read.

        .PARAMETER JsonFilePath
        Path to the JSON file (UTF-8).

        .PARAMETER MinimumCpuCount
        Inclusive lower bound for cpuCount.

        .PARAMETER MinimumMemoryMb
        Inclusive lower bound for memoryMB.

        .EXAMPLE
        $entries = Get-VmClassJsonValidatedEntryList -JsonFilePath ".\vmClasses.json"
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [ValidateScript( { Test-Path -LiteralPath $_ -PathType Leaf } )] [String]$JsonFilePath,
        [Parameter(Mandatory = $false)] [ValidateRange(1, [int]::MaxValue)] [Int]$MinimumCpuCount = 1,
        [Parameter(Mandatory = $false)] [ValidateRange(1, [int]::MaxValue)] [Int]$MinimumMemoryMb = 1
    )

    if ($null -ne $SCRIPT:VmClassJsonPreflightCachePath -and $null -ne $SCRIPT:VmClassJsonPreflightCacheEntries -and ($JsonFilePath -ieq $SCRIPT:VmClassJsonPreflightCachePath)) {
        return $SCRIPT:VmClassJsonPreflightCacheEntries
    }

    $rawJson = Get-Content -LiteralPath $JsonFilePath -Raw -Encoding UTF8
    $failureMessages = [System.Collections.Generic.List[string]]::new()
    foreach ($syntaxMessage in @(Get-VmClassesJsonStrictSyntaxFailureMessage -JsonText $rawJson -SourceLabel $JsonFilePath)) {
        [void]$failureMessages.Add($syntaxMessage)
    }

    if ($failureMessages.Count -gt 0) {
        foreach ($messageLine in $failureMessages) {
            Write-LogMessage -Type ERROR -Message $messageLine
        }
        exit 1
    }

    $vmClassData = $null
    try {
        $vmClassData = $rawJson | ConvertFrom-Json -Depth 100 -ErrorAction Stop
    } catch {
        Write-LogMessage -Type ERROR -Message "vmClasses JSON failed to deserialize after strict parse (file: $JsonFilePath): $($_.Exception.Message)"
        exit 1
    }

    $entries = @($vmClassData)
    if ($entries.Count -eq 0) {
        Write-LogMessage -Type ERROR -Message "vmClasses JSON must contain at least one VM class object (file: $JsonFilePath)."
        exit 1
    }

    $seenNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    for ($entryIndex = 0; $entryIndex -lt $entries.Count; $entryIndex++) {
        $entry = $entries[$entryIndex]
        $entryMessages = Get-VmClassJsonEntryValidationMessage `
            -Entry $entry `
            -EntryIndex $entryIndex `
            -MaximumCpuCount $SCRIPT:VmClassJsonMaximumCpuCount `
            -MaximumMemoryMb $SCRIPT:VmClassJsonMaximumMemoryMb `
            -MinimumCpuCount $MinimumCpuCount `
            -MinimumMemoryMb $MinimumMemoryMb

        foreach ($entryMessage in $entryMessages) {
            [void]$failureMessages.Add($entryMessage)
        }

        if ($null -ne $entry -and $entry -is [PSCustomObject]) {
            $normalizedName = Get-VmClassJsonEntryName -Entry $entry
            if (-not [string]::IsNullOrWhiteSpace($normalizedName)) {
                if (-not $seenNames.Add($normalizedName)) {
                    [void]$failureMessages.Add("Duplicate VM class name `"$normalizedName`" (case-insensitive) at index $entryIndex ($(Split-Path -Leaf $JsonFilePath)).")
                }
            }
        }
    }

    if ($failureMessages.Count -gt 0) {
        foreach ($messageLine in $failureMessages) {
            Write-LogMessage -Type ERROR -Message $messageLine
        }
        exit 1
    }

    $SCRIPT:VmClassJsonPreflightCachePath = $JsonFilePath
    $SCRIPT:VmClassJsonPreflightCacheEntries = $entries
    return $entries
}
Function Get-VgpuDeviceListFromVmClassJsonEntry {

    <#
        .SYNOPSIS
        Builds a list of VGPU device binding objects from optional vgpuDevices on a JSON entry.

        .DESCRIPTION
        Reads vgpuDevices and profileNames via PSObject.Properties so an omitted vgpuDevices
        property does not throw under Set-StrictMode.

        .PARAMETER Entry
        One vmClasses.json object (may omit vgpuDevices).

        .OUTPUTS
        System.Collections.Generic.List of VcenterNamespaceManagementVirtualMachineClassesVGPUDevice.
        Returned with the unary comma operator (, $result) to prevent PowerShell from enumerating
        the list on the pipeline; callers always receive the typed List object, never $null.
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNull()] [PSCustomObject]$Entry
    )

    $result = [System.Collections.Generic.List[VMware.Bindings.vSphere.Model.VcenterNamespaceManagementVirtualMachineClassesVGPUDevice]]::new()

    $vgpuDevicesProperty = Get-VmClassJsonPropertyByInsensitiveName -Entry $Entry -PropertyName "vgpuDevices"
    if ($null -eq $vgpuDevicesProperty) {
        return , $result
    }

    $vgpuRoot = $vgpuDevicesProperty.Value
    if ($null -eq $vgpuRoot) {
        return , $result
    }

    foreach ($deviceGroup in @($vgpuRoot)) {
        if ($null -eq $deviceGroup -or $deviceGroup -isnot [PSCustomObject]) {
            continue
        }

        $profileNamesProperty = Get-VmClassJsonPropertyByInsensitiveName -Entry $deviceGroup -PropertyName "profileNames"
        if ($null -eq $profileNamesProperty) {
            continue
        }

        $profileNamesValue = $profileNamesProperty.Value
        if ($null -eq $profileNamesValue) {
            continue
        }

        foreach ($rawName in @($profileNamesValue)) {
            $profileName = [string]$rawName
            if ([string]::IsNullOrWhiteSpace($profileName)) {
                continue
            }

            $device = Initialize-VcenterNamespaceManagementVirtualMachineClassesVGPUDevice -ProfileName $profileName
            [void]$result.Add($device)
        }
    }

    return , $result
}
Function Get-VmClassNamespaceManagementApiValuesFromJsonEntry {

    <#
        .SYNOPSIS
        Maps one vmClasses.json object to values for the vSphere namespace-management REST API.

        .DESCRIPTION
        Maps: name -> id; cpuCount -> cpu_count; memoryMb -> memory_mb; cpuCommitment/memoryCommitment
        -> reservations; vgpuDevices -> devices.vgpu_devices[].profile_name. memory_reservation is 100
        when memory is guaranteed or when vGPU profiles are present.

        .PARAMETER Entry
        One object from the vmClasses JSON array.

        .OUTPUTS
        PSCustomObject with CpuCount, CpuReservation, Description, Id, MemoryMb, MemoryReservation,
        VgpuProfileNames.
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNull()] [PSCustomObject]$Entry
    )

    $cpuCommitmentNormalized = ([string](Get-VmClassJsonPropertyRawValueInsensitive -Entry $Entry -PropertyName "cpuCommitment")).Trim().ToLowerInvariant()
    $memoryCommitmentNormalized = ([string](Get-VmClassJsonPropertyRawValueInsensitive -Entry $Entry -PropertyName "memoryCommitment")).Trim().ToLowerInvariant()
    $fullReservation = [int64]$SCRIPT:VmClassFullReservationPercent
    $vgpuList = Get-VgpuDeviceListFromVmClassJsonEntry -Entry $Entry
    $vgpuProfileNames = @(
        foreach ($binding in $vgpuList) {
            [string]$binding.ProfileName
        }
    )
    $hasVgpu = $vgpuProfileNames.Count -gt 0

    $cpuReservation = if ($cpuCommitmentNormalized -eq "guaranteed") { $fullReservation } else { $null }
    $memoryReservation = if ($memoryCommitmentNormalized -eq "guaranteed" -or $hasVgpu) { $fullReservation } else { $null }

    $description = $null
    $descriptionRaw = Get-VmClassJsonPropertyRawValueInsensitive -Entry $Entry -PropertyName "description"
    if (-not [string]::IsNullOrWhiteSpace([string]$descriptionRaw)) {
        $description = [string]$descriptionRaw
    }

    return [PSCustomObject]@{
        CpuCount          = [int64](Get-VmClassJsonPropertyRawValueInsensitive -Entry $Entry -PropertyName "cpuCount")
        CpuReservation    = $cpuReservation
        Description       = $description
        Id                = Get-VmClassJsonEntryName -Entry $Entry
        MemoryMb          = [int64](Get-VmClassJsonPropertyRawValueInsensitive -Entry $Entry -PropertyName "memoryMB")
        MemoryReservation = $memoryReservation
        VgpuProfileNames  = $vgpuProfileNames
    }
}
Function New-VmClassRestApiSession {

    <#
        .SYNOPSIS
        Creates a vCenter REST API session and returns the session token.

        .PARAMETER Credential
        PSCredential for vCenter authentication.

        .PARAMETER VcenterServer
        vCenter FQDN or IP.

        .OUTPUTS
        System.String — vmware-api-session-id token.
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNull()] [PSCredential]$Credential,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$VcenterServer
    )

    $uri = "https://$VcenterServer/api/session"
    $base64Auth = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$($Credential.UserName):$($Credential.GetNetworkCredential().Password)"))
    return Invoke-RestMethod -Method Post -Uri $uri -Headers @{ "Authorization" = "Basic $base64Auth" } -SkipCertificateCheck -ErrorAction Stop
}
Function Remove-VmClassRestApiSession {

    <#
        .SYNOPSIS
        Deletes a vCenter REST API session.

        .PARAMETER SessionToken
        The vmware-api-session-id token to invalidate.

        .PARAMETER VcenterServer
        vCenter FQDN or IP.
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$SessionToken,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$VcenterServer
    )

    $uri = "https://$VcenterServer/api/session"
    $headers = @{ "vmware-api-session-id" = $SessionToken }
    Invoke-RestMethod -Method Delete -Uri $uri -Headers $headers -SkipCertificateCheck -ErrorAction SilentlyContinue | Out-Null
}
Function ConvertTo-VmClassRestCreateBody {

    <#
        .SYNOPSIS
        Builds the request body hashtable for the vCenter REST create VM class endpoint.

        .DESCRIPTION
        Returns an ordered hashtable using memory_MB (mixed case) as required by the vCenter API.
        The VCF PowerCLI SDK serializes this field as memory_mb (lowercase), which the API rejects
        with INVALID_ARGUMENT. Direct REST construction avoids that mismatch. Re-evaluate when
        upgrading VCF PowerCLI if the SDK serialization is corrected in a future release.

        .PARAMETER Entry
        One object from the vmClasses JSON array (already validated).

        .OUTPUTS
        System.Collections.Specialized.OrderedDictionary — ready for ConvertTo-Json.
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNull()] [PSCustomObject]$Entry
    )

    $apiValues = Get-VmClassNamespaceManagementApiValuesFromJsonEntry -Entry $Entry
    $body = [ordered]@{
        id        = $apiValues.Id
        cpu_count = $apiValues.CpuCount
        memory_MB = $apiValues.MemoryMb
    }
    if ($null -ne $apiValues.CpuReservation) {
        $body.cpu_reservation = $apiValues.CpuReservation
    }
    if ($null -ne $apiValues.MemoryReservation) {
        $body.memory_reservation = $apiValues.MemoryReservation
    }
    if (-not [string]::IsNullOrWhiteSpace($apiValues.Description)) {
        $body.description = $apiValues.Description
    }
    if ($apiValues.VgpuProfileNames.Count -gt 0) {
        $body.devices = @{
            vgpu_devices = @($apiValues.VgpuProfileNames | ForEach-Object { @{ profile_name = $_ } })
        }
    }
    return $body
}
Function ConvertTo-VmClassRestUpdateBody {

    <#
        .SYNOPSIS
        Builds the request body hashtable for the vCenter REST update VM class endpoint.

        .DESCRIPTION
        Returns an ordered hashtable using memory_MB (mixed case) as required by the vCenter API.
        The VCF PowerCLI SDK serializes this field as memory_mb (lowercase), which the API rejects
        with INVALID_ARGUMENT. Direct REST construction avoids that mismatch. Re-evaluate when
        upgrading VCF PowerCLI if the SDK serialization is corrected in a future release.

        .PARAMETER Entry
        One object from the vmClasses JSON array.

        .OUTPUTS
        System.Collections.Specialized.OrderedDictionary — ready for ConvertTo-Json.
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNull()] [PSCustomObject]$Entry
    )

    $apiValues = Get-VmClassNamespaceManagementApiValuesFromJsonEntry -Entry $Entry
    $body = [ordered]@{
        cpu_count = $apiValues.CpuCount
        memory_MB = $apiValues.MemoryMb
    }
    if ($null -ne $apiValues.CpuReservation) {
        $body.cpu_reservation = $apiValues.CpuReservation
    }
    if ($null -ne $apiValues.MemoryReservation) {
        $body.memory_reservation = $apiValues.MemoryReservation
    }
    if (-not [string]::IsNullOrWhiteSpace($apiValues.Description)) {
        $body.description = $apiValues.Description
    }
    if ($apiValues.VgpuProfileNames.Count -gt 0) {
        $body.devices = @{
            vgpu_devices = @($apiValues.VgpuProfileNames | ForEach-Object { @{ profile_name = $_ } })
        }
    }
    return $body
}
Function Get-VmClassGpuColumnDisplayFromInfo {

    <#
        .SYNOPSIS
        Builds the List action Gpu column string from a namespace VM class Info object.

        .DESCRIPTION
        Comma-separated sorted vGPU profile_name values when Devices.VgpuDevices is present; appends
        DirectPath I/O after a semicolon when DynamicDirectPathIoDevices is non-empty. Returns "No"
        when neither is present.

        .PARAMETER Info
        VcenterNamespaceManagementVirtualMachineClassesInfo from list or get API.

        .OUTPUTS
        System.String
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNull()] [Object]$Info
    )

    $profileNames = [System.Collections.Generic.List[string]]::new()
    if ($null -ne $Info.Devices -and $null -ne $Info.Devices.VgpuDevices) {
        foreach ($device in @($Info.Devices.VgpuDevices)) {
            if ($null -ne $device -and $null -ne $device.ProfileName) {
                [void]$profileNames.Add([string]$device.ProfileName)
            }
        }
    }

    $profileNamesSorted = @($profileNames | Sort-Object)
    $hasDynamicDirectPathIo = $false
    if ($null -ne $Info.Devices -and $null -ne $Info.Devices.DynamicDirectPathIoDevices -and @($Info.Devices.DynamicDirectPathIoDevices).Count -gt 0) {
        $hasDynamicDirectPathIo = $true
    }

    if ($profileNamesSorted.Count -eq 0 -and -not $hasDynamicDirectPathIo) {
        return "No"
    }

    $parts = [System.Collections.Generic.List[string]]::new()
    if ($profileNamesSorted.Count -gt 0) {
        [void]$parts.Add(($profileNamesSorted -join ", "))
    }

    if ($hasDynamicDirectPathIo) {
        [void]$parts.Add("DirectPath I/O")
    }

    return ($parts -join "; ")
}
Function Get-VmClassListViewFromServer {

    <#
        .SYNOPSIS
        Returns display rows for all namespace VM classes on the given vCenter (Name, CpuCount, MemoryMB, Gpu).

        .PARAMETER Server
        vCenter Server passed to Invoke-ListNamespaceManagementVirtualMachineClasses.

        .OUTPUTS
        System.Collections.Generic.List of PSCustomObject with Name, CpuCount, MemoryMB, Default, Gpu.
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Server
    )

    $list = Invoke-ListNamespaceManagementVirtualMachineClasses -Server $Server -ErrorAction Stop
    $rows = [System.Collections.Generic.List[object]]::new()

    foreach ($item in @($list)) {
        if ($null -eq $item) {
            continue
        }

        $className = [string]$item.Id
        if ([string]::IsNullOrWhiteSpace($className)) {
            continue
        }

        $gpuDisplay = Get-VmClassGpuColumnDisplayFromInfo -Info $item
        [void]$rows.Add([PSCustomObject]@{
            Name     = $className
            CpuCount = $item.CpuCount
            MemoryMB = $item.MemoryMb
            Default  = if (Test-VmClassIsDefaultName -Name $className) { "Yes" } else { "No" }
            Gpu      = $gpuDisplay
        })
    }

    return $rows
}
Function Test-VmClassInteractiveAffirmativeResponse {

    <#
        .SYNOPSIS
        Returns whether user input from Read-Host should be treated as an affirmative answer (Y or Yes).

        .PARAMETER Response
        Raw string from Read-Host or similar.

        .OUTPUTS
        System.Boolean
    #>

    Param (
        [Parameter(Mandatory = $true)] [AllowEmptyString()] [String]$Response
    )

    return $Response -match $SCRIPT:VmClassInteractiveAffirmativeResponseRegexPattern
}
Function Resolve-VmClassNameForUpdateAgainstJson {

    <#
        .SYNOPSIS
        Ensures -VmClassName matches a vmClasses.json entry or "all", with interactive retry when
        the console session is interactive.

        .DESCRIPTION
        When the name is not "all" and does not match any entry name, logs an ERROR listing valid
        names. If stdin is interactive, prompts Y/N to try again; on N, exits with code 0.
        Non-interactive sessions log ERROR and exit 1.

        .PARAMETER JsonFilePath
        Path to vmClasses.json (must exist).

        .PARAMETER VmClassName
        Candidate name or "all" (trimmed for comparison).

        .OUTPUTS
        System.String — normalized trimmed name or "all".
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [ValidateScript( { Test-Path -LiteralPath $_ -PathType Leaf } )] [String]$JsonFilePath,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$VmClassName
    )

    $interactiveOk = $false
    try {
        $interactiveOk = [bool]([Environment]::UserInteractive -and -not [Console]::IsInputRedirected)
    } catch {
        $interactiveOk = $false
    }

    $currentName = $VmClassName.Trim()
    if ($currentName -ieq "all") {
        return $currentName
    }

    while ($true) {
        $entries = Get-VmClassJsonValidatedEntryList -JsonFilePath $JsonFilePath
        $jsonNames = @(
            foreach ($entry in $entries) {
                Get-VmClassJsonEntryName -Entry $entry
            }
        )
        $jsonNamesSorted = @($jsonNames | Sort-Object)
        $matched = $jsonNames | Where-Object { $_ -ieq $currentName } | Select-Object -First 1
        if ($null -ne $matched) {
            return $currentName
        }

        $previewMaximum = $SCRIPT:VmClassJsonValidNamePreviewMaximumCount
        $preview = if ($jsonNamesSorted.Count -le $previewMaximum) {
            $jsonNamesSorted -join ", "
        } else {
            $lastIndex = $previewMaximum - 1
            (@($jsonNamesSorted[0..$lastIndex]) -join ", ") + ", ..."
        }

        Write-LogMessage -Type ERROR -Message "No entry in `"$JsonFilePath`" matches `"$currentName`". The name must match a `"name`" property in the file. Names defined in the file: $preview"

        if (-not $interactiveOk) {
            exit 1
        }

        $answer = Read-Host "Enter a different VM class name? (Y/N)"
        if (-not (Test-VmClassInteractiveAffirmativeResponse -Response $answer)) {
            Write-LogMessage -Type INFO -Message "Exiting at user request."
            exit 0
        }

        Write-Host ""
        do {
            $next = Read-Host "Enter VM class name to update (or 'all' for every entry in $($SCRIPT:DEFAULT_VM_CLASSES_JSON_FILENAME))"
        } while ([string]::IsNullOrWhiteSpace($next))

        $currentName = $next.Trim()
        if ($currentName -ieq "all") {
            return $currentName
        }
    }
}
Function Get-VmClassJsonEntriesForMutationTarget {

    <#
        .SYNOPSIS
        Returns JSON entries matching a target name, "all", or an explicit list of names.

        .DESCRIPTION
        When -SelectedNames is provided (TUI result), entries matching those names are returned and
        -VmClassName is ignored. Otherwise -VmClassName is used: "all" returns every entry, and any
        other value returns the single matching entry (throws if not found).

        .PARAMETER JsonFilePath
        Path to vmClasses.json.

        .PARAMETER SelectedNames
        One or more class names from the TUI selection. When provided, -VmClassName is ignored.

        .PARAMETER VmClassName
        VM class name or "all" (case-insensitive). Used when -SelectedNames is not provided.

        .OUTPUTS
        Array of PSCustomObject entries from the JSON file.
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })] [String]$JsonFilePath,
        [Parameter(Mandatory = $false)] [String[]]$SelectedNames,
        [Parameter(Mandatory = $false)] [String]$VmClassName
    )

    $entries = Get-VmClassJsonValidatedEntryList -JsonFilePath $JsonFilePath

    if ($null -ne $SelectedNames -and $SelectedNames.Count -gt 0) {
        return @($entries | Where-Object { $SelectedNames -icontains (Get-VmClassJsonEntryName -Entry $_) })
    }

    if ([string]::IsNullOrWhiteSpace($VmClassName)) {
        throw "Either -SelectedNames or -VmClassName must be provided to Get-VmClassJsonEntriesForMutationTarget."
    }

    if ($VmClassName.Trim() -ieq "all") {
        return @($entries)
    }

    $match = $entries | Where-Object { (Get-VmClassJsonEntryName -Entry $_) -ieq $VmClassName.Trim() } | Select-Object -First 1
    if ($null -eq $match) {
        throw "No entry in `"$JsonFilePath`" matches `"$($VmClassName.Trim())`" (use `"all`" to select every entry in the file)."
    }

    return @($match)
}
Function Get-ExistingVmClassIdSet {

    <#
        .SYNOPSIS
        Returns a case-insensitive HashSet of existing VM class names on the connected vCenter.

        .PARAMETER Server
        vCenter Server parameter passed to Invoke-ListNamespaceManagementVirtualMachineClasses.

        .OUTPUTS
        System.Collections.Generic.HashSet[System.String]
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Server
    )

    $set = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $list = Invoke-ListNamespaceManagementVirtualMachineClasses -Server $Server -ErrorAction Stop
    foreach ($item in @($list)) {
        if ($null -ne $item -and $null -ne $item.Id) {
            [void]$set.Add([string]$item.Id)
        }
    }

    return $set
}
Function Get-VmClassOptionalPropertyValue {

    <#
        .SYNOPSIS
        Returns a single property value from an object when the property exists (StrictMode-safe).

        .PARAMETER InputObject
        Object to inspect (may be null).

        .PARAMETER PropertyName
        Property name (case-sensitive match).

        .OUTPUTS
        The property value, or $null when absent.
    #>

    Param (
        [Parameter(Mandatory = $false)] [AllowNull()] $InputObject,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$PropertyName
    )

    if ($null -eq $InputObject) {
        return $null
    }

    foreach ($property in $InputObject.PSObject.Properties) {
        if ($property.Name -ceq $PropertyName) {
            return $property.Value
        }
    }

    return $null
}
Function Get-VmClassErrorRecordDiagnosticText {

    <#
        .SYNOPSIS
        Builds a single diagnostic string from an ErrorRecord without assuming ErrorDetails.Message
        exists (PowerCLI-safe).

        .PARAMETER ErrorRecord
        The object from a catch block ($_ ).

        .OUTPUTS
        System.String
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNull()] [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $segments = [System.Collections.Generic.List[string]]::new()
    $exceptionCursor = $ErrorRecord.Exception
    while ($null -ne $exceptionCursor) {
        $segment = Get-VmClassOptionalPropertyValue -InputObject $exceptionCursor -PropertyName "Message"
        if ($null -ne $segment) {
            $segmentString = [string]$segment
            if (-not [string]::IsNullOrWhiteSpace($segmentString)) {
                [void]$segments.Add($segmentString)
            }
        }
        $exceptionCursor = Get-VmClassOptionalPropertyValue -InputObject $exceptionCursor -PropertyName "InnerException"
    }

    $errorDetails = $ErrorRecord.ErrorDetails
    if ($null -ne $errorDetails) {
        if ($errorDetails -is [string]) {
            [void]$segments.Add([string]$errorDetails)
        } else {
            $detailsMessage = Get-VmClassOptionalPropertyValue -InputObject $errorDetails -PropertyName "Message"
            if ($null -ne $detailsMessage -and -not [string]::IsNullOrWhiteSpace([string]$detailsMessage)) {
                [void]$segments.Add([string]$detailsMessage)
            } else {
                $asString = [string]$errorDetails
                if (-not [string]::IsNullOrWhiteSpace($asString)) {
                    [void]$segments.Add($asString)
                }
            }
        }
    }

    return ($segments -join " ")
}
Function Test-VmClassAlreadyExistsError {

    <#
        .SYNOPSIS
        Returns whether an exception likely indicates the VM class already exists on vCenter.

        .PARAMETER DiagnosticText
        Optional extra text (for example a REST error payload string).

        .PARAMETER ErrorRecord
        Preferred: the full catch block record ($_ ).

        .PARAMETER Exception
        The caught exception when -ErrorRecord is not supplied.

        .OUTPUTS
        System.Boolean
    #>

    Param (
        [Parameter(Mandatory = $false)] [String]$DiagnosticText,
        [Parameter(Mandatory = $false)] [System.Management.Automation.ErrorRecord]$ErrorRecord,
        [Parameter(Mandatory = $false)] [Object]$Exception
    )

    if ($null -ne $ErrorRecord) {
        $message = Get-VmClassErrorRecordDiagnosticText -ErrorRecord $ErrorRecord
    } else {
        if ($null -eq $Exception) {
            throw "Test-VmClassAlreadyExistsError requires -ErrorRecord or -Exception."
        }

        $message = Get-VmClassOptionalPropertyValue -InputObject $Exception -PropertyName "Message"
        if ($null -eq $message) {
            $message = [string]$Exception
        } else {
            $message = [string]$message
        }

        if (-not [string]::IsNullOrWhiteSpace($DiagnosticText)) {
            $message = "$message $DiagnosticText"
        }
    }

    switch -Regex ($message) {
        "already exists|AlreadyExists|ALREADY_EXISTS|vcenter\.wcp\.vmclass\.alreadyExists|duplicate|Duplicate|409|Conflict" {
            return $true
        }
        default {
            return $false
        }
    }
}
Function Test-VmClassNamespaceManagementGetNotFoundError {

    <#
        .SYNOPSIS
        Returns whether an exception from Invoke-GetVmClassNamespaceManagementVirtualMachineClasses
        indicates the VM class is absent.

        .PARAMETER ErrorRecord
        The full catch block record ($_ ).

        .OUTPUTS
        System.Boolean
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNull()] [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $message = Get-VmClassErrorRecordDiagnosticText -ErrorRecord $ErrorRecord

    switch -Regex ($message) {
        "\b404\b|NotFound|not found|was not found|could not be found|does not exist|Unknown identifier|UNKNOWN|Invalid.*vmclass" {
            return $true
        }
        default {
            return $false
        }
    }
}
Function Test-VmClassNamespaceManagementDeleteNotFoundError {

    <#
        .SYNOPSIS
        Returns whether Invoke-DeleteVmClassNamespaceManagementVirtualMachineClasses failed because
        the VM class is not on vCenter.

        .PARAMETER ErrorRecord
        The catch block record ($_ ).

        .OUTPUTS
        System.Boolean
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNull()] [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $message = Get-VmClassErrorRecordDiagnosticText -ErrorRecord $ErrorRecord

    switch -Regex ($message) {
        "NOT_FOUND|vcenter\.wcp\.vmclass\.notFound|Virtual Machine Class.*was not found in the vCenter inventory|VcenterNamespaceManagementVirtualMachineClassesDelete.*not found" {
            return $true
        }
        default {
            return $false
        }
    }
}
Function Test-VmClassSortedProfileNameListsEqual {

    <#
        .SYNOPSIS
        Compares two sorted vGPU profile name lists with case-sensitive equality.

        .PARAMETER Left
        Sorted string enumerable (desired).

        .PARAMETER Right
        Sorted string enumerable (existing).

        .OUTPUTS
        System.Boolean
    #>

    Param (
        [Parameter(Mandatory = $true)] [AllowEmptyCollection()] [String[]]$Left,
        [Parameter(Mandatory = $true)] [AllowEmptyCollection()] [String[]]$Right
    )

    $leftArr = @($Left)
    $rightArr = @($Right)
    if ($leftArr.Count -ne $rightArr.Count) {
        return $false
    }

    for ($i = 0; $i -lt $leftArr.Count; $i++) {
        if ($leftArr[$i] -cne $rightArr[$i]) {
            return $false
        }
    }

    return $true
}
Function ConvertTo-VmClassSpecComparableFromDesired {

    <#
        .SYNOPSIS
        Normalizes Get-VmClassNamespaceManagementApiValuesFromJsonEntry output for comparison to a
        vCenter class Info object.

        .PARAMETER DesiredApiOutput
        Output object from Get-VmClassNamespaceManagementApiValuesFromJsonEntry.

        .OUTPUTS
        PSCustomObject with fields aligned to ConvertTo-VmClassSpecComparableFromListOrGetItem.
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNull()] [PSCustomObject]$DesiredApiOutput
    )

    $description = $null
    if (-not [string]::IsNullOrWhiteSpace([string]$DesiredApiOutput.Description)) {
        $description = [string]$DesiredApiOutput.Description.Trim()
    }

    $vgpuSorted = @(
        @(foreach ($name in @($DesiredApiOutput.VgpuProfileNames)) {
            [string]$name
        }) | Sort-Object
    )

    $cpuReservation = $null
    if ($null -ne $DesiredApiOutput.CpuReservation) {
        $cpuReservation = [int64]$DesiredApiOutput.CpuReservation
    }

    $memoryReservation = $null
    if ($null -ne $DesiredApiOutput.MemoryReservation) {
        $memoryReservation = [int64]$DesiredApiOutput.MemoryReservation
    }

    return [PSCustomObject]@{
        CpuCount                     = [int64]$DesiredApiOutput.CpuCount
        CpuReservation               = $cpuReservation
        Description                  = $description
        HasDynamicDirectPathIoOnServer = $false
        MemoryMb                     = [int64]$DesiredApiOutput.MemoryMb
        MemoryReservation            = $memoryReservation
        VgpuProfileNamesSorted       = $vgpuSorted
    }
}
Function ConvertTo-VmClassSpecComparableFromListOrGetItem {

    <#
        .SYNOPSIS
        Maps one VM class from the list or get API to a comparable spec.

        .PARAMETER Item
        One list or get element (Info-shaped: Id, CpuCount, MemoryMb, optional Description,
        reservations, Devices).

        .OUTPUTS
        PSCustomObject for Compare-VmClassDesiredVersusExistingSpec.
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNull()] [Object]$Item
    )

    $description = $null
    if ($null -ne $Item.PSObject.Properties["Description"]) {
        $rawDescription = $Item.Description
        if (-not [string]::IsNullOrWhiteSpace([string]$rawDescription)) {
            $description = [string]$rawDescription.Trim()
        }
    }

    $vgpuSorted = [System.Collections.Generic.List[string]]::new()
    if ($null -ne $Item.Devices -and $null -ne $Item.Devices.VgpuDevices) {
        foreach ($device in @($Item.Devices.VgpuDevices)) {
            if ($null -ne $device -and $null -ne $device.ProfileName) {
                [void]$vgpuSorted.Add([string]$device.ProfileName)
            }
        }
    }

    $vgpuSortedArray = @($vgpuSorted | Sort-Object)
    $hasDynamicDirectPathIo = $false
    if ($null -ne $Item.Devices -and $null -ne $Item.Devices.DynamicDirectPathIoDevices -and @($Item.Devices.DynamicDirectPathIoDevices).Count -gt 0) {
        $hasDynamicDirectPathIo = $true
    }

    $cpuReservation = $null
    if ($null -ne $Item.PSObject.Properties["CpuReservation"] -and $null -ne $Item.CpuReservation) {
        $cpuReservation = [int64]$Item.CpuReservation
    }

    $memoryReservation = $null
    if ($null -ne $Item.PSObject.Properties["MemoryReservation"] -and $null -ne $Item.MemoryReservation) {
        $memoryReservation = [int64]$Item.MemoryReservation
    }

    return [PSCustomObject]@{
        CpuCount                     = [int64]$Item.CpuCount
        CpuReservation               = $cpuReservation
        Description                  = $description
        HasDynamicDirectPathIoOnServer = $hasDynamicDirectPathIo
        MemoryMb                     = [int64]$Item.MemoryMb
        MemoryReservation            = $memoryReservation
        VgpuProfileNamesSorted       = $vgpuSortedArray
    }
}
Function ConvertTo-VmClassJsonEntryFromApiItem {

    <#
        .SYNOPSIS
        Converts one PowerCLI VM class Get response to a vmClasses.json-format object.

        .DESCRIPTION
        Reverse-maps a vCenter PowerCLI item (Id, CpuCount, MemoryMb, CpuReservation,
        MemoryReservation, Description, Devices) to the same format used by vmClasses.json
        and written by -Action Discover. The result is directly usable with -Action Update.

        CpuCommitment is inferred from CpuReservation (100 = "guaranteed", else "bestEffort").
        MemoryCommitment is inferred the same way, with one exception: when vGPU profiles are
        present the reservation is always forced to 100 by vCenter regardless of the original
        commitment, so "bestEffort" is returned for those classes to avoid promoting an
        implicit reservation to an explicit guarantee.

        Classes with DynamicDirectPathIO devices are converted without that configuration;
        the caller is responsible for logging a warning.

        .PARAMETER Item
        One Get response object from Get-VmClassNamespaceManagementClassOrNull.

        .OUTPUTS
        PSCustomObject with name, cpuCount, cpuCommitment, memoryMB, memoryCommitment, and
        optionally description and vgpuDevices.
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNull()] [Object]$Item
    )

    $cpuReservation = $null
    if ($null -ne $Item.PSObject.Properties["CpuReservation"] -and $null -ne $Item.CpuReservation) {
        $cpuReservation = [int64]$Item.CpuReservation
    }
    $cpuCommitment = if ($cpuReservation -ge $SCRIPT:VmClassFullReservationPercent) { "guaranteed" } else { "bestEffort" }

    $vgpuProfileNames = [System.Collections.Generic.List[string]]::new()
    if ($null -ne $Item.Devices -and $null -ne $Item.Devices.VgpuDevices) {
        foreach ($device in @($Item.Devices.VgpuDevices)) {
            if ($null -ne $device -and $null -ne $device.ProfileName) {
                [void]$vgpuProfileNames.Add([string]$device.ProfileName)
            }
        }
    }
    $hasVgpu = $vgpuProfileNames.Count -gt 0

    $memoryReservation = $null
    if ($null -ne $Item.PSObject.Properties["MemoryReservation"] -and $null -ne $Item.MemoryReservation) {
        $memoryReservation = [int64]$Item.MemoryReservation
    }

    # When vGPU is present, vCenter forces memory_reservation to 100 regardless of the
    # original commitment choice. Return "bestEffort" so a round-trip restore does not
    # silently promote the class to a guaranteed memory reservation.
    $memoryCommitment = if ($hasVgpu) {
        "bestEffort"
    } elseif ($memoryReservation -ge $SCRIPT:VmClassFullReservationPercent) {
        "guaranteed"
    } else {
        "bestEffort"
    }

    $entry = [ordered]@{
        name             = [string]$Item.Id
        cpuCount         = [int]$Item.CpuCount
        cpuCommitment    = $cpuCommitment
        memoryMB         = [int64]$Item.MemoryMb
        memoryCommitment = $memoryCommitment
    }

    $descriptionRaw = $null
    if ($null -ne $Item.PSObject.Properties["Description"]) {
        $descriptionRaw = $Item.Description
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$descriptionRaw)) {
        $entry.description = [string]$descriptionRaw
    }

    if ($hasVgpu) {
        $entry.vgpuDevices = @([ordered]@{ profileNames = @($vgpuProfileNames) })
    }

    return [PSCustomObject]$entry
}
Function Compare-VmClassDesiredVersusExistingSpec {

    <#
        .SYNOPSIS
        Compares desired JSON-derived spec to an existing vCenter VM class spec and returns
        equality plus human diff lines.

        .PARAMETER DesiredComparable
        From ConvertTo-VmClassSpecComparableFromDesired.

        .PARAMETER ExistingComparable
        From ConvertTo-VmClassSpecComparableFromListOrGetItem.

        .OUTPUTS
        PSCustomObject with Equal ([bool]) and DiffLines ([string[]]).
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNull()] [PSCustomObject]$DesiredComparable,
        [Parameter(Mandatory = $true)] [ValidateNotNull()] [PSCustomObject]$ExistingComparable
    )

    $diffLines = [System.Collections.Generic.List[string]]::new()

    if ($DesiredComparable.CpuCount -ne $ExistingComparable.CpuCount) {
        [void]$diffLines.Add("The cpu_count is $($DesiredComparable.CpuCount) in JSON and $($ExistingComparable.CpuCount) in vCenter.")
    }

    if ($DesiredComparable.MemoryMb -ne $ExistingComparable.MemoryMb) {
        [void]$diffLines.Add("The memory_MB is $($DesiredComparable.MemoryMb) in JSON and $($ExistingComparable.MemoryMb) in vCenter.")
    }

    $desiredDesc = $DesiredComparable.Description
    $existingDesc = $ExistingComparable.Description
    if ($desiredDesc -cne $existingDesc) {
        $djPhrase = if ($null -eq $desiredDesc) { "not defined in JSON" } else { "`"$desiredDesc`" in JSON" }
        $evPhrase = if ($null -eq $existingDesc) { "not defined in vCenter" } else { "`"$existingDesc`" in vCenter" }
        [void]$diffLines.Add("The description is $djPhrase and $evPhrase.")
    }

    if ($DesiredComparable.CpuReservation -ne $ExistingComparable.CpuReservation) {
        [void]$diffLines.Add("The cpu_reservation is $($DesiredComparable.CpuReservation) in JSON and $($ExistingComparable.CpuReservation) in vCenter.")
    }

    if ($DesiredComparable.MemoryReservation -ne $ExistingComparable.MemoryReservation) {
        [void]$diffLines.Add("The memory_reservation is $($DesiredComparable.MemoryReservation) in JSON and $($ExistingComparable.MemoryReservation) in vCenter.")
    }

    if (-not (Test-VmClassSortedProfileNameListsEqual -Left $DesiredComparable.VgpuProfileNamesSorted -Right $ExistingComparable.VgpuProfileNamesSorted)) {
        $dj = ($DesiredComparable.VgpuProfileNamesSorted -join ", ")
        $ev = ($ExistingComparable.VgpuProfileNamesSorted -join ", ")
        [void]$diffLines.Add("The vGPU profile_name list is [$dj] in JSON and [$ev] in vCenter.")
    }

    if ($ExistingComparable.HasDynamicDirectPathIoOnServer) {
        [void]$diffLines.Add("vCenter reports dynamic_direct_path_IO_devices; the JSON file does not model this (treated as a mismatch; an update from the file may not fully reconcile this).")
    }

    return [PSCustomObject]@{
        DiffLines = @($diffLines)
        Equal     = ($diffLines.Count -eq 0)
    }
}
Function Get-VmClassNamespaceManagementClassOrNull {

    <#
        .SYNOPSIS
        Returns one namespace-management VM class by name (API id), or $null if vCenter reports it
        is missing.

        .PARAMETER Server
        vCenter Server for Invoke-GetVmClassNamespaceManagementVirtualMachineClasses.

        .PARAMETER VmClassId
        VM class name (same string as JSON name and API id).

        .OUTPUTS
        The get result object, or $null when not found.
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Server,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$VmClassId
    )

    try {
        return Invoke-GetVmClassNamespaceManagementVirtualMachineClasses -ErrorAction Stop -Server $Server -VmClass $VmClassId.Trim()
    } catch {
        if (Test-VmClassNamespaceManagementGetNotFoundError -ErrorRecord $_) {
            return $null
        }

        throw
    }
}

# =============================================================================
# Interactive workflow helpers: vCenter connection and per-action logic
# =============================================================================
Function Invoke-WorkflowVcenterConnect {

    <#
        .SYNOPSIS
        Prompts for and connects to a vCenter Server in an interactive workflow context.

        .DESCRIPTION
        Handles the full connection loop: FQDN prompt, reachability check, username prompt,
        password prompt, and Connect-VIServer. Re-prompts on any failure. Use -Label to
        include "source" or "destination" in connection messages. The INFO line asking you to
        connect is skipped when PowerCLI already has an active session to that same vCenter
        (FQDN or IP, case-insensitive).

        .PARAMETER InitialServer
        When set, used as the vCenter address without prompting until cleared (for example after a
        DNS retry). Invalid values are ignored with a warning.

        .PARAMETER InitialUser
        When set, used as the vCenter username without prompting until cleared after a connection retry.

        .PARAMETER Label
        Optional label (e.g. "source" or "destination") to prefix in connection log messages.

        .PARAMETER ReturnToMenuOnCancel
        When the user cancels the FQDN prompt with 'c', returns $null so the interactive menu can
        continue instead of exiting the script.

        .OUTPUTS
        PSCustomObject — { ServerName: String; Credential: PSCredential }, or $null when the user
        cancels the server prompt and -ReturnToMenuOnCancel is set.

        .NOTES
        Write-Host is used here by design for interactive prompts.
    #>

    Param (
        [Parameter(Mandatory = $false)] [String]$InitialServer = "",
        [Parameter(Mandatory = $false)] [String]$InitialUser = "",
        [Parameter(Mandatory = $false)] [String]$Label = "",
        [Parameter(Mandatory = $false)] [Switch]$ReturnToMenuOnCancel
    )

    $labelPhrase = if (-not [string]::IsNullOrWhiteSpace($Label)) { "$Label " } else { "" }
    $EmittedPleaseConnectBanner = $false

    $server = ""
    if (-not [string]::IsNullOrWhiteSpace($InitialServer)) {
        $candidateServer = $InitialServer.Trim()
        if (Test-ValidVcenterAddress -Address $candidateServer) {
            $server = $candidateServer
        } else {
            Write-LogMessage -Type WARNING -Message "Ignoring invalid vCenter server `"$candidateServer`"; you will be prompted for an address."
        }
    }

    $user = ""
    if (-not [string]::IsNullOrWhiteSpace($InitialUser)) {
        $user = $InitialUser.Trim()
    }

    $credential = $null

    while ($true) {
        if ([string]::IsNullOrWhiteSpace($server)) {
            try {
                $fqdnParams = @{}
                if ($ReturnToMenuOnCancel.IsPresent) {
                    $fqdnParams["ReturnToMenuOnCancel"] = $true
                }

                $server = Get-InteractiveVcenterServerFqdn @fqdnParams
            } catch [System.OperationCanceledException] {
                return $null
            }
        }

        if (-not (Test-IsAlreadyConnectedToVcenterServer -ServerName $server)) {
            if (-not $EmittedPleaseConnectBanner) {
                Write-Host ""
                Write-LogMessage -Type INFO -AppendNewLine -Message "Please connect to your ${labelPhrase}vCenter to continue."
                $EmittedPleaseConnectBanner = $true
            }
        }

        Write-LogMessage -Type DEBUG -Message "Checking reachability of `"$server`" before prompting for credentials..."
        $reachability = Test-VcenterReachability -Server $server
        if (-not $reachability.Success) {
            Write-LogMessage -Type ERROR -Message $reachability.ErrorMessage
            Write-Host ""
            $addrRetry = $null
            while ($addrRetry -ne "Y" -and $addrRetry -ne "N") {
                $addrRetry = (Read-Host "Would you like to re-enter the vCenter FQDN or IP address? (Y/N)").Trim().ToUpper()
            }
            if ($addrRetry -eq "N") {
                Write-LogMessage -Type INFO -Message "Exiting."
                exit 0
            }
            $server = ""
            continue
        }

        if ([string]::IsNullOrWhiteSpace($user)) {
            $user = Get-InteractiveVcenterUsername
        }

        Write-Host ""
        $password = Get-VmClassScriptVcenterPasswordSecureString
        $credential = New-Object System.Management.Automation.PSCredential($user, $password)
        Write-Host ""
        Write-LogMessage -Type INFO -Message "Connecting to ${labelPhrase}vCenter `"$server`"..."
        $connectResult = Connect-Vcenter -AllowVcenterAddressRetry -ServerCredential $credential -ServerName $server
        if ($connectResult -eq $SCRIPT:CONNECT_VCENTER_RETRY_VCENTER_ADDRESS) {
            $server = ""
            $user = ""
            continue
        }

        break
    }

    return [PSCustomObject]@{ ServerName = $server; Credential = $credential }
}
Function Write-InteractiveWorkflowDisconnectNotice {

    <#
        .SYNOPSIS
        Logs that the script is disconnecting from a vCenter before the interactive menu continues.

        .PARAMETER VcenterFqdn
        vCenter Server FQDN or IP that is being disconnected.

        .NOTES
        Ensures operators see which session is cleared before the next menu action.
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$VcenterFqdn
    )

    Write-LogMessage -Type INFO -Message "Disconnecting from vCenter `"$VcenterFqdn`" to clear the session; the next menu action will prompt for (or reuse) vCenter connection details."
}
Function Get-WorkflowBackupJsonPath {

    <#
        .SYNOPSIS
        Generates a timestamped backup JSON file path inside the Backup/ subdirectory.
        Creates the subdirectory if it does not already exist.

        .PARAMETER Qualifier
        Optional qualifier to include in the filename (e.g. "pre" or "post").

        .PARAMETER Server
        vCenter Server FQDN or IP, included in the filename.

        .OUTPUTS
        System.String — full path to the backup file inside the Backup/ subdirectory.
    #>

    Param (
        [Parameter(Mandatory = $false)] [String]$Qualifier = "",
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Server
    )

    $backupDir = Join-Path -Path $PSScriptRoot -ChildPath "Backup"
    if (-not (Test-Path -LiteralPath $backupDir -PathType Container)) {
        $null = New-Item -Path $backupDir -ItemType Directory -Force
        Write-LogMessage -Type DEBUG -Message "Created backup directory `"$backupDir`"."
    }

    $qualifierPart = if (-not [string]::IsNullOrWhiteSpace($Qualifier)) { "-$Qualifier" } else { "" }
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    return Join-Path -Path $backupDir -ChildPath "vmClasses-backup-$Server$qualifierPart-$timestamp.json"
}
Function Invoke-KeyPause {

    <#
        .SYNOPSIS
        Prints a blank line, displays the next step, waits for any key, then advances to a new line.

        .PARAMETER NextStep
        Short description of the step about to begin, shown in the prompt.
        Example: "Backup (pre-import) - Save all VM classes from vCenter to a JSON file"

        .NOTES
        Write-Host is used here by design for interactive prompts.
    #>

    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$NextStep
    )

    Write-Host ""
    Write-Host -NoNewline "Press any key to proceed to the next step - $NextStep..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    Write-Host ""
    Write-Host ""
}
Function Invoke-DiscoverAction {

    <#
        .SYNOPSIS
        Executes the Discover action: enumerates live VMs and writes a vmClasses JSON file.

        .PARAMETER ConfirmedJsonPath
        Output JSON path already confirmed by the caller (overwrite decision already made).

        .PARAMETER SaveAll
        Skip the interactive configuration selection and save every discovered configuration.

        .PARAMETER Server
        Connected vCenter Server to query for VM inventory.

        .OUTPUTS
        System.String — the confirmed output JSON path (unchanged from input).
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$ConfirmedJsonPath,
        [Parameter(Mandatory = $false)] [Switch]$SaveAll,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Server
    )

    Write-LogMessage -Type INFO -Message "Querying all VMs from vCenter `"$Server`"..."
    $inventoryData = @(Get-VmInventoryData -Server $Server)

    if ($inventoryData.Count -eq 0) {
        Write-LogMessage -Type WARNING -Message "No VMs found on vCenter `"$Server`". Nothing to export."
        return $ConfirmedJsonPath
    }

    Write-LogMessage -Type INFO -Message "Found $($inventoryData.Count) VM(s). Grouping by configuration..."
    $configGroups = @(Get-VmConfigurationGroups -InventoryData $inventoryData)
    Write-LogMessage -Type INFO -Message "Found $($configGroups.Count) unique VM configuration(s)."

    $selectedGroups = if ($SaveAll) {
        $classNames = @($configGroups | ForEach-Object { ConvertTo-VmClassJsonName -ConfigGroup $_ })
        Write-VmConfigurationSummaryTable -ClassNames $classNames -ConfigGroups $configGroups
        Write-LogMessage -Type INFO -Message "Saving all $($configGroups.Count) configuration(s) to `"$ConfirmedJsonPath`" (-SaveAll)."
        $configGroups
    } else {
        @(Get-UserConfigurationSelection -ConfigGroups $configGroups)
    }

    if ($selectedGroups.Count -eq 0) {
        Write-LogMessage -Type WARNING -Message "No configurations selected. No output file written."
    } else {
        Write-VmClassOutputJson -OutputFilePath $ConfirmedJsonPath -SelectedGroups $selectedGroups

        if (-not [Console]::IsInputRedirected -and -not $SaveAll) {
            $viewChoice = (Read-Host "View the output JSON? [Y/N]").Trim()
            if ($viewChoice -match "^[Yy]") {
                Write-Host ""
                Get-Content -Path $ConfirmedJsonPath | Out-Host
                Write-Host ""
            }
        }

        Write-LogMessage -Type INFO -Message "Discover completed."
    }

    return $ConfirmedJsonPath
}
Function Invoke-BackupAction {

    <#
        .SYNOPSIS
        Executes the Backup action: retrieves all VM class definitions from vCenter and writes them
        to a JSON file in vmClasses.json format.

        .PARAMETER ConfirmedJsonPath
        Output JSON path already confirmed by the caller (overwrite decision already made).

        .PARAMETER Server
        Connected vCenter Server to query for VM class definitions.
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$ConfirmedJsonPath,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Server
    )

    Write-LogMessage -Type INFO -Message "Retrieving all VM class definitions from vCenter `"$Server`"..."
    $allClassIds = Get-ExistingVmClassIdSet -Server $Server
    if ($allClassIds.Count -eq 0) {
        Write-LogMessage -Type WARNING -Message "No VM classes found on vCenter `"$Server`". No backup file written."
        return
    }

    $backupEntries = [System.Collections.Generic.List[PSCustomObject]]::new()
    $directPathCount = 0
    foreach ($classId in ($allClassIds | Sort-Object)) {
        $classItem = Get-VmClassNamespaceManagementClassOrNull -Server $Server -VmClassId $classId
        if ($null -eq $classItem) {
            Write-LogMessage -Type WARNING -Message "VM class `"$classId`" could not be retrieved from vCenter; skipping."
            continue
        }

        $hasDynamicDirectPath = $null -ne $classItem.Devices -and
            $null -ne $classItem.Devices.DynamicDirectPathIoDevices -and
            @($classItem.Devices.DynamicDirectPathIoDevices).Count -gt 0
        if ($hasDynamicDirectPath) {
            Write-LogMessage -Type WARNING -Message "VM class `"$classId`" has DynamicDirectPathIO device(s); those settings are not supported in this format and will be omitted."
            $directPathCount++
        }

        [void]$backupEntries.Add((ConvertTo-VmClassJsonEntryFromApiItem -Item $classItem))
    }

    Write-LogMessage -Type INFO -Message "Retrieved $($backupEntries.Count) VM class definition(s)."
    if ($directPathCount -gt 0) {
        Write-LogMessage -Type WARNING -Message "$directPathCount class(es) had DynamicDirectPathIO configuration that could not be included in the backup."
    }

    Write-LogMessage -Type DEBUG -Message "The backup file uses the same format as vmClasses.json and can be used directly with -Action Update."
    $backupEntries | ConvertTo-Json -Depth 10 | Set-Content -Path $ConfirmedJsonPath -Encoding UTF8 -ErrorAction Stop
    Write-LogMessage -Type INFO -Message "Wrote $($backupEntries.Count) VM class definition(s) to `"$ConfirmedJsonPath`"."
    Write-LogMessage -Type INFO -Message "Backup completed."
}
Function Invoke-ListAction {

    <#
        .SYNOPSIS
        Executes the List action: prints a formatted table of all VM classes on vCenter.

        .PARAMETER Server
        Connected vCenter Server to query for VM classes.

        .NOTES
        Write-Host is used here by design (Format-Table outputs to console).
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Server
    )

    Write-LogMessage -Type INFO -Message "Listing VM classes on vCenter `"$Server`"..."
    $rows = Get-VmClassListViewFromServer -Server $Server
    if ($rows.Count -eq 0) {
        Write-LogMessage -Type WARNING -Message "No VM classes returned from vCenter."
    } else {
        $rows | Sort-Object -Property Name | Format-Table -Property Name, CpuCount, MemoryMB, Default, Gpu -AutoSize -Wrap | Out-Host
        Write-LogMessage -Type INFO -Message "Listed $($rows.Count) VM class(es)."
    }
}
Function Invoke-CreateVmClass {

    <#
        .SYNOPSIS
        Creates a single VM class on vCenter via REST API.

        .PARAMETER Entry
        Validated JSON entry object for the VM class to create.

        .PARAMETER EntryName
        The VM class name (id field from the entry).

        .PARAMETER RestApiSessionToken
        Active vmware-api-session-id token.

        .PARAMETER VcenterServer
        vCenter Server FQDN or IP.
    #>

    [CmdletBinding(SupportsShouldProcess = $true)]
    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNull()] [Object]$Entry,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$EntryName,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$RestApiSessionToken,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$VcenterServer
    )

    if (-not $PSCmdlet.ShouldProcess($EntryName, "Create VM class on vCenter `"$VcenterServer`"")) {
        Write-LogMessage -Type INFO -Message "WhatIf: would create VM class `"$EntryName`"."
        return
    }

    try {
        Write-LogMessage -Type INFO -NoNewline -Message "Creating VM class `"$EntryName`"... "
        $createBody = ConvertTo-VmClassRestCreateBody -Entry $Entry
        $null = Invoke-RestMethod `
            -Method Post `
            -Uri "https://$VcenterServer/api/vcenter/namespace-management/virtual-machine-classes" `
            -Headers @{ "vmware-api-session-id" = $RestApiSessionToken } `
            -Body ($createBody | ConvertTo-Json -Depth 5 -Compress) `
            -ContentType "application/json" `
            -SkipCertificateCheck `
            -ErrorAction Stop
        Write-LogMessage -Type INFO -CompletePending -Message "Succeeded"
    } catch {
        $failureText = Get-VmClassErrorRecordDiagnosticText -ErrorRecord $_
        Write-LogMessage -Type ERROR -CompletePending -Message "Failed"
        Write-LogMessage -Type ERROR -Message "Failed to create VM class `"$EntryName`": $failureText"
        throw
    }
}
Function Invoke-PatchVmClass {

    <#
        .SYNOPSIS
        Patches an existing VM class on vCenter via REST API if it differs from the JSON entry.

        .PARAMETER Entry
        Validated JSON entry object containing the desired state.

        .PARAMETER EntryName
        The VM class name (id field from the entry).

        .PARAMETER ExistingClassItem
        The current VM class definition retrieved from vCenter.

        .PARAMETER ResolvedJsonPath
        Path to the source JSON file, used in log messages.

        .PARAMETER RestApiSessionToken
        Active vmware-api-session-id token.

        .PARAMETER VcenterServer
        vCenter Server FQDN or IP.
    #>

    [CmdletBinding(SupportsShouldProcess = $true)]
    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNull()] [Object]$Entry,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$EntryName,
        [Parameter(Mandatory = $true)] [ValidateNotNull()] [Object]$ExistingClassItem,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$ResolvedJsonPath,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$RestApiSessionToken,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$VcenterServer
    )

    $apiValuesForCompare = Get-VmClassNamespaceManagementApiValuesFromJsonEntry -Entry $Entry
    $desiredComparable = ConvertTo-VmClassSpecComparableFromDesired -DesiredApiOutput $apiValuesForCompare
    $existingComparable = ConvertTo-VmClassSpecComparableFromListOrGetItem -Item $ExistingClassItem
    $compareResult = Compare-VmClassDesiredVersusExistingSpec `
        -DesiredComparable $desiredComparable `
        -ExistingComparable $existingComparable

    if (-not $compareResult.Equal) {
        Write-LogMessage -Type INFO -Message "Detected a difference between `"$(Split-Path -Leaf $ResolvedJsonPath)`" and vCenter definition of VM class `"$EntryName`"."
        foreach ($diffLine in $compareResult.DiffLines) {
            Write-LogMessage -Type INFO -Message "        $diffLine"
        }
    }

    if (-not $PSCmdlet.ShouldProcess($EntryName, "Update VM class on vCenter `"$VcenterServer`"")) {
        Write-LogMessage -Type INFO -Message "WhatIf: would update VM class `"$EntryName`" on vCenter to match `"$(Split-Path -Leaf $ResolvedJsonPath)`"."
        return
    }

    Write-LogMessage -Type INFO -NoNewline -Message "Updating VM class `"$EntryName`" on vCenter to match `"$(Split-Path -Leaf $ResolvedJsonPath)`"... "
    if ($compareResult.Equal) {
        Write-LogMessage -Type INFO -CompletePending -Message "Skipped (vCenter already matches the file)"
        return
    }

    try {
        $updateBody = ConvertTo-VmClassRestUpdateBody -Entry $Entry
        $encodedName = [Uri]::EscapeDataString($EntryName)
        $null = Invoke-RestMethod `
            -Method Patch `
            -Uri "https://$VcenterServer/api/vcenter/namespace-management/virtual-machine-classes/$encodedName" `
            -Headers @{ "vmware-api-session-id" = $RestApiSessionToken } `
            -Body ($updateBody | ConvertTo-Json -Depth 5 -Compress) `
            -ContentType "application/json" `
            -SkipCertificateCheck `
            -ErrorAction Stop
        Write-LogMessage -Type INFO -CompletePending -Message "Succeeded"
    } catch {
        $updateFailureText = Get-VmClassErrorRecordDiagnosticText -ErrorRecord $_
        Write-LogMessage -Type ERROR -CompletePending -Message "Failed"
        Write-LogMessage -Type ERROR -Message "Failed to update VM class `"$EntryName`": $updateFailureText"
        throw
    }
}
Function Invoke-UpdateVmClassEntry {

    <#
        .SYNOPSIS
        Processes a single VM class entry: queries vCenter for its current state, then creates,
        patches, or skips based on the comparison result.

        .PARAMETER Entry
        Validated JSON entry object for the VM class.

        .PARAMETER ResolvedJsonPath
        Path to the source JSON file, used in diff log messages.

        .PARAMETER RestApiSessionToken
        Active vmware-api-session-id token.

        .PARAMETER VcenterServer
        vCenter Server FQDN or IP.
    #>

    [CmdletBinding(SupportsShouldProcess = $true)]
    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNull()] [Object]$Entry,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$ResolvedJsonPath,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$RestApiSessionToken,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$VcenterServer
    )

    $entryName = Get-VmClassJsonEntryName -Entry $Entry

    $existingClassItem = $null
    try {
        $existingClassItem = Get-VmClassNamespaceManagementClassOrNull -Server $VcenterServer -VmClassId $entryName
    } catch {
        $queryFailureText = Get-VmClassErrorRecordDiagnosticText -ErrorRecord $_
        Write-LogMessage -Type ERROR -Message "Failed to query VM class `"$entryName`" on vCenter: $queryFailureText"
        throw
    }

    if (Test-VmClassIsDefaultName -Name $entryName) {
        Write-LogMessage -Type WARNING -Message "VM class `"$entryName`" matches a built-in vCenter default class name."
        if (-not [Console]::IsInputRedirected -and -not $WhatIfPreference) {
            $confirmOverride = (Read-Host "        Proceed with modifying this default class? [y/N]").Trim()
            if ($confirmOverride -notmatch $SCRIPT:VmClassInteractiveAffirmativeResponseRegexPattern) {
                Write-LogMessage -Type INFO -Message "Skipping VM class `"$entryName`" (user declined to modify a built-in default)."
                return
            }
        }
    }

    if ($null -eq $existingClassItem) {
        Invoke-CreateVmClass `
            -Entry $Entry `
            -EntryName $entryName `
            -RestApiSessionToken $RestApiSessionToken `
            -VcenterServer $VcenterServer
        return
    }

    Invoke-PatchVmClass `
        -Entry $Entry `
        -EntryName $entryName `
        -ExistingClassItem $existingClassItem `
        -ResolvedJsonPath $ResolvedJsonPath `
        -RestApiSessionToken $RestApiSessionToken `
        -VcenterServer $VcenterServer
}
Function Invoke-UpdateAction {

    <#
        .SYNOPSIS
        Executes the Update action: applies VM class definitions from a JSON file to vCenter as an
        upsert (create new, patch changed, skip matching).

        .PARAMETER Credential
        PSCredential used to establish the REST API session for create/patch operations.

        .PARAMETER ResolvedJsonPath
        Path to the validated vmClasses JSON file.

        .PARAMETER ResolvedVmClassNames
        Class names selected via interactive TUI. Passed when -VmClassName is omitted.

        .PARAMETER Server
        Connected vCenter Server to apply VM classes to.

        .PARAMETER VmClassName
        Single class name or "all". Used when -ResolvedVmClassNames is empty.
    #>

    [CmdletBinding(SupportsShouldProcess = $true)]
    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNull()] [PSCredential]$Credential,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$ResolvedJsonPath,
        [Parameter(Mandatory = $false)] [String[]]$ResolvedVmClassNames = @(),
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Server,
        [Parameter(Mandatory = $false)] [String]$VmClassName = ""
    )

    Write-LogMessage -Type DEBUG -Message "Resolving update targets from `"$ResolvedJsonPath`"..."
    try {
        $updateEntries = Get-VmClassJsonEntriesForMutationTarget `
            -JsonFilePath $ResolvedJsonPath `
            -SelectedNames $ResolvedVmClassNames `
            -VmClassName $VmClassName
    } catch {
        Write-LogMessage -Type ERROR -Message "vmClasses JSON validation or target resolution failed: $($_.Exception.Message)"
        throw
    }

    $restApiSessionToken = New-VmClassRestApiSession -VcenterServer $Server -Credential $Credential
    Write-LogMessage -Type DEBUG -Message "vCenter REST API session established for Create/Update operations."

    try {
        foreach ($entry in $updateEntries) {
            Invoke-UpdateVmClassEntry `
                -Entry $entry `
                -ResolvedJsonPath $ResolvedJsonPath `
                -RestApiSessionToken $restApiSessionToken `
                -VcenterServer $Server
        }
    } finally {
        Remove-VmClassRestApiSession -VcenterServer $Server -SessionToken $restApiSessionToken
        Write-LogMessage -Type DEBUG -Message "vCenter REST API session closed."
    }
}
Function Invoke-DeleteAction {

    <#
        .SYNOPSIS
        Executes the Delete action: removes one or more VM classes from vCenter.

        .PARAMETER ResolvedVmClassNames
        Class names selected via interactive TUI. Used when -VmClassName is omitted.

        .PARAMETER Server
        Connected vCenter Server to delete VM classes from.

        .PARAMETER VmClassName
        Single class name or "all". Used when -ResolvedVmClassNames is empty.
    #>

    [CmdletBinding(SupportsShouldProcess = $true)]
    Param (
        [Parameter(Mandatory = $false)] [String[]]$ResolvedVmClassNames = @(),
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Server,
        [Parameter(Mandatory = $false)] [String]$VmClassName = ""
    )

    $namesToDelete = [System.Collections.Generic.List[string]]::new()

    if ($ResolvedVmClassNames.Count -gt 0) {
        foreach ($name in $ResolvedVmClassNames) {
            [void]$namesToDelete.Add($name)
        }
    } elseif (-not [string]::IsNullOrWhiteSpace($VmClassName) -and $VmClassName.Trim() -ieq "all") {
        Write-LogMessage -Type DEBUG -Message "Loading VM class names from vCenter for delete all (custom only)..."
        $allIds = Get-ExistingVmClassIdSet -Server $Server
        $customIds = @($allIds | Where-Object { -not (Test-VmClassIsDefaultName -Name $_) })
        $defaultCount = $allIds.Count - $customIds.Count
        Write-LogMessage -Type INFO -Message "Found $($customIds.Count) custom VM class(es) on vCenter (ignoring $defaultCount built-in default(s))."
        foreach ($id in $customIds) {
            [void]$namesToDelete.Add($id)
        }
    } elseif (-not [string]::IsNullOrWhiteSpace($VmClassName)) {
        [void]$namesToDelete.Add($VmClassName.Trim())
    }

    if ($namesToDelete.Count -eq 0) {
        Write-LogMessage -Type DEBUG -Message "No VM class names resolved for deletion; skipping delete step."
        return
    }

    Write-LogMessage -Type DEBUG -Message "Loading VM class names from vCenter for delete pre-check..."
    $existingVmClassIdsOnServer = Get-ExistingVmClassIdSet -Server $Server
    $deleteSingleExplicitName = $namesToDelete.Count -eq 1

    foreach ($className in $namesToDelete) {
        if (-not $existingVmClassIdsOnServer.Contains($className)) {
            if ($deleteSingleExplicitName) {
                if ($WhatIfPreference) {
                    Write-LogMessage -Type INFO -Message "WhatIf: VM class `"$className`" was not found on vCenter `"$Server`"; delete would not be performed. Run -Action List to see available VM class names."
                    continue
                }
                Write-LogMessage -Type ERROR -Message "VM class `"$className`" was not found on vCenter `"$Server`". Run -Action List to see available VM class names."
                exit 0
            }
            Write-LogMessage -Type WARNING -Message "VM class `"$className`" is not present on vCenter; skipping delete."
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($className, "Delete VM class on vCenter `"$Server`"")) {
            Write-LogMessage -Type INFO -Message "WhatIf: would delete VM class `"$className`"."
            continue
        }

        try {
            Write-LogMessage -Type INFO -NoNewline -Message "Deleting VM class `"$className`"... "
            Invoke-DeleteVmClassNamespaceManagementVirtualMachineClasses `
                -Confirm:$false `
                -ErrorAction Stop `
                -Server $Server `
                -VmClass $className
            Write-LogMessage -Type INFO -CompletePending -Message "Succeeded"
        } catch {
            if (Test-VmClassNamespaceManagementDeleteNotFoundError -ErrorRecord $_) {
                if ($deleteSingleExplicitName) {
                    Write-LogMessage -Type ERROR -CompletePending -Message "Failed"
                    Write-LogMessage -Type ERROR -Message "VM class `"$className`" was not found in the vCenter inventory on `"$Server`". Run -Action List to see available VM class names."
                    exit 0
                }
                Write-LogMessage -Type WARNING -CompletePending -Message "Skipped (not in inventory)"
                continue
            }

            $deleteFailureText = Get-VmClassErrorRecordDiagnosticText -ErrorRecord $_
            Write-LogMessage -Type ERROR -CompletePending -Message "Failed"
            Write-LogMessage -Type ERROR -Message "Failed to delete VM class `"$className`": $deleteFailureText"
            throw
        }
    }
}

# =============================================================================
# Interactive workflow orchestration functions
# =============================================================================
Function Invoke-DiscoverWorkflow {

    <#
        .SYNOPSIS
        Full guided workflow starting from Discover: connects to a source vCenter to scan VMs and
        generate a vmClasses JSON, then optionally imports to the same source vCenter or connects
        to a separate destination vCenter to back up, import, and re-backup VM classes.

        .PARAMETER ConfirmedJsonPath
        Output JSON path already confirmed by the caller. The caller is responsible for calling
        Get-ConfirmedDiscoverOutputPath first so that the confirmed path is persisted at the
        script level (making it the session default for the menu and other workflows).

        .PARAMETER DefaultVcenterServer
        Optional default vCenter FQDN or IP for the source connection (from the command line or menu session).

        .PARAMETER DefaultVcenterUser
        Optional default vCenter username for the source connection.

        .PARAMETER SaveAll
        Skip the interactive selection table and save all discovered configurations.

        .OUTPUTS
        System.Boolean — $true to return to the main menu (for example user cancelled a connection prompt);
        $false when the workflow finished or the user chose to exit for manual JSON edits.

        .NOTES
        Write-Host is used here by design for interactive prompts.
        A full successful run returns $false so the caller can exit the script; connection cancel returns $true.
    #>

    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$ConfirmedJsonPath,
        [Parameter(Mandatory = $false)] [String]$DefaultVcenterServer = "",
        [Parameter(Mandatory = $false)] [String]$DefaultVcenterUser = "",
        [Parameter(Mandatory = $false)] [Switch]$SaveAll
    )

    $jsonPath = $ConfirmedJsonPath

    # Phase 1: Connect to source vCenter and run discovery.
    $srcConn = Invoke-WorkflowVcenterConnect `
        -InitialServer $DefaultVcenterServer `
        -InitialUser $DefaultVcenterUser `
        -Label "source" `
        -ReturnToMenuOnCancel
    if ($null -eq $srcConn) {
        return $true
    }

    try {
        $jsonPath = Invoke-DiscoverAction -ConfirmedJsonPath $jsonPath -SaveAll:$SaveAll -Server $srcConn.ServerName
    } catch {
        Write-InteractiveWorkflowDisconnectNotice -VcenterFqdn $srcConn.ServerName
        Disconnect-Vcenter -ServerName $srcConn.ServerName -Silence
        Write-LogMessage -Type DEBUG -Message "Disconnected from source vCenter `"$($srcConn.ServerName)`"."
        throw
    }

    # Phase 2: Offer exit for manual class-name editing.
    Write-Host ""
    $jsonFile = Split-Path -Leaf $jsonPath
    $editChoice = $null
    while ($editChoice -ne "Y" -and $editChoice -ne "N") {
        $editChoice = (Read-Host "Exit to manually modify `"$jsonFile`" to rename VM classes before proceeding to the VM class import steps? [Y/N]").Trim().ToUpper()
    }
    if ($editChoice -eq "Y") {
        Write-InteractiveWorkflowDisconnectNotice -VcenterFqdn $srcConn.ServerName
        Disconnect-Vcenter -ServerName $srcConn.ServerName -Silence
        Write-LogMessage -Type DEBUG -Message "Disconnected from source vCenter `"$($srcConn.ServerName)`"."
        Write-LogMessage -Type INFO -Message "Exiting. Re-run the script and use Update to apply `"$jsonPath`" to your destination vCenter."
        return $false
    }

    # Phase 3: Same vCenter or a separate destination?
    Write-Host ""
    $sameChoice = $null
    while ($sameChoice -ne "Y" -and $sameChoice -ne "N") {
        $sameChoice = (Read-Host "Import VM classes into the same vCenter `"$($srcConn.ServerName)`"? [Y/N]").Trim().ToUpper()
    }

    $targetConn = $srcConn
    if ($sameChoice -eq "N") {
        Write-InteractiveWorkflowDisconnectNotice -VcenterFqdn $srcConn.ServerName
        Disconnect-Vcenter -ServerName $srcConn.ServerName -Silence
        Write-LogMessage -Type DEBUG -Message "Disconnected from source vCenter `"$($srcConn.ServerName)`"."
        $targetConn = Invoke-WorkflowVcenterConnect -Label "destination" -ReturnToMenuOnCancel
        if ($null -eq $targetConn) {
            return $true
        }
    }

    # Phase 4: List, backup, import, backup on the target vCenter.
    try {
        Write-LogMessage -Type INFO -Message "Proceeding to list VM classes on `"$($targetConn.ServerName)`"."
        Invoke-ListAction -Server $targetConn.ServerName

        Invoke-KeyPause -NextStep "Backup (pre-import) - Save all VM classes from vCenter to a JSON file"

        $preBackupPath = Get-WorkflowBackupJsonPath -Qualifier "pre" -Server $targetConn.ServerName
        Invoke-BackupAction -ConfirmedJsonPath $preBackupPath -Server $targetConn.ServerName

        Invoke-KeyPause -NextStep "Update - Apply vmClasses.json to vCenter"

        Write-LogMessage -Type INFO -AppendNewLine -Message "The default VM class file is `"$jsonPath`"."
        $importPath = $jsonPath
        $altChoice = $null
        while ($altChoice -ne "Y" -and $altChoice -ne "N") {
            $altChoice = (Read-Host "Use a different VM class file instead of `"$jsonFile`"? [Y/N]").Trim().ToUpper()
        }
        if ($altChoice -eq "Y") {
            $importPath = Get-InteractiveJsonPath -ForcePrompt -InitialResolvedPath $jsonPath
        }

        $null = Get-VmClassJsonValidatedEntryList -JsonFilePath $importPath
        $selectedNames = @(Get-UserVmClassSelection -DefaultSelectAll -JsonFilePath $importPath -Action "Update")
        Invoke-UpdateAction `
            -Credential $targetConn.Credential `
            -ResolvedJsonPath $importPath `
            -ResolvedVmClassNames $selectedNames `
            -Server $targetConn.ServerName

        Invoke-KeyPause -NextStep "Backup (post-import) - Save all VM classes from vCenter to a JSON file"

        $postBackupPath = Get-WorkflowBackupJsonPath -Qualifier "post" -Server $targetConn.ServerName
        Invoke-BackupAction -ConfirmedJsonPath $postBackupPath -Server $targetConn.ServerName
    } finally {
        Write-InteractiveWorkflowDisconnectNotice -VcenterFqdn $targetConn.ServerName
        Disconnect-Vcenter -ServerName $targetConn.ServerName -Silence
        $targetLabel = if ($sameChoice -eq "N") { "destination" } else { "source" }
        Write-LogMessage -Type DEBUG -Message "Disconnected from $targetLabel vCenter `"$($targetConn.ServerName)`"."
    }

    return $false
}
Function Invoke-BackupWorkflow {

    <#
        .SYNOPSIS
        Workflow for the Backup menu entry: connects to vCenter, takes a timestamped backup, and
        prompts whether to return to the main menu.

        .PARAMETER DefaultVcenterServer
        Optional default vCenter FQDN or IP from the command line or menu session.

        .PARAMETER DefaultVcenterUser
        Optional default vCenter username from the command line or menu session.

        .OUTPUTS
        System.Boolean — $true to return to the main menu, $false to exit.

        .NOTES
        Write-Host is used here by design for interactive prompts.
    #>

    Param (
        [Parameter(Mandatory = $false)] [String]$DefaultVcenterServer = "",
        [Parameter(Mandatory = $false)] [String]$DefaultVcenterUser = ""
    )

    $conn = Invoke-WorkflowVcenterConnect `
        -InitialServer $DefaultVcenterServer `
        -InitialUser $DefaultVcenterUser `
        -Label "destination" `
        -ReturnToMenuOnCancel
    if ($null -eq $conn) {
        return $true
    }

    try {
        $backupPath = Get-WorkflowBackupJsonPath -Server $conn.ServerName
        Invoke-BackupAction -ConfirmedJsonPath $backupPath -Server $conn.ServerName
    } finally {
        Write-InteractiveWorkflowDisconnectNotice -VcenterFqdn $conn.ServerName
        Disconnect-Vcenter -ServerName $conn.ServerName -Silence
        Write-LogMessage -Type DEBUG -Message "Disconnected from destination vCenter `"$($conn.ServerName)`"."
    }

    Write-Host ""
    $menuChoice = $null
    while ($menuChoice -ne "Y" -and $menuChoice -ne "N") {
        $menuChoice = (Read-Host "Return to the main menu? [Y/N]").Trim().ToUpper()
    }
    return ($menuChoice -eq "Y")
}
Function Invoke-ListWorkflow {

    <#
        .SYNOPSIS
        Workflow for the List menu entry: connects to destination vCenter, lists all VM classes,
        and optionally takes a pre-import backup, runs an import, takes a post-import backup, then
        prompts whether to return to the main menu.

        .PARAMETER DefaultVcenterServer
        Optional default vCenter FQDN or IP from the command line or menu session.

        .PARAMETER DefaultVcenterUser
        Optional default vCenter username from the command line or menu session.

        .PARAMETER InitialJsonPath
        Default VM classes JSON path offered when the user chooses to import.

        .OUTPUTS
        System.Boolean — $true to return to the main menu, $false to exit.

        .NOTES
        Write-Host is used here by design for interactive prompts.
    #>

    Param (
        [Parameter(Mandatory = $false)] [String]$DefaultVcenterServer = "",
        [Parameter(Mandatory = $false)] [String]$DefaultVcenterUser = "",
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$InitialJsonPath
    )

    $didImport = $false

    $conn = Invoke-WorkflowVcenterConnect `
        -InitialServer $DefaultVcenterServer `
        -InitialUser $DefaultVcenterUser `
        -Label "destination" `
        -ReturnToMenuOnCancel
    if ($null -eq $conn) {
        return $true
    }

    try {
        Invoke-ListAction -Server $conn.ServerName

        Write-Host ""
        $backupChoice = $null
        while ($backupChoice -ne "Y" -and $backupChoice -ne "N") {
            $backupChoice = (Read-Host "Would you like to take a backup? [Y/N]").Trim().ToUpper()
        }
        if ($backupChoice -eq "N") {
            return $true
        }

        $preBackupPath = Get-WorkflowBackupJsonPath -Qualifier "pre" -Server $conn.ServerName
        Invoke-BackupAction -ConfirmedJsonPath $preBackupPath -Server $conn.ServerName

        Write-Host ""
        $importChoice = $null
        while ($importChoice -ne "Y" -and $importChoice -ne "N") {
            $importChoice = (Read-Host "Would you like to start an import? [Y/N]").Trim().ToUpper()
        }
        if ($importChoice -eq "N") {
            return $true
        }

        Write-LogMessage -Type INFO -Message "The default VM class file is `"$InitialJsonPath`"."
        $importPath = $InitialJsonPath
        $altChoice = $null
        while ($altChoice -ne "Y" -and $altChoice -ne "N") {
            $altChoice = (Read-Host "Use a different VM class file instead? [Y/N]").Trim().ToUpper()
        }
        if ($altChoice -eq "Y") {
            $importPath = Get-InteractiveJsonPath -ForcePrompt -InitialResolvedPath $InitialJsonPath
        }

        $null = Get-VmClassJsonValidatedEntryList -JsonFilePath $importPath
        $selectedNames = @(Get-UserVmClassSelection -DefaultSelectAll -JsonFilePath $importPath -Action "Update")
        Invoke-UpdateAction `
            -Credential $conn.Credential `
            -ResolvedJsonPath $importPath `
            -ResolvedVmClassNames $selectedNames `
            -Server $conn.ServerName

        Invoke-KeyPause -NextStep "Backup (post-import) - Save all VM classes from vCenter to a JSON file"

        $postBackupPath = Get-WorkflowBackupJsonPath -Qualifier "post" -Server $conn.ServerName
        Invoke-BackupAction -ConfirmedJsonPath $postBackupPath -Server $conn.ServerName
        $didImport = $true
    } finally {
        Write-InteractiveWorkflowDisconnectNotice -VcenterFqdn $conn.ServerName
        Disconnect-Vcenter -ServerName $conn.ServerName -Silence
        Write-LogMessage -Type DEBUG -Message "Disconnected from destination vCenter `"$($conn.ServerName)`"."
    }

    if (-not $didImport) {
        return $true
    }

    Write-Host ""
    $menuChoice = $null
    while ($menuChoice -ne "Y" -and $menuChoice -ne "N") {
        $menuChoice = (Read-Host "Return to the main menu? [Y/N]").Trim().ToUpper()
    }
    return ($menuChoice -eq "Y")
}
Function Invoke-UpdateWorkflow {

    <#
        .SYNOPSIS
        Workflow for the Update menu entry: connects to source vCenter, imports VM classes, and
        optionally removes VM classes and lists the final state.

        .PARAMETER DefaultVcenterServer
        Optional default vCenter FQDN or IP from the command line or menu session.

        .PARAMETER DefaultVcenterUser
        Optional default vCenter username from the command line or menu session.

        .PARAMETER InitialJsonPath
        Default VM classes JSON path offered to the user for the import.

        .PARAMETER VmClassName
        Pre-selected VM class name or "all"; blank to prompt interactively.

        .OUTPUTS
        System.Boolean — $true to return to the main menu, $false to exit.

        .NOTES
        Write-Host is used here by design for interactive prompts.
    #>

    Param (
        [Parameter(Mandatory = $false)] [String]$DefaultVcenterServer = "",
        [Parameter(Mandatory = $false)] [String]$DefaultVcenterUser = "",
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$InitialJsonPath,
        [Parameter(Mandatory = $false)] [String]$VmClassName = ""
    )

    $conn = Invoke-WorkflowVcenterConnect `
        -InitialServer $DefaultVcenterServer `
        -InitialUser $DefaultVcenterUser `
        -Label "source" `
        -ReturnToMenuOnCancel
    if ($null -eq $conn) {
        return $true
    }

    try {
        $importPath = Get-InteractiveJsonPath -InitialResolvedPath $InitialJsonPath -TreatInitialPathAsOptionalDefault
        $null = Get-VmClassJsonValidatedEntryList -JsonFilePath $importPath

        $selectedNames = @(Get-UserVmClassSelection -DefaultSelectAll -JsonFilePath $importPath -Action "Update")
        Invoke-UpdateAction `
            -Credential $conn.Credential `
            -ResolvedJsonPath $importPath `
            -ResolvedVmClassNames $selectedNames `
            -Server $conn.ServerName

        Write-Host ""
        $deleteChoice = $null
        while ($deleteChoice -ne "Y" -and $deleteChoice -ne "N") {
            $deleteChoice = (Read-Host "Would you like to remove a VM class? [Y/N]").Trim().ToUpper()
        }
        if ($deleteChoice -eq "N") {
            return $true
        }

        $deleteNames = @(Get-UserCustomVmClassSelectionFromServer -Server $conn.ServerName)
        Invoke-DeleteAction -ResolvedVmClassNames $deleteNames -Server $conn.ServerName

        Invoke-KeyPause -NextStep "List - Show all VM classes on vCenter"
        Invoke-ListAction -Server $conn.ServerName
    } finally {
        Write-InteractiveWorkflowDisconnectNotice -VcenterFqdn $conn.ServerName
        Disconnect-Vcenter -ServerName $conn.ServerName -Silence
        Write-LogMessage -Type DEBUG -Message "Disconnected from source vCenter `"$($conn.ServerName)`"."
    }

    Write-Host ""
    $menuChoice = $null
    while ($menuChoice -ne "Y" -and $menuChoice -ne "N") {
        $menuChoice = (Read-Host "Return to the main menu? [Y/N]").Trim().ToUpper()
    }
    return ($menuChoice -eq "Y")
}
Function Invoke-DeleteWorkflow {

    <#
        .SYNOPSIS
        Workflow for the Delete menu entry: connects to destination vCenter, takes a pre-delete
        backup, removes the selected VM classes, lists the remaining classes, takes a post-delete
        backup, and prompts whether to return to the main menu.

        .PARAMETER DefaultVcenterServer
        Optional default vCenter FQDN or IP from the command line or menu session.

        .PARAMETER DefaultVcenterUser
        Optional default vCenter username from the command line or menu session.

        .PARAMETER VmClassName
        Pre-selected VM class name or "all"; blank to prompt interactively.

        .OUTPUTS
        System.Boolean — $true to return to the main menu, $false to exit.

        .NOTES
        Write-Host is used here by design for interactive prompts.
    #>

    Param (
        [Parameter(Mandatory = $false)] [String]$DefaultVcenterServer = "",
        [Parameter(Mandatory = $false)] [String]$DefaultVcenterUser = "",
        [Parameter(Mandatory = $false)] [String]$VmClassName = ""
    )

    $conn = Invoke-WorkflowVcenterConnect `
        -InitialServer $DefaultVcenterServer `
        -InitialUser $DefaultVcenterUser `
        -Label "destination" `
        -ReturnToMenuOnCancel
    if ($null -eq $conn) {
        return $true
    }

    try {
        $preBackupPath = Get-WorkflowBackupJsonPath -Qualifier "pre" -Server $conn.ServerName
        Invoke-BackupAction -ConfirmedJsonPath $preBackupPath -Server $conn.ServerName

        Write-Host ""
        $deleteNames = [string[]]@()
        if ([string]::IsNullOrWhiteSpace($VmClassName)) {
            $deleteNames = @(Get-UserCustomVmClassSelectionFromServer -Server $conn.ServerName)
        }
        Invoke-DeleteAction -ResolvedVmClassNames $deleteNames -Server $conn.ServerName -VmClassName $VmClassName

        Invoke-KeyPause -NextStep "List - Show all VM classes on vCenter"
        Invoke-ListAction -Server $conn.ServerName

        Invoke-KeyPause -NextStep "Backup (post-delete) - Save all VM classes from vCenter to a JSON file"
        $postBackupPath = Get-WorkflowBackupJsonPath -Qualifier "post" -Server $conn.ServerName
        Invoke-BackupAction -ConfirmedJsonPath $postBackupPath -Server $conn.ServerName
    } finally {
        Write-InteractiveWorkflowDisconnectNotice -VcenterFqdn $conn.ServerName
        Disconnect-Vcenter -ServerName $conn.ServerName -Silence
        Write-LogMessage -Type DEBUG -Message "Disconnected from destination vCenter `"$($conn.ServerName)`"."
    }

    Write-Host ""
    $menuChoice = $null
    while ($menuChoice -ne "Y" -and $menuChoice -ne "N") {
        $menuChoice = (Read-Host "Return to the main menu? [Y/N]").Trim().ToUpper()
    }
    return ($menuChoice -eq "Y")
}

# =============================================================================
# One-time initialization
# =============================================================================
$SCRIPT:ConfiguredLogLevel = $LogLevel
New-LogFile

if ([string]::IsNullOrWhiteSpace($Action)) {
    # Discard any keypresses buffered during startup so they cannot accidentally
    # pre-select a menu item before the user sees the menu.
    $Host.UI.RawUI.FlushInputBuffer()

    if ([string]::IsNullOrWhiteSpace($VcenterServer) -and -not [string]::IsNullOrWhiteSpace($env:VCENTER_SERVER)) {
        $VcenterServer = $env:VCENTER_SERVER.Trim()
    }
    if ([string]::IsNullOrWhiteSpace($VcenterUser) -and -not [string]::IsNullOrWhiteSpace($env:VCENTER_USER)) {
        $VcenterUser = $env:VCENTER_USER.Trim()
    }

    $interactiveVcenterDefaults = @{
        DefaultVcenterServer = if ([string]::IsNullOrWhiteSpace($VcenterServer)) { "" } else { $VcenterServer.Trim() }
        DefaultVcenterUser   = if ([string]::IsNullOrWhiteSpace($VcenterUser)) { "" } else { $VcenterUser.Trim() }
    }

    # Interactive workflow loop — redisplays the menu until a workflow exits or user quits.
    while ($true) {
        $menuJsonLeaf = Split-Path -Leaf $resolvedJsonPath
        if ([string]::IsNullOrWhiteSpace($menuJsonLeaf)) {
            $menuJsonLeaf = $SCRIPT:DEFAULT_VM_CLASSES_JSON_FILENAME
        }

        $selectedAction = Get-InteractiveAction -JsonFileName $menuJsonLeaf
        if ($selectedAction -eq "Quit") {
            Write-LogMessage -Type INFO -Message "User chose to quit. Exiting."
            exit 0
        }

        switch ($selectedAction) {
            "Discover" {
                # Confirm (and potentially rename) the output path before connecting so that the
                # new name is persisted to $resolvedJsonPath for the rest of this session.
                $confirmedPath = Get-ConfirmedDiscoverOutputPath -InitialPath $resolvedJsonPath -Force:$Force
                if ([string]::IsNullOrWhiteSpace($confirmedPath)) {
                    break
                }
                $resolvedJsonPath = $confirmedPath
                $returnToMenuFromDiscover = Invoke-DiscoverWorkflow @interactiveVcenterDefaults -ConfirmedJsonPath $resolvedJsonPath -SaveAll:$SaveAll
                if ($returnToMenuFromDiscover) {
                    continue
                }

                Write-LogMessage -Type INFO -Message "Discover workflow completed. Exiting."
                exit 0
            }
            "List" {
                $continueToMenu = Invoke-ListWorkflow @interactiveVcenterDefaults -InitialJsonPath $resolvedJsonPath
                if (-not $continueToMenu) {
                    Write-LogMessage -Type INFO -Message "User chose to exit. Exiting."
                    exit 0
                }
            }
            "Backup" {
                $continueToMenu = Invoke-BackupWorkflow @interactiveVcenterDefaults
                if (-not $continueToMenu) {
                    Write-LogMessage -Type INFO -Message "User chose to exit. Exiting."
                    exit 0
                }
            }
            "Update" {
                $continueToMenu = Invoke-UpdateWorkflow @interactiveVcenterDefaults -InitialJsonPath $resolvedJsonPath -VmClassName $VmClassName
                if (-not $continueToMenu) {
                    Write-LogMessage -Type INFO -Message "User chose to exit. Exiting."
                    exit 0
                }
            }
            "Delete" {
                $continueToMenu = Invoke-DeleteWorkflow @interactiveVcenterDefaults -VmClassName $VmClassName
                if (-not $continueToMenu) {
                    Write-LogMessage -Type INFO -Message "User chose to exit. Exiting."
                    exit 0
                }
            }
        }
    }
}

# ---- CLI / non-interactive single-action path ----
$jsonFileRequired = $false
switch ($Action) {
    "Backup"   { $jsonFileRequired = $false }
    "Delete"   { $jsonFileRequired = $false }
    "Discover" { $jsonFileRequired = $false }
    "List"     { $jsonFileRequired = $false }
    "Update"   { $jsonFileRequired = $true }
}

if ($Action -eq "Discover") {
    $resolvedJsonPath = Get-ConfirmedDiscoverOutputPath -InitialPath $resolvedJsonPath -Force:$Force
    if ($null -eq $resolvedJsonPath) { exit 0 }
}

if ($Action -eq "Backup") {
    if ([string]::IsNullOrWhiteSpace($JsonPath)) {
        $vcenterSuffix = if ([string]::IsNullOrWhiteSpace($VcenterServer)) { "" } else { "-$($VcenterServer.Trim())" }
        $resolvedJsonPath = Join-Path -Path $PSScriptRoot -ChildPath "vmClasses-backup$vcenterSuffix.json"
    }
    $resolvedJsonPath = Get-ConfirmedDiscoverOutputPath -ActionName "Backup" -InitialPath $resolvedJsonPath -Force:$Force
    if ($null -eq $resolvedJsonPath) { exit 0 }
}

if ($jsonFileRequired -and -not (Test-Path -LiteralPath $resolvedJsonPath -PathType Leaf)) {
    if ([Console]::IsInputRedirected) {
        throw "VM classes JSON file not found: `"$resolvedJsonPath`". Provide -JsonPath or place $($SCRIPT:DEFAULT_VM_CLASSES_JSON_FILENAME) next to this script. A non-interactive session cannot prompt for a path."
    }

    $getInteractiveJsonPathParams = @{ InitialResolvedPath = $resolvedJsonPath }
    if ([string]::IsNullOrWhiteSpace($JsonPath)) {
        $getInteractiveJsonPathParams["TreatInitialPathAsOptionalDefault"] = $true
    }

    $resolvedJsonPath = Get-InteractiveJsonPath @getInteractiveJsonPathParams
}

if ($jsonFileRequired) {
    Write-LogMessage -Type DEBUG -Message "Pre-flight validation of vmClasses JSON before vCenter connection: `"$resolvedJsonPath`"."
    $null = Get-VmClassJsonValidatedEntryList -JsonFilePath $resolvedJsonPath
}

if ($Action -eq "Update" -and -not [string]::IsNullOrWhiteSpace($VmClassName)) {
    $VmClassName = Resolve-VmClassNameForUpdateAgainstJson -JsonFilePath $resolvedJsonPath -VmClassName $VmClassName
}

try {
    while ($true) {
        if ([string]::IsNullOrWhiteSpace($VcenterServer)) {
            Write-Host ""
            $VcenterServer = Get-InteractiveVcenterServerFqdn
        } else {
            $VcenterServer = $VcenterServer.Trim()
            if (-not (Test-ValidVcenterAddress -Address $VcenterServer)) {
                throw "The -VcenterServer value `"$VcenterServer`" is not a valid FQDN or IPv4 address. Omit any scheme (https://), path, or port."
            }
        }

        Write-LogMessage -Type DEBUG -Message "Checking reachability of `"$VcenterServer`" before prompting for credentials..."
        $reachability = Test-VcenterReachability -Server $VcenterServer
        if (-not $reachability.Success) {
            Write-LogMessage -Type ERROR -Message $reachability.ErrorMessage
            if ([Console]::IsInputRedirected) {
                throw "vCenter `"$VcenterServer`" is not reachable. Cannot continue in a non-interactive session."
            }
            Write-Host ""
            $addrRetry = $null
            while ($addrRetry -ne "Y" -and $addrRetry -ne "N") {
                $addrRetry = (Read-Host "Would you like to re-enter your vCenter FQDN or IP address? (Y/N)").Trim().ToUpper()
            }
            if ($addrRetry -eq "N") {
                Write-LogMessage -Type INFO -Message "Exiting."
                exit 0
            }
            $VcenterServer = ""
            continue
        }

        if ([string]::IsNullOrWhiteSpace($VcenterUser)) {
            $VcenterUser = Get-InteractiveVcenterUsername
        } else {
            $VcenterUser = $VcenterUser.Trim()
        }

        Write-Host ""
        $vcenterSecurePassword = Get-VmClassScriptVcenterPasswordSecureString
        $credentialToUse = New-Object System.Management.Automation.PSCredential($VcenterUser, $vcenterSecurePassword)
        Write-Host ""
        Write-LogMessage -Type INFO -Message "Connecting to vCenter `"$VcenterServer`"..."
        $connectResult = Connect-Vcenter -AllowVcenterAddressRetry -ServerCredential $credentialToUse -ServerName $VcenterServer
        if ($connectResult -eq $SCRIPT:CONNECT_VCENTER_RETRY_VCENTER_ADDRESS) {
            $VcenterServer = ""
            $VcenterUser = ""
            continue
        }

        break
    }

    switch ($Action) {
        "Discover" {
            Invoke-DiscoverAction -ConfirmedJsonPath $resolvedJsonPath -SaveAll:$SaveAll -Server $VcenterServer
        }
        "Backup" {
            Invoke-BackupAction -ConfirmedJsonPath $resolvedJsonPath -Server $VcenterServer
        }
        "List" {
            Invoke-ListAction -Server $VcenterServer
        }
        "Update" {
            $selectedNames = [string[]]@()
            if ([string]::IsNullOrWhiteSpace($VmClassName)) {
                $selectedNames = @(Get-UserVmClassSelection -DefaultSelectAll -JsonFilePath $resolvedJsonPath -Action "Update")
            }
            Invoke-UpdateAction `
                -Credential $credentialToUse `
                -ResolvedJsonPath $resolvedJsonPath `
                -ResolvedVmClassNames $selectedNames `
                -Server $VcenterServer `
                -VmClassName $VmClassName
        }
        "Delete" {
            $selectedNames = [string[]]@()
            if ([string]::IsNullOrWhiteSpace($VmClassName)) {
                $selectedNames = @(Get-UserCustomVmClassSelectionFromServer -Server $VcenterServer)
            }
            Invoke-DeleteAction -ResolvedVmClassNames $selectedNames -Server $VcenterServer -VmClassName $VmClassName
        }
        default {
            throw "Unsupported -Action `"$Action`"."
        }
    }

    Write-LogMessage -Type DEBUG -Message "Manage-VMClasses action `"$Action`" completed."
} catch {
    Write-LogMessage -Type ERROR -Message "Manage-VMClasses failed: $($_.Exception.Message)"
    throw
} finally {
    try {
        Disconnect-Vcenter -AllServers -Silence
    } catch {
        Write-LogMessage -Type DEBUG -Message "Disconnect-Vcenter cleanup: $($_.Exception.Message)"
    }
}

# VM Class Management

Tools for discovering VM configurations from a vCenter and managing
vCenter Supervisor VM class definitions.

## Prerequisites

- PowerShell 7.4 or later [download](https://learn.microsoft.com/en-us/powershell/scripting/install/install-powershell).
- VCF PowerCLI 9.0+ [download](https://developer.broadcom.com/powercli/installation-guide).
- Network access to vCenter.
- A user with the following rights, at minimum, to the source vCenter: Read-only (at vCenter root level).
- A user with the following rights, at minimum, to the destination vCenter: Namespaces.Configure and Namespaces.ListAccess.

## Script: `Manage-VMClasses.ps1`

A single script that covers the full lifecycle of Supervisor VM classes —
discover, list, backup, update, and delete.

### Authentication

The script always prompts for credentials interactively unless you set the
`VCENTER_PASSWORD` environment variable before running it. Use this for
CI/CD or non-interactive pipelines.  This option is not compatible with
interactive mode.

> **Note:** if the password is incorrect, you will be prompted
> to enter your username and password interactively.

#### Example

```powershell
> $env:VCENTER_PASSWORD = "<elided>"
```

#### Interactive (default)

```powershell
.\Manage-VMClasses.ps1
```

#### Non-interactive

```powershell
.\Manage-VMClasses.ps1 -VcenterServer vcenter.example.com -VcenterUser admininstrator@vsphere.local -Action [Discover|List|Backup|Update|Delete]
```

### Actions

#### `Discover` — Scan live VMs and generate a class definition file

Connects to vCenter, enumerates all VMs, and groups them by unique
CPU / memory / GPU configuration. An interactive table lets you select
which groups to include (including all). The selected configurations are
written to the file `vmClasses.json` by default, or to the path you
specify with `-JsonPath`.

If the output file already exists, the script prompts you to overwrite
it, enter a different path, or cancel. Pass `-Force` parameter to overwrite
without prompting, and `-SaveAll` to skip the selection table and save every
discovered configuration automatically. Combine both for a fully
non-interactive run.

```powershell
# Interactive discovery; writes vmClasses.json
.\Manage-VMClasses.ps1 -Action Discover -VcenterServer vcenter.example.com -VcenterUser admininstrator@vsphere.local

# Write to a custom path
.\Manage-VMClasses.ps1 -Action Discover -VcenterServer vcenter.example.com -VcenterUser admininstrator@vsphere.local `
    -JsonPath .\my-classes.json

# Overwrite an existing file without prompting
.\Manage-VMClasses.ps1 -Action Discover -VcenterServer vcenter.example.com -VcenterUser admininstrator@vsphere.local `
    -Force

# Fully non-interactive: save all configurations, overwrite existing file
.\Manage-VMClasses.ps1 -Action Discover -VcenterServer vcenter.example.com -VcenterUser admininstrator@vsphere.local `
    -SaveAll -Force

# Example:

.\Manage-VMClasses.ps1 -Action Discover -VcenterServer vcenter.example.com -VcenterUser administrator@vsphere.local -Force -SaveAll

[ADVISORY] Using vCenter password from $env:VCENTER_PASSWORD. Unset the variable to be prompted interactively.
[INFO] Connecting to vCenter "vcenter.example.com"...
[INFO] Querying all VMs from vCenter "vcenter.example.com"...
[INFO] Found 121 VM(s). Grouping by configuration...
[INFO] Found 12 unique VM configuration(s).

Class name format: {N}cpu-{cpu-commitment}-{M}mb-{mem-commitment}[-{gpu-profile}]
  "guaranteed" = VMs in this group have a non-zero reservation; "besteffort" = no reservation.

Class Name                           CPUs Memory (MB) CPU Reserved Mem Reserved VM Count
----------                           ---- ----------- ------------ ------------ --------
32cpu-besteffort-262144mb-besteffort   32 262,144     No           No                 51
2cpu-besteffort-8192mb-besteffort       2 8,192       No           No                 20
2cpu-besteffort-3072mb-besteffort       2 3,072       No           No                 13
4cpu-besteffort-16384mb-besteffort      4 16,384      No           No                 11
8cpu-besteffort-98304mb-besteffort      8 98,304      No           No                 10
8cpu-besteffort-32768mb-besteffort      8 32,768      No           No                  4
16cpu-besteffort-131072mb-besteffort   16 131,072     No           No                  4
6cpu-guaranteed-24576mb-guaranteed      6 24,576      Yes          Yes                 3
1cpu-besteffort-2048mb-besteffort       1 2,048       No           No                  2
4cpu-besteffort-4096mb-besteffort       4 4,096       No           No                  1
4cpu-besteffort-12288mb-besteffort      4 12,288      No           No                  1
4cpu-besteffort-21504mb-besteffort      4 21,504      No           No                  1

[INFO] Saving all 12 configuration(s) to "/Users/testuser/vmClasses.json" (-SaveAll).
[INFO] Wrote 12 VM class definition(s) to "/Users/testuser/vmClasses.json".
[INFO] Discover completed.
```

---

#### `List` — Print all VM classes on vCenter

Prints a table of all VM classes (Name, CpuCount, MemoryMB, Default, Gpu). The **Default**
column shows **Yes** for the 16 pre-defined vCenter class names and **No** for any custom classes.
No JSON file is required.

```powershell
# List all VM classes
.\Manage-VMClasses.ps1 -Action List -VcenterServer vcenter.example.com -VcenterUser admininstrator@vsphere.local

# Example
 .\Manage-VMClasses.ps1 -Action List -VcenterServer vdest-vcenter.example.com -VcenterUser administrator@vsphere.local

[ADVISORY] Using vCenter password from $env:VCENTER_PASSWORD. Unset the variable to be prompted interactively.
[INFO] Connecting to vCenter "vcenter.example.com"...
[INFO] Listing VM classes on vCenter "vcenter.example.com"...

Name                 CpuCount MemoryMB Default Gpu
----                 -------- -------- ------- ---
best-effort-2xlarge         8    65536 Yes     No
best-effort-4xlarge        16   131072 Yes     No
best-effort-8xlarge        32   131072 Yes     No
best-effort-large           4    16384 Yes     No
best-effort-medium          2     8192 Yes     No
best-effort-small           2     4096 Yes     No
best-effort-xlarge          4    32768 Yes     No
best-effort-xsmall          2     2048 Yes     No
custom-1cpu-2gb-2gpu        4     2048 No      profile1, profile2
custom-2cpu-4gb             2     4096 No      No
guaranteed-2xlarge          8    65536 Yes     No
guaranteed-4xlarge         16   131072 Yes     No
guaranteed-8xlarge         32   131072 Yes     No
guaranteed-large            4    16384 Yes     No
guaranteed-medium           2     8192 Yes     No
guaranteed-small            2     4096 Yes     No
guaranteed-xlarge           4    32768 Yes     No
guaranteed-xsmall           2     2048 Yes     No

[INFO] Listed 18 VM class(es).
```

---

#### `Backup` — Save all VM classes from vCenter to a JSON file

This operation queries every VM class currently defined on vCenter
and writes them to a JSON file in the same format as `vmClasses.json`.
The backup file can be used directly with `-Action Update` to restore
or re-apply classes to any vCenter.

The default output filename embeds the vCenter name so that backups
from multiple environments are easy to distinguish at a glance:

```text
vmClasses-backup-vcenter.example.com.json
```

Pass `-JsonPath` to override the output path. Pass `-Force` to
overwrite an existing file without prompting.

```powershell
# Backup to the default file
.\Manage-VMClasses.ps1 -Action Backup -VcenterServer vcenter.example.com -VcenterUser administrator@vsphere.local

# Backup to a dated file and overwrite without prompting
.\Manage-VMClasses.ps1 -Action Backup -VcenterServer vcenter.example.com -VcenterUser administrator@vsphere.local `
    -JsonPath .\backup-$(Get-Date -Format yyyyMMdd).json -Force

# Example
.\Manage-VMClasses.ps1 -Action Backup -VcenterServer source-vcenter.example.com -VcenterUser administrator@vsphere.local

[ADVISORY] Using vCenter password from $env:VCENTER_PASSWORD. Unset the variable to be prompted interactively.
[INFO] Connecting to vCenter "source-vcenter.example.com"...
[INFO] Retrieving all VM class definitions from vCenter "source-vcenter.example.com"...
[WARNING] VM class "custom-pcidevice-class" has DynamicDirectPathIO device(s); those settings are not supported in this format and will be omitted.
[INFO] Retrieved 18 VM class definition(s).
[WARNING] 1 class(es) had DynamicDirectPathIO configuration that could not be included in the backup.
[INFO] Wrote 18 VM class definition(s) to "/Users/testuser/vmClasses-backup-source-vcenter.example.com.json".
[INFO] Backup completed.
```

---

#### `Update` — Apply VM class definitions to vCenter

Reads the JSON file and applies each entry to vCenter

Applies the following operations as needed:

- **Create** — class does not yet exist on vCenter
- **Patch** — class exists but differs from the file
- **Skip** — class already matches the file

If a class name matches one of the 16 built-in default names, the script logs
a `[WARNING]` and — in interactive sessions — asks for confirmation before
proceeding.

Use `-VmClassName all` to process every entry, or pass a specific class
name to target one.

```powershell
# Apply all classes from vmClasses.json
.\Manage-VMClasses.ps1 -Action Update -VcenterServer vcenter.example.com -VcenterUser admininstrator@vsphere.local -VmClassName all

# Apply or update a single named class
.\Manage-VMClasses.ps1 -Action Update -VcenterServer vcenter.example.com -VcenterUser admininstrator@vsphere.local `
    -VmClassName my-gpu-class

# Dry-run (no changes are made)
.\Manage-VMClasses.ps1 -Action Update -WhatIf -VcenterServer vcenter.example.com -VcenterUser admininstrator@vsphere.local -VmClassName all


# Example
.\Manage-VMClasses.ps1 -Action Update -VcenterServer vcenter.example.com -VcenterUser administrator@vsphere.local -VmClassName all

[ADVISORY] Using vCenter password from $env:VCENTER_PASSWORD. Unset the variable to be prompted interactively.
[INFO] Connecting to vCenter "vcenter.example.com"...
[INFO] Creating VM class "32cpu-besteffort-262144mb-besteffort"... Succeeded
[INFO] Creating VM class "2cpu-besteffort-8192mb-besteffort"... Succeeded
```

---

#### `Delete` — Remove a VM class from vCenter

Delete no longer reads from the JSON file. Instead it queries vCenter directly and operates
only on **custom** classes (the 16 built-in defaults are always excluded and not shown).

- **`-VmClassName all`** — deletes every custom class found on vCenter, logging how many
  built-in defaults were skipped.
- **`-VmClassName <name>`** — deletes the named class directly (no JSON lookup).

```powershell
# Interactive: choose from custom classes on vCenter
.\Manage-VMClasses.ps1 -Action Delete -VcenterServer vcenter.example.com -VcenterUser admininstrator@vsphere.local

# Delete all custom classes (built-in defaults are preserved)
.\Manage-VMClasses.ps1 -Action Delete -VcenterServer vcenter.example.com -VcenterUser admininstrator@vsphere.local `
    -VmClassName all

# Delete one specific class by name
.\Manage-VMClasses.ps1 -Action Delete -VcenterServer vcenter.example.com -VcenterUser admininstrator@vsphere.local `
    -VmClassName my-gpu-class

# Example
.\Manage-VMClasses.ps1 -Action Delete -VcenterServer vdest-vcenter.example.com -VcenterUser administrator@vsphere.local -VmClassName 32cpu-besteffort-262144mb-besteffort

[ADVISORY] Using vCenter password from $env:VCENTER_PASSWORD. Unset the variable to be prompted interactively.
[INFO] Connecting to vCenter "dest-vcenter.example.com"...
[INFO] Deleting VM class "32cpu-besteffort-262144mb-besteffort"... Succeeded
```

---

### Getting help

```powershell
.\Manage-VMClasses.ps1 -Examples   # show usage examples
.\Manage-VMClasses.ps1 -Detailed   # show parameters with descriptions
.\Manage-VMClasses.ps1 -Full       # show full comment-based help
```

### Parameters

| Parameter | Required | Default | Description |
| --- | --- | --- | --- |
| `-Action` | No | *(prompts)* | Action to perform: `Backup`, `Discover`, `Update`, `List`, or `Delete`. |
| `-Force` | No | — | For `Discover` and `Backup`: overwrite an existing output file without prompting. |
| `-JsonPath` | No | `vmClasses.json` (next to script) | Path to the JSON class definition file. For `Discover`, specifies the output path (default: `vmClasses.json`). For `Backup`, specifies the output path (default: `vmClasses-backup-<vCenter>.json`). |
| `-LogLevel` | No | `INFO` | Console log verbosity: `DEBUG`, `INFO`, `ADVISORY`, `WARNING`, `ERROR`. All levels are always written to the log file. |
| `-SaveAll` | No | — | For `Discover`: skip the interactive configuration selection and save every discovered VM configuration automatically. Combine with `-Force` for fully non-interactive runs. |
| `-VcenterServer` | No* | — | vCenter FQDN or IP address. Prompts interactively when omitted. |
| `-VcenterUser` | No* | — | vCenter sign-in name, e.g. `administrator@vsphere.local`. Prompts interactively when omitted. |
| `-VmClassName` | No* | — | VM class name to target, or `all`. Required for non-interactive `Update` and `Delete`; prompts when omitted in an interactive session. |

\* Prompted interactively when omitted in an interactive session.

---

### JSON File Format

`vmClasses.json` is a JSON array. Each object represents one VM class.

```json
[
  {
    "name": "best-effort-2xlarge",
    "cpuCount": 8,
    "cpuCommitment": "bestEffort",
    "memoryMB": 16384,
    "memoryCommitment": "bestEffort"
  },
  {
    "name": "guaranteed-gpu-class",
    "description": "Reserved class with A100 GPU",
    "cpuCount": 16,
    "cpuCommitment": "guaranteed",
    "memoryMB": 65536,
    "memoryCommitment": "guaranteed",
    "vgpuDevices": [
      {
        "profileNames": ["nvidia-a100-40c"]
      }
    ]
  }
]
```

#### Required fields

| Field | Type | Description |
| --- | --- | --- |
| `name` | string | Lowercase DNS-label format (`a-z0-9` and `-`, 1–63 chars). |
| `cpuCount` | integer | Number of vCPUs (1–960). |
| `cpuCommitment` | string | `bestEffort` or `guaranteed`. |
| `memoryMB` | integer | Memory in MiB (≤ 25165824). |
| `memoryCommitment` | string | `bestEffort` or `guaranteed`. |

#### Optional fields

| Field | Type | Description |
| --- | --- | --- |
| `description` | string | Human-readable label shown in the vCenter UI. Omit when not needed. |
| `vgpuDevices` | array | One or more vGPU device objects (see below). Required when `cpuCommitment` or `memoryCommitment` is `guaranteed` and a GPU is needed. |

#### vGPU device object

```json
{
  "profileNames": ["nvidia-a100-40c"]
}
```

Each object may contain 1–4 profile names. Multiple vGPU device objects
represent distinct GPU-profile combinations.

---

### Interactive guided workflow (no `-Action`)

Running the script without `-Action` displays an arrow-key menu in the order
**Discover → List → Backup → Update → Delete → Help → Quit**. Selecting an
action chains automatically into the next logical steps:

- **Discover** — connects to a source vCenter, scans VMs, writes the JSON.
  Offers to exit for manual class-name editing, or continues to an import
  flow (pre-backup → Update → post-backup) against the same or a different
  destination vCenter.
- **List** — connects to destination vCenter, lists classes, then optionally
  takes a pre-import backup, runs an import, and takes a post-import backup.
- **Backup** — connects to destination vCenter, takes a timestamped backup.
- **Update** — connects to source vCenter, imports classes, then optionally
  removes a class and lists the final state.
- **Delete** — connects to destination vCenter, takes a pre-delete backup,
  removes selected classes, lists remaining classes, takes a post-delete backup.

All workflow backup files are saved in a `Backup/` subdirectory next to the
script, with filenames that embed the vCenter name, qualifier (`pre`/`post`),
and timestamp for easy identification.

---

### Example of interactive workflow (Discovery to Insert)

> \.Manage-VMClasses.ps1

  Select an action below
  Arrow keys=navigate  Enter=confirm  Esc=quit

  > Discover   Scan live VMs and generate vmClasses.json
    List       Show all VM classes on vCenter
    Backup     Save all VM classes from vCenter to a JSON file
    Update     Apply vmClasses.json to vCenter
    Delete     Remove VM classes from vCenter
    Help       Show usage documentation for this script
    Quit       Exit without making any changes

[INFO] Please connect to your source vCenter to continue.

Enter your vCenter Server FQDN or IP address (or press 'c' to cancel): vcenter-1.example.com

Enter your vCenter username: administrator@vsphere.local

Enter your vCenter password: ****************
[INFO] Connecting to source vCenter "vcenter-1.example.com"...
[INFO] Querying all VMs from vCenter "vcenter-1.example.com"...
[INFO] Found 135 VM(s). Grouping by configuration...
[INFO] Found 13 unique VM configuration(s).

Class name format: {N}cpu-{cpu-commitment}-{M}mb-{mem-commitment}[-{gpu-profile}]
  "guaranteed" = VMs in this group have a non-zero reservation; "besteffort" = no reservation.

      Class Name                            CPUs Memory (MB)  CPU Reserved Mem Reserved  VM Count
  -----------------------------------------------------------------------------------------------
  Space=toggle  Arrow keys=navigate  A=select all / none  Enter=confirm

> [x] Select All
  [x] 32cpu-besteffort-262144mb-besteffort    32     262,144  No           No                  55
  [x] 2cpu-besteffort-8192mb-besteffort        2       8,192  No           No                  21
  [x] 8cpu-besteffort-98304mb-besteffort       8      98,304  No           No                  15
  [x] 2cpu-besteffort-3072mb-besteffort        2       3,072  No           No                  14
  [x] 4cpu-besteffort-16384mb-besteffort       4      16,384  No           No                  12
  [x] 8cpu-besteffort-32768mb-besteffort       8      32,768  No           No                   5
  [x] 16cpu-besteffort-131072mb-besteffort    16     131,072  No           No                   4
  [x] 6cpu-guaranteed-24576mb-guaranteed       6      24,576  Yes          Yes                  3
  [x] 1cpu-besteffort-2048mb-besteffort        1       2,048  No           No                   2
  [x] 4cpu-besteffort-4096mb-besteffort        4       4,096  No           No                   1
  [x] 4cpu-besteffort-12288mb-besteffort       4      12,288  No           No                   1
  [x] 4cpu-besteffort-21504mb-besteffort       4      21,504  No           No                   1
  [x] 32cpu-besteffort-131072mb-besteffort    32     131,072  No           No                   1

[INFO] Wrote 13 VM class definition(s) to "c:\Users\testuser\/vmClasses.json".
View the output JSON? [Y/N]: N
[INFO] Discover completed.

Exit to manually modify "vmClasses.json" to rename VM classes before proceeding to the VM class import steps? [Y/N]: N

Import VM classes into the same vCenter "vcenter-1.example.com"? [Y/N]: N

[INFO] Please connect to your destination vCenter to continue.

Enter your vCenter Server FQDN or IP address (or press 'c' to cancel): vcenter-2.example.com

Enter your vCenter username: administrator@vsphere.local

Enter your vCenter password: ****************
[INFO] Connecting to destination vCenter "vcenter-2.example.com"...
[INFO] Proceeding to list VM classes on "vcenter-2.example.com".
[INFO] Listing VM classes on vCenter "vcenter-2.example.com"...

Name                CpuCount MemoryMB Default Gpu
----                -------- -------- ------- ---
best-effort-2xlarge        8    65536 Yes     No
best-effort-4xlarge       16   131072 Yes     No
best-effort-8xlarge       32   131072 Yes     No
best-effort-large          4    16384 Yes     No
best-effort-medium         2     8192 Yes     No
best-effort-small          2     4096 Yes     No
best-effort-xlarge         4    32768 Yes     No
best-effort-xsmall         2     2048 Yes     No
guaranteed-2xlarge         8    65536 Yes     No
guaranteed-4xlarge        16   131072 Yes     No
guaranteed-8xlarge        32   131072 Yes     No
guaranteed-large           4    16384 Yes     No
guaranteed-medium          2     8192 Yes     No
guaranteed-small           2     4096 Yes     No
guaranteed-xlarge          4    32768 Yes     No
guaranteed-xsmall          2     2048 Yes     No

[INFO] Listed 16 VM class(es).

Press any key to proceed to the next step - Backup (pre-import) - Save all VM classes from vCenter to a JSON file...

[INFO] Retrieving all VM class definitions from vCenter "vcenter-2.example.com"...
[INFO] Retrieved 16 VM class definition(s).
[INFO] Wrote 16 VM class definition(s) to "c:\Users\testuser\Backup\vmClasses-backup-vcenter-2.example.com-pre-20260402-085744.json".
[INFO] Backup completed.

Press any key to proceed to the next step - Update - Apply vmClasses.json to vCenter...

[INFO] The default VM class file is "c:\Users\testuser\vmClasses.json".

Use a different VM class file instead of "vmClasses.json"? [Y/N]: N

[INFO] Select VM class(es) to update:
[INFO] Source file: "c:\Users\testuser\/vmClasses.json"

  Class Name
  ----------------------------------------
  Space=toggle  Arrow keys=navigate  A=select all / none  Enter=confirm  Esc=cancel

> [x] Select All
  [x] 32cpu-besteffort-262144mb-besteffort
  [x] 2cpu-besteffort-8192mb-besteffort
  [x] 8cpu-besteffort-98304mb-besteffort
  [x] 2cpu-besteffort-3072mb-besteffort
  [x] 4cpu-besteffort-16384mb-besteffort
  [x] 8cpu-besteffort-32768mb-besteffort
  [x] 16cpu-besteffort-131072mb-besteffort
  [x] 6cpu-guaranteed-24576mb-guaranteed
  [x] 1cpu-besteffort-2048mb-besteffort
  [x] 4cpu-besteffort-4096mb-besteffort
  [x] 4cpu-besteffort-12288mb-besteffort
  [x] 4cpu-besteffort-21504mb-besteffort
  [x] 32cpu-besteffort-131072mb-besteffort

[INFO] Creating VM class "32cpu-besteffort-262144mb-besteffort"... Succeeded
[INFO] Creating VM class "2cpu-besteffort-8192mb-besteffort"... Succeeded
[INFO] Creating VM class "8cpu-besteffort-98304mb-besteffort"... Succeeded
[INFO] Creating VM class "2cpu-besteffort-3072mb-besteffort"... Succeeded
[INFO] Creating VM class "4cpu-besteffort-16384mb-besteffort"... Succeeded
[INFO] Creating VM class "8cpu-besteffort-32768mb-besteffort"... Succeeded
[INFO] Creating VM class "16cpu-besteffort-131072mb-besteffort"... Succeeded
[INFO] Creating VM class "6cpu-guaranteed-24576mb-guaranteed"... Succeeded
[INFO] Creating VM class "1cpu-besteffort-2048mb-besteffort"... Succeeded
[INFO] Creating VM class "4cpu-besteffort-4096mb-besteffort"... Succeeded
[INFO] Creating VM class "4cpu-besteffort-12288mb-besteffort"... Succeeded
[INFO] Creating VM class "4cpu-besteffort-21504mb-besteffort"... Succeeded
[INFO] Creating VM class "32cpu-besteffort-131072mb-besteffort"... Succeeded

Press any key to proceed to the next step - Backup (post-import) - Save all VM classes from vCenter to a JSON file...

[INFO] Retrieving all VM class definitions from vCenter "vcenter-2.example.com"...
[INFO] Retrieved 29 VM class definition(s).
[INFO] Wrote 29 VM class definition(s) to "c:\Users\testuser\/Backup/vmClasses-backup-vcenter-2.example.com-post-20260402-085811.json".
[INFO] Backup completed

### Logs

Log files are written to `logs/Manage-VMClasses-<date>.log` next to the
script. All log levels are always captured regardless of the `-LogLevel`
setting.

---

### Notes

- SSL certificate validation follows your PowerCLI
  `InvalidCertificateAction` setting.
- The `description` field is fully optional. Omitting it from a JSON
  entry does not trigger a diff warning during `Update` if the class on
  vCenter also has no description.
# Examples

## Run script with no arguments (shows menu)

```text
> ./Manage-VMClasses.ps1

[INFO] Before connecting to your vCenter choose an action to perform.

  Select an action below
  Arrow keys=navigate  Enter=confirm  Esc=quit

  > Discover   Scan live VMs and generate vmClasses.json
    List       Show all VM classes on vCenter
    Backup     Save all VM classes from vCenter to a JSON file
    Update     Apply vmClasses.json to vCenter
    Delete     Remove VM classes from vCenter
    Help       Show usage documentation for this script
    Quit       Exit without making any changes
```

## Discovery (from menu)

```text
> ./Manage-VMClasses.ps1

[INFO] Before connecting to your vCenter choose an action to perform.

  Select an action below
  Arrow keys=navigate  Enter=confirm  Esc=quit

  > Discover   Scan live VMs and generate vmClasses.json
    List       Show all VM classes on vCenter
    Backup     Save all VM classes from vCenter to a JSON file
    Update     Apply vmClasses.json to vCenter
    Delete     Remove VM classes from vCenter
    Help       Show usage documentation for this script
    Quit       Exit without making any changes


Enter your vCenter Server FQDN or IP address (or press 'c' to cancel): source-vcenter.example.com"

Enter your vCenter username: administrator@vsphere.local

Enter your vCenter password: ****************

[INFO] Connecting to vCenter "source-vcenter.example.com"...
[INFO] Querying all VMs from vCenter "source-vcenter.example.com"...
[INFO] Found 121 VM(s). Grouping by configuration...
[INFO] Found 12 unique VM configuration(s).

Class name format: {N}cpu-{cpu-commitment}-{M}mb-{mem-commitment}[-{gpu-profile}]
  "guaranteed" = VMs in this group have a non-zero reservation; "besteffort" = no reservation.

      Class Name                            CPUs Memory (MB)  CPU Reserved Mem Reserved  VM Count
  -----------------------------------------------------------------------------------------------
  Space=toggle  Arrow keys=navigate  A=select all / none  Enter=confirm  Esc=cancel

  [ ] Select All
  [x] 32cpu-besteffort-262144mb-besteffort    32     262,144  No           No                  51
> [x] 2cpu-besteffort-8192mb-besteffort        2       8,192  No           No                  20
  [ ] 2cpu-besteffort-3072mb-besteffort        2       3,072  No           No                  13
  [ ] 4cpu-besteffort-16384mb-besteffort       4      16,384  No           No                  11
  [ ] 8cpu-besteffort-98304mb-besteffort       8      98,304  No           No                  10
  [ ] 8cpu-besteffort-32768mb-besteffort       8      32,768  No           No                   4
  [ ] 16cpu-besteffort-131072mb-besteffort    16     131,072  No           No                   4
  [ ] 6cpu-guaranteed-24576mb-guaranteed       6      24,576  Yes          Yes                  3
  [ ] 1cpu-besteffort-2048mb-besteffort        1       2,048  No           No                   2
  [ ] 4cpu-besteffort-4096mb-besteffort        4       4,096  No           No                   1
  [ ] 4cpu-besteffort-12288mb-besteffort       4      12,288  No           No                   1
  [ ] 4cpu-besteffort-21504mb-besteffort       4      21,504  No           No                   1

[INFO] Wrote 2 VM class definition(s) to "/Users/testuser/vmClasses.json".
View the output JSON? [Y/N]: y

[
  {
    "name": "32cpu-besteffort-262144mb-besteffort",
    "cpuCount": "32",
    "cpuCommitment": "bestEffort",
    "memoryMB": "262144",
    "memoryCommitment": "bestEffort"
  },
  {
    "name": "2cpu-besteffort-8192mb-besteffort",
    "cpuCount": "2",
    "cpuCommitment": "bestEffort",
    "memoryMB": "8192",
    "memoryCommitment": "bestEffort"
  }
]

[INFO] Discover completed.
```

## Update (from menu)

```text
> ./Manage-VMClasses.ps1

[INFO] Before connecting to your vCenter choose an action to perform.

  Select an action below
  Arrow keys=navigate  Enter=confirm  Esc=quit

    Discover   Scan live VMs and generate vmClasses.json
    List       Show all VM classes on vCenter
    Backup     Save all VM classes from vCenter to a JSON file
  > Update     Apply vmClasses.json to vCenter
    Delete     Remove VM classes from vCenter
    Help       Show usage documentation for this script
    Quit       Exit without making any changes


Enter your vCenter Server FQDN or IP address (or press 'c' to cancel): vdest-vcenter.example.com

Enter your vCenter username: administrator@vsphere.local

Enter your vCenter password: ****************

[INFO] Connecting to vCenter "dest-vcenter.example.com"...

[INFO] Select VM class(es) to update:

      Class Name
  ----------------------------------------
  Space=toggle  Arrow keys=navigate  A=select all / none  Enter=confirm  Esc=cancel

> [x] Select All
  [x] 32cpu-besteffort-262144mb-besteffort
  [x] 2cpu-besteffort-8192mb-besteffort

[INFO] Creating VM class "32cpu-besteffort-262144mb-besteffort"... Succeeded
[INFO] Creating VM class "2cpu-besteffort-8192mb-besteffort"... Succeeded
```

## Update (from menu) (notices a difference)

```text
> ./Manage-VMClasses.ps1

[INFO] Before connecting to your vCenter choose an action to perform.

  Select an action below
  Arrow keys=navigate  Enter=confirm  Esc=quit

    Discover   Scan live VMs and generate vmClasses.json
    List       Show all VM classes on vCenter
    Backup     Save all VM classes from vCenter to a JSON file
  > Update     Apply vmClasses.json to vCenter
    Delete     Remove VM classes from vCenter
    Help       Show usage documentation for this script
    Quit       Exit without making any changes


Enter your vCenter Server FQDN or IP address (or press 'c' to cancel): vdest-vcenter.example.com

Enter your vCenter username: administrator@vsphere.local

Enter your vCenter password: ****************

[INFO] Connecting to vCenter "dest-vcenter.example.com"...

[INFO] Select VM class(es) to update:

      Class Name
  ----------------------------------------
  Space=toggle  Arrow keys=navigate  A=select all / none  Enter=confirm  Esc=cancel

> [x] Select All
  [x] 32cpu-besteffort-262144mb-besteffort
  [x] 2cpu-besteffort-8192mb-besteffort

[INFO] Detected a difference between "vmClasses.json" and vCenter definition of VM class "32cpu-besteffort-262144mb-besteffort".
[INFO]         The cpu_count is 32 in JSON and 35 in vCenter.
[INFO]         The description is not defined in JSON and "great for DBs" in vCenter.
[INFO] Updating VM class "32cpu-besteffort-262144mb-besteffort" on vCenter to match "vmClasses.json"... Succeeded
[INFO] Updating VM class "2cpu-besteffort-8192mb-besteffort" on vCenter to match "vmClasses.json"... Skipped (vCenter already matches the file)
```

## List (from menu)

```text
> ./Manage-VMClasses.ps1

[INFO] Before connecting to your vCenter choose an action to perform.

  Select an action below
  Arrow keys=navigate  Enter=confirm  Esc=quit

    Discover   Scan live VMs and generate vmClasses.json
  > List       Show all VM classes on vCenter
    Backup     Save all VM classes from vCenter to a JSON file
    Update     Apply vmClasses.json to vCenter
    Delete     Remove VM classes from vCenter
    Help       Show usage documentation for this script
    Quit       Exit without making any changes


Enter your vCenter Server FQDN or IP address (or press 'c' to cancel): vdest-vcenter.example.com

Enter your vCenter username: administrator@vsphere.local

Enter your vCenter password: ****************

[INFO] Connecting to vCenter "dest-vcenter.example.com"...
[INFO] Listing VM classes on vCenter "dest-vcenter.example.com"...

Name                                 CpuCount MemoryMB Default Gpu
----                                 -------- -------- ------- ---
2cpu-besteffort-8192mb-besteffort           2     8192 No      No
32cpu-besteffort-262144mb-besteffort       32   262144 No      No
best-effort-2xlarge                         8    65536 Yes     No
best-effort-4xlarge                        16   131072 Yes     No
best-effort-8xlarge                        32   131072 Yes     No
best-effort-large                           4    16384 Yes     No
best-effort-medium                          2     8192 Yes     No
best-effort-small                           2     4096 Yes     No
best-effort-xlarge                          4    32768 Yes     No
best-effort-xsmall                          2     2048 Yes     No
custom-1cpu-2gb-2gpu                        4     2048 No      profile1, profile2
custom-2cpu-4gb                             2     4096 No      No
guaranteed-2xlarge                          8    65536 Yes     No
guaranteed-4xlarge                         16   131072 Yes     No
guaranteed-8xlarge                         32   131072 Yes     No
guaranteed-large                            4    16384 Yes     No
guaranteed-medium                           2     8192 Yes     No
guaranteed-small                            2     4096 Yes     No
guaranteed-xlarge                           4    32768 Yes     No
guaranteed-xsmall                           2     2048 Yes     No

[INFO] Listed 20 VM class(es).
```

## Parameter-based invocations

### List all VM classes

```text
$env:VCENTER_PASSWORD = "<elided>"
 ./Manage-VMClasses.ps1 -Action List -VcenterServer vdest-vcenter.example.com -VcenterUser administrator@vsphere.local

[ADVISORY] Using vCenter password from $env:VCENTER_PASSWORD. Unset the variable to be prompted interactively.
[INFO] Connecting to vCenter "dest-vcenter.example.com"...
[INFO] Listing VM classes on vCenter "dest-vcenter.example.com"...

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

### Update all VM classes

```text
./Manage-VMClasses.ps1 -Action Update -VcenterServer vdest-vcenter.example.com -VcenterUser administrator@vsphere.local -VmClassName all

[ADVISORY] Using vCenter password from $env:VCENTER_PASSWORD. Unset the variable to be prompted interactively.
[INFO] Connecting to vCenter "dest-vcenter.example.com"...
[INFO] Creating VM class "32cpu-besteffort-262144mb-besteffort"... Succeeded
[INFO] Creating VM class "2cpu-besteffort-8192mb-besteffort"... Succeeded
```

### Update specific VM class

```text
./Manage-VMClasses.ps1 -Action Update -VcenterServer vdest-vcenter.example.com -VcenterUser administrator@vsphere.local -VmClassName 32cpu-besteffort-262144mb-besteffort

[ADVISORY] Using vCenter password from $env:VCENTER_PASSWORD. Unset the variable to be prompted interactively.
[INFO] Connecting to vCenter "dest-vcenter.example.com"...
[INFO] Updating VM class "32cpu-besteffort-262144mb-besteffort" on vCenter to match "vmClasses.json"... Skipped (vCenter already matches the file)
```

### Delete specific VM class

```text
./Manage-VMClasses.ps1 -Action Delete -VcenterServer vdest-vcenter.example.com -VcenterUser administrator@vsphere.local -VmClassName 32cpu-besteffort-262144mb-besteffort

[ADVISORY] Using vCenter password from $env:VCENTER_PASSWORD. Unset the variable to be prompted interactively.
[INFO] Connecting to vCenter "dest-vcenter.example.com"...
[INFO] Deleting VM class "32cpu-besteffort-262144mb-besteffort"... Succeeded
```

### Backup VM classes

The default filename embeds the vCenter name so backups from different environments
are easy to identify. The file content is a plain JSON array compatible with `-Action Update`.

```text
> ./Manage-VMClasses.ps1 -Action Backup -VcenterServer source-vcenter.example.com -VcenterUser administrator@vsphere.local

[ADVISORY] Using vCenter password from $env:VCENTER_PASSWORD. Unset the variable to be prompted interactively.
[INFO] Connecting to vCenter "source-vcenter.example.com"...
[INFO] Retrieving all VM class definitions from vCenter "source-vcenter.example.com"...
[INFO] Retrieved 18 VM class definition(s).
[INFO] Wrote 18 VM class definition(s) to "/Users/testuser/vmClasses-backup-source-vcenter.example.com.json".
[INFO] Backup completed.
```

Sample output file (`vmClasses-backup-source-vcenter.example.com.json`):

```json
[
  {
    "name": "best-effort-2xlarge",
    "cpuCount": 8,
    "cpuCommitment": "bestEffort",
    "memoryMB": 65536,
    "memoryCommitment": "bestEffort"
  },
  {
    "name": "custom-4cpu-8gb-a100",
    "cpuCount": 4,
    "cpuCommitment": "bestEffort",
    "memoryMB": 8192,
    "memoryCommitment": "bestEffort",
    "vgpuDevices": [{ "profileNames": ["nvidia-a100-40c"] }]
  }
]
```

### Restore backup to a different vCenter

A backup file is a plain `vmClasses.json`-format array and can be passed directly to
`-Action Update` on any vCenter.

```text
./Manage-VMClasses.ps1 -Action Update -VcenterServer dest-vcenter.example.com -VcenterUser administrator@vsphere.local `
    -JsonPath ./vmClasses-backup-source-vcenter.example.com.json -VmClassName all

[ADVISORY] Using vCenter password from $env:VCENTER_PASSWORD. Unset the variable to be prompted interactively.
[INFO] Connecting to vCenter "dest-vcenter.example.com"...
[INFO] Processing 18 VM class definition(s)...
```

### Backup with DynamicDirectPathIO warning

```text
./Manage-VMClasses.ps1 -Action Backup -VcenterServer source-vcenter.example.com -VcenterUser administrator@vsphere.local

[ADVISORY] Using vCenter password from $env:VCENTER_PASSWORD. Unset the variable to be prompted interactively.
[INFO] Connecting to vCenter "source-vcenter.example.com"...
[INFO] Retrieving all VM class definitions from vCenter "source-vcenter.example.com"...
[INFO] Retrieved 18 VM class definition(s).
[INFO] Wrote 18 VM class definition(s) to "/Users/testuser/vmClasses-backup-source-vcenter.example.com.json".
[INFO] Backup completed.
```

### Specify JSON output path

```text
./Manage-VMClasses.ps1 -Action Backup -VcenterServer vdest-vcenter.example.com -VcenterUser administrator@vsphere.local -JsonPath ./backup-20260329.json -Force

[ADVISORY] Using vCenter password from $env:VCENTER_PASSWORD. Unset the variable to be prompted interactively.
[WARNING] Output file "./backup-20260329.json" already exists; overwriting (-Force).
[INFO] Connecting to vCenter "dest-vcenter.example.com"...
[INFO] Retrieving all VM class definitions from vCenter "dest-vcenter.example.com"...
[INFO] Retrieved 18 VM class definition(s).
[INFO] Wrote 18 VM class definition(s) to "./backup-20260329.json".
[INFO] Backup completed.
```

### Discover all VM configurations non-interactively

```text
./Manage-VMClasses.ps1 -Action Discover -VcenterServer source-vcenter.example.com" -VcenterUser administrator@vsphere.local -Force -SaveAll

[WARNING] Output file "/Users/testuser/vmClasses.json" already exists; overwriting (-Force).

[ADVISORY] Using vCenter password from $env:VCENTER_PASSWORD. Unset the variable to be prompted interactively.
[INFO] Connecting to vCenter "source-vcenter.example.com"...
[INFO] Querying all VMs from vCenter "source-vcenter.example.com"...
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

## Error checking examples

### Fast fail if vCenter address is invalid; validates before asking for credentials

```text
> ./Manage-VMClasses.ps1

[INFO] Before connecting to your vCenter choose an action to perform.

  Select an action below
  Arrow keys=navigate  Enter=confirm  Esc=quit

    Discover   Scan live VMs and generate vmClasses.json
    List       Show all VM classes on vCenter
    Backup     Save all VM classes from vCenter to a JSON file
  > Update     Apply vmClasses.json to vCenter
    Delete     Remove VM classes from vCenter
    Help       Show usage documentation for this script
    Quit       Exit without making any changes


Enter your vCenter Server FQDN or IP address (or press 'c' to cancel): httptttt:/222
[ERROR] "httptttt:/222" is not a valid FQDN or IPv4 address. Omit any scheme (https://), path, or port.
```

### Check if output file exists before overwriting; fast fail if new path is invalid

```text
./Manage-VMClasses.ps1

[INFO] Before connecting to your vCenter choose an action to perform.

  Select an action below
  Arrow keys=navigate  Enter=confirm  Esc=quit

  > Discover   Scan live VMs and generate vmClasses.json
    List       Show all VM classes on vCenter
    Backup     Save all VM classes from vCenter to a JSON file
    Update     Apply vmClasses.json to vCenter
    Delete     Remove VM classes from vCenter
    Help       Show usage documentation for this script
    Quit       Exit without making any changes


[WARNING] Output file "/Users/testuser/vmClasses.json" already exists.
Overwrite? Y=overwrite, N=enter new path, C=cancel: N

Enter a new output file path: /foo/bar
[ERROR] Directory "/foo" does not exist.
Would you like to enter a different path? (Y/N):
```

### Wrong password; interactive re-prompt then user cancels

```text
./Manage-VMClasses.ps1 -Action List -VcenterUser administrator@vsphere.local

Enter your vCenter Server FQDN or IP address (or press 'c' to cancel): dest-vcenter.example.com
[INFO] Connecting to vCenter "dest-vcenter.example.com"...
Enter your vCenter password: ################

[ERROR] Authentication failed for vCenter "dest-vcenter.example.com".

Would you like to re-enter your credentials? (Y/N): N
```

### Invalid `-VcenterServer` value; scheme included

Validation runs before any connection attempt, so no password is requested.

```text
./Manage-VMClasses.ps1 -Action List -VcenterServer "https://dest-vcenter.example.com" -VcenterUser administrator@vsphere.local
[ADVISORY] Using vCenter password from $env:VCENTER_PASSWORD. Unset the variable to be prompted interactively.
[ERROR] Manage-VMClasses failed: The -VcenterServer value "https://dest-vcenter.example.com" is not a valid FQDN or IPv4 address. Omit any scheme (https://), path, or port.
```

### vCenter not reachable on port 443; user declines to re-enter address

```text
./Manage-VMClasses.ps1 -Action List -VcenterServer 192.168.1.99 -VcenterUser administrator@vsphere.local
[ADVISORY] Using vCenter password from $env:VCENTER_PASSWORD. Unset the variable to be prompted interactively.
[ERROR] Cannot reach "192.168.1.99" on port 443 (timed out after 5000ms). Check network connectivity and firewall.

Would you like to re-enter your vCenter FQDN or IP address? (Y/N): N
```

### SSL certificate error with remediation steps

Common in lab environments with self-signed certificates.

```text
./Manage-VMClasses.ps1 -Action List -VcenterServer dest-vcenter.example.com-VcenterUser administrator@vsphere.local
[ADVISORY] Using vCenter password from $env:VCENTER_PASSWORD. Unset the variable to be prompted interactively.
[INFO] Connecting to vCenter "dest-vcenter.example.com"...
[ERROR] Failed to establish an SSL connection to vCenter "dest-vcenter.example.com".
[ERROR] Common solutions:
[ERROR]   1. Run: Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false
[ERROR]   2. Run: [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[ERROR]   3. Verify network connectivity to port 443 on "dest-vcenter.example.com".
[ERROR] Full error: The SSL connection could not be established. See inner exception.
[ERROR] Manage-VMClasses failed: Manage-VMClasses cannot continue. Check logs for details.
```

### Malformed JSON file; syntax error with offending line shown

JSON validation runs before connecting to vCenter, so no password is requested.

```text
./Manage-VMClasses.ps1 -Action Update -VcenterServer dest-vcenter.example.com-VcenterUser administrator@vsphere.local
[ERROR] Invalid vmClasses JSON in "/Users/testuser/vmClasses.json": Exception calling "Parse" with "1" argument(s): "'\\"' is invalid after a value. Expected either ',', '}', or ']'. LineNumber: 4 | BytePositionInLine: 2."
[ERROR]   Offending line 5:     "cpuCount": 4,
```

The offending JSON (missing comma after `"name"` value on line 4):

```json
[
  {
    "name": "my-custom-class"
    "cpuCount": 4,
    "cpuCommitment": "bestEffort",
    "memoryMB": 4096,
    "memoryCommitment": "bestEffort"
  }
]
```

### JSON content validation errors; multiple issues reported at once

Content validation also runs before connecting to vCenter.

```text
./Manage-VMClasses.ps1 -Action Update -VcenterServer dest-vcenter.example.com-VcenterUser administrator@vsphere.local
[ERROR] VM class "my-test-class" at index 0 (the JSON file) : missing required property "cpuCommitment" (any JSON key casing is accepted, for example cpuCommitment).
[ERROR] VM class "another-class" at index 1 (the JSON file) : cpuCount must be between 1 and 64 inclusive; got 0.
```

### `-VmClassName` does not match any entry in the JSON file

Name resolution also runs before connecting to vCenter. Valid names from the file are listed to help correct the typo.

```text
./Manage-VMClasses.ps1 -Action Update -VcenterServer dest-vcenter.example.com-VcenterUser administrator@vsphere.local -VmClassName nonexistent-class
[ERROR] No entry in "/Users/testuser/vmClasses.json" matches "nonexistent-class". The name must match a "name" property in the file. Names defined in the file: 4cpu-besteffort-4096mb-besteffort, 6cpu-guaranteed-24576mb-guaranteed

Enter a different VM class name? (Y/N): N
[INFO] Exiting at user request.
```

### Delete: target class not found on vCenter

```text
./Manage-VMClasses.ps1 -Action Delete -VcenterServer dest-vcenter.example.com-VcenterUser administrator@vsphere.local -VmClassName my-removed-class
[ADVISORY] Using vCenter password from $env:VCENTER_PASSWORD. Unset the variable to be prompted interactively.
[INFO] Connecting to vCenter "dest-vcenter.example.com"...
[ERROR] VM class "my-removed-class" was not found on vCenter "dest-vcenter.example.com". Run -Action List to see available VM class names.
```

### Update: attempting to modify a built-in default class; user declines

```text
./Manage-VMClasses.ps1 -Action Update -VcenterServer dest-vcenter.example.com-VcenterUser administrator@vsphere.local -VmClassName best-effort-large
[ADVISORY] Using vCenter password from $env:VCENTER_PASSWORD. Unset the variable to be prompted interactively.
[INFO] Connecting to vCenter "dest-vcenter.example.com"...
[WARNING] VM class "best-effort-large" matches a built-in vCenter default class name.
        Proceed with modifying this default class? [y/N]: N
[INFO] Skipping VM class "best-effort-large" (user declined to modify a built-in default).
```

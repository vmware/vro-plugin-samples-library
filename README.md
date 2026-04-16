
# Powershell Scripts for VMware vSphere Kubernetes Service (VKS)

[![PowerShell](https://img.shields.io/badge/PowerShell-7.4%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![License](https://img.shields.io/badge/License-Broadcom-green.svg)](LICENSE.md)
[![Version](https://img.shields.io/badge/Version-1.0.0.0-orange.svg)](CHANGELOG.md)
![Downloads](https://img.shields.io/github/downloads/vmware/powershell-vks-utilities/total?label=Release%20Downloads)
![GitHub Clones](https://img.shields.io/badge/dynamic/json?color=success&label=Clone&query=count&url=https://gist.githubusercontent.com/nathanthaler/79273cbf007c8f0d37ad994d83f10fac/raw/clone.json&logo=github)

## First Utility - Manage VM Classes

Easily export your common VM configurations into VM class definitions.  VM classes allow a user to define the such resources include CPU, memory, and GPU within a Kubernetes context.  This script simplifies the process by finding the most common vSphere VM configurations in a vCenter and then automatically constructing a simplified JSON definition that can be imported into the same or a different vCenter.

## Latest Release

[Download 1.0.0 with Documentation]( https://github.com/vmware/powershell-vks-utilities/releases/latest/download/Manage-VMClasses.zip)
## Prerequisites

- PowerShell 7.4 or later [download](https://learn.microsoft.com/en-us/powershell/scripting/install/install-powershell).
- VCF PowerCLI 9.0+ [download](https://developer.broadcom.com/powercli/installation-guide).
- Network access to vCenter.
- A user with the following rights, at minimum, to the source vCenter: Read-only (at vCenter root level).
- A user with the following rights, at minimum, to the destination vCenter: Namespaces.Configure and Namespaces.ListAccess.

## Screen Short showing TUI for Discovery

<img src="Manage-VMClasses/images/DiscoverVMs.png" alt="App Screenshot" width="1000">

## Screen Short showing TUI for Import

<img src="Manage-VMClasses/images/ImportVMs.png" alt="App Screenshot" width="1000">

## Example Usage

[Examples](Manage-VMClasses/EXAMPLES.md)

## Detailed VM Manage Readme

[Detailed Readme](Manage-VMClasses/README.md)

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

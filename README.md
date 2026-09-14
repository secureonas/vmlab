# vmlab

Throwaway Linux VMs on VMware Workstation for Windows, driven by `vmrun`.

Linked clones from a golden snapshot, so a new VM takes seconds and a few
hundred MB. Each clone renames itself to whatever you called it, so you never
end up with four machines all answering to `ubuntu-master`.

```
.\start-vm.ps1                   # pick an image, pick a name, boots and prints the IP
.\list-vms.ps1                   # what exists, what's running, what it's using
.\delete-vm.ps1                  # pick one and destroy it
.\refresh-master.ps1 -OS ubuntu  # patch a master and re-take its snapshot
```

## Setup

### 1. Configure

```powershell
Copy-Item vm-config.example.ps1 vm-config.ps1
notepad vm-config.ps1
```

Set `$VmRun`, `$BaseDir`, and one `$Masters` entry per image you have. The keys
are arbitrary - whatever you put there is what `-OS` accepts.

`vm-config.ps1` is gitignored. Keep your paths and usernames out of the repo.

### 2. Prepare each master image

Per master, once:

1. Power it on in Workstation and log in.
2. Copy `guest/install-hostname-hook.sh` into the guest and run it:
   ```bash
   sudo bash install-hostname-hook.sh
   ```
3. `sudo shutdown -h now`
4. Close the VM's tab in Workstation - an open tab holds a lock on the `.vmx`
   and `vmrun` will refuse to snapshot.
5. Take the snapshot from PowerShell:
   ```powershell
   . .\vm-lib.ps1
   & $VmRun snapshot "C:\vms\ubuntu_master\ubuntu_master.vmx" $SnapshotName
   & $VmRun listSnapshots "C:\vms\ubuntu_master\ubuntu_master.vmx"
   ```
   The listing must show exactly one snapshot. Two with the same name makes
   `-snapshot=` ambiguous and clones may link to the wrong one.

Requires `open-vm-tools` in the guest. Ubuntu and RHEL 9/10 ship it; verify with
`which vmware-rpctool` or `which vmtoolsd`.

### 3. Go

```powershell
.\start-vm.ps1 -OS ubuntu -Name test01
```

## How the hostname works

1. `start-vm.ps1` clones, then appends `guestinfo.hostname = "test01"` to the
   clone's `.vmx`.
2. The guest boots. `set-guest-hostname.service` runs after `vmtoolsd`.
3. The script reads the key over the VMware RPC channel and calls
   `hostnamectl set-hostname`.

The key must be in the `.vmx` **before** power-on - VMware only exposes it at
VMX start. Editing a running VM's `.vmx` needs a full power cycle, not a reboot.

## Refreshing a master

Golden snapshots are a point in time, so patches only reach new clones by going
back through the master.

```powershell
.\list-vms.ps1 | ForEach-Object { .\delete-vm.ps1 -Name $_.Name -Force }
.\refresh-master.ps1 -OS ubuntu
# patch, shut down, close the tab
.\refresh-master.ps1 -OS ubuntu -Snapshot
```

Deleting the clones first is not optional. A linked clone stores only the delta
against its parent snapshot; replacing that snapshot breaks the chain silently,
and you find out later.

For a clone that's merely out of date, deleting and re-creating it is usually
faster than patching it.

## Files

| File | |
|---|---|
| `vm-config.example.ps1` | template - copy to `vm-config.ps1` |
| `vm-lib.ps1` | config loader and shared helpers, dot-sourced by the rest |
| `start-vm.ps1` | clone, inject hostname, boot, report IP |
| `list-vms.ps1` | emits objects, so it pipes |
| `delete-vm.ps1` | stop, unregister, remove folder |
| `refresh-master.ps1` | two-phase golden image refresh |
| `guest/install-hostname-hook.sh` | run once per master image |

## Notes

- Save `.ps1` files as **UTF-8 with BOM** or plain ASCII. Windows PowerShell 5.1
  reads BOM-less files as ANSI, and a stray em dash or curly quote will break
  parsing in a way the error message does not explain.
- `list-vms.ps1` emits objects rather than printing, so:
  ```powershell
  .\list-vms.ps1 | Where-Object Status -eq 'Stopped' |
      ForEach-Object { .\delete-vm.ps1 -Name $_.Name -Force }
  ```
- `ORPHAN` status means a clone folder with no `.vmx` inside - usually a failed
  clone. `delete-vm.ps1` cleans those up.
- Tired of typing paths? In `$PROFILE`:
  ```powershell
  Set-Alias vmnew "C:\path\to\vmlab\start-vm.ps1"
  Set-Alias vmls  "C:\path\to\vmlab\list-vms.ps1"
  Set-Alias vmdel "C:\path\to\vmlab\delete-vm.ps1"
  ```

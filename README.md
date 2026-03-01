# clevis-luks-unlocker

Automated Clevis/Tang-based LUKS unlock for encrypted LXC container volumes on Proxmox VE. Waits for Tang server availability at boot, then unlocks specified LVM volumes via `clevis luks unlock` so encrypted LXC containers can start unattended.

## Prerequisites

- Proxmox VE with LVM Thin-Pool (`pve/data`)
- Encrypted LXC volumes (LUKS-formatted LVM thin volumes)
- Tang server running on a **physically separate** host (e.g. Raspberry Pi, separate server)
- Clevis with Tang binding configured on each LUKS volume
- LXC containers configured with mountpoints pointing to `/dev/mapper/lxc-<CTID>-<NAME>`

## Setup

### 1. Create and encrypt LVM volumes

```bash
lvcreate -V <SIZE> -T pve/data -n lxc-<CTID>-<NAME>
cryptsetup luksFormat /dev/pve/lxc-<CTID>-<NAME>
cryptsetup refresh --allow-discards --persistent lxc-<CTID>-<NAME>
cryptsetup open /dev/pve/lxc-<CTID>-<NAME> lxc-<CTID>-<NAME>
mkfs.ext4 /dev/mapper/lxc-<CTID>-<NAME>
```

For unprivileged containers, set ownership to the mapped UID:

```bash
mount /dev/mapper/lxc-<CTID>-<NAME> /mnt
chown 100000:100000 /mnt
umount /mnt
```

### 2. Configure LXC mountpoints

Add to `/etc/pve/lxc/<CTID>.conf`:

```
mp0: /dev/mapper/lxc-<CTID>-<NAME>,mp=<MOUNT_PATH>
```

### 3. Install Clevis and bind to Tang

```bash
apt install clevis clevis-luks
clevis luks bind -d /dev/pve/lxc-<CTID>-<NAME> tang '{"url":"https://tang.example.com"}'
```

Confirm the thumbprint and enter the existing LUKS passphrase. This creates a second keyslot (slot 1) for automatic unlock while keeping the passphrase in slot 0 as fallback.

Verify:

```bash
clevis luks list -d /dev/pve/lxc-<CTID>-<NAME>
```

### 4. Install the unlock script

Clone the repository to `/opt/clevis-luks-unlocker`:

```bash
git clone https://github.com/henne93/clevis-luks-unlocker.git /opt/clevis-luks-unlocker
chmod +x /opt/clevis-luks-unlocker/clevis-luks-unlocker.sh
```

Edit `/opt/clevis-luks-unlocker/clevis-luks-unlocker.conf` to match your environment:

| Key              | Description                                          | Default                   |
|------------------|------------------------------------------------------|---------------------------|
| `LOG`            | Path to the log file                                 | `/var/log/unlock-lxc.log` |
| `TANG_TIMEOUT`   | Total wall-clock seconds to wait for any Tang server | `60`                      |
| `RETRY_INTERVAL` | Seconds to sleep between Tang retry cycles           | `5`                       |
| `UNLOCK_TIMEOUT` | Timeout in seconds per volume unlock attempt         | `15`                      |
| `TANG_URLS`      | Space-separated list of Tang server URLs             | —                         |
| `LUKS_VOLUMES`   | Space-separated list of `device:mapper-name` pairs   | —                         |

Example:

```bash
TANG_URLS="https://tang1.example.com https://tang2.example.com"
LUKS_VOLUMES="/dev/pve/lxc-100-data:lxc-100-data /dev/pve/lxc-101-data:lxc-101-data"
```

The script tries each Tang URL in order and uses the first one that responds. If none respond, it sleeps `RETRY_INTERVAL` seconds and retries, until `TANG_TIMEOUT` wall-clock seconds have elapsed.

### 5. Create and enable the systemd service

Create `/etc/systemd/system/clevis-luks-unlocker.service`:

```ini
[Unit]
Description=Unlock LUKS LXC Volumes
After=network-online.target
Wants=network-online.target
Before=pve-guests.service

[Service]
Type=oneshot
ExecStart=/opt/clevis-luks-unlocker/clevis-luks-unlocker.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

```bash
systemctl daemon-reload
systemctl enable clevis-luks-unlocker.service
```

## Boot sequence

1. Network comes up (`network-online.target`)
2. `clevis-luks-unlocker.service` runs — polls Tang servers, unlocks LUKS volumes
3. `pve-guests.service` starts — LXC containers launch with decrypted mountpoints available

The Tang server **must** be reachable before the Proxmox host completes boot. It must not run on the same host.

## Manual fallback

If Tang is unreachable, unlock volumes manually with the LUKS passphrase:

```bash
cryptsetup open /dev/pve/lxc-<CTID>-<NAME> lxc-<CTID>-<NAME>
pct start <CTID>
```

## Logs

All unlock activity is logged to the path configured via `LOG` in `clevis-luks-unlocker.conf` (default: `/var/log/unlock-lxc.log`).
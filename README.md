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

```bash
cp unlock-lxc.sh /usr/local/bin/unlock-lxc.sh
chmod +x /usr/local/bin/unlock-lxc.sh
```

Edit the script to match your environment:

- `TANG_URL` — URL of your Tang server
- `TANG_TIMEOUT` — seconds to wait for Tang availability (default: 60)
- `UNLOCK_TIMEOUT` — timeout per volume unlock (default: 15)
- Add/remove `unlock` calls at the bottom for your volumes

### 5. Create and enable the systemd service

Create `/etc/systemd/system/unlock-lxc.service`:

```ini
[Unit]
Description=Unlock LUKS LXC Volumes
After=network-online.target
Wants=network-online.target
Before=pve-guests.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/unlock-lxc.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

```bash
systemctl daemon-reload
systemctl enable unlock-lxc.service
```

## Boot sequence

1. Network comes up (`network-online.target`)
2. `unlock-lxc.service` runs — polls Tang, unlocks LUKS volumes
3. `pve-guests.service` starts — LXC containers launch with decrypted mountpoints available

The Tang server **must** be reachable before the Proxmox host completes boot. It must not run on the same host.

## Manual fallback

If Tang is unreachable, unlock volumes manually with the LUKS passphrase:

```bash
cryptsetup open /dev/pve/lxc-<CTID>-<NAME> lxc-<CTID>-<NAME>
pct start <CTID>
```

## Logs

All unlock activity is logged to `/var/log/unlock-lxc.log`.

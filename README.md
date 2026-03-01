# clevis-luks-unlocker
Automated Clevis/Tang-based LUKS unlock for encrypted LXC container volumes on Proxmox VE. Waits for Tang server availability at boot, then unlocks specified LVM volumes via clevis luks unlock so encrypted LXC containers can start unattended.

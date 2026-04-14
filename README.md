# YT6801 Auto Installer

[![ShellCheck](https://github.com/finallyjay/yt6801-auto-installer/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/finallyjay/yt6801-auto-installer/actions/workflows/shellcheck.yml)
[![License: GPL v2](https://img.shields.io/badge/License-GPL_v2-blue.svg)](https://www.gnu.org/licenses/old-licenses/gpl-2.0.en.html)
[![Version](https://img.shields.io/badge/version-1.0.0-green.svg)](https://github.com/finallyjay/yt6801-auto-installer/releases)

Automatically installs and maintains the YT6801 (Motorcomm) network driver on Linux systems. Handles kernel updates by reinstalling the driver at boot if the module is not loaded, and reboots once if necessary.

## Requirements

- Ubuntu 24.04 (or compatible Debian-based distribution)
- Root/sudo access
- `dpkg` and `systemd`
- Linux kernel headers installed (`linux-headers-$(uname -r)`)

## Repository Structure

```
yt6801-auto-installer/
├── .github/workflows/
│   └── shellcheck.yml
├── deb/
│   └── tuxedo-yt6801_1.0.28-1_all.deb
├── install_yt6801_if_needed.sh
├── check_yt6801_and_reboot.sh
├── yt6801-reinstall.service
├── setup.sh
├── uninstall.sh
├── CHANGELOG.md
├── LICENSE
├── VERSION
└── README.md
```

| File | Description |
|------|-------------|
| `deb/` | Contains the `.deb` driver package(s). The install script auto-detects the latest one. |
| `install_yt6801_if_needed.sh` | Installs/reinstalls the driver if the module is not loaded. |
| `check_yt6801_and_reboot.sh` | Checks module status and triggers a single reboot if needed. |
| `yt6801-reinstall.service` | systemd oneshot service that runs at boot. |
| `setup.sh` | Automated installer: copies files and enables the service. |
| `uninstall.sh` | Automated uninstaller: stops, disables, and removes everything. |

## Quick Install

```bash
git clone https://github.com/finallyjay/yt6801-auto-installer.git
cd yt6801-auto-installer
sudo bash setup.sh
```

This will:
1. Copy all files to `/opt/yt6801-auto-installer/`
2. Install and enable the systemd service
3. The driver will be checked and installed automatically on every boot

## Manual Installation

If you prefer to install step by step:

```bash
chmod +x install_yt6801_if_needed.sh check_yt6801_and_reboot.sh
sudo cp yt6801-reinstall.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable yt6801-reinstall.service
```

To start the service immediately:

```bash
sudo systemctl start yt6801-reinstall.service
```

## Uninstallation

```bash
sudo bash uninstall.sh
```

This stops the service, removes the service file, and deletes `/opt/yt6801-auto-installer/`. The kernel module and its `/etc/modules` entry are preserved. To fully remove:

```bash
sudo sed -i '/^yt6801$/d' /etc/modules
sudo modprobe -r yt6801
```

## Updating the Driver

To update to a newer driver version:

1. Place the new `.deb` file in the `deb/` directory
2. Re-run `sudo bash setup.sh`

The install script automatically picks the latest `.deb` file (sorted by version).

## Logs

All activity is logged to `/opt/yt6801-auto-installer/install_yt6801.log`:

```bash
cat /opt/yt6801-auto-installer/install_yt6801.log
```

## Troubleshooting

**Module not loading after installation:**
```bash
# Check if the module exists for your kernel
find /lib/modules/$(uname -r) -name 'yt6801*'

# Try loading manually
sudo modprobe yt6801

# Check dmesg for errors
dmesg | grep -i yt6801
```

**Service not running:**
```bash
sudo systemctl status yt6801-reinstall.service
journalctl -u yt6801-reinstall.service
```

**Driver not surviving kernel updates:**
Make sure the service is enabled. It will automatically reinstall on the next boot after a kernel update:
```bash
sudo systemctl is-enabled yt6801-reinstall.service
```

## Compatibility

| Distribution | Version | Status |
|-------------|---------|--------|
| Ubuntu | 24.04 LTS | Tested |
| Ubuntu | 22.04 LTS | Should work |
| Debian | 12 (Bookworm) | Should work |
| Other Debian-based | - | Untested |

## How It Works

1. On boot, the systemd service runs `install_yt6801_if_needed.sh`
2. If the `yt6801` module is already loaded, it exits immediately
3. If not, it installs the `.deb` package, runs `depmod`, and adds the module to `/etc/modules`
4. Then `check_yt6801_and_reboot.sh` verifies the module loaded correctly
5. If the module still isn't loaded, it reboots the system **once** (tracked via a flag file)

## License

This project is licensed under the GNU General Public License v2.0 - see the [LICENSE](LICENSE) file for details.

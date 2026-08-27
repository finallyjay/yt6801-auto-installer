# YT6801 Auto Installer

[![ShellCheck](https://github.com/finallyjay/yt6801-auto-installer/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/finallyjay/yt6801-auto-installer/actions/workflows/shellcheck.yml)
[![License: GPL v2](https://img.shields.io/badge/License-GPL_v2-blue.svg)](https://www.gnu.org/licenses/old-licenses/gpl-2.0.en.html)
[![Version](https://img.shields.io/badge/version-1.0.0-green.svg)](https://github.com/finallyjay/yt6801-auto-installer/releases)

Automatically installs and maintains the YT6801 (Motorcomm) network driver on Linux systems. Handles kernel updates by reinstalling the driver at boot if the module is not loaded, and reboots once if necessary.

## Requirements

- Ubuntu 24.04 (or compatible Debian-based distribution)
- Root/sudo access
- `dpkg` and `systemd`
- `dkms` (the driver package is a DKMS module: it declares `Depends: dkms (>= 2.1.0.0)`)
- Linux kernel headers installed (`linux-headers-$(uname -r)`)

> **Note:** If you install the `.deb` manually, prefer `sudo apt-get install -y ./deb/tuxedo-yt6801_1.0.28-1_all.deb` (or, if `deb/` holds more than one version, the newest one — mirroring the `sort -V | tail -n 1` selection `install_yt6801_if_needed.sh` uses), which resolves and installs `dkms` and other dependencies automatically, over a bare `sudo dpkg -i ...`, which will fail (or leave the package unconfigured) if `dkms` isn't already installed.

## Driver Package Provenance

The bundled package, `deb/tuxedo-yt6801_1.0.28-1_all.deb`, is redistributed unmodified from [TUXEDO Computers GmbH](https://www.tuxedocomputers.com/) (`tux@tuxedocomputers.com`), the upstream maintainer of the `tuxedo-yt6801` DKMS driver for the Motorcomm YT6801 controller.

Verify its integrity before installing:

```bash
echo "20f3626790956d14806934b10358894d25deeaa8c5cf63b56871c2d38cad3db7  deb/tuxedo-yt6801_1.0.28-1_all.deb" | sha256sum -c -
```

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

If you prefer to install step by step (this mirrors what `setup.sh` does): the service's `ExecStart`/`ExecStartPost` and `WorkingDirectory` point at `/opt/yt6801-auto-installer/`, so the scripts and the `deb/` directory must be copied there first, not just the unit file.

```bash
sudo mkdir -p /opt/yt6801-auto-installer
sudo cp -r deb install_yt6801_if_needed.sh check_yt6801_and_reboot.sh yt6801-reinstall.service /opt/yt6801-auto-installer/
sudo chmod +x /opt/yt6801-auto-installer/install_yt6801_if_needed.sh /opt/yt6801-auto-installer/check_yt6801_and_reboot.sh
sudo cp /opt/yt6801-auto-installer/yt6801-reinstall.service /etc/systemd/system/
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

Both scripts run under systemd and write their output to stdout/stderr, which the
`yt6801-reinstall.service` unit sends to the journal. View the logs with:

```bash
sudo journalctl -u yt6801-reinstall.service
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
sudo journalctl -u yt6801-reinstall.service
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

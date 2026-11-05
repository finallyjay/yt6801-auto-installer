# YT6801 Auto Installer

[![ShellCheck](https://github.com/finallyjay/yt6801-auto-installer/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/finallyjay/yt6801-auto-installer/actions/workflows/shellcheck.yml)
[![License: GPL v2](https://img.shields.io/badge/License-GPL_v2-blue.svg)](https://www.gnu.org/licenses/old-licenses/gpl-2.0.en.html)
[![Version](https://img.shields.io/badge/version-1.1.0)](https://github.com/finallyjay/yt6801-auto-installer/releases) <!-- x-release-please-version -->

Automatically installs and maintains the YT6801 (Motorcomm) network driver on Linux systems. Handles kernel updates by reinstalling the driver at boot if the module is not loaded, and reboots once if necessary.

## Do You Need This?

Only if your kernel has no driver for the YT6801.

- **Linux 7.0 and newer** ship an in-tree driver, `dwmac-motorcomm` (for example the Ubuntu 24.04 HWE 7.0 kernel). You do **not** need this project, nor the TUXEDO package.
- **Older kernels** (for example the Ubuntu 24.04 GA 6.8 kernel) do not recognise the controller, so the ethernet port stays dead without the TUXEDO driver. That is what this project is for.

Check what your kernel does:

```bash
lspci -nnk -d 1f0a:6801   # "Kernel driver in use: dwmac-motorcomm" -> nothing to do
```

The installer checks this too: on a kernel that drives the YT6801 natively (or on a machine without one) it does nothing, and it never reboots over a missing TUXEDO module. If you move to Linux 7.0+, see [Uninstallation](#uninstallation).

## Install

On the machine with the YT6801 (it needs some other way online: Wi-Fi, USB tethering…):

```bash
curl -fsSL https://yt6801.finallyjay.dev/install.sh | sudo bash
```

`yt6801.finallyjay.dev` only redirects to this repository's latest release. The same command straight from GitHub:

```bash
curl -fsSL https://github.com/finallyjay/yt6801-auto-installer/releases/latest/download/install.sh | sudo bash
```

The script downloads the release it belongs to, checks it against the release's `SHA256SUMS`, and only then runs it. Run from a terminal, it shows what it is going to do and asks before changing anything (`--yes` skips the question; without a terminal it goes ahead). Want to read it first? It is the `install.sh` asset of the [latest release](https://github.com/finallyjay/yt6801-auto-installer/releases/latest).

What it does:

1. Checks this machine: if there is no YT6801, or the kernel already drives it (Linux 7.0+), it stops there without touching anything.
2. Installs `dkms` and the headers of the running kernel if they are missing, refreshing the package lists first (this part needs internet). If that fails, nothing else is changed.
3. Installs the bundled TUXEDO driver, loads it, and enables `yt6801-reinstall.service`, which rebuilds it after kernel updates.
4. Tells you whether the port is up, and how to uninstall.

### Offline install

Download `yt6801-auto-installer.tar.gz` from another computer ([direct link](https://yt6801.finallyjay.dev/download), or from the [latest release](https://github.com/finallyjay/yt6801-auto-installer/releases/latest)), copy it over (USB stick…), then:

```bash
tar -xzf yt6801-auto-installer.tar.gz
sudo ./yt6801-auto-installer-*/install.sh
```

Without internet, `dkms` and the kernel headers must already be installed.

### From a clone

```bash
git clone https://github.com/finallyjay/yt6801-auto-installer.git
cd yt6801-auto-installer
sudo ./install.sh
```

`setup.sh` still works too; it now just runs `install.sh`.

## Requirements

- Ubuntu 24.04 (or compatible Debian-based distribution)
- Root/sudo access
- `dpkg`, `apt` and `systemd`
- `dkms` and the headers of the running kernel (`linux-headers-$(uname -r)`); the installer installs them if they are missing

> **Note:** If you install the `.deb` manually, prefer `sudo apt-get install -y ./deb/tuxedo-yt6801_1.0.28-1_all.deb`, which resolves and installs `dkms` and other dependencies automatically, over a bare `sudo dpkg -i ...`, which will fail (or leave the package unconfigured) if `dkms` isn't already installed.

## Uninstallation

```bash
curl -fsSL https://yt6801.finallyjay.dev/uninstall.sh | sudo bash
# or, offline:
sudo /opt/yt6801-auto-installer/uninstall.sh
```

This removes everything: it purges the `tuxedo-yt6801` package (which also drops its DKMS module from every kernel, and catches a package left half-installed by a failed build), removes the `yt6801` line from `/etc/modules`, and only then removes the boot service and `/opt/yt6801-auto-installer/`, so if removing the driver fails, everything needed to retry is still in place. If the kernel has its own driver (Linux 7.0+), it is loaded right away so the network comes back without a reboot.

It will not remove the driver when your ethernet port depends on it (the port runs on the TUXEDO module and the kernel has no driver of its own), because that would cut the network immediately and after every reboot. It explains why and asks (default: no); without a terminal it refuses. `--yes` does not answer this question: only `--force` skips it.

| Option | Effect |
|--------|--------|
| `--keep-driver` | Only remove the auto-installer; keep the TUXEDO driver and `/etc/modules` entry (the old behaviour). |
| `--force` | Remove the driver even if the ethernet port depends on it. |
| `--yes` | Do not ask for confirmation. |

Options go after `-s --` when piping: `curl -fsSL https://yt6801.finallyjay.dev/uninstall.sh | sudo bash -s -- --keep-driver`.

## Updating the Driver

Run the installer again: a newer release ships the newer driver package, and the boot service picks the newest `.deb` in `/opt/yt6801-auto-installer/deb/`.

## Driver Package Provenance

The bundled package, `deb/tuxedo-yt6801_1.0.28-1_all.deb`, is redistributed unmodified from [TUXEDO Computers GmbH](https://www.tuxedocomputers.com/) (`tux@tuxedocomputers.com`), the upstream maintainer of the `tuxedo-yt6801` DKMS driver for the Motorcomm YT6801 controller.

Verify its integrity before installing:

```bash
echo "20f3626790956d14806934b10358894d25deeaa8c5cf63b56871c2d38cad3db7  deb/tuxedo-yt6801_1.0.28-1_all.deb" | sha256sum -c -
```

Known upstream issue: the package's `dkms.conf` builds against `uname -r` (the *running* kernel) instead of the kernel being installed, so the module DKMS builds while installing a new kernel does not load on it. The boot service covers this by rebuilding the driver on the first boot of the new kernel.

## Repository Structure

```
yt6801-auto-installer/
├── deb/
│   └── tuxedo-yt6801_1.0.28-1_all.deb
├── install.sh                    # installer (also the `curl | sudo bash` entry point)
├── uninstall.sh                  # uninstaller (same)
├── yt6801-common.sh              # shared helpers
├── install_yt6801_if_needed.sh   # boot-time driver (re)install
├── check_yt6801_and_reboot.sh    # boot-time check, reboots once if needed
├── yt6801-reinstall.service      # systemd unit running the two above
├── setup.sh                      # compatibility wrapper for install.sh
├── tools/build-release.sh        # builds the release assets
└── test/                         # bats tests
```

| File | Description |
|------|-------------|
| `install.sh` | Installer. Piped into bash, it downloads and verifies its release first. |
| `uninstall.sh` | Uninstaller: removes the service, `/opt/yt6801-auto-installer` and the driver. |
| `yt6801-common.sh` | Shared helpers: detects the controller and whether the kernel already drives it; terminal output. |
| `deb/` | Contains the `.deb` driver package(s). The install script auto-detects the latest one. |
| `install_yt6801_if_needed.sh` | Installs/reinstalls the driver if the module is not loaded. |
| `check_yt6801_and_reboot.sh` | Checks module status and triggers a single reboot if needed. |
| `yt6801-reinstall.service` | systemd oneshot service that runs at boot. |

## Manual Installation

If you prefer to install step by step (this mirrors what `install.sh` does): the service's `ExecStart`/`ExecStartPost` and `WorkingDirectory` point at `/opt/yt6801-auto-installer/`, so the scripts and the `deb/` directory must be copied there first, not just the unit file.

```bash
sudo mkdir -p /opt/yt6801-auto-installer
sudo cp -r deb install_yt6801_if_needed.sh check_yt6801_and_reboot.sh yt6801-common.sh uninstall.sh yt6801-reinstall.service /opt/yt6801-auto-installer/
sudo chmod +x /opt/yt6801-auto-installer/*.sh
sudo cp /opt/yt6801-auto-installer/yt6801-reinstall.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now yt6801-reinstall.service
```

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
2. If there is no YT6801 controller, or the running kernel already provides a driver for it (Linux 7.0+ `dwmac-motorcomm`), it exits without touching anything
3. If the `yt6801` module is already loaded, it exits, unless `deb/` holds a newer package than the installed one
4. If not, it installs the `.deb` package, runs `depmod`, and adds the module to `/etc/modules`
5. Then `check_yt6801_and_reboot.sh` verifies the module loaded correctly (it applies the same check as step 2, so it never reboots on a kernel with a native driver)
6. If the module still isn't loaded, it reboots the system **once** (tracked via a flag file)

## License

This project is licensed under the GNU General Public License v2.0 - see the [LICENSE](LICENSE) file for details.

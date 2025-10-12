# YT6801 Driver Installer

This repository contains scripts and a systemd service to automatically install and verify the YT6801 network driver on Linux systems (tested on Ubuntu 24.04). It handles kernel updates by reinstalling the driver if necessary and can reboot the system automatically if the module is not loaded.

## Repository Structure

```
yt6801-driver/
├─ deb/
│   └─ tuxedo-yt6801_1.0.28-1_all.deb
├─ install_yt6801_if_needed.sh
├─ check_yt6801_and_reboot.sh
├─ yt6801-reinstall.service
└─ README.md
```

- `deb/` - Contains the `.deb` driver package.
- `install_yt6801_if_needed.sh` - Installs or reinstalls the driver if not loaded.
- `check_yt6801_and_reboot.sh` - Checks if the module is loaded and triggers a reboot if needed.
- `yt6801-reinstall.service` - systemd service to run the scripts at startup.

## Installation Steps

1. Clone or copy this repository to your system.
2. Make the scripts executable:
   ```bash
   chmod +x install_yt6801_if_needed.sh
   chmod +x check_yt6801_and_reboot.sh
   ```
3. Copy the systemd service to `/etc/systemd/system/`:
   ```bash
   sudo cp yt6801-reinstall.service /etc/systemd/system/
   ```
4. Reload systemd and enable the service:
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable yt6801-reinstall.service
   ```
5. Optionally, start the service manually to test:
   ```bash
   sudo systemctl start yt6801-reinstall.service
   ```
6. Check logs to verify the installation and module status:
   ```bash
   cat ./install_yt6801.log
   ```

## Notes

- The service ensures the driver is installed after a kernel update.
- The reboot only occurs **once per boot** if the module is not loaded.
- All logs are written to `install_yt6801.log` in the repository folder.

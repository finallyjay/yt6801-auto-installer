<!--
Thanks for contributing! Please fill out the sections below so reviewers
can understand the change quickly. Feel free to delete sections that do
not apply.
-->

## Summary

<!-- What does this PR do, and why? One or two sentences is fine. -->

## Type of change

- [ ] Bug fix (non-breaking change that fixes an issue)
- [ ] New feature (non-breaking change that adds functionality)
- [ ] Breaking change (fix or feature that changes existing behavior)
- [ ] Documentation only
- [ ] CI / tooling only
- [ ] Driver package update (new `.deb` under `deb/`)

## Related issues

<!-- e.g. Closes #123, Refs #456 -->

## How was this tested?

<!--
Describe the distribution, kernel, and scenarios you tested on. For
install/reinstall/uninstall changes, please test on a disposable VM.
-->

- Distribution and version:
- Kernel version (`uname -r`):
- Scenarios exercised:
  - [ ] Fresh `sudo bash setup.sh`
  - [ ] Reboot and verify `yt6801` module is loaded
  - [ ] Simulated kernel update + reboot
  - [ ] `sudo bash uninstall.sh` leaves the system clean

## Checklist

- [ ] `shellcheck *.sh` passes locally
- [ ] I have read the [Contributing guide](../CONTRIBUTING.md)
- [ ] I have updated the README / CHANGELOG if behavior changed
- [ ] This change is licensed under GPL v2 (same as the project)

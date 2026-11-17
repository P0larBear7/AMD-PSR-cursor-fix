# AMD PSR Cursor Fix

Windows workaround for hardware cursor stutter when an AMD GPU drives an internal eDP panel. It sets `DalPSRFeatureEnable` to `0` on the selected adapter, disabling panel self-refresh (PSR).

**Tested:** ASUS TUF Gaming A16 FA617NT, Radeon RX 7700S, internal 165 Hz panel, Windows 11 build 26300.9818, and AMD Adrenalin 26.11.1 (RX driver 32.0.32015.16001). The fix cleared desktop cursor stutter with a 1000 Hz mouse. Compatibility with other hardware and driver versions varies.

**SmartAccess Graphics:** On the tested A16, the switch back to the integrated GPU stalled with PSR disabled on the RX 7700S alone. Both switch directions worked with default PSR settings. Keep the defaults if you rely on SmartAccess Graphics. [Test results](docs/TECHNICAL-REPORT.md#smartaccess-graphics)

## Use

1. For mixed packages or stale settings, a clean reinstall with DDU is recommended before testing. [Clean-install guide](docs/CLEAN-INSTALL.md)
2. Extract the ZIP, open `Start.cmd`, and choose **Disable PSR on an AMD adapter**. On the tested A16 this targets the RX 7700S. On other systems, use **Advanced display > Connected to** to identify the GPU driving the affected panel. [Release ZIP](https://github.com/P0larBear7/amd-psr-cursor-fix/releases)
3. Restart Windows to load the setting, then test the cursor. A PnP restart also worked on the test system. [Activation and recovery](docs/CLEAN-INSTALL.md)

The registry change requires administrator access. Disabling PSR can increase idle display power use. Choose **Restore AMD adapter setting** and restart if switching hangs.

**Restore** reinstates the saved value, including its original absence. **Status** shows the policy on each AMD adapter. Check it again after a driver update or clean reinstall.

[Technical report](docs/TECHNICAL-REPORT.md) · [Optional ASUS extension](docs/ASUS-COMPATIBILITY.md) · [Report an issue](https://github.com/P0larBear7/amd-psr-cursor-fix/issues/new/choose)

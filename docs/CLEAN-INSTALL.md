# Clean installation and SmartAccess Graphics

A clean driver reinstall is recommended when troubleshooting mixed OEM and AMD packages, stale settings or a retrofit that behaves differently after an update. For this workaround, an already clean AMD installation is a sufficient baseline.

1. Download the desired AMD driver and, for an ASUS laptop, the model-specific ASUS driver as a recovery option. Download Display Driver Uninstaller (DDU) from Wagnardsoft. AMD Cleanup Utility is another option for AMD graphics drivers. [DDU guide](https://www.wagnardsoft.com/content/How-use-Display-Driver-Uninstaller-DDU-Guide-Tutorial) · [AMD Cleanup Utility](https://www.amd.com/en/resources/support-articles/faqs/GPU-601.html)
2. Disconnect from the internet to keep Windows Update from installing a driver mid-process. Follow the DDU guide to enter Windows Safe Mode, select AMD and run **Clean and restart**. Cleanup removes graphics drivers and may reset graphics profiles or remove OEM extensions.
3. Back in normal Windows, install the downloaded driver, restart, then reconnect. On hybrid laptops, confirm both display adapters have loaded their drivers.
4. Test SAG on the clean base driver. Record which GPU drives the display at the desktop, after opening a game that triggers SAG, and after closing it.
5. If you depend on SAG on the tested A16, keep default PSR settings. To evaluate the workaround on another configuration, apply it only to the affected adapter, restart Windows and repeat the same switching and cursor tests. Install any matching ASUS extension separately and retest. [ASUS extension instructions](ASUS-COMPATIBILITY.md)

## Check SmartAccess Graphics

On supported ASUS laptops, use **Standard** GPU mode and enable **AMD SmartAccess Graphics** in Adrenalin. ASUS documents a brief black screen or flicker during a normal switch, with approximately 3–5 seconds of transition time. Verify actual panel ownership in **Advanced display** after each switch. Opening and exiting GPU-Z triggered the handoff on the reference system. Confirm that GPU-Z has exited if the panel stays on the RX. [ASUS SAG setup](https://www.asus.com/support/faq/1049569/)

If a switch repeatedly stalls, restore the original PSR policy on every adapter you changed and restart Windows. Verify that Status shows the original settings and test both directions again. On the tested RX 7700S, an RX-only override was enough to stall the return to the integrated GPU. Default PSR on both adapters restored switching with the same driver installation. [Test results](TECHNICAL-REPORT.md#smartaccess-graphics)

If switching still fails and an optional OEM extension was added, return to your working driver baseline and test again. Restore only changes the PSR setting. Record the switch direction, triggering application, delay, the connected GPU after the stall, both adapter driver versions and the active extension, if any.

PnPUtil reloaded each adapter without a Windows reboot during testing. To do this from an administrator terminal, pass the exact adapter ID from **Status** to `pnputil /restart-device`. The screen may blink. Restart Windows if PnPUtil requests it or to establish a fresh startup baseline. [PnPUtil documentation](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/pnputil-command-syntax)

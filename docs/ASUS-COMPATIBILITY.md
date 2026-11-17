# ASUS display extension

ASUS distributes some OEM display policies as a signed extension INF. Windows applies an applicable extension alongside the installed base driver. The matching INF can carry display and panel settings across a base-driver update. [Microsoft extension INF documentation](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/using-an-extension-inf-file)

The ASUS package examined here provides model and revision matching for AMD GPU hardware IDs, including the Navi 33 discrete GPU and Rembrandt integrated GPU in the TUF A16 FA617NT. The extension contains refresh policies such as `DalVirtualizedRefreshRateSupport` and `DalDLRCFeatureEnable`, plus a panel-specific override table in the integrated GPU section. Its effect depends on the driver and matching device. The extension was already active during the initial stutter reproduction, and a separate stability benefit has not been measured.

## Install the matching package

Test SmartAccess Graphics on the base driver first. If you install the optional extension, test again before changing any other settings. [Clean install and SAG checks](CLEAN-INSTALL.md)

1. Download the graphics package for the exact laptop model from ASUS Support and extract it. In the display driver directory, locate the original `amduw23e.inf` and `amduw23e.cat`. Keep the `amdpcibridge` subdirectory intact when present, with its own INF and catalog. The tested Navi 33 section references that directory through `CopyINF`.
2. Open a terminal as administrator in the directory containing the display INF. Install the extension with Windows PnPUtil.

   ```powershell
   pnputil /add-driver .\amduw23e.inf /install
   ```

3. Restart Windows if requested, then check the actual driver association.

   ```powershell
   pnputil /enum-devices /class Display /connected /drivers
   ```

In the output, check the base driver version and look for the extension's published name under **Extension Driver Names**. A newer matching extension can take precedence. Windows verifies the catalog and hardware match during staging and installation. [PnPUtil reference](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/pnputil-command-syntax)

Installing the extension may update settings on both GPUs. Keep the package contents unmodified and let Windows use the original hardware matching. For a full return to a known configuration, reinstall the working driver package and retest. Deleting an extension from the Driver Store may leave settings it previously supplied.

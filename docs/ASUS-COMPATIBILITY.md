# Original ASUS display extensions

ASUS supplies display settings in a signed extension package alongside its base AMD driver. Windows can apply an extension after the base driver and retain the extension across base-driver updates. This gives a way to use an AMD base driver together with matching OEM customization. [Microsoft extension INF documentation](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/using-an-extension-inf-file)

## What was found

The investigated ASUS `amduw23e.inf` version 32.0.21040.6 includes exact AMD PCI hardware IDs with ASUS subsystem IDs and revision matching. Its extension ID is `{07A2A561-D001-4503-B239-EF2FE0379EFB}`. One package supports multiple models and GPU families, with different install sections chosen by the hardware match.

| Policy | Observed ASUS setting | Interpretation boundary |
|---|---|---|
| `DalVirtualizedRefreshRateSupport` | 0 for both reference GPUs | Private AMD policy |
| `DalSupportExternalPanelDrr` | 1 for both reference GPUs | The name concerns external-panel DRR |
| `DalMonitorSpecificDrrOverride` | A 492-byte panel table on the integrated GPU | Panel-specific data should follow the original INF matching |
| `DalDLRCFeatureEnable` | 5 in the newer ASUS package | Runtime semantics require vendor context |
| `StutterMode` | 0x200A in both compared ASUS and generic Navi 33 base paths | This value did not distinguish smooth and failing packages |

The generic base INF omitted explicit additions for several OEM values. The effective state also depends on compiled defaults, surviving registry state and active extensions. A registry-value name alone cannot establish a stability or power benefit.

The ASUS extension was installed and active on the reference system while the current driver's cursor stutter persisted. The PSR-disable override supplied the verified improvement. No separate stability increase from reinstalling the already-active extension was demonstrated.

## Simple installation

Obtain the AMD graphics package for the exact laptop model from ASUS support. Extract it using the package's extraction option or a tool capable of extracting its archive. Locate the directory containing the following original files.

```text
amduw23e.inf
amduw23e.cat
amdpcibridge/
    amdpcibridgeextension.inf
    amdpcibridgeextension.cat
```

The Navi 33 extension install section declares the PCI bridge dependency through `CopyINF`. Keep the original relative directory. The dependency matches AMD PCI bridge device IDs 1478 and 1479 and contains bridge-specific properties. Windows determines which connected devices match it.

Double-click **ASUS-Extension.cmd**, paste the directory path and allow the administrator prompt. For a read-only package check, run the following from the project directory.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-ASUS-Extension.ps1 -PackageFolder "D:\Extracted-ASUS\Packages\Drivers\Display\WT6A_INF"
```

Add `-Install` to install. The helper validates the expected extension identity, matching present ASUS AMD display hardware and both catalog signatures. Windows performs catalog membership checks when staging the package. The helper installs only the two named extension packages and checks the matched GPUs' base-driver versions afterward.

PnPUtil applies the highest-ranked applicable package. Successful staging alone does not prove that this version is associated with the device. The helper displays per-device driver information so the extension association can be checked. A newer installed extension may take precedence. Restart Windows if requested, then check the cursor tool's Status and test the original mouse behavior. [PnPUtil installation behavior](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/pnputil-command-syntax)

## Applicability and recovery

Use the original package for the laptop model. Copying a panel table or generic registry bundle into another GPU loses the OEM's section and hardware matching. The helper therefore delegates application to the original INF and Windows selection rules.

This helper has been checked against the signed extension from the reference ASUS package. Its matching and signature checks are also useful for another package using the same extension identity. Support for unrelated OEM packages would require a separate review.

The PSR tool's Restore action reverses its single registry override. OEM-extension installation is managed separately by Windows. To return to an OEM software baseline, use the original model-specific driver installer. Removing an extension from the Driver Store does not necessarily reconstruct every registry value it previously supplied, so this project does not describe package deletion as a complete settings rollback.

The release distributes this helper and documentation. Original AMD/ASUS driver files remain with their original vendor downloads and licenses.

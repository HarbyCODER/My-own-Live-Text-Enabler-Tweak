# Live Text Enabler for RootHide

A Theos tweak project that relaxes iOS Live Text capability checks for selected Apple apps. It is intended for iOS 15 and newer on arm64 devices and packages with Theos' `roothide` scheme.

## What it changes

- Reports image analysis as supported to VisionKitCore and Camera.
- Reports the relevant MobileGestalt capability as enabled so the Live Text switch can appear in Settings.
- Targets VisionKitCore, Camera, Photos, and Settings.

This does not add an OCR engine. Apple's public `ImageAnalyzer` API is documented as available only on A12 Bionic devices and later, so forcing the checks on older hardware may expose the UI without making analysis work. The private checks can also change between iOS builds.

## Build

Install the RootHide-compatible Theos fork and an iOS SDK, then run from this directory:

```sh
make clean package FINALPACKAGE=1
```

The Makefile sets `THEOS_PACKAGE_SCHEME=roothide`, an iOS 15 deployment target, and arm64/arm64e build architectures. The generated Debian package appears in `packages/`.

### Build without installing Linux on your computer

This project includes a manual GitHub Actions workflow at `.github/workflows/build.yml`. Create a private GitHub repository, upload this project's files including the `.github` folder, then open **Actions → Build RootHide package → Run workflow**. When the run finishes, download the `LiveTextEnabler-deb` artifact; it contains the `.deb` file. GitHub runs the Linux build environment on its servers, so Ubuntu is not installed on your laptop.

Install the resulting `.deb` with the package manager used by your RootHide jailbreak, then respring or restart the affected apps.

## iPhone X on iOS 16.7.14

The iPhone X uses Apple's A11 Bionic chip. Apple's supported Live Text range starts at iPhone XS/XR, and the public VisionKit image analyzer requires A12 or later. This tweak can force some private availability checks, but it does not replace the image analyzer. Treat this target as experimental: the Live Text controls may appear without recognition working.

After installing and respringing, check **Settings → General → Language & Region → Live Text** and turn it on if the switch appears. For Camera, also check **Settings → Camera → Show Detected Text**. Then try a photo with clear printed text in Photos. These switches are needed for the corresponding system surfaces; their presence does not guarantee analysis will run on A11.

## Compatibility notes

- Requires iOS 15 or later and a RootHide jailbreak that supports Theos tweak injection.
- Apple officially supports Live Text on iPhone XS/XR and later; older models are outside Apple's supported range.
- The tweak changes private, version-sensitive system checks. Missing symbols are skipped, but iOS updates can change or remove those checks.
- No compiled `.deb` is included in this source project.

## Credits and license

The hook strategy is based on [PoomSmart's LiveTextEnabler-iOS](https://github.com/PoomSmart/LiveTextEnabler-iOS), licensed under MIT. This project retains that license and includes an in-project Mach-O symbol lookup helper in place of the upstream PSHeader helper dependency.

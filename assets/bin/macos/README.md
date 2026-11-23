# macOS cores

Built macOS core binaries are not committed to git. Generate them locally before building or packaging the macOS app:

```bash
bash tool/build_macos_cores.sh          # build separate arm64 and x86_64 binaries
bash tool/build_macos_cores.sh native   # host architecture only (arm64 or x86_64)
bash tool/build_macos_cores.sh arm64    # Apple Silicon only
bash tool/build_macos_cores.sh x86_64   # Intel only
```

The script places binaries in `assets/bin/macos/arm64/` and `assets/bin/macos/x86_64/` and geo databases in `assets/bin/macos/`. The Xcode build phase embeds the active architecture into `keqdroid.app/Contents/Resources/bin/`, and `tool/package_macos.sh` produces separate single-arch `arm64` and `x86_64` `.dmg` packages.

# macOS cores

Built macOS core binaries are not committed to git. Generate them locally before building or packaging the macOS app:

```bash
bash tool/build_macos_cores.sh            # native host architecture (arm64 or x86_64)
bash tool/build_macos_cores.sh universal  # universal arm64 + x86_64 binaries via lipo
```

The script places `xray`, `mihomo`, `geoip.dat` and `geosite.dat` in this directory, and the Xcode build phase embeds them into `keqdroid.app/Contents/Resources/bin/`.

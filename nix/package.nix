{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  copyDesktopItems,
  makeDesktopItem,
  wrapGAppsHook3,
  gsettings-desktop-schemas,
  gtk3,
  libepoxy,
  libx11,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "keqdroid";
  version = "0.40.1";

  src = fetchurl {
    url = "https://github.com/Lemonochka/keqdroid/releases/download/v${finalAttrs.version}/keqdroid-${finalAttrs.version}-linux-x64.tar.gz";
    hash = "sha256-991g5DoRM3dYqsYjTvgulXUXgQ7iYHEy3Jy1QvZGLXQ=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    copyDesktopItems
    wrapGAppsHook3
  ];
  buildInputs = [
    gsettings-desktop-schemas
    gtk3
    libepoxy
    libx11
    stdenv.cc.cc.lib
  ];

  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/keqdroid $out/bin
    cp -r . $out/lib/keqdroid
    ln -s $out/lib/keqdroid/keqdroid $out/bin/keqdroid
    for name in keqdroid com.keqdroid.keqdroid; do
      install -Dm644 data/flutter_assets/assets/icon.png $out/share/icons/hicolor/256x256/apps/$name.png
    done
    runHook postInstall
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "keqdroid";
      desktopName = "KeqDroid";
      comment = "keqdroid proxy/VPN client";
      exec = "keqdroid %u";
      icon = "keqdroid";
      categories = [ "Network" ];
      mimeTypes = [
        "x-scheme-handler/keqdroid"
        "x-scheme-handler/keqdis"
      ];
      startupWMClass = "com.keqdroid.keqdroid";
    })
    (makeDesktopItem {
      name = "com.keqdroid.keqdroid";
      desktopName = "KeqDroid";
      exec = "keqdroid %u";
      icon = "keqdroid";
      noDisplay = true;
    })
  ];

  meta = {
    description = "Proxy/VPN client on Xray-core and mihomo";
    homepage = "https://github.com/Lemonochka/keqdroid";
    license = with lib.licenses; [
      agpl3Only
      gpl3Only
      mpl20
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "keqdroid";
    platforms = [ "x86_64-linux" ];
  };
})

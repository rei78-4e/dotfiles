{
  lib,
  rustPlatform,
  src,
  pkg-config,
  glib,
  gettext,
  wrapGAppsHook4,
  gtk4,
  libadwaita,
  gtksourceview5,
  enchant,
}:
rustPlatform.buildRustPackage {
  pname = "scribe";
  version = (lib.importTOML "${src}/Cargo.toml").package.version;
  inherit src;

  cargoLock.lockFile = "${src}/Cargo.lock";

  nativeBuildInputs = [
    pkg-config
    glib # glib-compile-resources (build.rs) / glib-compile-schemas
    gettext
    wrapGAppsHook4
  ];

  buildInputs = [
    gtk4
    libadwaita
    gtksourceview5
    enchant
  ];

  # The gschema is mandatory: without it the app aborts at startup.
  postInstall = ''
    install -Dm644 data/io.github.gnacho.Scribe.gschema.xml -t $out/share/gsettings-schemas/$name/glib-2.0/schemas
    glib-compile-schemas $out/share/gsettings-schemas/$name/glib-2.0/schemas
    install -Dm644 data/io.github.gnacho.Scribe.desktop -t $out/share/applications
    install -Dm644 data/io.github.gnacho.Scribe.metainfo.xml -t $out/share/metainfo
    install -Dm644 data/icons/hicolor/scalable/apps/*.svg -t $out/share/icons/hicolor/scalable/apps
    install -Dm644 data/icons/hicolor/scalable/actions/*.svg -t $out/share/icons/hicolor/scalable/actions
    mkdir -p $out/share/locale/es/LC_MESSAGES
    msgfmt po/es.po -o $out/share/locale/es/LC_MESSAGES/scribe.mo
  '';

  meta = {
    description = "Lightweight native GNOME Markdown editor with live preview";
    homepage = "https://github.com/gnacho/scribe";
    license = lib.licenses.agpl3Plus;
    mainProgram = "scribe";
  };
}

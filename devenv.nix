{
  pkgs,
  inputs,
  ...
}: {
  packages = with pkgs; [
    luajit
    readline
    raylib
    inputs.nixgl.packages.${pkgs.system}.nixGLDefault
  ];

  env.LUA_BIN = "${pkgs.luajit}/bin/luajit";
  env.PKG_CONFIG_PATH = "${pkgs.raylib}/lib/pkgconfig";
}

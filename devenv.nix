{pkgs, ...}: {
  packages = with pkgs; [
    gcc
    gnumake
    cmake
    pkg-config
    binutils

    luajit
    raylib
    readline
  ];

  env.LUA_BIN = "${pkgs.luajit}/bin/luajit";
}

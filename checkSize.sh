#!/usr/bin/bash
set -xe

case $1 in
  base)
    # nix build ".#nixosConfigurations.x64.config.system.build.toplevel"
    nix build ".#nixosConfigurations.x64-minimal.config.system.build.toplevel"
    export BASE_IMAGE="$(readlink -f result)"
    ;;
  next)
    if [ -z "$BASE_IMAGE" ]; then
        exit -1
    fi
    # nix build ".#nixosConfigurations.x64.config.system.build.toplevel"
    nix build ".#nixosConfigurations.x64-minimal.config.system.build.toplevel"
    currentImage="$(readlink -f result)"
    nix run .#nix -- store send $BASE_IMAGE $currentImage --bsdiff-nars --append-data > out.bin
    gzip out.bin
    ls -la *.gz
    ;;
  *)
    echo "Invalid option. Please select base or next."
    ;;
esac

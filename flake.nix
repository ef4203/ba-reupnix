{ description = (
    "NixOS Configuration for lightweight container systems"
    /**
     * This flake file defines the main inputs (all except for some files/archives fetched by hardcoded hash) and exports almost all usable results.
     * It should always pass »nix flake check« and »nix flake show --allow-import-from-derivation«, which means inputs and outputs comply with the flake convention.
     */
); inputs = {

    # To update »./flake.lock«: $ nix flake update
    # nixpkgs = { url = "github:NixOS/nixpkgs/nixos-23.11"; };
    # nixpkgs = { url = "github:NixOS/nixpkgs/01768412a223856e9345f89aa5cf9d3798628a5d"; }; # 23.11 @ 2023-11-01
    # nixpkgs = { url = "github:NixOS/nixpkgs/9fafb41329fdd37cb2c96ad5fa6fcffbacf7264c"; }; # 23.11 @ 2024-03-16
    nixpkgs = { url = "github:NixOS/nixpkgs/044d5c630f1d977f49676f854270edc3761535fa"; }; # 23.11 glibc 2.38-44
    # nixpkgs = { url = "github:NixOS/nixpkgs/6e88989e90cfd4af498ad7c6e4125ca2f8c40992"; }; # 23.11 glibc 2.38-27
    old-nixpkgs = { url = "github:NixOS/nixpkgs/c777cdf5c564015d5f63b09cc93bef4178b19b01"; }; # 22.05 @ 2022-05-05
    new-nixpkgs = { url = "github:NixOS/nixpkgs/9370544d849be8a07193e7611d02e6f6f1b10768"; }; # 22.05 @ 2022-07-29
    functions = { url = "github:NiklasGollenstede/nix-functions"; inputs.nixpkgs.follows = "nixpkgs"; };
    installer = { url = "github:NiklasGollenstede/nixos-installer"; inputs.nixpkgs.follows = "nixpkgs"; inputs.functions.follows = "functions"; };
    wiplib = { url = "github:NiklasGollenstede/nix-wiplib"; inputs.nixpkgs.follows = "nixpkgs"; inputs.installer.follows = "installer";  inputs.functions.follows = "functions"; };
    nixos-imx = { url = "github:NiklasGollenstede/nixos-imx"; inputs.nixpkgs.follows = "nixpkgs"; inputs.installer.follows = "installer";  inputs.functions.follows = "functions"; inputs.wiplib.follows = "wiplib"; };
    nix = { url = "github:NixOS/nix/38b90c618f5ce4334b89c0124c5a54f339a23db6"; inputs.nixpkgs.follows = "nixpkgs"; inputs.nixpkgs-regression.follows = "nixpkgs"; };
    # ba-aziot-nixos = { url = "github:ef4203/ba-aziot-nixos"; inputs.nixpkgs.follows = "nixpkgs"; };
    # ba-aziot-nixos = { url = "github:ef4203/ba-aziot-nixos/f9a8bc3d5213fefe72e3817471f2ae1390d6bdb4"; inputs.nixpkgs.follows = "nixpkgs"; }; # Azure IoT Edge 1.4.25
    ba-aziot-nixos = { url = "github:ef4203/ba-aziot-nixos/ddeb9e81f58193115bbac8d4686c8eee2a152653"; inputs.nixpkgs.follows = "nixpkgs"; }; # Azure IoT Edge 1.4.26
    latest-nixpkgs = { url = "github:NixOS/nixpkgs/nixos-unstable"; };

}; outputs = inputs@{ wiplib, ... }: let patches = let
    base = [
        inputs.wiplib.patches.nixpkgs.test
        inputs.wiplib.patches.nixpkgs.fix-systemd-boot-install
        ./patches/nixpkgs/make-required-packages-optional.patch
    ];
in rec {

    nixpkgs = base ++ [
        # make-switchable is implemented in 23.11
    ];
    new-nixpkgs = base ++ [
        ./patches/nixpkgs/make-bootable-optional.patch
    ];
    old-nixpkgs = new-nixpkgs;

    nix = [ ./patches/nix-store-send.patch ]; # Applying this patch to the »nix« input (above) implements »nix store send«.

}; in inputs.functions.lib.patchFlakeInputsAndImportRepo inputs patches ./. (all-inputs@{ self, nixpkgs, ... }: repo@{ overlays, ... }: let
    lib = repo.lib.__internal__;

    inputs = builtins.removeAttrs all-inputs [ "new-nixpkgs" "old-nixpkgs" ];

    # The normal build of all hosts:
    systemsFlake = lib.installer.mkSystemsFlake {
        inputs = inputs; overlayInputs = builtins.removeAttrs inputs [ "nix" ];
    };

    # All hosts cross compiled from x64 (which is irrelevant for those already x64):
    x64-systemsFlake = lib.installer.mkSystemsFlake {
        inputs = inputs; overlayInputs = builtins.removeAttrs inputs [ "nix" ];
        buildPlatform = "x86_64-linux";
        renameOutputs = key: "x64:${key}";
    };

    # The "normal" hosts, but built with a "new"(er) and an "old"(er) version of `nixpkgs`, for update tests:
    inherit (lib.fun.mapMerge (age: let
        legacyFix = { nixosArgs.modules = [ (args: (let inherit (args) config options; in { # (older versions of nixpkgs require this to be passed)
            disabledModules = [ "nixos/lib/eval-config.nix" ]; # this uses now-undefined arguments
            options.nixpkgs.hostPlatform = lib.mkOption { }; # cross-building (buildPlatform) not supported here
            config.nixpkgs.system = config.nixpkgs.hostPlatform; config.nixpkgs.initialSystem = config.nixpkgs.hostPlatform;
        })) ]; };
        age-inputs = inputs // { nixpkgs = all-inputs."${age}-nixpkgs"; };
        # Note: Any »inputs.nixpkgs.follows = "nixpkgs"« above will always point at the "current" version of »nixpkgs«. »wiplib« and »nixos-imx« use »inputs.nixpkgs.lib« (explicitly, but nothing else).
        # »repo«, which gets merged into the outputs, which are also »inputs.self«, used the new »nixpkgs« to import its stuff, so that import has to be repeated:
    in lib.fun.importRepo age-inputs ./. (repo: { "${age}-systemsFlake" = lib.installer.mkSystemsFlake (rec {
        inputs = age-inputs // { self = self // repo; }; overlayInputs = builtins.removeAttrs inputs [ "nix" ];
        renameOutputs = key: "${age}:${key}";
    } // legacyFix); })) [ "new" "old" ]) new-systemsFlake old-systemsFlake;

in [ # Run »nix flake show --allow-import-from-derivation« to see what this merges to:
    repo systemsFlake new-systemsFlake old-systemsFlake x64-systemsFlake
    (lib.fun.forEachSystem [ "aarch64-linux" "x86_64-linux" ] (localSystem: let
        pkgs = lib.fun.importPkgs (builtins.removeAttrs inputs [ "nix" ]) { system = localSystem; };
        checks = (lib.fun.importWrapped all-inputs "${self}/checks").required pkgs;
        packages = lib.fun.getModifiedPackages pkgs overlays;
        everything = checks.packages // (lib.genAttrs [ "all-systems" "new:all-systems" "old:all-systems" ] (name: self.packages.${localSystem}.${name})); # ("x64:all-systems" doesn't quite build completely yet)
        defaultPackage = pkgs.symlinkJoin { name = "everything"; paths = builtins.attrValues everything; };
        #defaultPackage = pkgs.linkFarm "everything" everything;
    in {
        packages = { default = defaultPackage; } // { nix = inputs.nix.packages.${pkgs.system}.nix; };
        # checks = packages // checks.checks; inherit (checks) apps;
    }))
]); }

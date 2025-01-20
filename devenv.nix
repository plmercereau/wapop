{
  pkgs,
  lib,
  config,
  inputs,
  ...
}: {
  packages = let
    custom-operator-sdk = pkgs.stdenv.mkDerivation {
      name = "operator-sdk";
      src = let
        os =
          if pkgs.stdenv.hostPlatform.isDarwin
          then "darwin"
          else "linux";
        arch =
          if pkgs.stdenv.hostPlatform.isAarch64
          then "arm64"
          else "amd64";
        hashes = {
          "darwin-arm64" = "sha256-Nf+tZJU0NejmbjuAJdUtwhOrCPimw/7Z6PwNlve8nIQ=";
          "linux-amd64" = "";
        };
      in
        pkgs.fetchurl {
          url = "https://github.com/operator-framework/operator-sdk/releases/download/v1.38.0/operator-sdk_${os}_${arch}";
          sha256 = hashes."${os}-${arch}";
        };
      phases = ["installPhase" "patchPhase"];
      installPhase = ''
        mkdir -p $out/bin
        cp $src $out/bin/operator-sdk
        chmod +x $out/bin/operator-sdk
      '';
    };

    helmify = pkgs.stdenv.mkDerivation {
      name = "helmify";
      src = let
        os = pkgs.stdenv.hostPlatform.uname.system;
        arch = pkgs.stdenv.hostPlatform.linuxArch;

        hashes = {
          "Darwin-arm64" = "sha256-yelo1YhTk/Zj0C2w64ii1xDOTdUuMSNV5+Sk6ZXlsoc=";
          "Linux-amd64" = "";
        };
      in
        pkgs.fetchurl {
          url = "https://github.com/arttor/helmify/releases/download/v0.4.17/helmify_${os}_${arch}.tar.gz";
          sha256 = hashes."${os}-${arch}";
        };
      phases = ["installPhase" "patchPhase"];
      installPhase = ''
        mkdir -p $out/bin
        cp $src $out/bin/helmify
        chmod +x $out/bin/helmify
      '';
    };
  in
    with pkgs; [custom-operator-sdk tilt go yq-go kustomize helmify kubernetes-controller-tools];

  processes = {
    tilt.exec = "tilt up";
  };

  # TODO go lint, fmt, test, etc
  git-hooks.hooks = {
  };
}

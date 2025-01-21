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
        system = "${os}_${arch}";
        hashes = {
          "darwin_arm64" = "sha256-Nf+tZJU0NejmbjuAJdUtwhOrCPimw/7Z6PwNlve8nIQ=";
          "linux_amd64" = "sha256-NfdZAQwFrvf+2d6zGkamaCrt/3q/jBCTMczZMclm5sA=";
        };
      in
        pkgs.fetchurl {
          url = "https://github.com/operator-framework/operator-sdk/releases/download/v1.38.0/operator-sdk_${system}";
          sha256 = hashes.${system};
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
        system = "${pkgs.stdenv.hostPlatform.uname.system}_${pkgs.stdenv.hostPlatform.linuxArch}";
        hashes = {
          "Darwin_arm64" = "sha256-8YHUsztufdpaG0/ij6gjXUN5NHopRoKLAUKTSOSzRvo=";
          "Linux_x86_64" = "sha256-P7SR3WV6Z2EnvVyk/PMu2CKJjuZGWOXk2/NMD5WmphM=";
        };
      in
        pkgs.fetchzip {
          url = "https://github.com/arttor/helmify/releases/download/v0.4.17/helmify_${system}.tar.gz";
          sha256 = hashes.${system};
        };
      phases = ["installPhase" "patchPhase"];
      installPhase = ''
        mkdir -p $out/bin
        cp -r $src/helmify $out/bin/helmify
        chmod +x $out/bin/helmify
      '';
    };
  in
    with pkgs; [custom-operator-sdk tilt go yq-go kustomize helmify kubernetes-controller-tools];

  processes = {
    tilt.exec = "tilt up";
  };

  git-hooks.hooks = {
    gofmt.enable = true;
    govet.enable = true;
  };
}

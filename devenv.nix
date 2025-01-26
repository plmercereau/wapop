{
  pkgs,
  lib,
  config,
  inputs,
  ...
}: {
  packages = let
  in
    with pkgs; [tilt kustomize];

  processes = {
    tilt.exec = "tilt up";
  };
}

{ pkgs ? import <nixpkgs> { }
, lib ? pkgs.lib
, super ? if !isOverlayLib then lib else { }
, self ? if !isOverlayLib then lib else { }
, before ? if !isOverlayLib then lib else { }
, isOverlayLib ? false
}@args:

let
  lib = before // iris // self;
  iris = with before; with iris; with self;
    {
      moduleList = import ./module-list.nix { inherit lib; };
    };

in
{
  inherit iris;
}

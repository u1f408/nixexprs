{
  nixlib = import <nixpkgs/lib>;
  lib = import ./lib.nix;
  pkgs = import ./pkgs.nix;

  __functor = fp: with fp; nixlib.composeManyExtensions [
    lib
    pkgs
  ];
}

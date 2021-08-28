{
  machine-cert = ./machine-cert.nix;

  __functionArgs = { };
  __functor = self: { ... }: {
    imports = with self; [
      machine-cert
    ];
  };
}

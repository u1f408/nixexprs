{
  theme = ./theme.nix;

  __functionArgs = { };
  __functor = self: { ... }: {
    imports = with self; [
      theme
    ];
  };
}

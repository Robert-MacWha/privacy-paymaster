{
  description = "light-client";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      rust-overlay,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ rust-overlay.overlays.default ];
        };
        unstable = nixpkgs-unstable.legacyPackages.${system};

        rustToolchain = pkgs.rust-bin.stable."1.93.0".default.override {
          extensions = [
            "rust-src"
            "llvm-tools"
          ];
          targets = [ "wasm32-unknown-unknown" ];
        };

        rustfmtNightly = pkgs.rust-bin.nightly.latest.rustfmt;

        aderyn = pkgs.stdenv.mkDerivation {
          pname = "aderyn";
          version = "0.6.8";
          src = pkgs.fetchurl {
            url = "https://github.com/cyfrin/aderyn/releases/download/aderyn-v0.6.8/aderyn-x86_64-unknown-linux-gnu.tar.xz";
            sha256 = "ffd6ca658962e211a3ac821c646f69c8e14bf1b1001cbfe091bcd4535a691e46";
          };
          sourceRoot = "aderyn-x86_64-unknown-linux-gnu";
          nativeBuildInputs = [ pkgs.autoPatchelfHook ];
          buildInputs = [ pkgs.stdenv.cc.cc.lib ];
          installPhase = ''
            install -Dm755 aderyn $out/bin/aderyn
          '';
        };

      in
      {
        devShells.default = pkgs.mkShell {
          packages = [
            # Rust
            rustToolchain
            rustfmtNightly
            pkgs.rust-analyzer

            # JS / WASM
            pkgs.bun
            pkgs.binaryen
            pkgs.wasm-pack

            # Solidity
            unstable.foundry
            aderyn

            pkgs.just
            pkgs.sops
          ];
        };
      }
    );
}

{
  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs, mach-nix, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        lib = pkgs.lib;

        scriptDeps = with pkgs; [
          stdenv
          hugo
        ];

        scriptEnv = pkgs.buildEnv {
          name = "scriptEnv";
          paths = scriptDeps;
        };

        script_header = ''
          #!${pkgs.stdenv.shell}
          set -Eeou pipefail
          export PATH=$PATH:${scriptEnv}/bin
        '';

        script_content = {
          hugo = ''hugo $@'';
          build = ''hugo --minify'';
          server = ''hugo server'';
        };

        scripts = builtins.mapAttrs
          (name: value: flake-utils.lib.mkApp {
            drv = pkgs.writeScriptBin "${name}" ''
              ${script_header}
              ${value}
            '';
          })
          script_content;
      in
      rec
      {
        apps = {
          default = scripts.init;
        } // scripts;

        devShell = pkgs.mkShell {
          packages = scriptDeps;
        };
      });
}

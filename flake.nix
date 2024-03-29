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
          asciinema
          asciinema-agg
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

          new-general-post = ''hugo new general/$1/index.md'';
          new-devops-post = ''hugo new devops/$1/index.md'';

          record-term = ''pushd "$RUN_FROM_DIR" ; asciinema rec $(date '+%s').cast -c bash'';
          cast-to-gif = ''agg "$1" "$(basename -s .cast $1).gif" --cols 80 --rows 20 --theme monokai'';
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

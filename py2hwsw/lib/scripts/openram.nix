# SPDX-FileCopyrightText: 2026 IObundle
#
# SPDX-License-Identifier: GPL-3.0-only

{ pkgs ? import <nixpkgs> {} }:

let
  inherit (pkgs) lib;

  python = pkgs.python3;

  openram_tools = with pkgs; [
    magic-vlsi
    netgen-vlsi
    ngspice
    klayout
    pdk-ciel
    git
  ];

  pythonEnv = python.withPackages (ps:
    with ps; [
      numpy
      scipy
      scikit-learn
      coverage
    ]);
in
python.pkgs.buildPythonPackage rec {
  pname = "openram";
  version = "1.2.49";
  pyproject = true;

  src = pkgs.fetchFromGitHub {
    owner = "VLSIDA";
    repo = "OpenRAM";
    rev = "b2b069ce119d1488cbe6883b2240bceb5c7ce29a";
    sha256 = "01pxwly22k57yqc1fxpwyw8rb648fh7vccl5fz2a9fs0lk0nmx32";
  };

  nativeBuildInputs = [
    pkgs.makeWrapper
    python.pkgs.setuptools
    python.pkgs.wheel
  ];

  propagatedBuildInputs = with python.pkgs; [
    numpy
    scipy
    scikit-learn
    coverage
  ];

  # OpenRAM uses a private Nix devShell/conda by default. Use the tools
  # provided by this derivation instead.
  postPatch = ''
    substituteInPlace compiler/options.py \
      --replace-fail "use_nix = True" "use_nix = False"

    # scn4m_subm does not define the ROM interconnect layers, but
    # compiler/modules/rom_bank.py imports them unconditionally.
    echo 'lef_rom_interconnect = ["m1", "m2", "m3", "m4"]' \
      >> technology/scn4m_subm/tech/tech.py
  '';

  # The test suite needs PDKs and a writable technology directory.
  doCheck = false;
  dontCheckRuntimeDeps = true;

  postInstall = ''
    # Keep the full source tree (Makefiles, technology and macros) so it can
    # be used to generate custom memories and set up PDK-specific libraries.
    mkdir -p $out/share/openram
    cp -r compiler technology macros $out/share/openram/
    for file in \
      LICENSE README.md VERSION Makefile openram.mk setpaths.sh \
      requirements.txt __init__.py common.py \
      sram_compiler.py rom_compiler.py sram_char.py sram_func.py; do
      cp "$file" $out/share/openram/
    done

    for tool in sram_compiler rom_compiler; do
      makeWrapper ${python.interpreter} $out/bin/$tool \
        --add-flags "$out/share/openram/$tool.py" \
        --prefix PYTHONPATH : \
          "${pythonEnv}/${python.sitePackages}:$out/${python.sitePackages}" \
        --prefix PATH : "${lib.makeBinPath openram_tools}" \
        --set OPENRAM_HOME "$out/share/openram/compiler" \
        --set OPENRAM_TECH "$out/share/openram/technology"
    done

    # Expose OpenRAM and its tools to shells that include this package.
    mkdir -p $out/nix-support
    cat > $out/nix-support/setup-hook <<EOF
    export OPENRAM_SRC="$out/share/openram"
    export OPENRAM_HOME="''${OPENRAM_HOME:-$out/share/openram/compiler}"
    export OPENRAM_TECH="''${OPENRAM_TECH:-$out/share/openram/technology}"
    export PATH="${lib.makeBinPath openram_tools}:$out/bin:''${PATH:-}"
    EOF
  '';

  meta = {
    description = "Open-source static random access memory (SRAM) compiler";
    homepage = "https://openram.org/";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.linux;
  };
}

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

  # Sky130 SRAM library cells (separate repo from Google)
  sky130_sram_lib = pkgs.fetchFromGitHub {
    owner = "google";
    repo = "skywater-pdk-libs-sky130_fd_bd_sram";
    rev = "be33adbcf188fdeab5c061699847d9d440f7a084";
    sha256 = "0a6ndz4xl3laqync9m3bfn23njacbz5j2pnbg4i9wn1lpivxi75k";
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

    # Fix regex in hierarchy_spice.py to match .subckt anywhere in file
    substituteInPlace compiler/base/hierarchy_spice.py \
      --replace-fail 're.compile("^.subckt {}".format(self.cell_name), re.IGNORECASE)' \
      're.compile("^.subckt {}".format(self.cell_name), re.IGNORECASE | re.MULTILINE)'

    # Fix sp_file path in hierarchy_spice.py: sp_lib has subdirectories for each cell
    # sky130 cells are in sp_lib/<cell_subdir>/<cell_name>.sp where cell_subdir is cell_name without "sky130_fd_bd_sram__" prefix
    substituteInPlace compiler/base/hierarchy_spice.py \
      --replace-fail 'self.sp_file = OPTS.openram_tech + "sp_lib/" + cell_name + ".sp"' \
      'self.sp_file = OPTS.openram_tech + "sp_lib/" + cell_name.replace("sky130_fd_bd_sram__", "") + "/" + cell_name + ".sp"'

    # Fix lvs_file path: use .lvs.spice file for LVS verification (not GDS)
    substituteInPlace compiler/base/hierarchy_spice.py \
      --replace-fail 'self.lvs_file = self.sp_file' \
      'self.lvs_file = OPTS.openram_tech + "sp_lib/" + cell_name.replace("sky130_fd_bd_sram__", "") + "/" + cell_name + ".lvs.spice"'

    # Fix sky130 tech.py: port_order and port_map must match library subckt pin order
    # Library 2port bitcell: .subckt sky130_fd_bd_sram__openram_dp_cell BL0 BL1 BR0 BR1 GND VDD WL0 WL1
    # Library 1port bitcell (opt1): .subckt sky130_fd_bd_sram__sram_sp_cell_opt1 BL BR VGND VPWR VPB VNB WL
    ${python.interpreter} << 'EOF'
import re

with open('technology/sky130/tech/tech.py', 'r') as f:
    content = f.read()

# Fix 2port bitcell port_order (first occurrence only)
content = re.sub(
    r"cell_properties\.bitcell_2port\.port_order = \['bl0', 'br0', 'bl1', 'br1', 'wl0', 'wl1', 'vdd', 'gnd'\]",
    "cell_properties.bitcell_2port.port_order = ['bl0', 'bl1', 'br0', 'br1', 'gnd', 'vdd', 'wl0', 'wl1']",
    content,
    count=1
)

# Fix 2port bitcell port_map (first occurrence only) - replace the entire multi-line dict
content = re.sub(
    r"cell_properties\.bitcell_2port\.port_map = \{[^}]+\}",
    "cell_properties.bitcell_2port.port_map = {'bl0': 'BL0', 'bl1': 'BL1', 'br0': 'BR0', 'br1': 'BR1', 'wl0': 'WL0', 'wl1': 'WL1', 'vdd': 'VDD', 'gnd': 'GND'}",
    content,
    count=1
)

# Fix 1port bitcell port_map (first occurrence only) - use VGND/VPWR to match spice file
content = re.sub(
    r"cell_properties\.bitcell_1port\.port_map = \{[^}]+\}",
    "cell_properties.bitcell_1port.port_map = {'bl': 'BL', 'br': 'BR', 'gnd': 'VGND', 'vdd': 'VPWR', 'vpb': 'VPB', 'vnb': 'VNB', 'wl': 'WL'}",
    content,
    count=1
)

with open('technology/sky130/tech/tech.py', 'w') as f:
    f.write(content)
EOF

    # Fix import_tech in globals.py:
    # 1. Don't prepend wrong path from openram.__file__ (replace the += line with comment)
    # 2. Don't add trailing ":" which causes empty path in split (replace the += ":" line with pass)
    substituteInPlace compiler/globals.py \
      --replace-fail 'OPENRAM_TECH += os.path.dirname(openram.__file__) + "/technology"' \
      'pass  # OPENRAM_TECH is already set correctly by wrapper/setup-hook; do not prepend wrong path'

    substituteInPlace compiler/globals.py \
      --replace-fail 'OPENRAM_TECH += ":"' \
      'pass  # Keep OPENRAM_TECH as-is; do not add trailing colon'
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

    # Copy sky130 technology files to installed package for sky130 SRAM support
    mkdir -p $out/share/openram/technology/sky130
    cp -r technology/sky130/tech $out/share/openram/technology/sky130/
    mkdir -p $out/share/openram/technology/sky130/sp_lib
    mkdir -p $out/share/openram/technology/sky130/gds_lib
    # Copy sky130 library cells from fetched source
    cp -r ${sky130_sram_lib}/cells/* $out/share/openram/technology/sky130/sp_lib/ 2>/dev/null || true
    cp -r ${sky130_sram_lib}/cells/* $out/share/openram/technology/sky130/gds_lib/ 2>/dev/null || true

    # Make sp_lib writable and create .sp symlinks for all .spice files
    # (OpenRAM expects .sp extension, library uses .spice)
    chmod -R u+w $out/share/openram/technology/sky130/sp_lib
    find $out/share/openram/technology/sky130/sp_lib -name "*.spice" | while read spice_file; do
      sp_file="''${spice_file%.spice}.sp"
      if [ ! -e "$sp_file" ]; then
        ln -sf "$(basename "$spice_file")" "$sp_file"
      fi
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
#!/bin/bash
set -euo pipefail

# Parametri da personalizzare
# Percorso agli esempi Geant4 dentro il container
G4_EXAMPLE_DIR="${G4_EXAMPLE_DIR:-/opt/geant4/share/Geant4/examples/basic/B5}"
# Nome della build dir relativa alla initialdir
BUILD_DIR="${BUILD_DIR:-build_condor}"

echo "[BUILD] Start: $(date)"
echo "[BUILD] Host:  $(hostname)"
echo "[BUILD] User:  $(whoami)"
echo "[BUILD] Pwd:   $(pwd)"
echo "[BUILD] G4_EXAMPLE_DIR = ${G4_EXAMPLE_DIR}"
echo "[BUILD] BUILD_DIR      = ${BUILD_DIR}"
echo

# Ambiente (ridondante se la SIF li sourcia già, ma innocuo)
if [[ -f /opt/geant4/bin/geant4.sh ]]; then
  echo "[BUILD] Sourcing Geant4..."
  source /opt/geant4/bin/geant4.sh
fi
if [[ -f /opt/root/bin/thisroot.sh ]]; then
  echo "[BUILD] Sourcing ROOT..."
  source /opt/root/bin/thisroot.sh
fi

mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

echo "[BUILD] Now in: $(pwd)"

if [[ -f CMakeCache.txt ]]; then
  echo "[BUILD] CMakeCache.txt already present, reconfiguring is usually not needed."
fi

echo "[BUILD] Running CMake..."
cmake "${G4_EXAMPLE_DIR}"

echo "[BUILD] Building..."
cmake --build . -- -j"$(nproc)"

echo
echo "[BUILD] Done: $(date)"

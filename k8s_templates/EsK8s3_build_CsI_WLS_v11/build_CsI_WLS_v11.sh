#!/bin/bash
set -euo pipefail

echo "[CsI-BUILD] Start: $(date)"
echo "[CsI-BUILD] Node:  $(hostname)"
echo "[CsI-BUILD] User:  $(whoami)"
echo "[CsI-BUILD] Pwd:   $(pwd)"
echo

if [[ -f /opt/geant4/bin/geant4.sh ]]; then
  echo "[CsI-BUILD] Sourcing Geant4..."
  source /opt/geant4/bin/geant4.sh
fi
if [[ -f /opt/root/bin/thisroot.sh ]]; then
  echo "[CsI-BUILD] Sourcing ROOT..."
  source /opt/root/bin/thisroot.sh
fi

SRC_DIR="src"
BUILD_DIR="build"

echo "[CsI-BUILD] SRC_DIR   = ${SRC_DIR}"
echo "[CsI-BUILD] BUILD_DIR = ${BUILD_DIR}"
echo

if [[ ! -d "${SRC_DIR}" ]]; then
  echo "[CsI-BUILD] ERROR: sorgenti non trovate in ${SRC_DIR}"
  exit 1
fi

mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

echo "[CsI-BUILD] Now in build dir: $(pwd)"

if [[ -x CsI-WLS ]]; then
  echo "[CsI-BUILD] CsI-WLS already built, skipping cmake/cmake --build."
else
  echo "[CsI-BUILD] Configuring with CMake..."
  cmake "../${SRC_DIR}"

  echo "[CsI-BUILD] Building CsI-WLS..."
  cmake --build . -- -j"$(nproc)"
fi

if [[ ! -x CsI-WLS ]]; then
  echo "[CsI-BUILD] ERROR: CsI-WLS binary not found after build."
  exit 1
fi

echo
echo "[CsI-BUILD] Done: $(date)"

#!/bin/bash
set -euo pipefail

echo "[K8S-B5] Start: $(date)"
echo "[K8S-B5] Node:  $(hostname)"
echo "[K8S-B5] User:  $(whoami)"
echo "[K8S-B5] Pwd:   $(pwd)"
echo

# Script di ambiente (in caso l'immagine non abbia un entrypoint che li sorga già)
if [[ -f /opt/geant4/bin/geant4.sh ]]; then
  echo "[K8S-B5] Sourcing Geant4..."
  source /opt/geant4/bin/geant4.sh
fi
if [[ -f /opt/root/bin/thisroot.sh ]]; then
  echo "[K8S-B5] Sourcing ROOT..."
  source /opt/root/bin/thisroot.sh
fi

SRC_DIR="/opt/geant4/share/Geant4/examples/basic/B5"
BUILD_DIR="B5_build_k8s"
MACRO="${SRC_DIR}/run1.mac"

echo "[K8S-B5] SRC_DIR   = ${SRC_DIR}"
echo "[K8S-B5] BUILD_DIR = ${BUILD_DIR}"
echo "[K8S-B5] MACRO     = ${MACRO}"
echo

mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"
echo "[K8S-B5] Now in build dir: $(pwd)"

if [[ -x exampleB5 ]]; then
  echo "[K8S-B5] exampleB5 already built, skipping CMake/cmake --build."
else
  echo "[K8S-B5] Running CMake..."
  cmake "${SRC_DIR}"

  echo "[K8S-B5] Building..."
  cmake --build . -- -j"$(nproc)"
fi

if [[ ! -x exampleB5 ]]; then
  echo "[K8S-B5] ERROR: exampleB5 not found after build."
  exit 1
fi

echo
echo "[K8S-B5] Running exampleB5 with macro: ${MACRO}"
./exampleB5 "${MACRO}"

echo
echo "[K8S-B5] ROOT files under $(pwd):"
find . -maxdepth 3 -type f -name '*.root' -print || echo "[K8S-B5] Nessun .root trovato."

echo
echo "[K8S-B5] Done: $(date)"

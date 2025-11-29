#!/bin/bash
set -euo pipefail

# ========= Parametri configurabili (via environment o editando il file) =========

# Directory dell'esempio Geant4 dentro il container
# (esempio B5: /opt/geant4/share/Geant4/examples/basic/B5)
G4_EXAMPLE_DIR="${G4_EXAMPLE_DIR:-/opt/geant4/share/Geant4/examples/basic/B5}"

# Directory di build relativa alla initialdir
BUILD_DIR="${BUILD_DIR:-B5_build_condor}"

# Nome dell'eseguibile prodotto dalla build (per B5: exampleB5)
EXEC_NAME="${EXEC_NAME:-exampleB5}"

# Macro da usare per il run (path ASSOLUTO o RELATIVO nel container)
# Per B5 tipico: /opt/geant4/share/Geant4-11.3.1/examples/basic/B5/run1.mac
MACRO_PATH="${MACRO_PATH:-${G4_EXAMPLE_DIR}/run1.mac}"

# ========= Inizio script =========

echo "[BUILD+RUN] Start: $(date)"
echo "[BUILD+RUN] Host:      $(hostname)"
echo "[BUILD+RUN] User:      $(whoami)"
echo "[BUILD+RUN] Pwd:       $(pwd)"
echo "[BUILD+RUN] G4_EXAMPLE_DIR = ${G4_EXAMPLE_DIR}"
echo "[BUILD+RUN] BUILD_DIR      = ${BUILD_DIR}"
echo "[BUILD+RUN] EXEC_NAME      = ${EXEC_NAME}"
echo "[BUILD+RUN] MACRO_PATH     = ${MACRO_PATH}"
echo

# Ambiente (ridondante se la SIF lo fa già, ma innocuo)
if [[ -f /opt/geant4/bin/geant4.sh ]]; then
  echo "[BUILD+RUN] Sourcing Geant4..."
  # shellcheck disable=SC1091
  source /opt/geant4/bin/geant4.sh
fi

if [[ -f /opt/root/bin/thisroot.sh ]]; then
  echo "[BUILD+RUN] Sourcing ROOT..."
  # shellcheck disable=SC1091
  source /opt/root/bin/thisroot.sh
fi

# --- BUILD ---

mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

echo "[BUILD+RUN] Now in build dir: $(pwd)"

if [[ -x "${EXEC_NAME}" ]]; then
  echo "[BUILD+RUN] ${EXEC_NAME} already built, skipping CMake/cmake --build."
else
  echo "[BUILD+RUN] Running CMake..."
  cmake "${G4_EXAMPLE_DIR}"

  echo "[BUILD+RUN] Building ${EXEC_NAME}..."
  cmake --build . -- -j"$(nproc)"
fi

if [[ ! -x "${EXEC_NAME}" ]]; then
  echo "[BUILD+RUN] ERROR: binary ${EXEC_NAME} not found after build."
  exit 1
fi

# --- RUN ---

echo
echo "[BUILD+RUN] Running ${EXEC_NAME} with macro: ${MACRO_PATH}"
./"${EXEC_NAME}" "${MACRO_PATH}"

echo
echo "[BUILD+RUN] ROOT files under $(pwd):"
find . -maxdepth 3 -type f -name '*.root' -print || echo "[BUILD+RUN] Nessun .root trovato."

echo
echo "[BUILD+RUN] Done at $(date)"

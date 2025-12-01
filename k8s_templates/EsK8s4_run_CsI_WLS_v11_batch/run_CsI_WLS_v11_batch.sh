#!/bin/bash
set -euo pipefail

echo "[CsI-K8s] Start @ $(date)"
echo "[CsI-K8s] Pod : ${HOSTNAME}"
echo "[CsI-K8s] BATCH_TAG=${BATCH_TAG:-undefined}"
echo "[CsI-K8s] Pwd : $(pwd)"
echo

if [[ -f /opt/geant4/bin/geant4.sh ]]; then
  echo "[CsI-K8s] Sourcing Geant4..."
  source /opt/geant4/bin/geant4.sh
fi
if [[ -f /opt/root/bin/thisroot.sh ]]; then
  echo "[CsI-K8s] Sourcing ROOT..."
  source /opt/root/bin/thisroot.sh
fi

# Directory dove EsK8s3 ha compilato CsI-WLS
CSI_BUILD_DIR="/lustrehome/bob/k8s_tests/EsK8s3_build_CsI_WLS_v11/build"
CSI_SRC_DIR="/lustrehome/bob/k8s_tests/EsK8s3_build_CsI_WLS_v11/src"

echo "[CsI-K8s] Using build dir: ${CSI_BUILD_DIR}"
echo "[CsI-K8s] Using src dir  : ${CSI_SRC_DIR}"
echo

if [[ ! -x "${CSI_BUILD_DIR}/CsI-WLS" ]]; then
  echo "[CsI-K8s] ERROR: CsI-WLS non trovato in ${CSI_BUILD_DIR}."
  echo "           Eseguire prima il job EsK8s3_build_CsI_WLS_v11."
  exit 1
fi
if [[ ! -f "${CSI_SRC_DIR}/run_electrons_batch.py" ]]; then
  echo "[CsI-K8s] ERROR: run_electrons_batch.py non trovato in ${CSI_SRC_DIR}."
  exit 1
fi

cd "${CSI_BUILD_DIR}"
echo "[CsI-K8s] Now in: $(pwd)"

# Passiamo BATCH_TAG allo script Python (opzionale, per personalizzare i nomi dei file)
export BATCH_TAG

echo "[CsI-K8s] Launching Python batch..."
python3 "${CSI_SRC_DIR}/run_electrons_batch.py"

echo
echo "[CsI-K8s] ROOT files under $(pwd):"
find . -maxdepth 4 -type f -name '*.root' -print || echo "[CsI-K8s] Nessun .root trovato."

echo
echo "[CsI-K8s] Done @ $(date)"

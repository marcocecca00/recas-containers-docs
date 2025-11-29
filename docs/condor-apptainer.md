# HTCondor + Apptainer

## Introduzione

Questa guida descrive in modo operativo come usare immagini Apptainer/Singularity (file `.sif`) insieme a HTCondor sul cluster ReCaS.

L’idea di fondo è che nel gruppo ci sia almeno un utente **manutentore** (che chiameremo `alice`) che può costruire immagini Docker su una macchina dedicata (ad esempio una macchina con Docker come `tesla02`), convertirle in immagini Apptainer/Singularity e metterle a disposizione di tutti in una posizione condivisa su lustre.

Gli altri utenti (ad esempio `bob`) non devono occuparsi della parte Docker: si limitano a usare le immagini `.sif` già pronte all’interno dei job Condor, tramite *symlink* verso la directory condivisa di `alice`.

Per rendere le cose concrete, assumiamo che nella directory condivisa di `alice` siano presenti due immagini Apptainer:

```bash
/lustrehome/alice/apptainer_images/G4_v10.6.3_NOMULTITHREAD.sif
/lustrehome/alice/apptainer_images/G4_v11.3.1.sif
```

Queste immagini contengono Ubuntu 24.04, Geant4, ROOT, Python3 con numpy e matplotlib. In particolare l’immagine `G4_v10.6.3_NOMULTITHREAD.sif` ha il multithreading disattivato per Geant4 ed è adatta ad applicazioni che richiedono esecuzione single–thread.

La struttura logica è:

- [Concetti di base](#concetti-di-base-container-apptainer-e-htcondor)
- [Organizzazione delle directory](#organizzazione-delle-directory)
- [Esempi](#esempi) (cinque casi completi)

---

## Concetti di base: container, Apptainer e HTCondor

Un **container** è un ambiente software isolato, definito da un’immagine che contiene un sistema operativo minimale (ad esempio Ubuntu), le librerie e le applicazioni necessarie.

Quando si avvia un container, il programma viene eseguito in quell’ambiente software, indipendentemente dal sistema operativo del nodo fisico. Nel nostro caso un’immagine `.sif` contiene Geant4, ROOT, Python e le relative dipendenze, così che un job Condor non deve installare o configurare nulla: trova tutto già predisposto.

Su ReCaS i container sono gestiti da **Apptainer** (discendente di Singularity), progettato per ambienti HPC multiutente. Un’immagine Apptainer è un file in sola lettura; durante il job, Apptainer:

1. monta il filesystem dell’immagine;
2. monta la directory di lavoro dell’utente (su lustre);
3. esegue il comando richiesto all’interno del container, con il filesystem dell’utente disponibile.

Questo è più leggero di una macchina virtuale perché il kernel rimane quello del nodo, mentre il container fornisce solo lo strato utente.

HTCondor si occupa di:

1. trovare un worker node compatibile;
2. creare la directory di lavoro del job;
3. avviare Apptainer con l’immagine indicata;
4. far girare lo script/eseguibile richiesto nel container.

Dal punto di vista di chi scrive il file di submit Condor, i parametri chiave sono tre: `initialdir`, `executable` e `container_image`.

- `initialdir` è la directory sul filesystem di lustre che rappresenta la cartella di lavoro del job. Condor la monta nel container come current working directory (CWD), quindi tutto ciò che viene scritto in CWD o in sottocartelle relative finisce direttamente in questa directory su lustre.

- `executable` è lo script o l’eseguibile che verrà lanciato all’interno del container. Deve trovarsi nella `initialdir` o in una sua sottocartella ed è specificato con un percorso relativo (es. `executable = run_B5_exec.sh`).

- `container_image` indica quale immagine Apptainer usare. I test sul cluster hanno mostrato che Condor si aspetta che `container_image` sia il **nome di un file presente nella `initialdir`**. Per questo, anche se l’immagine “vera” vive in una directory centrale (es. `/lustrehome/alice/apptainer_images`), per ogni job conviene creare nella `initialdir` un symlink locale all’immagine e poi usare nel submit il nome del symlink.

Esempio tipico nella directory del job di `bob`:

```bash
ln -sf /lustrehome/alice/apptainer_images/G4_v11.3.1.sif        G4_v11.3.1.sif
```

e nel file di submit:

```bash
container_image = G4_v11.3.1.sif
```

In questo modo Condor trova il file `G4_v11.3.1.sif` nella `initialdir`, avvia Apptainer con quell’immagine e monta la `initialdir` all’interno del container. Lo script `executable` viene eseguito dentro il container e la directory di lavoro corrisponde alla directory dell’utente su lustre.

Gli esempi pratici della sezione seguente non fanno altro che declinare questo schema in casi d’uso via via più complessi.

---

## Organizzazione delle directory

Per lavorare in modo ordinato conviene scegliere una convenzione semplice all’interno della propria home su lustre. Nel caso di `bob`, la directory di riferimento per i job è:

```bash
/lustrehome/bob
```

L’utente manutentore `alice` usa invece:

```bash
/lustrehome/alice
```

per ospitare le immagini condivise.

### Directory immagini condivise

Le immagini Apptainer di `alice` possono essere raccolte, ad esempio, in:

```bash
/lustrehome/alice/apptainer_images
```

dove si trovano file `.sif` come:

```bash
/lustrehome/alice/apptainer_images/G4_v11.3.1.sif
/lustrehome/alice/apptainer_images/G4_v10.6.3_NOMULTITHREAD.sif
```

### Directory dei test e dei job Condor

Per gli esempi e i job di `bob` si può usare:

```bash
/lustrehome/bob/condor_tests
```

All’interno di `condor_tests` è comodo creare sottodirectory dedicate per ciascun tipo di job, ad esempio:

- `test_container`
- `build_B5_11.3.1`
- `run_B5_11.3.1`
- `build_run_B5_11.3.1`
- `CsI-WLS_v1.2.2`

Ogni directory conterrà:

- il file di submit `.csi`;
- gli script `.sh`;
- un link locale all’immagine `.sif` (da `/lustrehome/alice/apptainer_images`);
- una sottocartella `logs/` per gli output di Condor;
- opzionalmente una `build/` per CMake.

Questa organizzazione rende chiaro dove si trova il codice sorgente, dove viene compilato il programma e dove finiscono i file prodotti dai job Condor.

---

## Esempi

In questa sezione sono riportati cinque esempi completi che illustrano come utilizzare immagini Apptainer/Singularity in combinazione con HTCondor.

Gli esempi seguono un ordine progressivo, dal test più semplice fino a un caso realistico con un progetto Geant4 personalizzato:

1. **Esempio 1** – test minimale dell’immagine `.sif` per verificare la versione di Geant4, ROOT e Python e controllare che il container venga avviato correttamente su un worker node.
2. **Esempio 2** – compilazione dell’esempio Geant4 B5 all’interno del container utilizzando CMake.
3. **Esempio 3** – esecuzione di un binario Geant4 precompilato con una macro, in un job dedicato.
4. **Esempio 4** – compilazione ed esecuzione dell’esempio B5 nello stesso job HTCondor, utile quando si vuole una build “pulita” per ogni run.
5. **Esempio 5** – caso realistico con il progetto CsI-WLS, che prevede build con CMake e un batch di simulazioni pilotato da uno script Python.

I template completi degli script `.sh` e dei file di submit `.csi` utilizzati negli esempi sono disponibili in un repository o in un’area condivisa (nel tuo caso puoi usare lo stesso link SharePoint che hai indicato nel PDF).

---

### Esempio 1: test dell'immagine Geant4

Scopo: verificare che l’immagine `G4_v11.3.1.sif` funzioni correttamente su un worker node e che Geant4/ROOT/Python siano visibili nel container.

Crea la directory del test e la sottocartella per i log:

```bash
cd /lustrehome/bob
mkdir -p condor_tests/test_container/logs
cd condor_tests/test_container
```

Crea un link all’immagine condivisa di `alice`:

```bash
ln -sf /lustrehome/alice/apptainer_images/G4_v11.3.1.sif        G4_v11.3.1.sif
```

Crea `test_container.sh`:

```bash
#!/bin/bash
set -euo pipefail

echo "[TEST] Start: $(date)"
echo "[TEST] Host:  $(hostname)"
echo "[TEST] User:  $(whoami)"
echo "[TEST] Pwd:   $(pwd)"
echo

echo "[TEST] Environment snippet:"
echo "  G4INSTALL=${G4INSTALL:-undefined}"
echo "  G4VERSION=${G4VERSION:-undefined}"
echo "  ROOTSYS=${ROOTSYS:-undefined}"
echo

echo "[TEST] Checking Geant4 / ROOT / Python..."
command -v geant4-config  >/dev/null 2>&1 &&   geant4-config --version || echo "geant4-config NOT found"
command -v root-config    >/dev/null 2>&1 &&   root-config --version   || echo "root-config NOT found"
command -v python3        >/dev/null 2>&1 &&   python3 --version       || echo "python3 NOT found"
echo

python3 - << 'EOF'
import sys, platform
print("Python:", sys.version.split()[0])
print("Platform:", platform.platform())
EOF

echo
echo "[TEST] Done: $(date)"
```

Rendilo eseguibile:

```bash
chmod +x test_container.sh
```

Crea `test_container.csi`:

```bash
universe        = vanilla

initialdir      = /lustrehome/bob/condor_tests/test_container

executable      = test_container.sh
arguments       =

container_image = G4_v11.3.1.sif

request_cpus    = 1
request_memory  = 1 GB
request_disk    = 4 GB

output          = logs/test_$(ClusterId).$(ProcId).out
error           = logs/test_$(ClusterId).$(ProcId).err
log             = logs/test_$(ClusterId).$(ProcId).log

queue 1
```

Sottometti:

```bash
condor_submit test_container.csi
```

Quando il job è completato, in `logs/test_...out` troverai hostname, utente, CWD, variabili di ambiente e versioni dei software. Questo conferma che l’immagine è utilizzabile con HTCondor secondo lo schema di base.

---

### Esempio 2: build dell’esempio B5 di Geant4

Scopo: compilare l’esempio B5 di Geant4 usando l’immagine `G4_v11.3.1.sif` e ottenere l’eseguibile `exampleB5` in una directory di build.

Crea la directory di build:

```bash
cd /lustrehome/bob
mkdir -p condor_tests/build_B5_11.3.1/logs
cd condor_tests/build_B5_11.3.1
```

Symlink all’immagine:

```bash
ln -sf /lustrehome/alice/apptainer_images/G4_v11.3.1.sif        G4_v11.3.1.sif
```

Script `build_B5_exec.sh`:

```bash
#!/bin/bash
set -euo pipefail

echo "[BUILD] Start: $(date)"
echo "[BUILD] Host:  $(hostname)"
echo "[BUILD] User:  $(whoami)"
echo "[BUILD] Pwd:   $(pwd)"
echo

SRC_DIR="/opt/geant4/share/Geant4/examples/basic/B5"
BUILD_DIR="B5_build_condor"

echo "[BUILD] SRC_DIR   = ${SRC_DIR}"
echo "[BUILD] BUILD_DIR = ${BUILD_DIR}"
echo

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

echo "[BUILD] Running CMake..."
cmake "${SRC_DIR}"

echo "[BUILD] Building..."
cmake --build . -- -j"$(nproc)"

echo
echo "[BUILD] Done: $(date)"
```

Rendilo eseguibile:

```bash
chmod +x build_B5_exec.sh
```

File di submit `build_B5_11.3.1.csi`:

```bash
universe        = vanilla

initialdir      = /lustrehome/bob/condor_tests/build_B5_11.3.1

executable      = build_B5_exec.sh
arguments       =

container_image = G4_v11.3.1.sif

request_cpus    = 4
request_memory  = 4 GB
request_disk    = 8 GB

output          = logs/build_$(ClusterId).$(ProcId).out
error           = logs/build_$(ClusterId).$(ProcId).err
log             = logs/build_$(ClusterId).$(ProcId).log

queue 1
```

Sottometti:

```bash
condor_submit build_B5_11.3.1.csi
```

A fine job, in `/lustrehome/bob/condor_tests/build_B5_11.3.1/B5_build_condor` trovi i file CMake e l’eseguibile `exampleB5`. Questo verrà riutilizzato nell’esempio successivo.

---

### Esempio 3: run dell’esempio B5

Scopo: riutilizzare `exampleB5` compilato in precedenza e farne il run con una macro in un job dedicato.

Crea la directory di run:

```bash
cd /lustrehome/bob
mkdir -p condor_tests/run_B5_11.3.1/logs
cd condor_tests/run_B5_11.3.1
```

Symlink all’immagine:

```bash
ln -sf /lustrehome/alice/apptainer_images/G4_v11.3.1.sif        G4_v11.3.1.sif
```

Copia eseguibile e macro:

```bash
cp /lustrehome/bob/condor_tests/build_B5_11.3.1/B5_build_condor/exampleB5 .
cp /lustrehome/bob/condor_tests/build_B5_11.3.1/B5_build_condor/run1.mac .
```

Script `run_B5_exec.sh`:

```bash
#!/bin/bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <exec_rel_path> <macro_rel_path>"
  echo "Example: $0 exampleB5 run1.mac"
  exit 1
fi

EXEC_REL="$1"
MACRO_REL="$2"

echo "[RUN] Start: $(date)"
echo "[RUN] Host:  $(hostname)"
echo "[RUN] User:  $(whoami)"
echo "[RUN] Pwd:   $(pwd)"
echo "[RUN] Exec:  ${EXEC_REL}"
echo "[RUN] Macro: ${MACRO_REL}"
echo

if [[ -f /opt/geant4/bin/geant4.sh ]]; then
  echo "[RUN] Sourcing Geant4..."
  source /opt/geant4/bin/geant4.sh
fi
if [[ -f /opt/root/bin/thisroot.sh ]]; then
  echo "[RUN] Sourcing ROOT..."
  source /opt/root/bin/thisroot.sh
fi

EXEC_PATH="./${EXEC_REL}"
MACRO_PATH="./${MACRO_REL}"

if [[ ! -x "${EXEC_PATH}" ]]; then
  echo "[RUN] ERROR: executable not found or not executable: ${EXEC_PATH}"
  exit 1
fi
if [[ ! -f "${MACRO_PATH}" ]]; then
  echo "[RUN] ERROR: macro not found: ${MACRO_PATH}"
  exit 1
fi

echo "[RUN] Launching: ${EXEC_PATH} ${MACRO_PATH}"
"${EXEC_PATH}" "${MACRO_PATH}"

echo
echo "[RUN] Done: $(date)"
```

Rendilo eseguibile:

```bash
chmod +x run_B5_exec.sh
```

File di submit `run_B5_11.3.1.csi`:

```bash
universe        = vanilla

initialdir      = /lustrehome/bob/condor_tests/run_B5_11.3.1

executable      = run_B5_exec.sh
arguments       = exampleB5 run1.mac

container_image = G4_v11.3.1.sif

request_cpus    = 1
request_memory  = 2 GB
request_disk    = 4 GB

output          = logs/run_$(ClusterId).$(ProcId).out
error           = logs/run_$(ClusterId).$(ProcId).err
log             = logs/run_$(ClusterId).$(ProcId).log

queue 1
```

Sottometti:

```bash
condor_submit run_B5_11.3.1.csi
```

Gli output prodotto da B5 vengono scritti in `/lustrehome/bob/condor_tests/run_B5_11.3.1`, cioè la directory di lavoro montata nel container.

---

### Esempio 4: build e run di B5 in un unico job

Scopo: compilare B5 e lanciarlo subito, all’interno dello stesso job Condor.

Crea la directory:

```bash
cd /lustrehome/bob
mkdir -p condor_tests/build_run_B5_11.3.1/logs
cd condor_tests/build_run_B5_11.3.1
```

Symlink all’immagine:

```bash
ln -sf /lustrehome/alice/apptainer_images/G4_v11.3.1.sif        G4_v11.3.1.sif
```

Script `build_run_B5_exec.sh`:

```bash
#!/bin/bash
set -euo pipefail

echo "[BUILD+RUN] Start: $(date)"
echo "[BUILD+RUN] Host:  $(hostname)"
echo "[BUILD+RUN] User:  $(whoami)"
echo "[BUILD+RUN] Pwd:   $(pwd)"
echo

SRC_DIR="/opt/geant4/share/Geant4/examples/basic/B5"
BUILD_DIR="B5_build_condor"
MACRO="${SRC_DIR}/run1.mac"

echo "[BUILD+RUN] SRC_DIR   = ${SRC_DIR}"
echo "[BUILD+RUN] BUILD_DIR = ${BUILD_DIR}"
echo "[BUILD+RUN] MACRO     = ${MACRO}"
echo

if [[ -f /opt/geant4/bin/geant4.sh ]]; then
  echo "[BUILD+RUN] Sourcing Geant4..."
  source /opt/geant4/bin/geant4.sh
fi

if [[ -f /opt/root/bin/thisroot.sh ]]; then
  echo "[BUILD+RUN] Sourcing ROOT..."
  source /opt/root/bin/thisroot.sh
fi

mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

echo "[BUILD+RUN] Now in: $(pwd)"

if [[ -x exampleB5 ]]; then
  echo "[BUILD+RUN] exampleB5 already built, skipping CMake/cmake --build."
else
  echo "[BUILD+RUN] Running CMake..."
  cmake "${SRC_DIR}"

  echo "[BUILD+RUN] Building..."
  cmake --build . -- -j"$(nproc)"
fi

if [[ ! -x exampleB5 ]]; then
  echo "[BUILD+RUN] ERROR: build failed, exampleB5 not found."
  exit 1
fi

echo
echo "[BUILD+RUN] Running exampleB5 with macro: ${MACRO}"
./exampleB5 "${MACRO}"

echo
echo "[BUILD+RUN] ROOT files under $(pwd):"
find . -maxdepth 3 -type f -name '*.root' -print ||   echo "[BUILD+RUN] Nessun .root trovato."

echo
echo "[BUILD+RUN] Done: $(date)"
```

Rendilo eseguibile:

```bash
chmod +x build_run_B5_exec.sh
```

File di submit `build_run_B5_11.3.1.csi`:

```bash
universe        = vanilla

initialdir      = /lustrehome/bob/condor_tests/build_run_B5_11.3.1

executable      = build_run_B5_exec.sh
arguments       =

container_image = G4_v11.3.1.sif

request_cpus    = 4
request_memory  = 4 GB
request_disk    = 8 GB

output          = logs/build_run_$(ClusterId).$(ProcId).out
error           = logs/build_run_$(ClusterId).$(ProcId).err
log             = logs/build_run_$(ClusterId).$(ProcId).log

queue 1
```

Sottometti:

```bash
condor_submit build_run_B5_11.3.1.csi
```

A fine job, in `B5_build_condor` trovi sia il risultato della build, sia i file output del run.

---

### Esempio 5: progetto CsI-WLS con Python

Scopo: build di un’applicazione Geant4 personalizzata (CsI-WLS) con CMake e lancio di un batch di simulazioni pilotato da uno script Python, usando l’immagine `G4_v10.6.3_NOMULTITHREAD.sif`.

Assumiamo che il progetto CsI-WLS esista già come:

```bash
/lustrehome/bob/ADAPT/simulation/CsI-WLS_v1.2.2
```

con una sottodirectory `source` contenente CMakeLists e codice.

Per rendere il job auto-contenuto dentro `condor_tests`:

```bash
cd /lustrehome/bob/condor_tests
mkdir -p CsI-WLS_v1.2.2
cp -r /lustrehome/bob/ADAPT/simulation/CsI-WLS_v1.2.2/source CsI-WLS_v1.2.2/
cd CsI-WLS_v1.2.2
mkdir -p logs
```

Symlink all’immagine:

```bash
ln -sf /lustrehome/alice/apptainer_images/G4_v10.6.3_NOMULTITHREAD.sif        G4_v10.6.3_NOMULTITHREAD.sif
```

Nella directory `source` definisci lo script Python (si aspetta di essere eseguito da dentro `build`, dove esiste `./CsI-WLS`):

```python
import numpy as np
import os
import matplotlib.pyplot as plt  # non usato, ma non da fastidio

DIR_MAC = "./mac_electron"
DIR_ROOT = "rootOutput_electron"

N_EVENTS = 10
subdir = "random_rectangular_source_200keV"
nfiles = 50

for k in range(nfiles):
    seed1, seed2 = np.random.randint(0, 2**32, size=2)

    mac = (f"{DIR_MAC}/{subdir}/"
           f"random_rectangular_source_electron_ene_"
           f"200keV_ly1_n{k}.mac")
    root = mac.replace(DIR_MAC, DIR_ROOT).replace(".mac", "")

    os.makedirs(os.path.dirname(mac),  exist_ok=True)
    os.makedirs(os.path.dirname(root), exist_ok=True)

    with open(mac, "w") as f:
        f.write(
            "/run/initialize\n"
            "/tracking/verbose 0\n"
            "/gps/particle e-\n"
            "/gps/position 0 0 0 mm\n"
            "/gps/direction 0 0 -1\n"
            f"/random/setSeeds [{seed1} {seed2}]\n"
            "/gps/pos/type Plane\n"
            "/gps/pos/shape Rectangle\n"
            "/gps/pos/halfx 220 mm\n"
            "/gps/pos/halfy 220 mm\n"
            "/gps/ene/mono 200 keV\n"
            f"/RunManager/NameOfOutputFile {root}\n"
            f"/run/beamOn {N_EVENTS}\n"
        )

    os.system(f"./CsI-WLS {mac}")

print(f"\n {N_EVENTS*nfiles} eventi salvati in "
      f"{DIR_MAC}/{subdir} e simulati con ./CsI-WLS")
```

Salva questo file come `source/run_electrons_batch.py`.

Nella root di `CsI-WLS_v1.2.2` definisci lo script `run_CsI_WLS_electron_batch.sh`:

```bash
#!/bin/bash
set -euo pipefail

echo "[PYRUN] Start: $(date)"
echo "[PYRUN] Host: $(hostname)"
echo "[PYRUN] User: $(whoami)"
echo "[PYRUN] Pwd:  $(pwd)"
echo

if [[ -f /opt/geant4/bin/geant4.sh ]]; then
  echo "[PYRUN] Sourcing Geant4..."
  source /opt/geant4/bin/geant4.sh
fi
if [[ -f /opt/root/bin/thisroot.sh ]]; then
  echo "[PYRUN] Sourcing ROOT..."
  source /opt/root/bin/thisroot.sh
fi

BUILD_DIR="build"
SRC_DIR="source"

mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

echo "[PYRUN] Now in build dir: $(pwd)"

if [[ -x CsI-WLS ]]; then
  echo "[PYRUN] CsI-WLS already built, skipping cmake/cmake --build."
else
  echo "[PYRUN] Configuring with CMake..."
  cmake "../${SRC_DIR}"

  echo "[PYRUN] Building CsI-WLS..."
  cmake --build . -- -j"$(nproc)"
fi

if [[ ! -x CsI-WLS ]]; then
  echo "[PYRUN] ERROR: CsI-WLS binary not found after build."
  exit 1
fi

echo
echo "[PYRUN] Running Python batch script..."
python3 ../source/run_electrons_batch.py

echo
echo "[PYRUN] ROOT files under rootOutput_electron/:"
find rootOutput_electron -maxdepth 3 -type f -name '*.root' -print   || echo "[PYRUN] Nessun .root trovato."

echo
echo "[PYRUN] Done at $(date)"
```

Rendilo eseguibile:

```bash
chmod +x run_CsI_WLS_electron_batch.sh
```

File di submit `CsI_WLS_python_electrons.csi`:

```bash
universe        = vanilla

initialdir      = /lustrehome/bob/condor_tests/CsI-WLS_v1.2.2

executable      = run_CsI_WLS_electron_batch.sh
arguments       =

container_image = G4_v10.6.3_NOMULTITHREAD.sif

request_cpus    = 1
request_memory  = 2 GB
request_disk    = 16 GB

output          = logs/pyCsI_$(ClusterId).$(ProcId).out
error           = logs/pyCsI_$(ClusterId).$(ProcId).err
log             = logs/pyCsI_$(ClusterId).$(ProcId).log

queue 1
```

Sottometti:

```bash
cd /lustrehome/bob/condor_tests/CsI-WLS_v1.2.2
condor_submit CsI_WLS_python_electrons.csi
```

A fine job, nella directory `build` compaiono:

- l’eseguibile `CsI-WLS`;
- le macro generate dallo script Python;
- gli output ROOT (ad esempio in `build/rootOutput_electron/random_rectangular_source_200keV`).

Tutto è salvato su lustre dentro `/lustrehome/bob/condor_tests/CsI-WLS_v1.2.2`.

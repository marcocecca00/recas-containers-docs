# Uso di immagini Apptainer/Singularity con HTCondor su ReCaS

## **Introduzione**

Questa guida descrive in modo operativo come usare immagini Apptainer/Singularity (file `.sif`) insieme a HTCondor sul cluster ReCaS. L’idea di fondo è che ci sia almeno un utente “manutentore” (che chiameremo `alice`) che possa costruire immagini Docker su una macchina dedicata, convertirle in immagini Apptainer/Singularity e metterle a disposizione di tutti in una posizione condivisa su lustre. Gli altri utenti (ad esempio `bob`) non devono occuparsi della parte Docker: si limitano a usare le immagini `.sif` già pronte all’interno dei job Condor, tramite *symlink* verso la directory condivisa di `alice`.

Nel seguito useremo come esempio un utente chiamato `bob` per i job Condor, mentre `alice` rappresenterà l’utente che ospita le immagini condivise. Per rendere gli esempi concreti, si assume che siano già presenti due immagini Apptainer nella directory condivisa di `alice`:

```bash
/lustrehome/alice/apptainer_images/G4_v10.6.3_NOMULTITHREAD.sif
/lustrehome/alice/apptainer_images/G4_v11.3.1.sif
```

Queste immagini contengono Ubuntu 24.04, Geant4, ROOT, Python3 con numpy e matplotlib. In particolare l’immagine `G4_v10.6.3_NOMULTITHREAD.sif` ha il multithreading disattivato per Geant4 ed è adatta ad applicazioni che richiedono esecuzione single-thread.

La sezione [Concetti di base: container, Apptainer e HTCondor](#sec-concetti-base) introduce i concetti di base su container, Apptainer e HTCondor, mentre la sezione [Organizzazione delle directory](#sec-organizzazione) propone una convenzione semplice per organizzare le directory su lustre dal punto di vista di `bob`.

La sezione [Esempi](#sec-esempi) illustra cinque esempi completi di utilizzo: test dell’immagine, build dell’esempio B5 di Geant4, run di B5, build+run in un unico job e un caso reale con una simulazione Geant di una tile scintillante tra due piani di fibre WLS (CsI-WLS) e Python.

La sezione [Costruzione di un’immagine Docker e conversione in SIF](#sec-docker-sif) mostra come costruire e convertire immagini Docker in `.sif`, mentre la sezione [Prospettive: uso di Kubernetes con container](#sec-kubernetes) è prevista come estensione futura.

In Appendice, la sezione [Dockerfile di esempio per ambiente Geant4/ROOT](#sec-dockerfile-esempio) contiene un Dockerfile di esempio.

Per comodità, la sezione [Immagini Docker / Apptainer disponibili su ReCaS](#sec-images)
riporta un elenco aggiornato delle immagini attualmente disponibili e dei relativi percorso reali su lustre, che possono essere riutilizzate come base per nuovi workflow.


---

## **Concetti di base: container, Apptainer e HTCondor** {#sec-concetti-base}

Prima di entrare negli esempi conviene chiarire cosa si intende per container e come Apptainer interagisce con HTCondor nel contesto del cluster ReCaS.

Un container è un ambiente software isolato, definito da un’immagine che contiene un sistema operativo minimale (ad esempio Ubuntu), le librerie e le applicazioni necessarie. Quando si avvia un container, il programma viene eseguito con quell’ambiente software, indipendentemente dal sistema operativo del nodo fisico. Nel nostro caso un’immagine `.sif` contiene Geant4, ROOT, Python e le relative dipendenze, così che un job Condor non deve installare o configurare nulla: trova tutto già predisposto.

Su ReCaS i container sono gestiti da Apptainer (discendente di Singularity), progettato per ambienti HPC multiutente. Un’immagine Apptainer è un file in sola lettura; durante il job, Apptainer monta il filesystem dell’immagine e allo stesso tempo monta la directory di lavoro dell’utente, in modo che il programma possa leggere e scrivere i propri file su lustre. Questo approccio è più leggero di una macchina virtuale, perché il kernel del sistema è condiviso e si avvia solo lo strato utente.

HTCondor si occupa di individuare i worker node disponibili, preparare la directory di lavoro e avviare Apptainer. Dal punto di vista dell’utente, la cosa fondamentale è capire il ruolo di tre parametri nel file di submit: `initialdir`, `executable` e `container_image`.

- La direttiva `initialdir` indica la directory sul filesystem di lustre che rappresenta la cartella di lavoro del job. Condor monta questa directory nel container come current working directory (CWD), quindi tutto ciò che viene scritto in CWD o in sottocartelle relative finisce direttamente in questa directory su lustre.
- La direttiva `executable` indica lo script o l’eseguibile che verrà lanciato all’interno del container. Deve trovarsi nella `initialdir` o in una sua sottocartella ed è specificato nel file di submit con un percorso relativo.
- La direttiva `container_image` indica quale immagine Apptainer usare. I test effettuati sul cluster hanno mostrato un comportamento pratico importante: Condor si aspetta che il valore di `container_image` sia il nome di un file presente nella `initialdir`. Per questa ragione, anche se l’immagine “reale” vive in una directory centrale, per ogni job conviene creare nella `initialdir` un symlink locale all’immagine e poi usare nel submit il nome del symlink (ad esempio un symlink a `/lustrehome/alice/apptainer_images/immagine.sif`).

In pratica, quando Condor avvia Apptainer, la `initialdir` viene montata nel container come directory di lavoro corrente: non c’è copia dei file, tutto ciò che il job legge o scrive in CWD (e nelle sottocartelle relative) finisce direttamente sulla stessa directory di lustre.

!!! warning " Attenzione: comportamento specifico di ReCaS"

    Il requisito che `container_image` debba essere il nome di un file presente nella
    `initialdir` (tipicamente un symlink verso la `.sif` reale su lustre) è legato alla
    configurazione di HTCondor su ReCaS. Al momento questa è la modalità supportata e
    testata; in futuro potrebbero essere aggiunti anche path assoluti o altri meccanismi
    per individuare l’immagine del container.

!!! tip "Cosa fa davvero HTCondor con `container_image`"

    Quando nel file di submit si imposta:

    ```text
    container_image = G4_v11.3.1.sif
    ```

    dal punto di vista pratico HTCondor, sul worker node, fa qualcosa di
    **equivalente** a:

    ```bash
    apptainer exec G4_v11.3.1.sif ./script_che_hai_messo_in_executable.sh
    ```
    *(oppure `singularity exec` a seconda del runtime disponibile).*

    Questo significa che:
    
    - l’ambiente dentro il container è lo stesso che avresti lanciando
      `apptainer exec` a mano da shell;
    - le variabili d’ambiente e i PATH di Geant4/ROOT **non vengono magicamente
      settati da Condor**, ma solo:
      - da eventuali script di entrypoint dell’immagine;
      - oppure da quello che fai tu nello `executable` (ad es.):
        ```bash
        source /opt/geant4/bin/geant4.sh
        source /opt/root/bin/thisroot.sh
        ```
    
    Per questo, in tutti gli esempi della guida, gli script `*.sh` eseguiti
    come `executable` fanno esplicitamente il `source` degli script di ambiente
    di Geant4 e ROOT all’inizio.

Un esempio tipico è il seguente. Nella directory del job di `bob` si crea un link all’immagine condivisa di `alice`:

```bash
ln -sf /lustrehome/alice/apptainer_images/G4_v11.3.1.sif G4_v11.3.1.sif
```

e nel file di submit si scrive:

```bash
container_image = G4_v11.3.1.sif
```

In questo modo Condor trova il file `G4_v11.3.1.sif` nella `initialdir`, avvia Apptainer con quell’immagine e monta la `initialdir` all’interno del container. Da quel momento in poi lo script `executable` viene eseguito dentro il container e la directory di lavoro corrisponde alla directory dell’utente su lustre.

Gli esempi pratici della sezione [Esempi](#sec-esempi) non fanno altro che declinare questo schema base in casi d’uso via via più complessi.

---

## **Organizzazione delle directory** {#sec-organizzazione}

Per lavorare in modo ordinato conviene scegliere una convenzione semplice all’interno della propria home su lustre. Nel caso di `bob`, la directory di riferimento per i job è `/lustrehome/bob`, mentre l’utente manutentore `alice` usa `/lustrehome/alice` per ospitare le immagini condivise.

Le immagini Apptainer condivise dal manutentore possono essere raccolte in una directory dedicata, ad esempio `/lustrehome/alice/apptainer_images`. In questa directory si collocano i file `.sif` che `alice` ha costruito o recuperato. Nel nostro esempio vi si trovano `G4_v11.3.1.sif` e `G4_v10.6.3_NOMULTITHREAD.sif`.

Per gli esempi e i job Condor di `bob` si può usare una directory `condor_tests`. All’interno di `condor_tests` è utile creare sottodirectory dedicate per ciascun tipo di job. Ogni directory contiene i file di submit `.csi`, gli script `.sh`, un link locale all’immagine `.sif` (proveniente da `/lustrehome/alice/apptainer_images`) e una sottocartella `logs/` per gli output di Condor. Questa struttura rende chiaro dove si trova il codice sorgente, dove viene compilato il programma e dove finiscono i file prodotti dai job Condor, seguendo lo schema introdotto in [Concetti di base: container, Apptainer e HTCondor](#sec-concetti-base) e utilizzato in tutti gli esempi successivi.

!!! example " Esempio di gerarchia tipica su lustre"

    Una possibile organizzazione delle directory per `alice` (manutentore) e `bob`
    (utente che sottomette i job) può essere:

    ```text
    /lustrehome/alice/
      apptainer_images/
        G4_v11.3.1.sif
        G4_v10.6.3_NOMULTITHREAD.sif

    /lustrehome/bob/
      condor_tests/
        test_container/
          logs/
          G4_v11.3.1.sif -> /lustrehome/alice/apptainer_images/G4_v11.3.1.sif
          test_container.sh
          test_container.csi

        build_B5_11.3.1/
          logs/
          G4_v11.3.1.sif -> /lustrehome/alice/apptainer_images/G4_v11.3.1.sif
          build_B5_exec.sh
          build_B5_11.3.1.csi
          B5_build_condor/      # directory di build creata dal job

        run_B5_11.3.1/
          logs/
          G4_v11.3.1.sif -> /lustrehome/alice/apptainer_images/G4_v11.3.1.sif
          run_B5_exec.sh
          run_B5_11.3.1.csi
          exampleB5
          run1.mac
          # file di output prodotti da B5
    ```

    In questa configurazione:

    - `alice` mantiene tutte le immagini `.sif` in un’unica directory centrale;
    - `bob` crea, per ogni tipo di job, una directory dedicata con i file `.csi`,
      gli script `.sh`, una sottocartella `logs/` e un symlink locale all’immagine `.sif`.

---

## **Esempi** {#sec-esempi}

In questa sezione sono riportati cinque esempi completi che illustrano come utilizzare immagini Apptainer/Singularity in combinazione con HTCondor. Gli esempi seguono un ordine progressivo, dal test più semplice fino a un caso realistico con un progetto Geant4 personalizzato:

- **Esempio [1](#sec-esempio1)** – test minimale dell’immagine `.sif` per verificare la versione di Geant4, ROOT e Python e controllare che il container venga avviato correttamente su un worker node;
- **Esempio [2](#sec-esempio2)** – compilazione dell’esempio Geant4 B5 all’interno del container utilizzando CMake;
- **Esempio [3](#sec-esempio3)** – esecuzione di un binario Geant4 precompilato con una macro, in un job dedicato;
- **Esempio [4](#sec-esempio4)** – compilazione ed esecuzione dell’esempio B5 nello stesso job HTCondor, utile quando si vuole una build “pulita” per ogni run;
- **Esempio [5](#sec-esempio5)** – caso realistico con il progetto CsI-WLS, che prevede build con CMake e un batch di simulazioni pilotato da uno script Python.

I template completi degli script `.sh` e dei file di submit `.csi` utilizzati negli esempi successivi sono disponibili nella cartella
[`templates/`](https://github.com/marcocecca00/recas-containers-docs/tree/master/templates) del repository GitHub.

In particolare:

- [`Es1_test_container`](https://github.com/marcocecca00/recas-containers-docs/tree/master/templates/Es1_test_container)
- [`Es2_build_geant_project`](https://github.com/marcocecca00/recas-containers-docs/tree/master/templates/Es2_build_geant_project)
- [`Es3_run_geant_exec`](https://github.com/marcocecca00/recas-containers-docs/tree/master/templates/Es3_run_geant_exec)
- [`Es4_build_and_run_geant_example`](https://github.com/marcocecca00/recas-containers-docs/tree/master/templates/Es4_build_and_run_geant_example)
- [`Es5_build_and_run_python`](https://github.com/marcocecca00/recas-containers-docs/tree/master/templates/Es5_build_and_run_python)



---

### Esempio 1: test dell'immagine Geant4 {#sec-esempio1}

Il primo esempio ha lo scopo di verificare che l’immagine `G4_v11.3.1.sif` funzioni correttamente su un worker node. L’obiettivo è sapere su quale nodo gira il job, quali versioni di Geant4, ROOT e Python sono visibili dall’interno del container e se l’ambiente è coerente.

Si inizia creando la directory del test e una sottocartella per i log:

```bash
cd /lustrehome/bob
mkdir -p condor_tests/test_container/logs
cd condor_tests/test_container
```

Si crea un link all’immagine condivisa di `alice`:

```bash
ln -sf /lustrehome/alice/apptainer_images/G4_v11.3.1.sif \
       G4_v11.3.1.sif
```

Lo script `test_container.sh`, che sarà eseguito dentro il container, può essere definito come segue:

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
command -v geant4-config  >/dev/null 2>&1 && \
  geant4-config --version || echo "geant4-config NOT found"
command -v root-config    >/dev/null 2>&1 && \
  root-config --version   || echo "root-config NOT found"
command -v python3        >/dev/null 2>&1 && \
  python3 --version       || echo "python3 NOT found"
echo

python3 - << 'EOF'
import sys, platform
print("Python:", sys.version.split()[0])
print("Platform:", platform.platform())
EOF

echo
echo "[TEST] Done: $(date)"
```

Lo script va reso eseguibile:

```bash
chmod +x test_container.sh
```

Il file di submit `test_container.csi` specifica la directory iniziale, lo script da eseguire e l’immagine da usare:

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

La sottomissione avviene con:

```bash
condor_submit test_container.csi
```

Quando il job è completato, il file `logs/test_...out` contiene le informazioni stampate dallo script: il nome del worker node, l’utente, la directory di lavoro, le variabili di ambiente e le versioni dei software principali. Questo conferma che l’immagine è correttamente utilizzabile con HTCondor secondo lo schema introdotto in [Concetti di base: container, Apptainer e HTCondor](#sec-concetti-base).

!!! warning " Job in HOLD: controlli rapidi"

    Se il job va in stato **HOLD** subito dopo la sottomissione, controllare:

    - **Symlink alla `.sif`**  
      Verificare che il link non sia rotto:
      ```bash
      ls -l G4_v11.3.1.sif
      ```
      Deve puntare a `/lustrehome/alice/apptainer_images/G4_v11.3.1.sif` (o percorso equivalente).

    - **Esistenza e permessi dell’immagine reale**  
      Controllare che il file reale esista e sia leggibile:
      ```bash
      ls -l /lustrehome/alice/apptainer_images/G4_v11.3.1.sif
      ```

    - **Coerenza del nome in `container_image`**  
      Nel file di submit, il valore di:
      ```text
      container_image = G4_v11.3.1.sif
      ```
      deve coincidere esattamente con il nome del file presente nella `initialdir`.

    - **Percorso corretto di `initialdir`**  
      Verificare che la directory indicata da `initialdir` esista e contenga sia
      lo script `executable` sia il symlink all’immagine.


---

### Esempio 2: build dell’esempio B5 di Geant4 {#sec-esempio2}

Il secondo esempio mostra come compilare l’esempio B5 di Geant4 usando l’immagine `G4_v11.3.1.sif`. L’obiettivo è ottenere l’eseguibile `exampleB5` in una directory di build gestita dal job.

Si crea la directory del test di build:

```bash
cd /lustrehome/bob
mkdir -p condor_tests/build_B5_11.3.1/logs
cd condor_tests/build_B5_11.3.1
```

Si collega l’immagine condivisa:

```bash
ln -sf /lustrehome/alice/apptainer_images/G4_v11.3.1.sif G4_v11.3.1.sif
```

Lo script `build_B5_exec.sh` viene eseguito dentro il container e si occupa di configurare e compilare il progetto:

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

Lo script viene reso eseguibile:

```bash
chmod +x build_B5_exec.sh
```

Il file di submit `build_B5_11.3.1.csi` è:

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

Il job si sottomette con:

```bash
condor_submit build_B5_11.3.1.csi
```

Al termine della compilazione, nella directory `/lustrehome/bob/condor_tests/build_B5_11.3.1/B5_build_condor` si trovano i file di CMake e l’eseguibile `exampleB5`. Lo standard output del job contiene i messaggi di CMake e l’esito del build, che verrà riutilizzato nella sezione [Esempio 3: run dell’esempio B5](#sec-esempio3).

---

### Esempio 3: run dell’esempio B5 {#sec-esempio3}

Il terzo esempio riutilizza l’eseguibile `exampleB5` compilato in [Esempio 2: build dell’esempio B5 di Geant4](#sec-esempio2) e mostra come preparare una directory di run separata, in cui copiare l’eseguibile e le macro e lanciare la simulazione.

Si crea la directory per il run:

```bash
cd /lustrehome/bob
mkdir -p condor_tests/run_B5_11.3.1/logs
cd condor_tests/run_B5_11.3.1
```

Si collega l’immagine:

```bash
ln -sf /lustrehome/alice/apptainer_images/G4_v11.3.1.sif G4_v11.3.1.sif
```

Si copiano l’eseguibile e la macro `run1.mac` dalla build:

```bash
cp /lustrehome/bob/condor_tests/build_B5_11.3.1/B5_build_condor/exampleB5 .
cp /lustrehome/bob/condor_tests/build_B5_11.3.1/B5_build_condor/run1.mac .
```

Lo script `run_B5_exec.sh` lancia l’eseguibile con la macro:

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

Lo script va reso eseguibile:

```bash
chmod +x run_B5_exec.sh
```

Il file di submit `run_B5_11.3.1.csi` utilizza lo script, l’immagine e specifica le risorse richieste:

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

La sottomissione avviene come nei casi precedenti:

```bash
condor_submit run_B5_11.3.1.csi
```

Gli output prodotti da B5 vengono scritti nella directory `/lustrehome/bob/condor_tests/run_B5_11.3.1`, che corrisponde alla directory di lavoro del job dentro il container, e rimangono quindi disponibili all’utente anche dopo la fine dell’esecuzione.

---

### Esempio 4: build e run di B5 in un unico job {#sec-esempio4}

In alcune situazioni è comodo compilare il codice e far partire subito il run all’interno dello stesso job Condor. Questo permette di avere un singolo file di submit per l’intera catena e di garantire che il run utilizzi esattamente la build prodotta nel job.

Per questo esempio si crea una nuova directory:

```bash
cd /lustrehome/bob
mkdir -p condor_tests/build_run_B5_11.3.1/logs
cd condor_tests/build_run_B5_11.3.1
```

Si collega l’immagine Geant4 11.3.1:

```bash
ln -sf /lustrehome/alice/apptainer_images/G4_v11.3.1.sif G4_v11.3.1.sif
```

Lo script `build_run_B5_exec.sh` esegue prima la compilazione dell’esempio B5 e subito dopo l’eseguibile con una macro di esempio:

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
find . -maxdepth 3 -type f -name '*.root' -print || \
  echo "[BUILD+RUN] Nessun .root trovato."

echo
echo "[BUILD+RUN] Done: $(date)"
```

Lo script viene reso eseguibile:

```bash
chmod +x build_run_B5_exec.sh
```

Il file di submit `build_run_B5_11.3.1.csi` è il seguente:

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

La sottomissione avviene con:

```bash
condor_submit build_run_B5_11.3.1.csi
```

Alla conclusione del job, la directory `B5_build_condor` contiene sia i file generati da CMake, sia l’eseguibile `exampleB5`, sia i file di output del run (ad esempio file ROOT). Tutti questi file risiedono in `/lustrehome/bob/condor_tests/build_run_B5_11.3.1/B5_build_condor` e sono quindi accessibili per analisi successive.

---

### Esempio 5: progetto CsI-WLS con Python {#sec-esempio5}

L’ultimo esempio mostra una situazione più vicina a un caso reale, in cui un’applicazione Geant4 custom (CsI-WLS) viene compilata da sorgente con CMake e poi eseguita molte volte con parametri diversi, gestiti da uno script Python. Per questo caso si sfrutta l’immagine `G4_v10.6.3_NOMULTITHREAD.sif`, che contiene Geant4 10.6.3 senza multithreading, ROOT 6.36.4 e Python3 con le librerie principali.

Si assume che il progetto CsI-WLS esista già in una directory di sviluppo, ad esempio `/lustrehome/bob/ADAPT/simulation/CsI-WLS_v1.2.2`, che contiene una sottodirectory `src` con i file CMake e il codice. Per rendere il job auto-contenuto dentro `condor_tests` si copia solo la directory `src`:

```bash
cd /lustrehome/bob/condor_tests
mkdir -p CsI-WLS_v1.2.2
cp -r /lustrehome/bob/ADAPT/simulation/CsI-WLS_v1.2.2/src CsI-WLS_v1.2.2/
cd CsI-WLS_v1.2.2
mkdir -p logs
```

Si crea il link all’immagine senza multithreading di `alice`:

```bash
ln -sf /lustrehome/alice/apptainer_images/G4_v10.6.3_NOMULTITHREAD.sif G4_v10.6.3_NOMULTITHREAD.sif
```

Nella directory `src` si definisce lo script Python che si aspetta di essere eseguito da dentro `build` (dove esiste `./CsI-WLS`). Questo script genera un certo numero di macro, ognuna con un seed diverso, e per ciascuna macro lancia l’eseguibile:

```python
import numpy as np
import os
import matplotlib.pyplot as plt 

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

Questo file può essere salvato come `src/run_electrons_batch.py` all’interno della copia di CsI-WLS sotto `condor_tests`.

Nella root della directory `CsI-WLS_v1.2.2` si definisce lo script `run_CsI_WLS_electron_batch.sh`, che compila il progetto nella directory `build` e poi lancia lo script Python:

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
SRC_DIR="src"

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
find rootOutput_electron -maxdepth 3 -type f -name '*.root' -print \
  || echo "[PYRUN] Nessun .root trovato."

echo
echo "[PYRUN] Done at $(date)"
```

Lo script va reso eseguibile:

```bash
chmod +x run_CsI_WLS_electron_batch.sh
```

Infine si definisce il file di submit `CsI_WLS_python_electrons.csi`:

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

La sottomissione avviene con:

```bash
cd /lustrehome/bob/condor_tests/CsI-WLS_v1.2.2
condor_submit CsI_WLS_python_electrons.csi
```

Quando il job è terminato, nella directory `build` compaiono l’eseguibile `CsI-WLS`, le macro generate dallo script Python e gli output ROOT. Tutti questi file sono salvati su lustre dentro `/lustrehome/bob/condor_tests/CsI-WLS_v1.2.2`.

---

## **Costruzione di un’immagine Docker e conversione in SIF** {#sec-docker-sif}

Gli esempi della sezione [Esempi](#sec-esempi) assumono che le immagini `.sif` siano già disponibili in una cartella condivisa, gestita dall’utente `alice`. Questa sezione descrive in modo sintetico come costruire un’immagine Docker con Geant4, ROOT e Python, come convertirla in un’immagine Apptainer/Singularity e come distribuirla agli altri utenti, senza entrare nei dettagli dei singoli comandi di installazione del software all’interno del container.

La costruzione di immagini Docker richiede una macchina con Docker installato e accessibile, ad esempio le macchine come `tesla02.recas.infn.ba.it`. Un utente può connettersi a quella macchina con le stesse credenziali delle macchine di frontend `ui-al9.recas.infn.ba.it`, preparare un `Dockerfile` e costruire l’immagine. Un esempio completo di `Dockerfile` per un ambiente Ubuntu 24.04 con Geant4, ROOT e Python3 è riportato in appendice, nella sezione [Dockerfile di esempio per ambiente Geant4/ROOT](#sec-dockerfile-esempio).

!!! info " Dove gira Docker su ReCaS"

    Attualmente Docker è installato solo sulla macchina
    `tesla02.recas.ba.infn.it`. Per usarlo occorre prima collegarsi da una
    delle macchine di frontend:

    ```bash
    ssh username@tesla02.recas.ba.infn.it
    ```

    Al primo accesso viene creata automaticamente la home locale su `tesla02`.
    Tutta la fase di build e test interattivo delle immagini Docker va fatta su
    `tesla02`; le immagini poi vengono caricate sul registry
    `registry-clustergpu.recas.ba.infn.it` e da lì convertite in immagini
    Apptainer/Singularity utilizzabili con HTCondor sui worker node.

Una volta scritto il `Dockerfile`, l’utente manutentore può costruire l’immagine con un comando del tipo:

```bash
docker build -t registry-clustergpu.recas.ba.infn.it/alice/geant4:10.6.3 .
```

In seguito, l’immagine può essere inviata al registry interno, dove le credenziali sono le stesse del frontend:

```bash
docker login registry-clustergpu.recas.ba.infn.it
docker push registry-clustergpu.recas.ba.infn.it/alice/geant4:10.6.3
```

La conversione da immagine Docker a immagine Apptainer/Singularity deve avvenire un worker node dove Apptainer è installato e eseguire il comando `build`. Un esempio di comando è:

```bash
apptainer build G4_v10.6.3.sif docker://registry-clustergpu.recas.ba.infn.it/alice/geant4:10.6.3
```

Il file `G4_v10.6.3.sif` così generato può essere copiato o spostato nella directory condivisa delle immagini:

```bash
mv G4_v10.6.3.sif /lustrehome/alice/apptainer_images/
```

Dopo questo passaggio, tutti gli utenti (come `bob`) possono usare l’immagine nei propri job Condor creando un symlink nella `initialdir` e impostando `container_image` al nome del symlink, come mostrato nella sezione [Concetti di base: container, Apptainer e HTCondor](#sec-concetti-base) e negli esempi.

!!! tip "Tip"

    Sia la build della immagine Docker che la conversione in `.sif` può anche essere fatta in locale sul proprio pc e poi copiata su una directory accessibile su lustrehome. 

### Comandi essenziali Docker

Non è necessario che ogni utente conosca Docker in dettaglio, ma è utile riassumere i comandi più usati nel ciclo di vita di un’immagine. La costruzione da `Dockerfile` nella directory corrente avviene di solito con:

```bash
docker build -t nome_immagine:tag .
```

Per visualizzare le immagini locali si può usare:

```bash
docker images
```

Per testare interattivamente un’immagine, ad esempio verificando che gli script di ambiente siano corretti, si può avviare un container con:

```bash
docker run -it nome_immagine:tag
```

Infine, per taggare e inviare un’immagine verso il registry remoto, si possono usare comandi del tipo:

```bash
docker tag nome_immagine:tag registry-clustergpu.recas.ba.infn.it/alice/nome_immagine:tag

docker push registry-clustergpu.recas.ba.infn.it/alice/nome_immagine:tag
```

Questi comandi vengono eseguiti sulla macchina che ha Docker installato, come `tesla02.recas.infn.ba.it`.

### Comandi essenziali Apptainer/Singularity

Apptainer viene utilizzato sia per testare manualmente le immagini sia in maniera indiretta tramite HTCondor. Per un test rapido si può eseguire un comando dentro un’immagine `.sif` con:

```bash
apptainer exec G4_v11.3.1.sif geant4-config --version
```

Per aprire una shell interattiva nel container si può usare:

```bash
apptainer shell G4_v11.3.1.sif
```

La conversione da immagine Docker a `.sif` avviene, come già mostrato, con:

```bash
apptainer build G4_v11.3.1.sif \
  docker://registry-clustergpu.recas.ba.infn.it/alice/geant4:11.3.1
```

I job Condor che usano `container_image` nascondono questi dettagli, perché è il sistema a chiamare internamente Apptainer. Tuttavia, conoscere questi comandi aiuta a testare rapidamente un’immagine su una macchina di frontend prima di costruire i file `.csi`, come quelli della sezione [Esempi](#sec-esempi).

---

## **Prospettive: uso di Kubernetes con container** {#sec-kubernetes}

*(TODO)*

---

## **Immagini Docker / Apptainer disponibili su ReCaS** {#sec-images}

Questa sezione elenca alcune immagini già presenti sul registry di ReCaS o su
lustre che possono essere riutilizzate come base per nuovi progetti.  
L’elenco non è esaustivo e va considerato come “fotografia” dello stato attuale:
nel tempo possono essere aggiunte nuove immagini o aggiornate le versioni.

| # | Docker image                                                     | Singularity/Apptainer path                                      | Contenuto principale                                              | Note |
|---|------------------------------------------------------------------|------------------------------------------------------------------|-------------------------------------------------------------------|------|
| 1 | `federicacuna/herd_centos07_devtoolset11_root:v2`                | –                                                                | CentOS 7 + devtoolset-11 + ROOT, ambiente per HerdSoftware        | Immagine su Docker Hub/registry esterno. |
| 2 | `megalib-3.06`                                                   | –                                                                | MEGAlib 3.06 con tutte le dipendenze necessarie                   | Usata per simulazioni MEGAlib. |
| 3 | `registry-clustergpu.recas.ba.infn.it/marcocecca/geant4:10.6.3`  | `/lustrehome/marcocecca/apptainer_images/G4_v10.6.3.sif`        | Ubuntu 24.04 + Geant4 10.6.3 + ROOT 6.36.4 + Python3/numpy/matplotlib | Dati Geant4 inclusi; env Geant4/ROOT inizializzato all’apertura del container. |
| 4 | `registry-clustergpu.recas.ba.infn.it/marcocecca/geant4:10.6.3_NOMULTITHREAD` | `/lustrehome/marcocecca/apptainer_images/G4_v10.6.3_NOMULTITHREAD.sif` | Come (3), ma con Geant4 10.6.3 compilato senza multithreading | Adatta a job single-thread (uno per core) con HTCondor. |
| 5 | `registry-clustergpu.recas.ba.infn.it/marcocecca/geant4:11.3.1`  | `/lustrehome/marcocecca/apptainer_images/G4_v11.3.1.sif`        | Ubuntu 24.04 + Geant4 11.3.1 + ROOT 6.36.4 + Python3/numpy/matplotlib | Dati Geant4 inclusi; env Geant4/ROOT inizializzato all’apertura del container. |

Se si utilizza una di queste immagini come base per nuovi workflow, è buona pratica:

- documentare nel proprio progetto quale **tag** specifico si sta usando;
- generare nuove immagini con tag/versioni diverse quando servono modifiche significative;
- mantenere questa sezione aggiornata nel tempo, aggiungendo righe per nuove immagini “ufficiali”.

## **Appendice**

### Dockerfile di esempio per ambiente Geant4/ROOT {#sec-dockerfile-esempio}

In questa sezione è riportato un esempio completo di `Dockerfile` per costruire un’immagine Docker basata su Ubuntu 24.04, con Geant4, ROOT e Python3. Il risultato atteso è un’immagine che espone gli script di environment `/opt/geant4/bin/geant4.sh` e `/opt/root/bin/thisroot.sh` e che può essere convertita in un file `.sif` come descritto nella sezione [Costruzione di un’immagine Docker e conversione in SIF](#sec-docker-sif).

!!! warning " USERNAME, USERID e GROUPID vanno modificati"

    Nel Dockerfile di esempio, i campi:
    ```docker
    ENV USERNAME=alice
    ENV USERID=000001
    ENV GROUPID=1234
    ```
    sono solo **segnaposto**. Prima di eseguire `docker build` vanno sostituiti con:
    
    - il proprio nome utente su ReCaS (`USERNAME`),
    - il proprio UID numerico (`USERID`),
    - il proprio GID numerico (`GROUPID`).

    I valori corretti si ottengono, dalle macchine di frontend con:
    ```bash
    id
    # uid=881525(alice) gid=2435(alice) groups=...
    ```

    L’uso di un utente reale all’interno del container (con UID/GID coerenti a quelli
    del cluster) è **richiesto dai manuali ufficiali di ReCaS** per garantire
    che i file scritti dal container abbiano permessi corretti su lustre.

```docker
FROM ubuntu:24.04

LABEL author="marcocecca"
LABEL version="G4v11.3.1_Rootv6.36.4_Ubuntu24"

# ===========================
# Env Geant4 + ROOT (base)
# ===========================
ENV DEBIAN_FRONTEND=noninteractive TZ=Etc/UTC

ENV G4VERSION=11.3.1
ENV G4INSTALL=/opt/geant4
ENV G4DATA_DIR=$G4INSTALL/share/Geant4/data
ENV G4LIB_DIR=$G4INSTALL/lib
ENV G4GDMLROOT=$G4INSTALL

# ROOT
ENV ROOT_VERSION=6.36.04
ENV ROOTSYS=/opt/root

# ==========================================
# Dipendenze base (Qt5 + OpenGL/X11 + ROOT + Python + Vdt)
# ==========================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    git \
    pkg-config \
    ca-certificates \
    wget \
    curl \
    # Geant4 + GDML
    libxerces-c-dev \
    libexpat1-dev \
    # Qt5 + OpenGL + X11
    qtbase5-dev \
    qtbase5-dev-tools \
    qt5-qmake \
    libqt5opengl5-dev \
    libx11-dev \
    libxmu-dev \
    libxi-dev \
    libxrandr-dev \
    libxinerama-dev \
    libxcursor-dev \
    libgl1-mesa-dev \
    libglu1-mesa-dev \
    # runtime Qt/X11
    libxkbcommon-x11-0 \
    libfontconfig1 \
    libxrender1 \
    libxcb-icccm4 \
    libxcb-image0 \
    libxcb-keysyms1 \
    libxcb-render-util0 \
    libxcb-xfixes0 \
    libxcb-xinerama0 \
    # dipendenze ROOT
    libxpm-dev \
    libxft-dev \
    libssl-dev \
    libpcre3-dev \
    libgsl-dev \
    libgraphviz-dev \
    libtbb12 \
    libtbb-dev \
    libvdt-dev \
    # Python per gli script di simulazione
    python3 \
    python3-numpy \
    python3-matplotlib \
    python3-pip \
    # utility
    adduser \
 && rm -rf /var/lib/apt/lists/*

# ================================
# Mandatory ReCaS: utente reale
# ================================
ENV USERNAME=alice
ENV USERID=000001
ENV GROUPID=1234

RUN groupadd -g "$GROUPID" "$USERNAME" && \
    adduser --disabled-password --gecos '' --uid "$USERID" --gid "$GROUPID" "$USERNAME"

# ==========================================
# Sorgenti Geant4 11.3.1 (da GitLab CERN)
# ==========================================
RUN mkdir -p /opt/geant4-source /tmp/g4 && \
    cd /tmp/g4 && \
    wget https://gitlab.cern.ch/geant4/geant4/-/archive/v11.3.1/geant4-v11.3.1.tar.gz && \
    tar -xzf geant4-v11.3.1.tar.gz -C /opt/geant4-source --strip-components=1 && \
    rm -rf /tmp/g4

# ==========================================
# Build + install Geant4 (dataset inclusi)
# ==========================================
RUN mkdir -p /opt/geant4-build && cd /opt/geant4-build && \
    cmake ../geant4-source \
      -DCMAKE_INSTALL_PREFIX=${G4INSTALL} \
      -DGEANT4_BUILD_MULTITHREADED=ON \
      -DGEANT4_BUILD_CXXSTD=17 \
      -DGEANT4_INSTALL_DATA=ON \
      -DGEANT4_INSTALL_EXAMPLES=ON \
      -DGEANT4_USE_GDML=ON \
      -DGEANT4_USE_SYSTEM_EXPAT=ON \
      -DGEANT4_USE_SYSTEM_XERCESC=ON \
      -DGEANT4_USE_QT=ON \
      -DCMAKE_PREFIX_PATH=/usr/lib/x86_64-linux-gnu/cmake/Qt5 \
      -DGEANT4_USE_OPENGL_X11=ON \
      -DGEANT4_USE_XM=OFF \
      -DGEANT4_USE_RAYTRACER_X11=ON && \
    cmake --build . -j"$(nproc)" && \
    cmake --install . && \
    rm -rf /opt/geant4-build

# =================================================
# Install ROOT (precompiled per Ubuntu 24.04)
# =================================================
RUN cd /opt && \
    wget -O root.tar.gz https://root.cern/download/root_v6.36.04.Linux-ubuntu24.04-x86_64-gcc13.3.tar.gz && \
    tar -xzf root.tar.gz && \
    mv root root-${ROOT_VERSION} && \
    ln -s root-${ROOT_VERSION} root && \
    rm root.tar.gz

# =================================================
# Linker config + PATH/LD_LIBRARY_PATH globali
# =================================================
RUN echo "${G4LIB_DIR}"   > /etc/ld.so.conf.d/geant4.conf && \
    echo "${ROOTSYS}/lib" > /etc/ld.so.conf.d/root.conf && \
    ldconfig

ENV PATH=${G4INSTALL}/bin:${ROOTSYS}/bin:${PATH}
ENV LD_LIBRARY_PATH=${G4LIB_DIR}:${ROOTSYS}/lib

# ===========================
# Permessi su /opt/geant4
# ===========================
RUN chown -R "$USERNAME:$GROUPID" "$G4INSTALL"

# ======================================================
# EntryPoint: inizializza Geant4 + ROOT nel modo "giusto"
# ======================================================
RUN printf '%s\n' \
'#!/bin/bash' \
'set -e' \
'# --- Geant4 env ---' \
'G4_SH="${G4INSTALL}/bin/geant4.sh"' \
'if [ -f "$G4_SH" ]; then' \
'  OLD_G4="$(pwd)"' \
'  cd "$(dirname "$G4_SH")"' \
'  . ./geant4.sh' \
'  cd "$OLD_G4"' \
'fi' \
'# --- geant4make (opzionale, per vecchi workflow) ---' \
'if [ -f "${G4INSTALL}/share/Geant4-${G4VERSION}/geant4make/geant4make.sh" ]; then' \
'  . "${G4INSTALL}/share/Geant4-${G4VERSION}/geant4make/geant4make.sh"' \
'fi' \
'# --- ROOT env ---' \
'if [ -f "/opt/root/bin/thisroot.sh" ]; then' \
'  OLD_ROOT="$(pwd)"' \
'  cd /opt/root' \
'  . bin/thisroot.sh' \
'  cd "$OLD_ROOT"' \
'fi' \
'# --- Esegui il comando richiesto ---' \
'exec "$@"' \
> /usr/local/bin/geant4-entrypoint.sh && \
chmod +x /usr/local/bin/geant4-entrypoint.sh

WORKDIR /home/$USERNAME
USER $USERNAME

ENTRYPOINT ["/usr/local/bin/geant4-entrypoint.sh"]
CMD ["bash"]
```

### Riferimenti ufficiali ReCaS

Per dettagli aggiornati sull’uso di Docker e Dockerfile sul cluster ReCaS si
rimanda alla guida ufficiale:

- [Docker e Dockerfile su ReCaS](https://jvino.github.io/cluster-hpc-gpu-guides/guides/docker_and_dockerfile/#5-dockerfile)

La guida presente in questo documento va intesa come complemento operativo
orientato agli esempi Geant4/ROOT e all’integrazione con HTCondor, non come
sostituto della documentazione ufficiale del cluster.

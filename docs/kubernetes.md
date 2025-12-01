# Uso di Kubernetes con container su ReCaS {#sec-k8}

## Introduzione e abilitazione dell’account

Questa guida affianca la guida su Apptainer/HTCondor: l’idea è usare **gli stessi container Docker** (costruiti e testati come descritto nella guida su Apptainer/Singularity con HTCondor) anche tramite **Kubernetes** (K8s) sul cluster ReCaS.

Nel seguito useremo ancora due utenti fittizi:

- `alice`: utente “manutentore” che costruisce e pubblica le immagini Docker su  
  `registry-clustergpu.recas.ba.infn.it` (per esempio l’immagine Geant4/ROOT descritta nella sezione sulle immagini).
- `bob`: utente “normale” che vuole solo usare quelle immagini per lanciare job di simulazione.

Come per Apptainer/HTCondor, assumeremo che `alice` abbia già pubblicato almeno l’immagine:

```bash
registry-clustergpu.recas.ba.infn.it/alice/geant4:11.3.1
```

che corrisponde, lato Apptainer, all’immagine `.sif` `G4_v11.3.1.sif` elencata nella sezione  
*Immagini Docker / Apptainer disponibili su ReCaS* della guida precedente.

Con Kubernetes, invece di sottomettere job Condor che avviano Apptainer, `bob` sottomette **Job Kubernetes** che lanciano container Docker direttamente sui nodi del cluster. In pratica:

- il contenuto del container è lo stesso (Ubuntu 24.04 + Geant4 + ROOT + Python);
- cambia il “motore” che orchestra i job (Kubernetes invece di HTCondor);
- la directory `/lustrehome` rimane la sorgente di tutti i dati persistenti, montata nei Pod.

### Abilitazione a Kubernetes in pratica

Per poter usare Kubernetes, l’account di `bob` deve essere abilitato e `kubectl` deve essere configurato correttamente. I passi “ufficiali” sono descritti nel dettaglio nella guida ReCaS [Job submission using Kubernetes](https://jvino.github.io/cluster-hpc-gpu-guides/job_submission/k8s-jobs/); qui li riassumiamo in forma operativa:

1. **Account HPC/HTC attivo**  
   `bob` deve avere un account ReCaS-Bari per i servizi HPC/HTC e riuscire a collegarsi ai frontend (es. `frontend.recas.ba.infn.it`) via SSH.

2. **Richiesta di accesso a Kubernetes**  
   Una volta attivo l’account, `bob` apre un ticket tramite il sistema di supporto ReCaS chiedendo l’accesso al cluster Kubernetes HPC/GPU, come indicato nella sezione [Access to the service](https://jvino.github.io/cluster-hpc-gpu-guides/job_submission/k8s-jobs/#2-access-to-the-service) della guida ufficiale (titolo del ticket e dati richiesti sono specificati lì).

3. **Configurazione di `kubectl` e del `kubeconfig`**  
   Dopo l’abilitazione a K8s, `bob` configura il client `kubectl`:
   - crea `~/.kube/config` con il template suggerito nella guida, impostando il namespace  
     `batch-<username>` (ad es. `batch-bob`);
   - inserisce nel campo `token:` il proprio access token personale ottenuto via web.

4. **Token di accesso**  
   Il token si ottiene autenticandosi con le credenziali ReCaS sull’URL indicato nella [guida ufficiale](https://jvino.github.io/cluster-hpc-gpu-guides/job_submission/k8s-jobs/#32-access-token); il token va copiato nel `~/.kube/config` e ha una durata limitata (quando scade, `kubectl` smette di funzionare finché non si aggiorna il token). È buona pratica proteggere il file di configurazione, ad esempio con:
   ```bash
   chmod 700 ~/.kube/config
   ```

5. **Verifica della configurazione**  
   Con il token valido e il `kubeconfig` configurato, `bob` può verificare l’accesso con:
   ```bash
   kubectl get pod
   ```
   Se la configurazione è corretta, il comando risponde con un messaggio del tipo  
   `No resources found in batch-bob namespace`, che indica che `kubectl` riesce a parlare con il cluster sul namespace giusto.

Da questo punto in poi, gli esempi nelle sezioni successive presuppongono che `bob` abbia già:
- un account HPC/HTC attivo,
- l’accesso al cluster Kubernetes abilitato,
- `kubectl` funzionante sul proprio namespace.

---

## Concetti di base di Kubernetes su ReCaS {#sec-k8-concepts}

Per usare Kubernetes in modo consapevole bastano pochi concetti chiave; in questa sezione li adattiamo allo scenario tipico del cluster ReCaS.

### Oggetti principali

- **Pod**  
  È l’unità minima di esecuzione in K8s. Un Pod contiene uno o più container che condividono la stessa rete e gli stessi volumi.  
  Negli esempi useremo un solo container per Pod.

- **Job** (`kind: Job`)  
  È l’oggetto Kubernetes pensato per eseguire job batch che terminano.  
  Un Job crea uno o più Pod e considera la sua esecuzione completata quando un certo numero di Pod termina con successo.  
  Negli esempi useremo `kind: Job` a **singolo Pod** (`completions: 1` implicito).

- **Immagine Docker**  
  È la stessa immagine che `alice` ha caricato su `registry-clustergpu.recas.ba.infn.it` e che abbiamo già usato con Apptainer.  
  Nei file YAML verrà richiamata con:
  ```yaml
  image: registry-clustergpu.recas.ba.infn.it/alice/geant4:11.3.1
  ```

- **Volume / `hostPath` verso lustre**

  In molti casi è sufficiente montare l’intera `/lustrehome` nel Pod, così che:

  - all’esterno, `bob` lavora in `/lustrehome/bob/k8s_tests/...`;
  - dentro il container, il percorso è lo stesso.

  Questo si traduce in un blocco YAML del tipo:

  ```yaml
  volumes:
    - name: lustre
      hostPath:
        path: /lustrehome

  containers:
    - name: main
      volumeMounts:
        - name: lustre
          mountPath: /lustrehome
  ```

!!! tip "Stesso path dentro e fuori dal container"

    Usare `/lustrehome` come `hostPath` e `mountPath` semplifica molto il debug:
    nei log del Pod vedrai percorsi del tipo
    `/lustrehome/bob/k8s_tests/...`, esattamente gli stessi che usi da shell
    sui frontend (`ui-al9`, ecc.).

### Struttura tipica di un Job YAML

Tutti gli esempi usano una struttura YAML molto simile:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: esempio-k8s
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: main
          image: registry-clustergpu.recas.ba.infn.it/alice/geant4:11.3.1
          workingDir: /lustrehome/bob/k8s_tests/EsK8sX_esempio
          command: ["/bin/bash", "script_esempio.sh"]
          volumeMounts:
            - name: lustre
              mountPath: /lustrehome
      volumes:
        - name: lustre
          hostPath:
            path: /lustrehome
  backoffLimit: 0
```

Elementi importanti:

- `apiVersion: batch/v1` e `kind: Job`  
  Indicano che stiamo definendo un Job batch.

- `metadata.name`  
  Nome del Job; verrà usato anche nei nomi dei Pod (con un suffisso random).

- `spec.template.spec.containers`  
  Elenco dei container nel Pod.  
  Qui definiamo:
  - l’immagine Docker da usare;
  - il comando da eseguire (`/bin/bash script_esempio.sh`);
  - la directory di lavoro (`workingDir`);
  - i volumi montati.

- `restartPolicy: Never`  
  Il Pod non viene riavviato automaticamente se termina (in linea con l’uso batch).

- `volumes` e `volumeMounts`  
  Montano `/lustrehome` come volume condiviso, così che il job possa leggere/scrivere
  negli stessi percorsi visibili dai frontend.

- `backoffLimit: 0`  
  Evita che il Job ritenti più volte se lo script fallisce subito (utile in fase di debug).

!!! warning "Attenzione alle path hard-coded"

    Negli esempi si usano percorsi espliciti come  
    `/lustrehome/bob/k8s_tests/...`.  
    Ricordarsi di sostituire **`bob` con il proprio username reale** e di
    creare effettivamente le directory necessarie prima di lanciare i Job.

---

## Esempi pratici Kubernetes {#sec-k8-examples}

In questa sezione vedremo quattro esempi completi, paralleli agli esempi HTCondor con Apptainer:

1. **Esempio K8s1 – Geant4 11.3.1 “sanity check”**  
   Job minimale che lancia uno script di test dentro il container Geant4 11.3.1 e stampa versione di Geant4, ROOT e Python.

2. **Esempio K8s2 – Build+run dell’esempio Geant4 B5**  
   Job che compila l’esempio Geant4 B5 dentro il container e subito dopo lancia `exampleB5` con una macro di test.

3. **Esempio K8s3 – Build del progetto CsI-WLS con Geant4 v11**  
   Job che esegue solo la fase di **build** del progetto CsI-WLS (sorgenti su lustre, build directory nella stessa cartella).

4. **Esempio K8s4 – Batch di run CsI-WLS pilotati da Python**  
   Job che riutilizza la build dell’esempio precedente e lancia un batch di simulazioni tramite uno script Python (macro multiple, output ROOT su lustre).

I template completi (file `.sh` e `.yaml`) per questi esempi possono essere raccolti in una cartella, ad esempio:

```text
templates_k8s/
  EsK8s1_geant4_11.3.1_sanity/
    geant4_11.3.1_sanity.sh
    geant4_11.3.1_sanity.yaml

  EsK8s2_geant4_11.3.1_B5_build_run/
    B5_build_run.sh
    B5_build_run.yaml

  EsK8s3_CsI_WLS_v11_build/
    csi-wls-v11-build.sh
    csi-wls-v11-build.yaml

  EsK8s4_CsI_WLS_v11_batch_runs/
    run_electrons_batch.py
    csi-wls-v11-run-batch.sh
    csi-wls-v11-run-batch.yaml
```

Nelle sottosezioni seguenti riportiamo il contenuto completo dei template.

### Esempio K8s1 – Geant4 11.3.1 “sanity check”

Obiettivo: verificare che:

- il Job Kubernetes parta correttamente;
- il container `registry-clustergpu.recas.ba.infn.it/marcocecca/geant4:11.3.1` sia funzionante;
- Geant4, ROOT e Python siano visibili dentro il Pod.

#### Script `geant4_11.3.1_sanity.sh`

```bash
#!/bin/bash
set -euo pipefail

echo "[K8S-TEST] Start: $(date)"
echo "[K8S-TEST] Host:  $(hostname)"
echo "[K8S-TEST] User:  $(whoami)"
echo "[K8S-TEST] Pwd:   $(pwd)"
echo

echo "[K8S-TEST] Environment:"
echo "  G4INSTALL=${G4INSTALL:-undefined}"
echo "  G4VERSION=${G4VERSION:-undefined}"
echo "  ROOTSYS=${ROOTSYS:-undefined}"
echo

echo "[K8S-TEST] Checking Geant4 / ROOT / Python..."
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
echo "[K8S-TEST] Done: $(date)"
```

#### Job `geant4_11.3.1_sanity.yaml`

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: geant4-11-3-1-sanity
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: geant4-11-3-1
          image: registry-clustergpu.recas.ba.infn.it/alice/geant4:11.3.1
          workingDir: /lustrehome/bob/k8s_tests/EsK8s1_geant4_11.3.1_sanity
          command: ["/bin/bash", "geant4_11.3.1_sanity.sh"]
          volumeMounts:
            - name: lustre
              mountPath: /lustrehome
      volumes:
        - name: lustre
          hostPath:
            path: /lustrehome
  backoffLimit: 0
```

#### Comandi da lanciare

Da un frontend (es. `ui-al9`) come utente `bob`:

```bash
cd /lustrehome/bob/k8s_tests/EsK8s1_geant4_11.3.1_sanity

# Crea la directory e copia i template
mkdir -p /lustrehome/bob/k8s_tests/EsK8s1_geant4_11.3.1_sanity
# (poi copia qui i file .sh/.yaml)

chmod +x geant4_11.3.1_sanity.sh

# Sottomissione del Job
kubectl create -f geant4_11.3.1_sanity.yaml

# Stato dei Pod
kubectl get pods

# Log del Pod (sostituire <pod-name> con quello reale)
kubectl logs <pod-name>

# Pulizia (Job + Pod associati)
kubectl delete -f geant4_11.3.1_sanity.yaml
```

!!! tip "Verificare il mount di `/lustrehome`"

    Nei log dovresti vedere come `pwd` qualcosa tipo:
    `/lustrehome/bob/k8s_tests/EsK8s1_geant4_11.3.1_sanity`.  
    Se non è così, controlla `workingDir` e i blocchi `volumes/volumeMounts`
    nel file YAML.

---

### Esempio K8s2 – Build+run dell’esempio Geant4 B5

Questo esempio replica, in ambiente Kubernetes, il flusso *build+run* dell’esempio B5 descritto nella guida HTCondor:

- i sorgenti di B5 sono già inclusi nell’immagine Docker sotto  
  `/opt/geant4/share/Geant4/examples/basic/B5`;
- il job crea una directory di build su lustre;
- compila `exampleB5`;
- esegue `exampleB5` con una macro di test.

#### Script `B5_build_run.sh`

```bash
#!/bin/bash
set -euo pipefail

echo "[B5-K8S] Start: $(date)"
echo "[B5-K8S] Host:  $(hostname)"
echo "[B5-K8S] User:  $(whoami)"
echo "[B5-K8S] Pwd:   $(pwd)"
echo

SRC_DIR="/opt/geant4/share/Geant4/examples/basic/B5"
BUILD_DIR="B5_build_k8s"
MACRO="${SRC_DIR}/run1.mac"

echo "[B5-K8S] SRC_DIR   = ${SRC_DIR}"
echo "[B5-K8S] BUILD_DIR = ${BUILD_DIR}"
echo "[B5-K8S] MACRO     = ${MACRO}"
echo

# Env (di solito già inizializzato dall'entrypoint dell'immagine)
if [[ -f /opt/geant4/bin/geant4.sh ]]; then
  echo "[B5-K8S] Sourcing Geant4..."
  source /opt/geant4/bin/geant4.sh
fi
if [[ -f /opt/root/bin/thisroot.sh ]]; then
  echo "[B5-K8S] Sourcing ROOT..."
  source /opt/root/bin/thisroot.sh
fi

mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

echo "[B5-K8S] Now in: $(pwd)"

if [[ -x exampleB5 ]]; then
  echo "[B5-K8S] exampleB5 already built, skipping cmake/cmake --build."
else
  echo "[B5-K8S] Running CMake..."
  cmake "${SRC_DIR}"

  echo "[B5-K8S] Building..."
  cmake --build . -- -j"$(nproc)"
fi

if [[ ! -x exampleB5 ]]; then
  echo "[B5-K8S] ERROR: exampleB5 not found after build."
  exit 1
fi

echo
echo "[B5-K8S] Running exampleB5 with macro: ${MACRO}"
./exampleB5 "${MACRO}"

echo
echo "[B5-K8S] ROOT files under $(pwd):"
find . -maxdepth 3 -type f -name '*.root' -print || \
  echo "[B5-K8S] Nessun .root trovato."

echo
echo "[B5-K8S] Done: $(date)"
```

#### Job `B5_build_run.yaml`

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: geant4-11-3-1-b5-build-run
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: geant4-11-3-1-b5
          image: registry-clustergpu.recas.ba.infn.it/alice/geant4:11.3.1
          workingDir: /lustrehome/bob/k8s_tests/EsK8s2_geant4_11.3.1_B5_build_run
          command: ["/bin/bash", "B5_build_run.sh"]
          resources:
            requests:
              cpu: "4"
              memory: "4Gi"
          volumeMounts:
            - name: lustre
              mountPath: /lustrehome
      volumes:
        - name: lustre
          hostPath:
            path: /lustrehome
  backoffLimit: 0
```

#### Comandi da lanciare

```bash
cd /lustrehome/bob/k8s_tests/EsK8s2_geant4_11.3.1_B5_build_run
mkdir -p /lustrehome/bob/k8s_tests/EsK8s2_geant4_11.3.1_B5_build_run

chmod +x B5_build_run.sh

kubectl create -f B5_build_run.yaml
kubectl get pods
kubectl logs <pod-name>

# Al termine
kubectl delete -f B5_build_run.yaml
```

Gli output (in particolare i file `.root` prodotti da B5) saranno in:

```text
/lustrehome/bob/k8s_tests/EsK8s2_geant4_11.3.1_B5_build_run/B5_build_k8s/
```

---

### Esempio K8s3 – Build del progetto CsI-WLS con Geant4 v11

In questo esempio `bob` ha già una versione del progetto CsI-WLS compatibile con Geant4 v11 (per esempio una copia dei sorgenti in `src/` come nella sezione HTCondor) e vuole eseguire **solo la build** dentro il container.

Struttura suggerita:

```text
/lustrehome/bob/k8s_tests/EsK8s3_CsI_WLS_v11/
  src/                 # sorgenti CsI-WLS (CMakeLists.txt, .cc, .hh, OptData, etc.)
  csi-wls-v11-build.sh
  csi-wls-v11-build.yaml
```

#### Script `csi-wls-v11-build.sh`

```bash
#!/bin/bash
set -euo pipefail

echo "[CsI-K8S-BUILD] Start: $(date)"
echo "[CsI-K8S-BUILD] Host:  $(hostname)"
echo "[CsI-K8S-BUILD] User:  $(whoami)"
echo "[CsI-K8S-BUILD] Pwd:   $(pwd)"
echo

if [[ -f /opt/geant4/bin/geant4.sh ]]; then
  echo "[CsI-K8S-BUILD] Sourcing Geant4..."
  source /opt/geant4/bin/geant4.sh
fi
if [[ -f /opt/root/bin/thisroot.sh ]]; then
  echo "[CsI-K8S-BUILD] Sourcing ROOT..."
  source /opt/root/bin/thisroot.sh
fi

BUILD_DIR="build"
SRC_DIR="src"

mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

echo "[CsI-K8S-BUILD] Now in build dir: $(pwd)"

echo "[CsI-K8S-BUILD] Configuring with CMake..."
cmake "../${SRC_DIR}"

echo "[CsI-K8S-BUILD] Building CsI-WLS..."
cmake --build . -- -j"$(nproc)"

if [[ ! -x CsI-WLS ]]; then
  echo "[CsI-K8S-BUILD] ERROR: CsI-WLS binary not found after build."
  exit 1
fi

echo
echo "[CsI-K8S-BUILD] Build completed, CsI-WLS is available in $(pwd)"
ls -l CsI-WLS || true

echo
echo "[CsI-K8S-BUILD] Done: $(date)"
```

#### Job `csi-wls-v11-build.yaml`

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: csi-wls-v11-build
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: csi-wls-v11-build
          image: registry-clustergpu.recas.ba.infn.it/alice/geant4:11.3.1
          workingDir: /lustrehome/bob/k8s_tests/EsK8s3_CsI_WLS_v11
          command: ["/bin/bash", "csi-wls-v11-build.sh"]
          resources:
            requests:
              cpu: "4"
              memory: "4Gi"
          volumeMounts:
            - name: lustre
              mountPath: /lustrehome
      volumes:
        - name: lustre
          hostPath:
            path: /lustrehome
  backoffLimit: 0
```

#### Comandi da lanciare

```bash
cd /lustrehome/bob/k8s_tests/EsK8s3_CsI_WLS_v11
chmod +x csi-wls-v11-build.sh

kubectl create -f csi-wls-v11-build.yaml
kubectl get pods
kubectl logs <pod-name>

# Pulizia
kubectl delete -f csi-wls-v11-build.yaml
```

Al termine, l’eseguibile `CsI-WLS` sarà disponibile in:

```text
/lustrehome/bob/k8s_tests/EsK8s3_CsI_WLS_v11/build/
```

---

### Esempio K8s4 – Batch di run CsI-WLS pilotati da Python

Qui estendiamo l’esempio K8s3: assumiamo che la build sia già stata eseguita (l’eseguibile `CsI-WLS` esiste in `build/`) e vogliamo far partire un batch di simulazioni pilotate da uno script Python, in stile HTCondor esempio 5.

Struttura suggerita:

```text
/lustrehome/bob/k8s_tests/EsK8s3_CsI_WLS_v11/
  src/
    ...                 # sorgenti CsI-WLS
    run_electrons_batch.py
  build/
    CsI-WLS             # ottenuto da K8s3
  csi-wls-v11-run-batch.sh
  csi-wls-v11-run-batch.yaml
```

#### Script Python `run_electrons_batch.py`

Esempio minimale che genera N macro, ognuna con un seed diverso, e lancia `./CsI-WLS` per ciascuna:

```python
import numpy as np
import os

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

print(f"\n{N_EVENTS * nfiles} eventi simulati. "
      f"Macro in {DIR_MAC}/{subdir}, output ROOT in {DIR_ROOT}/{subdir}")
```

#### Script `csi-wls-v11-run-batch.sh`

```bash
#!/bin/bash
set -euo pipefail

echo "[CsI-K8S-RUN] Start: $(date)"
echo "[CsI-K8S-RUN] Host:  $(hostname)"
echo "[CsI-K8S-RUN] User:  $(whoami)"
echo "[CsI-K8S-RUN] Pwd:   $(pwd)"
echo

if [[ -f /opt/geant4/bin/geant4.sh ]]; then
  echo "[CsI-K8S-RUN] Sourcing Geant4..."
  source /opt/geant4/bin/geant4.sh
fi
if [[ -f /opt/root/bin/thisroot.sh ]]; then
  echo "[CsI-K8S-RUN] Sourcing ROOT..."
  source /opt/root/bin/thisroot.sh
fi

BUILD_DIR="build"

if [[ ! -d "${BUILD_DIR}" ]]; then
  echo "[CsI-K8S-RUN] ERROR: build directory '${BUILD_DIR}' not found."
  exit 1
fi

cd "${BUILD_DIR}"
echo "[CsI-K8S-RUN] Now in build dir: $(pwd)"

if [[ ! -x CsI-WLS ]]; then
  echo "[CsI-K8S-RUN] ERROR: CsI-WLS binary not found in $(pwd)."
  exit 1
fi

echo
echo "[CsI-K8S-RUN] Running Python batch script..."
python3 ../src/run_electrons_batch.py

echo
echo "[CsI-K8S-RUN] ROOT files under rootOutput_electron/:"
find rootOutput_electron -maxdepth 3 -type f -name '*.root' -print \
  || echo "[CsI-K8S-RUN] Nessun .root trovato."

echo
echo "[CsI-K8S-RUN] Done: $(date)"
```

#### Job `csi-wls-v11-run-batch.yaml`

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: csi-wls-v11-run-batch
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: csi-wls-v11-run-batch
          image: registry-clustergpu.recas.ba.infn.it/alice/geant4:11.3.1
          workingDir: /lustrehome/bob/k8s_tests/EsK8s3_CsI_WLS_v11
          command: ["/bin/bash", "csi-wls-v11-run-batch.sh"]
          resources:
            requests:
              cpu: "1"
              memory: "4Gi"
          volumeMounts:
            - name: lustre
              mountPath: /lustrehome
      volumes:
        - name: lustre
          hostPath:
            path: /lustrehome
  backoffLimit: 0
```

#### Comandi da lanciare

```bash
cd /lustrehome/bob/k8s_tests/EsK8s3_CsI_WLS_v11
chmod +x csi-wls-v11-run-batch.sh

kubectl create -f csi-wls-v11-run-batch.yaml
kubectl get pods
kubectl logs <pod-name>

# Pulizia
kubectl delete -f csi-wls-v11-run-batch.yaml
```

!!! warning "Assicurarsi che la build esista prima del batch"

    L’esempio K8s4 **presuppone** che:
    - la directory `build/` esista;
    - l’eseguibile `CsI-WLS` sia stato prodotto da K8s3.

    Se il Job fallisce immediatamente con un errore tipo “CsI-WLS binary not found”,
    rilanciare prima il Job di build (`csi-wls-v11-build.yaml`).

---

## Comandi essenziali di Kubernetes {#sec-k8-commands}

Questa sezione riassume i comandi `kubectl` più usati nello scenario degli esempi.

### Gestione dei Job e dei Pod

```bash
# Creare un Job da un file YAML
kubectl create -f job_esempio.yaml

# Elenco dei Job nel namespace corrente
kubectl get jobs

# Dettagli di un Job specifico
kubectl describe job nome-job

# Elenco dei Pod (inclusi quelli creati dai Job)
kubectl get pods

# Dettagli di un Pod
kubectl describe pod nome-pod
```

### Log e debug

```bash
# Log standard di un Pod
kubectl logs nome-pod

# Log in streaming (finché il Pod è in esecuzione)
kubectl logs -f nome-pod

# Shell interattiva dentro il container del Pod
kubectl exec -it nome-pod -- /bin/bash
```

### Pulizia

```bash
# Eliminare un Job (e i Pod associati)
kubectl delete -f job_esempio.yaml
# oppure
kubectl delete job nome-job

# Eliminare un Pod singolo (se necessario)
kubectl delete pod nome-pod
```

!!! tip "Allineare naming e directory"

    Mantenere un mapping chiaro tra:
    - directory su lustre (`EsK8s1_...`, `EsK8s2_...`, ecc.),
    - nomi dei Job (`metadata.name`),
    - nomi dei file YAML (`EsK8sX_*.yaml`).

    Questo rende molto più semplice capire cosa cancellare e dove andare a
    leggere gli output.

---

## Appendice – Riferimenti ufficiali e documentazione Kubernetes {#sec-k8-refs}

Per approfondimenti oltre gli esempi di questa guida ci si può rifare alla [Documentazione ufficiale Kubernetes](https://kubernetes.io/docs/reference/kubectl/), introduttiva e di riferimento su concetti come Pod, Job, volumi, risorse, ecc, e alla [guida ufficiale di ReCaS su Kubernetes](https://jvino.github.io/cluster-hpc-gpu-guides/job_submission/k8s-jobs/) che contiene istruzioni aggiornate per l’abilitazione degli utenti, esempi di configurazione `kubectl` per il cluster e policy su limiti di CPU/RAM e best practice per l’uso di K8s in ambiente HPC.

La parte Kubernetes di questo documento va intesa come **complemento operativo** agli esempi Geant4/ROOT/CsI-WLS, non come sostituto della documentazione ufficiale.
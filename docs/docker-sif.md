# Docker & SIF

Questa sezione completa gli esempi della pagina *HTCondor + Apptainer* assumendo che tu voglia costruire nuove immagini `.sif` da condividere con il gruppo.

L’utente manutentore (`alice`) si occupa di:

1. costruire un’immagine Docker con Geant4, ROOT e Python;
2. caricarla sul registry Docker interno;
3. convertirla in un file Apptainer/Singularity (`.sif`);
4. copiarla in una directory condivisa su lustre, ad esempio:

   ```bash
   /lustrehome/alice/apptainer_images
   ```

Gli altri utenti (`bob`, ecc.) usano l’immagine `.sif` nei job Condor tramite symlink, come illustrato nella sezione sugli esempi.

---

## Costruzione di un’immagine Docker e conversione in SIF

Gli esempi di [HTCondor + Apptainer](condor-apptainer.md) assumono che le immagini `.sif` siano già disponibili in una cartella condivisa, gestita dall’utente `alice`.

Questa sezione riassume il flusso:

1. costruire un’immagine Docker con Geant4/ROOT/Python;
2. push sul registry interno;
3. conversione in `.sif` con Apptainer;
4. distribuzione agli altri utenti.

Non entriamo nei dettagli di ogni singolo comando di installazione di Geant4/ROOT all’interno del container: ti forniamo un `Dockerfile` di riferimento che puoi adattare.

### Macchina con Docker (es. tesla02)

La costruzione di immagini Docker richiede una macchina con Docker installato e accessibile, ad esempio:

```bash
tesla02.recas.infn.ba.it
```

L’utente `alice` può connettersi a quella macchina con le stesse credenziali delle macchine di frontend (`ui-al9.recas.infn.ba.it`), clonare il repository della guida (o creare una directory di lavoro) e preparare un `Dockerfile`.

Un `Dockerfile` completo di esempio per un ambiente Ubuntu 24.04 con Geant4 11.3.1, ROOT 6.36.04 e Python3 è riportato in fondo a questa pagina.

### Build dell’immagine Docker

Una volta scritto il `Dockerfile`, dalla directory che lo contiene:

```bash
docker build -t registry-clustergpu.recas.ba.infn.it/alice/geant4:11.3.1 .
```

Il tag è composto da:

- registry interno `registry-clustergpu.recas.ba.infn.it`;
- namespace utente `alice`;
- nome dell’immagine `geant4`;
- tag `11.3.1`.

Puoi naturalmente scegliere nomi/tag diversi, ma è utile mantenere una convenzione semplice.

### Push sul registry interno

Per caricare l’immagine sul registry interno:

```bash
docker login registry-clustergpu.recas.ba.infn.it
docker push registry-clustergpu.recas.ba.infn.it/alice/geant4:11.3.1
```

Le credenziali sono in genere le stesse del frontend.

### Conversione Docker → SIF con Apptainer

La conversione da immagine Docker a immagine Apptainer/Singularity avviene su un nodo dove Apptainer è installato e autorizzato a eseguire il comando `build` (es. un frontend tipo `ui-al9`).

Esempio:

```bash
apptainer build G4_v11.3.1.sif   docker://registry-clustergpu.recas.ba.infn.it/alice/geant4:11.3.1
```

Questo comando scarica l’immagine dal registry interno e crea il file `G4_v11.3.1.sif`.

Infine sposta il file nella directory condivisa delle immagini:

```bash
mv G4_v11.3.1.sif /lustrehome/alice/apptainer_images/
```

Dopo questo passaggio, tutti gli utenti (come `bob`) possono usare l’immagine nei propri job Condor creando un symlink nella `initialdir` e impostando `container_image` al nome del symlink, come mostrato negli esempi.

---

## Comandi essenziali Docker

Non è necessario che ogni utente conosca Docker in dettaglio, ma è utile riassumere i comandi più usati nel ciclo di vita di un’immagine.

### Build da Dockerfile

Per costruire un’immagine dalla directory corrente:

```bash
docker build -t nome_immagine:tag .
```

Esempio:

```bash
docker build -t registry-clustergpu.recas.ba.infn.it/alice/geant4:11.3.1 .
```

### Elenco immagini locali

```bash
docker images
```

### Test interattivo di un’immagine

Per entrare nel container e verificare che gli script di environment funzionino:

```bash
docker run -it nome_immagine:tag /bin/bash
```

Esempio:

```bash
docker run -it registry-clustergpu.recas.ba.infn.it/alice/geant4:11.3.1 /bin/bash
```

Dentro il container puoi controllare:

```bash
geant4-config --version
root-config --version
python3 --version
```

### Tag e push verso il registry

Per taggare un’immagine locale:

```bash
docker tag nome_immagine:tag   registry-clustergpu.recas.ba.infn.it/alice/nome_immagine:tag
```

e poi inviarla al registry:

```bash
docker push registry-clustergpu.recas.ba.infn.it/alice/nome_immagine:tag
```

Questi comandi vengono eseguiti sulla macchina che ha Docker installato, come `tesla02`.

---

## Comandi essenziali Apptainer/Singularity

Apptainer viene utilizzato sia per testare manualmente le immagini sia in maniera indiretta tramite HTCondor (quando usi `container_image` nel file `.csi`).

### Esecuzione di un comando dentro una `.sif`

Per un test rapido:

```bash
apptainer exec G4_v11.3.1.sif geant4-config --version
```

### Shell interattiva nel container

```bash
apptainer shell G4_v11.3.1.sif
```

Da lì puoi verificare l’ambiente:

```bash
geant4-config --version
root-config --version
python3 --version
```

### Conversione Docker → SIF

Già mostrata sopra, ma la riportiamo per completezza:

```bash
apptainer build G4_v11.3.1.sif   docker://registry-clustergpu.recas.ba.infn.it/alice/geant4:11.3.1
```

I job Condor che usano `container_image` nascondono questi dettagli: è il sistema a chiamare internamente Apptainer. Conoscere questi comandi è comunque utile per testare rapidamente un’immagine su un frontend prima di costruire i file `.csi`.

---

## Dockerfile di esempio per ambiente Geant4/ROOT

Qui riportiamo un `Dockerfile` completo per costruire un’immagine Docker basata su Ubuntu 24.04, con Geant4 11.3.1, ROOT 6.36.04 e Python3.

Lo scopo è ottenere un’immagine che espone gli script di environment:

- `/opt/geant4/bin/geant4.sh`
- `/opt/root/bin/thisroot.sh`

e che può essere convertita in un file `.sif` come descritto sopra.

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
RUN apt-get update && apt-get install -y --no-install-recommends     build-essential     cmake     git     pkg-config     ca-certificates     wget     curl     # Geant4 + GDML
    libxerces-c-dev     libexpat1-dev     # Qt5 + OpenGL + X11
    qtbase5-dev     qtbase5-dev-tools     qt5-qmake     libqt5opengl5-dev     libx11-dev     libxmu-dev     libxi-dev     libxrandr-dev     libxinerama-dev     libxcursor-dev     libgl1-mesa-dev     libglu1-mesa-dev     # runtime Qt/X11
    libxkbcommon-x11-0     libfontconfig1     libxrender1     libxcb-icccm4     libxcb-image0     libxcb-keysyms1     libxcb-render-util0     libxcb-xfixes0     libxcb-xinerama0     # dipendenze ROOT
    libxpm-dev     libxft-dev     libssl-dev     libpcre3-dev     libgsl-dev     libgraphviz-dev     libtbb12     libtbb-dev     libvdt-dev     # Python per gli script di simulazione
    python3     python3-numpy     python3-matplotlib     python3-pip     # utility
    adduser  && rm -rf /var/lib/apt/lists/*

# ================================
# Mandatory ReCaS: utente reale
# ================================
ENV USERNAME=alice
ENV USERID=000001
ENV GROUPID=1234

RUN groupadd -g "$GROUPID" "$USERNAME" &&     adduser --disabled-password --gecos '' --uid "$USERID" --gid "$GROUPID" "$USERNAME"

# ==========================================
# Sorgenti Geant4 11.3.1 (da GitLab CERN)
# ==========================================
RUN mkdir -p /opt/geant4-source /tmp/g4 &&     cd /tmp/g4 &&     wget https://gitlab.cern.ch/geant4/geant4/-/archive/v11.3.1/geant4-v11.3.1.tar.gz &&     tar -xzf geant4-v11.3.1.tar.gz -C /opt/geant4-source --strip-components=1 &&     rm -rf /tmp/g4

# ==========================================
# Build + install Geant4 (dataset inclusi)
# ==========================================
RUN mkdir -p /opt/geant4-build && cd /opt/geant4-build &&     cmake ../geant4-source       -DCMAKE_INSTALL_PREFIX=${G4INSTALL}       -DGEANT4_BUILD_MULTITHREADED=ON       -DGEANT4_BUILD_CXXSTD=17       -DGEANT4_INSTALL_DATA=ON       -DGEANT4_INSTALL_EXAMPLES=ON       -DGEANT4_USE_GDML=ON       -DGEANT4_USE_SYSTEM_EXPAT=ON       -DGEANT4_USE_SYSTEM_XERCESC=ON       -DGEANT4_USE_QT=ON       -DCMAKE_PREFIX_PATH=/usr/lib/x86_64-linux-gnu/cmake/Qt5       -DGEANT4_USE_OPENGL_X11=ON       -DGEANT4_USE_XM=OFF       -DGEANT4_USE_RAYTRACER_X11=ON &&     cmake --build . -j"$(nproc)" &&     cmake --install . &&     rm -rf /opt/geant4-build

# =================================================
# Install ROOT (precompiled per Ubuntu 24.04)
# =================================================
RUN cd /opt &&     wget -O root.tar.gz https://root.cern/download/root_v6.36.04.Linux-ubuntu24.04-x86_64-gcc13.3.tar.gz &&     tar -xzf root.tar.gz &&     mv root root-${ROOT_VERSION} &&     ln -s root-${ROOT_VERSION} root &&     rm root.tar.gz

# =================================================
# Linker config + PATH/LD_LIBRARY_PATH globali
# =================================================
RUN echo "${G4LIB_DIR}"   > /etc/ld.so.conf.d/geant4.conf &&     echo "${ROOTSYS}/lib" > /etc/ld.so.conf.d/root.conf &&     ldconfig

ENV PATH=${G4INSTALL}/bin:${ROOTSYS}/bin:${PATH}
ENV LD_LIBRARY_PATH=${G4LIB_DIR}:${ROOTSYS}/lib

# ===========================
# Permessi su /opt/geant4
# ===========================
RUN chown -R "$USERNAME:$GROUPID" "$G4INSTALL"

# ======================================================
# EntryPoint: inizializza Geant4 + ROOT nel modo "giusto"
# ======================================================
RUN printf '%s\n' '#!/bin/bash' 'set -e' '# --- Geant4 env ---' 'G4_SH="${G4INSTALL}/bin/geant4.sh"' 'if [ -f "$G4_SH" ]; then' '  OLD_G4="$(pwd)"' '  cd "$(dirname "$G4_SH")"' '  . ./geant4.sh' '  cd "$OLD_G4"' 'fi' '# --- geant4make (opzionale, per vecchi workflow) ---' 'if [ -f "${G4INSTALL}/share/Geant4-${G4VERSION}/geant4make/geant4make.sh" ]; then' '  . "${G4INSTALL}/share/Geant4-${G4VERSION}/geant4make/geant4make.sh"' 'fi' '# --- ROOT env ---' 'if [ -f "/opt/root/bin/thisroot.sh" ]; then' '  OLD_ROOT="$(pwd)"' '  cd /opt/root' '  . bin/thisroot.sh' '  cd "$OLD_ROOT"' 'fi' '# --- Esegui il comando richiesto ---' 'exec "$@"' > /usr/local/bin/geant4-entrypoint.sh && chmod +x /usr/local/bin/geant4-entrypoint.sh

WORKDIR /home/$USERNAME
USER $USERNAME

ENTRYPOINT ["/usr/local/bin/geant4-entrypoint.sh"]
CMD ["bash"]
```

Adatta:

- `USERNAME`, `USERID`, `GROUPID` alle esigenze del cluster;
- versioni di Geant4/ROOT se preferisci versioni diverse;
- eventuali librerie extra (es. per Python, Jupyter, ecc.).

Da questo punto puoi usare il flusso:

1. `docker build`
2. `docker push`
3. `apptainer build`
4. symlink nei job Condor (`container_image = ...`)

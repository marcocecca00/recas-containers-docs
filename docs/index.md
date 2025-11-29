# Uso di immagini Apptainer/Singularity con HTCondor su ReCaS

Questa documentazione descrive in modo operativo come usare immagini Apptainer/Singularity (file `.sif`) insieme a HTCondor sul cluster ReCaS.

L’idea di fondo è che nel gruppo ci sia almeno un utente **manutentore** (che chiameremo `alice`) che costruisce immagini Docker su una macchina dedicata (ad esempio una macchina con Docker come `tesla02`), le converte in immagini Apptainer/Singularity e le mette a disposizione di tutti in una posizione condivisa su lustre.

Gli altri utenti (ad esempio `bob`) non devono occuparsi della parte Docker: usano le immagini `.sif` già pronte all’interno dei job Condor, tramite *symlink* verso la directory condivisa di `alice`.

---

## Contenuti

- **HTCondor + Apptainer**  
  Concetti di base su container, Apptainer e HTCondor, organizzazione delle directory su lustre e cinque esempi completi di utilizzo:
  1. Test dell’immagine (`G4_v11.3.1.sif`)
  2. Build dell’esempio Geant4 B5
  3. Run di B5 con macro
  4. Build + run di B5 in un unico job
  5. Caso reale con progetto CsI-WLS e batch Python

- **Docker & SIF**  
  Come costruire un’immagine Docker con Geant4/ROOT/Python, caricarla sul registry interno e convertirla in un’immagine Apptainer/Singularity (`.sif`), con un `Dockerfile` di esempio.

- **Kubernetes (TODO)**  
  Idea di mapping dei workflow HTCondor+Apptainer in job Kubernetes (pod, volumi persistenti, immagini condivise), con esempi che verranno aggiunti in futuro.

---

## Come usare questa documentazione

1. Parti da **HTCondor + Apptainer → Introduzione** se non hai mai usato container su ReCaS.
2. Segui gli esempi nell’ordine, lavorando dentro la tua home su lustre (`/lustrehome/<username>`).
3. Se ti serve costruire nuove immagini per il gruppo, passa alla sezione **Docker & SIF**.
4. Quando (e se) verrà attivato Kubernetes per questi workflow, useremo la sezione dedicata per mantenere una documentazione omogenea.

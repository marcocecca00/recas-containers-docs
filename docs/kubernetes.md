# Kubernetes (TODO)

Questa sezione è un *placeholder* per una futura estensione della guida all’uso di Kubernetes con le stesse immagini container usate per HTCondor+Apptainer.

L’idea è di mappare, in modo quanto più possibile diretto, i concetti già introdotti:

- `container_image` → image di un Pod/Job Kubernetes;
- `initialdir` su lustre → volume persistente montato nel Pod;
- script `executable` → comando/entrypoint del container;
- risorse richieste (`request_cpus`, `request_memory`, `request_disk`) → `resources.requests/limits` nel manifest Kubernetes.

Quando la parte Kubernetes sarà stabile sul cluster, qui potremmo aggiungere:

- manifest YAML di esempio per:
  - test dell’immagine (`kubectl apply -f test-container.yaml`);
  - build e run di Geant4 B5;
  - un Job che compila e lancia CsI-WLS con batch Python;
- note pratiche sul montaggio di volumi (lustre o PVC);
- convenzioni per i namespace e per la condivisione delle immagini tra utenti.

Per ora puoi considerare questa pagina come uno “scheletro” da riempire, mantenendo la stessa struttura narrativa usata per HTCondor+Apptainer, in modo da poter passare da un backend all’altro (Condor ↔ Kubernetes) con cambiamenti minimi agli script.

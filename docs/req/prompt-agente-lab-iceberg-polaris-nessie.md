# Prompt per l'agente — Laboratorio Iceberg su EC2 con dati su S3 (Spark + Polaris + Nessie)

## 1. Ruolo

Tu sei un Data Platform Engineer senior.
Il tuo compito è realizzare un laboratorio riproducibile con Docker Compose.
Il laboratorio gira su una sola VM Amazon EC2.
Il laboratorio serve a valutare e confrontare due cataloghi Iceberg REST: Apache Polaris e Project Nessie.

## 2. Contesto

- Il punto di partenza è il Quickstart ufficiale: https://iceberg.apache.org/spark-quickstart/
- Il Quickstart usa un object store locale (RustFS) e il catalogo `apache/iceberg-rest-fixture`.
- In questo laboratorio i data file e i metadata file sono su un bucket **AWS S3 reale**. Non usare un object store locale.
- Il laboratorio è un ambiente di prova. Non è un ambiente di produzione.
- Il cliente finale ha due vincoli architetturali: nessun vendor lock-in e installazione on-premise. Il laboratorio deve quindi poter passare da AWS S3 a uno storage S3-compatibile on-premise (per esempio MinIO o RustFS) con la sola modifica di variabili d'ambiente.

## 3. Obiettivo

Costruisci un ambiente in cui una sola sessione Spark vede due cataloghi Iceberg:

| Nome catalogo Spark | Servizio | Prefisso S3 |
|---|---|---|
| `polaris` | Apache Polaris | `s3://${S3_BUCKET}/polaris/` |
| `nessie` | Project Nessie (endpoint Iceberg REST) | `s3://${S3_BUCKET}/nessie/` |
| `rest` (opzionale, profilo Compose `baseline`) | `apache/iceberg-rest-fixture` | `s3://${S3_BUCKET}/rest/` |

L'utente deve poter eseguire gli stessi scenari di test sui due cataloghi e confrontare i risultati.

## 4. Regole generali

1. Verifica online ogni versione prima di usarla. Usa la documentazione ufficiale di ogni progetto.
2. Fissa ogni versione in un file `.env`. Non usare mai il tag `latest`.
3. Verifica la compatibilità tra la versione di Spark, la versione di Iceberg e la versione dei client di Polaris e Nessie.
4. Scrivi nel file `VERSIONS.md` ogni versione scelta, con il link alla fonte.
5. Non scrivere credenziali nei file del repository. Usa `.env` (escluso da git) e un file `.env.example`.
6. Non usare access key statiche AWS. Usa il ruolo IAM della VM (instance profile).
7. Se ti serve un permesso AWS che non hai, fermati. Scrivi il comando o la policy necessaria. Chiedi all'utente di applicarla.
8. Dopo ogni fase, esegui i test di accettazione della fase. Passa alla fase successiva solo se i test passano.
9. Se la documentazione di un progetto è in contrasto con questo prompt, segui la documentazione e scrivi la differenza in `NOTES.md`.

## 5. Architettura richiesta

### 5.1 Servizi Docker Compose

| Servizio | Immagine | Funzione |
|---|---|---|
| `postgres` | `postgres` (versione fissata) | Persistenza per Polaris e per Nessie. Due database separati: `polaris` e `nessie`. |
| `polaris` | `apache/polaris` (versione fissata) | Catalogo Iceberg REST con RBAC e credential vending. Persistenza `relational-jdbc` su Postgres. |
| `polaris-setup` | immagine leggera con `curl` e `jq` | Job one-shot. Crea il catalogo Polaris, i principal, i ruoli e i grant. Deve essere idempotente. |
| `nessie` | `ghcr.io/projectnessie/nessie` (versione fissata) | Catalogo con endpoint Iceberg REST (`/iceberg`) e API nativa Nessie. Version store JDBC su Postgres. |
| `spark` | immagine costruita da te (`spark/Dockerfile`) | Spark con Iceberg runtime, Iceberg AWS bundle, Jupyter. In `spark-defaults.conf` è configurato ogni catalogo acceso. |
| `rest-fixture` (profilo `baseline`) | `apache/iceberg-rest-fixture` | Catalogo di riferimento, come nel Quickstart. Opzionale. |

I cataloghi (`polaris`, `nessie`, `rest-fixture`) sono spenti di default. L'utente sceglie quali accendere con la variabile `COMPOSE_PROFILES` in `.env` (profili Compose `polaris`, `nessie`, `baseline`). Il laboratorio deve contenere tutti i cataloghi, ma non deve farli girare insieme: per i test basta un catalogo acceso alla volta. Spegnere un catalogo non cancella i suoi dati.

Il laboratorio include anche la Nessie CLI, per usare l'API nativa di Nessie (branch, tag, commit, merge) dalla riga di comando. Questo requisito è per una fase successiva (issue #22): la progettazione e il piano vengono fatti in quella fase.

### 5.2 Immagine Spark

1. Parti dall'immagine ufficiale `apache/spark` o da un'immagine Python con Spark installato.
2. Aggiungi il JAR `iceberg-spark-runtime` compatibile con la versione di Spark.
3. Aggiungi il JAR `iceberg-aws-bundle`.
4. Aggiungi JupyterLab e PySpark.
5. Configura `spark.sql.extensions` con le Iceberg Spark Session Extensions.
6. Configura il catalogo `polaris`:
   - `type=rest`
   - URI dell'API catalog di Polaris
   - autenticazione OAuth2 con un principal dedicato a Spark (non il principal `root`)
   - header `X-Iceberg-Access-Delegation=vended-credentials`
7. Configura il catalogo `nessie`:
   - `type=rest`
   - URI dell'endpoint Iceberg REST di Nessie
   - riferimento al branch `main`
8. Configura il catalogo `rest` solo se il profilo `baseline` è attivo.

### 5.3 Accesso a S3

1. Usa un solo bucket: `${S3_BUCKET}`.
2. Usa tre prefissi separati, uno per catalogo (vedi tabella al paragrafo 3).
3. I container ottengono le credenziali dall'instance profile della VM tramite IMDSv2.
4. Configura la VM con `HttpPutResponseHopLimit=2` per IMDSv2. Con il valore predefinito (1) i container sulla rete bridge non ricevono le credenziali. Verifica questo punto nella documentazione AWS.
5. Per Polaris, configura il credential vending:
   - crea un ruolo IAM dedicato (`polaris-s3-access`) con accesso solo al prefisso `polaris/`
   - configura la trust policy del ruolo per permettere `sts:AssumeRole` al ruolo della VM
   - usa un `externalId`
   - inserisci il `roleArn` nella `storageConfigInfo` del catalogo Polaris
6. Per Nessie, configura l'accesso a S3 lato server con la default credential chain AWS. Verifica nella documentazione di Nessie se il credential vending è disponibile e come si configura. Scrivi il risultato in `NOTES.md`.
7. Rendi parametrici endpoint S3, region e path-style access. Il passaggio a uno storage S3-compatibile on-premise deve richiedere solo la modifica di `.env`.

### 5.4 Rete e sicurezza

1. Pubblica le porte dei servizi solo su `127.0.0.1` della VM.
2. L'utente accede alle UI tramite tunnel SSH o AWS SSM port forwarding. Documenta i due metodi nel README.
3. Il Security Group della VM apre solo la porta 22, e solo verso l'IP dell'utente. Se l'utente usa SSM, nessuna porta in ingresso.
4. Abilita il blocco dell'accesso pubblico sul bucket.
5. Abilita la cifratura SSE-S3 sul bucket.

## 6. Risorse AWS

Tu non crei direttamente le risorse AWS. Tu produci gli script. L'utente li esegue.

Produci nella cartella `aws/`:

1. `iam/vm-role-policy.json` — policy del ruolo della VM (accesso S3 ai prefissi `nessie/` e `rest/`, `sts:AssumeRole` su `polaris-s3-access`).
2. `iam/polaris-role-policy.json` — policy del ruolo `polaris-s3-access` (accesso S3 al solo prefisso `polaris/`).
3. `iam/polaris-role-trust.json` — trust policy del ruolo `polaris-s3-access`, con `externalId`.
4. `setup.sh` — script AWS CLI che crea bucket, ruoli, policy, instance profile e imposta l'hop limit IMDSv2. Lo script deve essere idempotente.
5. `teardown.sh` — script che elimina tutte le risorse create da `setup.sh`. Lo script chiede conferma prima di svuotare il bucket.
6. `README-aws.md` — dimensionamento consigliato della VM (almeno 4 vCPU e 16 GB RAM), sistema operativo consigliato, installazione di Docker e del plugin Compose.

## 7. Struttura del repository

```text
iceberg-catalog-lab/
├── README.md
├── VERSIONS.md
├── NOTES.md
├── EVALUATION.md
├── .env.example
├── docker-compose.yml
├── Makefile
├── aws/
├── postgres/init/        # crea i database polaris e nessie
├── polaris/setup/        # script di bootstrap idempotente
├── nessie/               # configurazione application.properties (se necessaria)
├── spark/
│   ├── Dockerfile
│   └── conf/spark-defaults.conf
├── scenarios/            # notebook e file SQL degli scenari di test
└── tests/                # script di smoke test
```

Il `Makefile` deve avere almeno questi target: `up`, `up-baseline`, `down`, `reset` (elimina i volumi), `smoke-test`, `logs`, `sql-polaris`, `sql-nessie`.

## 8. Fasi di realizzazione

### Fase 1 — Infrastruttura e Spark

1. Scrivi gli script AWS del paragrafo 6.
2. Scrivi il `Dockerfile` di Spark.
3. Scrivi il servizio `spark` e il servizio `postgres` nel `docker-compose.yml`.
4. Test di accettazione: da Spark, leggi e scrivi un file di prova in `s3://${S3_BUCKET}/` con le credenziali dell'instance profile.

### Fase 2 — Polaris

1. Aggiungi il servizio `polaris` con persistenza su Postgres.
2. Aggiungi il job `polaris-setup`.
3. Il job crea: il catalogo `lab_catalog`, il principal `spark_user`, un principal role, un catalog role con i privilegi necessari, i grant tra questi oggetti.
4. Il job scrive le credenziali di `spark_user` in un file locale escluso da git, letto dal servizio `spark`.
5. Test di accettazione:
   - crea un namespace e una tabella in `polaris`
   - inserisci righe
   - leggi le righe
   - verifica che i file sono in `s3://${S3_BUCKET}/polaris/`
   - riavvia lo stack e verifica che la tabella esiste ancora

### Fase 3 — Nessie

1. Aggiungi il servizio `nessie` con version store JDBC su Postgres.
2. Configura il warehouse S3 di Nessie sul prefisso `nessie/`.
3. Test di accettazione: gli stessi test della Fase 2 sul catalogo `nessie`.

### Fase 4 — Baseline (opzionale)

1. Aggiungi `rest-fixture` con profilo Compose `baseline`.
2. Test di accettazione: gli stessi test della Fase 2 sul catalogo `rest`.

### Fase 5 — Scenari di confronto

Scrivi un notebook per ogni scenario. Ogni notebook esegue lo scenario sul catalogo acceso (`polaris` o `nessie`). Per confrontare i cataloghi, l'utente esegue lo stesso notebook una volta per ogni catalogo.

| N. | Scenario | Cosa verificare |
|---|---|---|
| 1 | Ciclo base | `CREATE TABLE`, `INSERT`, `SELECT` con lo stesso dataset del Quickstart (`nyc.taxis`). |
| 2 | Layout su S3 | Struttura delle cartelle di metadata e data per ogni catalogo. Usa `aws s3 ls`. |
| 3 | Schema evolution e partition evolution | `ALTER TABLE` per colonne e partizioni. |
| 4 | Time travel | `VERSION AS OF` e `TIMESTAMP AS OF`. |
| 5 | Branch e tag Iceberg (livello tabella) | Branch e tag sulla singola tabella. Funziona in entrambi i cataloghi? |
| 6 | Branch Nessie (livello catalogo) | Branch su più tabelle, commit su più tabelle, merge. Mostra cosa è possibile con Nessie e cosa non è possibile con Polaris. Usa l'API nativa Nessie dove serve. |
| 7 | Controllo accessi | In Polaris: crea un secondo principal con sola lettura e verifica che la scrittura fallisce. In Nessie: documenta il modello di autorizzazione disponibile. |
| 8 | Credential vending | Mostra quali credenziali riceve Spark in ogni catalogo e su quale prefisso sono valide. |
| 9 | Manutenzione tabelle | `expire_snapshots`, `rewrite_data_files`, `remove_orphan_files`. Verifica il comportamento con branch Nessie attivi. |
| 10 | Drop e purge | `DROP TABLE` e `DROP TABLE ... PURGE`. Verifica cosa rimane su S3. |
| 11 | Accesso da un secondo client | Accedi alle tabelle con PyIceberg. Verifica la configurazione minima del client per ogni catalogo. |

### Fase 6 — Documento di valutazione

Scrivi `EVALUATION.md` con una tabella di confronto Polaris / Nessie. Criteri minimi:

1. Conformità alla Iceberg REST Catalog spec (endpoint supportati, views, multi-table commit).
2. Modello di branching (tabella vs catalogo).
3. Sicurezza: autenticazione, RBAC, credential vending.
4. Persistenza e operatività: backend supportati, backup, upgrade.
5. Complessità di configurazione (numero di passi, numero di parametri).
6. Portabilità verso storage S3-compatibile on-premise.
7. Governance e salute del progetto: fondazione, release recenti, numero di contributori, roadmap. Usa fonti verificabili e scrivi la data della verifica.
8. Problemi incontrati durante la realizzazione.

Per ogni criterio scrivi i fatti osservati nel laboratorio. Separa i fatti osservati dalle informazioni prese dalla documentazione. Cita le fonti.

## 9. README

Il README contiene:

1. Diagramma dell'architettura (Mermaid).
2. Prerequisiti.
3. Procedura di avvio, un passo per un'azione.
4. Procedura di accesso tramite tunnel SSH e tramite SSM.
5. Elenco delle URL dei servizi.
6. Procedura per passare a uno storage S3-compatibile on-premise.
7. Procedura di arresto e di pulizia completa, inclusi i costi AWS da evitare.
8. Risoluzione dei problemi più comuni (credenziali IMDS, endpoint S3, token Polaris scaduto).

## 10. Criteri di completamento

Il lavoro è completo quando:

1. `make up` avvia lo stack senza errori su una VM nuova.
2. `make smoke-test` passa su ogni catalogo acceso. Il test è eseguito almeno una volta con `polaris` acceso e una volta con `nessie` acceso.
3. Tutti i notebook degli scenari girano dall'inizio alla fine.
4. Nessuna credenziale è presente nel repository.
5. `VERSIONS.md`, `NOTES.md` ed `EVALUATION.md` sono compilati.
6. `aws/teardown.sh` elimina tutte le risorse AWS create.

## 11. Formato della risposta finale

Alla fine, scrivi un riepilogo con:

1. Le versioni usate.
2. Le deviazioni da questo prompt e il motivo.
3. I problemi aperti.
4. I comandi che l'utente deve eseguire, in ordine.

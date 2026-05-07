# bootstrap-de-stack: Data Engineering tech stack bootstrap (IaC)

An idempotent, layered orchestration framework designed for automated
deployment of a portable and reproducible Data Engineering lab. This stack
provides a production-grade foundation for batch and real-time streaming
analytics.

## Architecture (The Layered Approach)

This platform follows a "Systems Engineering" philosophy, where components
are isolated into logical layers to ensure portability and high availability.

### Phase 1: Foundation (COMPLETE)
*   **Base Environment:** OS provisioning, idempotent and absolute directory
    hierarchies, Python environment, and secure identity/secrets initialization.

### Phase 2: Storage (COMPLETE)
*   **PostgreSQL:** Deployment of a managed, portable database instance with
    Medallion Architecture schemas (raw, staging, analytics), dedicated
    role-based access, automated port discovery, and a generated lab entry
    point.

### Phase 3: Orchestration (COMPLETE)
*   **Apache Airflow:** Deployment of an orchestration engine with dedicated
    metadata database, Fernet key encryption, pre-seeded connections, and
    health-checked scheduler and API server processes. Delivers lab in cold state
    — user starts services on demand via generated entry point.

### Phase 4: Streaming (PLANNED)
*   **Apache Kafka/KRaft:** High-throughput event backbone for real-time
    ingestion.
    *   **Schema Registry (Apicurio):** Schema management with Avro
        serialization for data governance.
*   **Debezium (CDC):** Change Data Capture connector for streaming PostgreSQL
    changes into Kafka topics using logical replication.

### Phase 5: Processing (PLANNED)
*   **Apache Spark:** Distributed compute engine for large-scale batch
    processing and historical analysis.

### Phase 6: Observability (PLANNED)
*   **Monitoring & Logging:** Centralized logging, metrics collection, and
    automated state-validation testing.

### Future Phases (TENTATIVE)
*   **Object Storage:** MinIO (S3-compatible) for local blob/document storage.
*   **Containerization:** Docker Compose deployment profile for cross-platform
    portability.
*   **Cloud Connectors:** AWS S3 integration.
*   **NoSQL & Graph:** MongoDB, Neo4j for document and graph workloads.

## Quick Start
1.  **Clone the repository:**
    `git clone https://github.com/iota-sama/bootstrap-de-stack.git`
2.  **Environment Configuration:**
    `cp settings.env.example settings.env` (Edit values as needed)
3.  **Run Orchestrator:**
    `./run_setup.sh`
4.  **Start Your Lab:**
    `source <LAB_HOME>/bin/lab_entry.sh`
5.  **Stop Your Lab:**
    `bash <LAB_HOME>/bin/lab_shutdown.sh`
6.  **Delete a Lab:**
    `bash utils/delete_lab.sh --lab-name <absolute-path-to-lab>`

## What You Get

After running `run_setup.sh`, your lab includes:

| Component | Details |
|-----------|---------|
| **PostgreSQL** | Latest stable version with Medallion Architecture schemas (Bronze/Silver/Gold), dedicated role-based access, automated port discovery |
| **Apache Airflow** | Full orchestration engine with metadata database, Fernet-encrypted connections, pre-seeded PostgreSQL connection (`lab_postgres`), LocalExecutor for parallel task execution |
| **Lab Scripts** | `lab_entry.sh` (start all services), `lab_shutdown.sh` (graceful stop), `lab_config.sh` (user customizations) |
| **Secrets Management** | Auto-generated credentials stored in `secrets/generated.env` with strict permissions (umask 077) |
| **Port Management** | Automated port allocation with OS-level conflict detection, persisted in factory registry for consistent lab identities |

## Technical Highlights

**Idempotency:** "Check-before-Action" logic ensures scripts can be rerun
without state corruption. Every operation validates current state before
making changes.

**Portability:** Decoupled from system paths using absolute directory
mapping, allowing deployment across any Ubuntu/Debian environment.

**Security:** Strict file permissioning (umask 077) and automated
.gitignore generation for platform secrets. Administrative database
access via Unix socket peer authentication — no plaintext passwords
for admin operations. Application access via dedicated roles with
least-privilege permissions. Fernet key encryption for all Airflow
connections and variables.

**Medallion Architecture:** Pre-configured Bronze (raw), Silver (staging),
and Gold (analytics) schemas for structured data pipeline development.

**Service Discovery:** Automated port allocation with OS-level conflict
detection, persisted via factory registry for consistent lab identities
across reboots.

**Cold Lab Delivery:** The factory provisions and validates all services,
then gracefully shuts them down. Your lab is delivered in a clean,
inactive state. Run `lab_entry.sh` to start everything on demand.

**Extensibility:** Designed for companion tools. Connect DBeaver (open-source
SQL GUI) using credentials from `lab_entry.sh`. Airflow and Spark provide
their own web UIs — all service URLs are dynamically discovered and printed
at startup.

**Modular Architecture:** Lab generation is split into focused generator
scripts under `scripts/generators/`. Each generator produces one artifact
(state file, entry point, shutdown script, config). Easy to understand,
maintain, and extend.

## Airflow Details

| Setting | Value |
|---------|-------|
| **Version** | 3.2.x (configurable via settings.env) |
| **Executor** | LocalExecutor (configurable) |
| **Metadata DB** | Dedicated PostgreSQL database (`airflow_db`) |
| **API server** | Auto-discovered port, health-checked on startup |
| **Connection** | `lab_postgres` pre-seeded for DAG development |
| **DAGs Folder** | `$LAB_HOME/data/airflow/dags/` |
| **Encryption** | Fernet key generated and stored in secrets file |

## Directory Structure
```
$LAB_HOME/
├── bin/
│   ├── lab_entry.sh          # Start all lab services
│   └── lab_shutdown.sh       # Gracefully stop all services
├── configs/
│   ├── state.env             # Internal lab state (auto-generated)
│   ├── lab_config.sh         # User-editable configuration
│   └── airflow.cfg           # Airflow configuration
├── data/
│   ├── postgres/             # PostgreSQL data cluster
│   └── airflow/
│       ├── dags/             # User DAG files
│       └── plugins/          # Airflow plugins
├── logs/
│   ├── postgres/             # PostgreSQL logs
│   └── airflow/              # Airflow task logs
├── run/
│   ├── postgres/             # PostgreSQL socket/PID files
│   └── airflow/              # Airflow PID files
├── venvs/
│   └── airflow/              # Airflow Python virtual environment
└── secrets/
    └── generated.env         # All auto-generated credentials
```

## Requirements

*   **OS:** Ubuntu 20.04+ or Debian 11+ (Other platforms via Docker - planned)
*   **Python:** 3.10+ (installed automatically by Layer 1)
*   **Architecture:** x86_64
*   **Disk:** ~2 GB free (for PostgreSQL + Airflow + dependencies)
*   **Memory:** 2 GB+ recommended
*   **Network:** Internet connection required during initial setup

## Known Limitations (by Design)

These limitations are acknowledged and have planned resolutions in future
phases. They represent deliberate trade-offs made to keep the project
simple, secure, and focused on its core mission: democratized local data
infrastructure for individuals and small teams.

**Services bind to localhost by default:**
All services (PostgreSQL, Airflow, and planned Kafka, Spark) listen on
localhost — accessible to all users on the same machine but not to
external devices. This is secure by default and appropriate for a lab
running on a personal workstation or shared research server. Network
access for team use across multiple machines is configurable via
`settings.env` and will be fully supported in a future deployment profile.

**Services run in single-node mode:**
PostgreSQL, Airflow, and planned Kafka and Spark are configured for
single-node operation — the standard mode for local development, testing,
and personal or small-team data work. Multi-node distributed deployment
is a planned future milestone. The author looks forward to the day he
can afford a small server rack to test it properly.

**Ubuntu/Debian only (cross-platform support planned):**
The factory currently supports Debian-based Linux distributions (Ubuntu
20.04+, Debian 11+). Cross-platform accessibility — making the lab
available on macOS, Windows, and other Linux distributions — is a
priority for a future phase. This may be achieved through containerization,
a web-based configuration interface, or other mechanisms yet to be decided.

**Basic provisioning logging:**
Factory scripts use echo-based logging with `[INFO]`, `[WARN]`, and
`[ERROR]` prefixes. This is sufficient for provisioning visibility but
does not provide structured logging, log rotation, or centralized
aggregation. Comprehensive observability — including structured logging,
metrics collection, and alerting — is planned for Phase 6.

**No authentication on Airflow API server:**
The Airflow API server runs without user authentication. Anyone with
access to the lab machine can reach the Airflow UI and trigger DAGs.
This is acceptable for a local or shared lab environment. Adding
authentication is a planned enhancement.

**No automated backups:**
The lab does not include backup or disaster recovery mechanisms. Users
are responsible for backing up their data directories and DAG files.
Backup automation may be added in a future phase.

**Secrets stored on local filesystem:**
All credentials are stored in `$LAB_HOME/secrets/generated.env` with
strict file permissions (`umask 077`). They are not encrypted at rest.
For a local or shared lab, filesystem permissions and OS user isolation
provide adequate protection. Encrypted secrets storage may be explored
in a future release.

**Airflow metadata database shares the lab's PostgreSQL instance:**
The Airflow metadata database runs on the same PostgreSQL instance as
the lab's data database. For a local lab, this is efficient and practical.
In a production deployment, the metadata database would typically be
isolated on a separate instance.

## Status

This project is in active solo development. Phases 1-3 are complete.
Phase 4 (Kafka, Schema Registry, Debezium) is planned.
See [CHANGELOG.md](CHANGELOG.md) for details.

Feedback and bug reports are welcome via
[GitHub Issues](https://github.com/iota-sama/bootstrap-de-stack/issues).

## License

MIT License — see [LICENSE](LICENSE) for details.


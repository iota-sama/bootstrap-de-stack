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

### Phase 3: Orchestration (IN PROGRESS)
*   **Apache Airflow:** Deployment of an orchestration engine for scheduled
    DAG execution and pipeline management. *(Code complete — final testing
    and push in progress)*

### Phase 4: Streaming (PLANNED)
*   **Apache Kafka/KRaft:** High-throughput event backbone for real-time
    ingestion, including Schema Registry for data governance.
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

## Technical Highlights

**Idempotency:** "Check-before-Action" logic ensures scripts can be rerun
without state corruption. Every operation validates current state before
making changes.

**Portability:** Decoupled from system paths using absolute directory
mapping, allowing deployment across any Ubuntu/Debian environment.

**Security:** Strict file permissioning (umask 077) and automated
.gitignore generation for platform secrets. Superuser access via OS-level
peer authentication — no plaintext passwords for admin operations.

**Medallion Architecture:** Pre-configured Bronze (raw), Silver (staging),
and Gold (analytics) schemas for structured data pipeline development.

**Service Discovery:** Automated port allocation with OS-level conflict
detection, persisted via factory registry for consistent lab identities
across reboots.

**Extensibility:** Designed for companion tools. Connect DBeaver (open-source
SQL GUI) using credentials from `lab_entry.sh`. Future phases will add web
UIs for Airflow and Spark — all service URLs are dynamically discovered and
printed at startup.

## Requirements

*   **OS:** Ubuntu 20.04+ or Debian 11+
*   **Architecture:** x86_64
*   **Disk:** ~1 GB free (for PostgreSQL + dependencies)
*   **Memory:** 1 GB+ recommended
*   **Network:** Internet connection required during initial setup

## Status

This project is in active solo development. Phases 1-2 are complete.
Phase 3 (Airflow) is in progress. See [CHANGELOG.md](CHANGELOG.md) for details.

Feedback and suggestions are welcome via [GitHub Issues](https://github.com/iota-sama/bootstrap-de-stack/issues)

## License

MIT License — see [LICENSE](LICENSE) for details.

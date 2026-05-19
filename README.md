# bootstrap-de-stack: Data Engineering Lab Factory (IaC)

A layered, idempotent infrastructure-as-code framework that provisions a complete, production-pattern data engineering environment from a single command. Built for learning, development, and testing. Free and open-source.

## Architecture (The Layered Approach)

This platform follows a "Systems Engineering" philosophy, where components are isolated into logical layers to ensure portability and high availability.

### Phase 1: Foundation (COMPLETE)
*   **Base Environment:** OS provisioning, idempotent and absolute directory hierarchies, Python environment, and secure identity/secrets initialization.

### Phase 2: Storage (COMPLETE)
*   **PostgreSQL:** Deployment of a managed, portable database instance with Medallion Architecture schemas (raw, staging, analytics), dedicated role-based access, automated port discovery, and a generated lab entry point.

### Phase 3: Orchestration (COMPLETE)
*   **Apache Airflow:** Deployment of an orchestration engine with dedicated metadata database, Fernet key encryption, pre-seeded connections, and health-checked scheduler and API server processes. Delivers lab in cold state. User starts services on demand via generated entry point.

### Phase 4: Streaming (COMPLETE)
*   **Apache Kafka/KRaft:** High-throughput event backbone with KRaft consensus (no ZooKeeper). Three-listener architecture (CLIENT, INTERNAL, CONTROLLER) with SASL/PLAIN authentication, dynamic port discovery, and configurable heap and retention.
*   **Schema Registry (Apicurio):** Schema management with Avro serialization, Kafka-backed storage, and Confluent-compatible REST API. Dual-port allocation for application and management interfaces.
*   **Debezium (CDC):** Change Data Capture connector streaming PostgreSQL WAL changes into Kafka topics using logical replication and Avro encoding. Auto-created publication and replication slot with slot preservation across restarts.

### Phase 5: Processing (PLANNED)
*   **Apache Spark:** Distributed compute engine for large-scale batch processing and historical analysis.

### Phase 6: Observability (PLANNED)
*   **Monitoring & Logging:** Centralized logging, metrics collection, and automated state-validation testing.

### Phase 7: Distributed Deployment (PLANNED)
*   **Multi-Node Architecture:** Multi-broker Kafka, multi-worker Spark, and distributed service deployment across machines. Single-command provisioning with shared cluster configuration.

### Future Phases (TENTATIVE)
*   **Object Storage:** MinIO (S3-compatible) for local blob/document storage.
*   **Containerization:** Docker Compose deployment profile for cross-platform portability.
*   **Cloud Connectors:** AWS integration.
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
    `bash utils/delete_lab.sh --lab-path <absolute-path-to-lab> [--force]`

## Factory Behavior

The factory follows a behavioral contract defined in [CONTRACT.md](CONTRACT.md). Key points:

- **Idempotent:** Running the factory multiple times with the same settings is safe. Completed steps are detected and skipped.
- **Interruption recovery:** If the factory is interrupted, re-run it. It resumes from the beginning. Idempotent scripts skip completed work.
- **Completion protection:** Once a lab is complete, the factory refuses to overwrite it. Use `--force` to intentionally reprovision.
- **Name collision resolution:** If a lab name already exists, the factory automatically appends a numeric suffix.
- **Persistent state:** Port assignments, secrets, and credentials persist across factory reruns and system reboots.
- **Path portability:** The lab can be moved to a different directory on the same machine. Configuration files are automatically updated at startup.

## What You Get

After running `run_setup.sh`, your lab includes:

| Component | Details |
|-----------|---------|
| **PostgreSQL** | Latest stable version with Medallion Architecture schemas (Bronze/Silver/Gold), dedicated role-based access, automated port discovery, logical replication enabled for CDC |
| **Apache Airflow** | Full orchestration engine with metadata database, Fernet-encrypted connections, pre-seeded PostgreSQL connection (`lab_postgres`), Kafka connection (`lab_kafka`), Schema Registry connection (`lab_schema_registry`), LocalExecutor for parallel task execution |
| **Apache Kafka** | KRaft-based event streaming (no ZooKeeper), SASL/PLAIN authentication, three-listener architecture (CLIENT, INTERNAL, CONTROLLER), all ports dynamically discovered, configurable heap and log retention |
| **Schema Registry** | Apicurio Registry with Kafka-backed storage, Confluent-compatible REST API, Avro schema enforcement, dual-port allocation (application and management), both ports dynamically discovered |
| **Kafka Connect + Debezium CDC** | Distributed Connect worker with Debezium PostgreSQL connector, Avro serialization with Schema Registry, real-time CDC from all Medallion schemas into Kafka topics, auto-created publication and replication slot with slot preservation |
| **Lab Scripts** | `lab_entry.sh` (start all services with START_STREAMING_SERVICES toggle, automatic path correction for moved labs), `lab_shutdown.sh` (graceful stop with WAL health check), `lab_config.sh` (user customizations) |
| **Secrets Management** | Auto-generated credentials for PostgreSQL, Airflow, Kafka, and Debezium stored in `secrets/generated.env` with strict permissions (umask 077) |
| **Port Management** | Automated port allocation with OS-level conflict detection, persisted in factory registry for consistent lab identities across reboots |
| **Integration Tests** | CDC pipeline validation run during provisioning, results logged to `logs/test_results.log` |

## Technical Highlights

**Idempotency:** "Check-before-Action" logic ensures scripts can be rerun without state corruption. Every operation validates current state before making changes.

**Portability:** Decoupled from system paths using absolute directory mapping, allowing deployment across any Ubuntu/Debian environment. Lab includes its own pinned JDK. No system Java dependency. The lab can be moved to a different directory on the same machine and will automatically correct its configuration at startup.

**Security:** Strict file permissioning (umask 077) and automated .gitignore generation for platform secrets. Administrative database access via Unix socket peer authentication. No plaintext passwords for admin operations. Application access via dedicated roles with least-privilege permissions. Each service (PostgreSQL, Airflow, Debezium, Kafka) gets its own dedicated credentials with only the privileges it needs. Kafka uses SASL/PLAIN authentication for multi-user environments. Fernet key encryption for all Airflow connections and variables.

**Medallion Architecture:** Pre-configured Bronze (raw), Silver (staging), and Gold (analytics) schemas for structured data pipeline development. CDC captures changes from all schemas into Kafka topics automatically.

**Service Discovery:** Automated port allocation with OS-level conflict detection, persisted via factory registry for consistent lab identities across reboots. Each service gets a unique, persistent port. All six streaming service ports are dynamically discovered.

**Cold Lab Delivery:** The factory provisions and validates all services, runs integration tests, then gracefully shuts everything down. Your lab is delivered in a clean, inactive state. Run `lab_entry.sh` to start everything on demand.

**Extensibility:** Designed for companion tools. Connect DBeaver (open-source SQL GUI) using credentials from `lab_entry.sh`. Airflow, Schema Registry, and Kafka Connect provide their own web UIs and REST APIs. All service URLs are dynamically discovered and printed at startup.

**Modular Architecture:** Lab generation is split into focused generator scripts under `scripts/generators/`. Each generator produces one artifact (state file, entry point, shutdown script, config). The build, test, deliver pipeline ensures quality at every factory run.

**Streaming Infrastructure:** Full CDC pipeline from PostgreSQL to Kafka with Debezium using Avro serialization and Schema Registry. Pre-seeded Airflow connections for immediate DAG development against Kafka topics.

## Airflow Details

| Setting | Value |
|---------|-------|
| **Version** | 3.2.x (configurable via settings.env) |
| **Executor** | LocalExecutor (configurable) |
| **Metadata DB** | Dedicated PostgreSQL database (`airflow_db`) |
| **API server** | Auto-discovered port, health-checked on startup |
| **Connections** | `lab_postgres` (PostgreSQL), `lab_kafka` (Kafka with SASL), `lab_schema_registry` (Schema Registry) |
| **DAGs Folder** | `$LAB_HOME/data/airflow/dags/` |
| **Encryption** | Fernet key generated and stored in secrets file |
| **Providers** | PostgreSQL, Apache Kafka |

## Kafka & Streaming Details

| Setting | Value |
|---------|-------|
| **Kafka Version** | 4.0.2 (KRaft only, no ZooKeeper, Scala 2.13) |
| **Authentication** | SASL/PLAIN with generated kafka_admin credentials |
| **Listeners** | CLIENT (broker), INTERNAL (inter-broker), CONTROLLER (KRaft) |
| **Client Port** | Auto-discovered (default 9092) |
| **Internal Port** | Auto-discovered (default 9094) |
| **Controller Port** | Auto-discovered (default 9093) |
| **Schema Registry** | Apicurio 3.2.4 (application and management ports auto-discovered) |
| **Connect REST API** | Auto-discovered (default 8083) |
| **Debezium Version** | 3.4.3.Final |
| **Serialization** | Avro with Schema Registry integration |
| **CDC Tables** | raw.*, staging.*, analytics.* (configurable) |
| **Topic Prefix** | lab_<stack_id_short> |

## Directory Structure

```

$LAB_HOME/
├── bin/
│   ├── lab_entry.sh          # Start all lab services
│   └── lab_shutdown.sh       # Gracefully stop all services
├── configs/
│   ├── state.env             # Internal lab state (auto-generated)
│   ├── lab_config.sh         # User-editable configuration
│   ├── factory.state         # Factory provisioning state
│   ├── airflow.cfg           # Airflow configuration
│   ├── kafka/
│   │   ├── server.properties # Kafka broker configuration
│   │   └── kafka_jaas.conf   # SASL authentication configuration
│   └── connect/
│       └── connect-distributed.properties
├── data/
│   ├── postgres/             # PostgreSQL data cluster
│   ├── kafka/
│   │   └── logs/             # Kafka topic data + KRaft metadata
│   └── airflow/
│       ├── dags/             # User DAG files
│       └── plugins/          # Airflow plugins
├── engine/
│   ├── java/                 # Lab-isolated JDK (Eclipse Temurin 17)
│   ├── kafka/                # Kafka binaries
│   │   └── plugins/
│   │       ├── debezium-postgres/
│   │       └── avro-converter/
│   ├── schema-registry/      # Apicurio Registry runner JAR
│   └── airflow/              # Airflow Python virtual environment
├── logs/
│   ├── postgres/
│   ├── airflow/
│   ├── kafka/
│   ├── schema-registry/
│   ├── connect/
│   └── test_results.log      # CDC integration test results
├── runtime/
│   ├── postgres/             # PostgreSQL socket/PID files
│   ├── airflow/              # Airflow PID files
│   ├── kafka/                # Kafka PID files
│   ├── schema-registry/      # Schema Registry PID files
│   └── connect/              # Connect PID files
└── secrets/
└── generated.env         # All auto-generated credentials

```

## Requirements

*   **OS:** Ubuntu 20.04+ or Debian 11+ (Other platforms via Docker planned)
*   **Python:** 3.10+ (installed automatically by Layer 1)
*   **Java:** 17+ (provisioned per-lab via Eclipse Temurin, no system JDK required)
*   **Architecture:** x86_64
*   **Disk:** ~4 GB free (for full stack: PostgreSQL, Airflow, Kafka, and dependencies)
*   **Memory:** 4 GB+ recommended (full streaming stack), 2 GB minimum (PostgreSQL and Airflow only)
*   **Network:** Internet connection required during initial setup for downloads

## Known Limitations (by Design)

These limitations are acknowledged and have planned resolutions in future phases. They represent deliberate trade-offs made to keep the project simple, secure, and focused on its core mission: democratized local data infrastructure for individuals and small teams.

**Services bind to localhost by default:**
All services (PostgreSQL, Airflow, Kafka, Schema Registry, Connect) listen on localhost. Accessible to all users on the same machine but not to external devices. This is secure by default and appropriate for a lab running on a personal workstation or shared research server. Network access for team use across multiple machines is configurable via settings.env and will be fully supported in a future deployment profile.

**Services run in single-node mode:**
PostgreSQL, Airflow, Kafka, and Connect are configured for single-node operation. The standard mode for local development, testing, and personal or small-team data work. Kafka's KRaft configuration uses combined broker and controller mode. Multi-node distributed deployment is planned as Phase 7.

**Kafka SASL/PLAIN without SSL encryption:**
Kafka uses SASL/PLAIN authentication to control access in multi-user environments on shared machines. Connections are not encrypted (SASL_PLAINTEXT). SSL/TLS encryption is deferred to a future phase when multi-machine deployment is supported.

**All-or-nothing service operation:**
The lab is designed for all-services or no-services operation. Running PostgreSQL without the streaming stack while replication slots exist may cause WAL accumulation over time if the database is actively receiving writes. Use lab_shutdown.sh for complete shutdown. WAL health checks at startup and shutdown provide visibility into slot status.

**CDC events in Avro binary format:**
Debezium CDC events in Kafka topics are Avro-encoded binary. Use kafka-avro-console-consumer for human-readable debugging. Schema Registry stores and serves schemas for decoding.

**JVM memory footprint:**
Kafka broker (default 512MB heap), Connect worker (512MB), Schema Registry (256MB), plus the JVM itself, together consume approximately 1.5GB of RAM at runtime. Combined with PostgreSQL shared buffers and Airflow workers, 4GB+ RAM is recommended for full streaming stack operation. All heap sizes are configurable via settings.env.

**Cross-machine portability not supported:**
The lab can be moved to a different directory on the same machine. Configuration files are automatically updated at startup. Moving to a different machine is not supported due to system-level dependencies. Full environment migration tooling is planned for a future release.

**Ubuntu/Debian only (cross-platform support planned):**
The factory currently supports Debian-based Linux distributions (Ubuntu 20.04+, Debian 11+). Cross-platform accessibility is a priority for a future phase, planned through containerization or alternative mechanisms.

**Basic provisioning logging:**
Factory scripts use echo-based logging with [INFO], [WARN], and [ERROR] prefixes. Sufficient for provisioning visibility but does not provide structured logging, log rotation, or centralized aggregation. Comprehensive observability is planned for Phase 6.

**No automated backups:**
The lab does not include backup or disaster recovery mechanisms. Users are responsible for backing up their data directories and DAG files. Backup automation may be added in a future phase.

**Secrets stored on local filesystem:**
All credentials are stored in `$LAB_HOME/secrets/generated.env` with strict file permissions (umask 077). They are not encrypted at rest. For a local or shared lab, filesystem permissions and OS user isolation provide adequate protection.

**Airflow metadata database shares the lab's PostgreSQL instance:**
The Airflow metadata database runs on the same PostgreSQL instance as the lab's data database. For a local lab, this is efficient and practical. In a production deployment, the metadata database would typically be isolated on a separate instance.

## Status

This project is in active solo development. Phases 1 through 4 are complete. Phase 5 (Apache Spark) and Phase 6 (Observability) are planned. Phase 7 (Distributed Deployment) will extend the platform to multi-node architectures. See [CHANGELOG.md](CHANGELOG.md) for details.

Feedback and bug reports are welcome via [GitHub Issues](https://github.com/iota-sama/bootstrap-de-stack/issues).

## License

Apache License 2.0. See [LICENSE](LICENSE) for details.
```
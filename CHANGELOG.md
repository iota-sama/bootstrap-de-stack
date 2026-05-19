# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.4.0] — 2026-05-19 — Phase 4: Streaming (Apache Kafka + Debezium + Schema Registry)

### Added

- Per-lab pinned JDK provisioning via Eclipse Temurin (Java 17)
  - Downloaded through the Adoptium API with SHA-256 checksum verification
  - Stored in $LAB_HOME/engine/java/ for full lab isolation
  - Java version validated at provision time; fails fast if below 17
  - No system JDK dependency (default-jdk removed from base setup)
- Apache Kafka 4.0.2 with KRaft consensus (ZooKeeper removed)
  - Tarball download with Scala 2.13, extracted to engine/kafka/
  - Binary and data separation: topic data lives in data/kafka/, binaries in engine/kafka/
  - Three listeners: CLIENT (broker), INTERNAL (inter-broker), CONTROLLER (KRaft)
  - All three ports dynamically discovered via port manager
  - Minimal server.properties generated early for KRaft metadata formatting
  - Full config with SASL, replication, and retention settings generated at runtime
  - Health check via kafka-broker-api-versions.sh with 60s timeout
- SASL/PLAIN authentication for Kafka
  - kafka_admin user with generated password stored in secrets
  - JAAS configuration file with restricted permissions (umask 077)
  - All Kafka clients (broker, Connect, Schema Registry, Airflow) conditionally use SASL
  - Configurable via KAFKA_ENABLE_SASL in settings.env
- Apicurio Schema Registry 3.2.4
  - Runner JAR extracted from official archive, stored in engine/schema-registry/
  - Kafka-backed storage for schemas
  - Confluent-compatible API at /apis/ccompat/v7
  - Dual-port allocation: application port and management port, both dynamically discovered
  - Health check on management interface with 30s timeout
- Kafka Connect in Distributed mode with Debezium CDC
  - Debezium PostgreSQL connector 3.4.3.Final downloaded from Maven Central
  - Avro converter 8.0.5 (Confluent Platform, Apache 2.0 licensed)
  - Connect worker configured with SASL authentication
  - connect-distributed.properties generated with restricted permissions (umask 077)
  - REST API health check with 30s timeout
- Debezium CDC connector for PostgreSQL
  - Dedicated debezium_connector role with REPLICATION privilege
  - Auto-created publication and replication slot
  - Avro serialization with Schema Registry integration from the start
  - CDC over all Medallion schemas: raw.*, staging.*, analytics.*
  - Connector configured via Connect REST API with idempotent create-or-update logic
  - Connector status polled until RUNNING with 30s timeout
  - Replication slot preserved across restarts for CDC continuity
  - WAL health check at lab startup and shutdown (informational, slot not dropped)
  - Slot dropped only on lab deletion
- PostgreSQL WAL configuration for logical replication
  - wal_level=logical, max_wal_senders=10, max_replication_slots=10
  - Applied in custom_lab.conf sidecar before first PostgreSQL ignition
  - No mid-provisioning restart needed
- Airflow streaming connection seeding
  - lab_kafka connection (Kafka provider with SASL credentials)
  - lab_schema_registry connection (generic HTTP for Apicurio)
  - Apache Kafka provider installed in Airflow virtual environment
  - Both native Apicurio API and Confluent-compatible API endpoints documented
- Integration testing
  - CDC pipeline end-to-end validation in 98_run_tests.sh
  - Test schema created, data inserted, topic verified, then cleaned up
  - Results logged to $LAB_HOME/logs/test_results.log
  - Tests do not block cold delivery on failure
- Factory state tracking
  - factory.state file in $LAB_HOME/configs/ tracks provisioning progress
  - Records STATUS, CURRENT_SCRIPT, LAST_COMPLETED, and timestamps
  - Interrupted provisioning detected and resumed on re-run
  - Completed labs protected from accidental overwrite
  - --force flag to override completion check with automatic running-lab shutdown
  - Lab name collision detection with automatic suffix increment
- Port registry extended with streaming service entries
  - kafka_broker (9092), kafka_controller (9093), kafka_internal (9094)
  - schema_registry (8081), schema_registry_management (9000), kafka_connect (8083)
- New provisioning scripts (08 through 15)
  - 08_setup_java.sh: JDK download, extraction, and validation
  - 09_setup_kafka.sh: Kafka tarball download, extraction, KRaft format
  - 10_runtime_kafka.sh: Kafka configuration, SASL, startup, health check
  - 11_setup_schema_registry.sh: Apicurio download and extraction
  - 12_runtime_schema_registry.sh: Schema Registry startup and health check
  - 13_setup_connect.sh: Debezium and Avro converter download
  - 14_runtime_connect.sh: Connect startup, Debezium connector configuration
  - 15_seed_airflow_kafka.sh: Airflow Kafka and Schema Registry connection seeding
- Script renumbering for build-test-deliver flow
  - 97_assemble_lab.sh (renamed from 98)
  - 98_run_tests.sh (new)
  - 99_finalize_lab.sh (unchanged)
- Behavioral contract (CONTRACT.md)
  - Defines factory guarantees, prohibitions, and user responsibilities
  - Numbered guarantees for testability and reference
- Lab path portability
  - lab_entry.sh automatically corrects absolute paths when lab directory is moved
  - Configuration files updated at startup with new LAB_HOME

### Changed

- Directory restructure for cleaner separation of concerns
  - engine/: service binaries and runtimes (Java, Kafka, Schema Registry, Airflow venv)
  - runtime/: ephemeral runtime artifacts (PIDs, sockets), renamed from run/
  - data/: pure user data, Kafka data moved from kafka-data/ to data/kafka/
  - venvs/ removed; Airflow venv now in engine/airflow/
- Variable renames across all scripts for consistency
  - *_RUN_DIR renamed to *_RUNTIME_DIR
  - JAVA_VERSION renamed to JAVA_MAJOR
  - SCHEMA_REGISTRY_DATA_DIR renamed to SCHEMA_REGISTRY_HOME
  - AIRFLOW_VENV path updated to engine/airflow/
- 00_base_setup.sh: removed default-jdk, added engine/ and runtime/ directories, umask restore after secrets creation
- 02_runtime_pg_service.sh: added WAL logical replication settings, PG_RUNTIME_DIR rename
- 04_setup_airflow_venv.sh: Apache Kafka provider installation, path updated to engine/airflow/
- 06_configure_airflow.sh: removed hardcoded sql_alchemy_conn and base_url from airflow.cfg
- port_manager.sh: DEFAULT_PORTS array updated with all streaming service entries
- run_setup.sh: Phase 4 script calls, factory state tracking, --force flag with automatic shutdown, name collision resolution, stale environment warning, streaming cleanup trap
- 99_finalize_lab.sh: streaming service shutdown blocks, WAL health check, replication slot preserved
- generate_state_env.sh: all Phase 4 state variables including Schema Registry URLs and Airflow connection IDs
- generate_lab_entry.sh: streaming startup with SASL awareness, path correction for moved labs, Schema Registry dual-URL summary
- generate_lab_shutdown.sh: streaming shutdown blocks, WAL health check, replication slot preserved
- delete_lab.sh: streaming shutdown blocks, replication slot cleanup on deletion
- settings.env.example: Java, Kafka, Schema Registry, Connect, and Debezium configuration sections
- .gitignore: added cache/ directory
- Removed self-referential comments from generated files and secrets
- Port discovery simplified: scripts always call port_manager.sh directly, environment variable guards removed

### Architectural Decisions

- Per-lab JDK isolation: Java 17 provisioned per lab via tarball. Version pinned, fully isolated, reproducible.
- Kafka 4.0 KRaft: ZooKeeper removed entirely. Forward-looking choice for a greenfield project. Single-node combined broker and controller mode.
- Binary and data separation: Kafka binaries in engine/kafka/, topic data in data/kafka/. Version upgrades replace binaries without touching data.
- Three-listener architecture: CLIENT for external connections, INTERNAL for inter-broker communication, CONTROLLER for KRaft protocol. Production-correct even for single-node.
- SASL/PLAIN authentication: Multi-user security on shared machines. Testable locally without SSL. SSL deferred to multi-machine phase.
- Apicurio over Confluent Schema Registry: Apache 2.0 license alignment. Confluent-compatible API bridges the ecosystem gap.
- Avro serialization from the start: Production-standard serialization with full Schema Registry integration.
- Dual-port Schema Registry: Application and management ports separated per Quarkus best practices. Both dynamically discovered.
- Replication slot preservation: Slots kept alive across restarts for CDC continuity. WAL health checks provide visibility. Slots dropped only on lab deletion.
- All-or-nothing service operation: Lab designed for full-stack operation. Partial operation documented as a known limitation.
- Build, test, deliver flow: Assembly (97), integration tests (98), cold delivery (99).
- Factory state tracking: factory.state provides visibility into provisioning progress. Supports interrupted run detection and completed lab protection.
- Directory restructure: engine/ for binaries, runtime/ for PIDs, data/ for user content.
- Lab path portability: Configuration files automatically corrected when lab directory is moved.
- Defensive parsing: KRaft metadata cluster ID extraction validates non-empty result.

---

## [0.3.1] — 2026-05-11

### Changed
- License changed from MIT to Apache License 2.0
- README: Phase 4 status updated to IN DEVELOPMENT
- README: Quick Start corrected for delete_lab.sh usage
- README: Removed incorrect Known Limitation about Airflow lacking authentication
- CHANGELOG: Updated Unreleased section with Phase 4 items

---

## [0.3.0] — 2026-05-08 — Phase 3: Orchestration (Apache Airflow)

### Added
- Airflow 3.2.x installation in isolated Python virtual environment
  - Version-pinned installation with official constraints file for reproducible builds
  - Python version validation (3.10+ required) with clear error messaging
  - PostgreSQL provider verification with explicit fallback installation
- Airflow metadata database provisioning on lab PostgreSQL
  - Dedicated airflow_db database and airflow_admin role with generated password
  - Database initialization via airflow db migrate (idempotent)
  - Least-privilege access pattern
- Fernet key generation and management
  - Cryptographic key generated via Python cryptography library
  - Stored in secrets/generated.env with strict permissions
  - Idempotent: existing key preserved on reruns
- Airflow configuration (airflow.cfg) generation
  - All paths anchored to LAB_HOME
  - LocalExecutor as default with configurable parallelism
  - Example DAGs disabled by default
- Automated connection seeding
  - lab_postgres connection pre-configured for DAG development
  - Connection URI built from lab credentials in generated.env
  - Idempotent: connection deleted and recreated on reruns
- Airflow scheduler and API server with health checks
  - PID-based idempotent startup
  - Scheduler health check: process existence verification with 30s timeout
  - API server health check: HTTP 200 from /health endpoint with 30s timeout
- Port discovery for Airflow API server via port manager
- Lab shutdown script (lab_shutdown.sh)
  - Graceful stop for Airflow API server and scheduler
  - Graceful stop for PostgreSQL via pg_ctl
  - PID file cleanup after shutdown
- Lab deletion utility (utils/delete_lab.sh)
  - Complete teardown: stops processes, removes directory, cleans registry
  - Confirmation prompt with --force flag for scripting
- Cold state delivery architecture
  - Factory provisions and validates all services, then shuts them down
  - 99_finalize_lab.sh orchestrates graceful shutdown
  - Lab delivered inactive, user starts on demand via lab_entry.sh
- Generator-based modular architecture (scripts/generators/)
  - generate_state_env.sh, generate_lab_config.sh, generate_lab_entry.sh, generate_lab_shutdown.sh
  - 98_assemble_lab.sh as thin orchestrator
  - Replaces monolithic 99_generate_lab_manifest.sh
- New provisioning scripts: 04 through 07
  - 04_setup_airflow_venv.sh: Python venv creation and Airflow installation
  - 05_provision_airflow_db.sh: metadata database and role provisioning
  - 06_configure_airflow.sh: config generation, Fernet key, connection seeding
  - 07_runtime_airflow.sh: port discovery, scheduler and API server startup, health checks

### Changed
- Port manager registry columns reordered for more efficient queries
- Port manager validates registered ports against OS before returning
- run_setup.sh extended with Airflow layer calls and trap cleanup handler
- 00_base_setup.sh creates run/ directory and adds to platform .gitignore
- settings.env.example expanded with Airflow configuration section

### Architectural Decisions
- Cold state delivery: factory provisions and validates all services, then shuts them down. Lab delivered inactive. User starts on demand.
- Generator-based modular architecture: each generated artifact has a dedicated generator script. Extensible for future services.
- Application-level connection seeding: Airflow connections pre-configured during provisioning.
- Per-service privilege isolation: each service gets its own PostgreSQL role with least-privilege permissions.
- Admin via socket, application via TCP: consistent with Phase 2 authentication model.
- Airflow metadata isolation: airflow_db separate from dev_lab. airflow_admin role has no access to user data.

---

## [0.2.1] — 2026-05-05

### Added
- CHANGELOG.md to track all project changes and architectural decisions

### Changed
- README.md updated with accurate phase descriptions and project status

---

## [0.2.0] — 2026-05-01 — Phase 2: Storage (PostgreSQL)

### Added
- PostgreSQL 18 installation from official PGDG repository
- Idempotent data cluster initialization with initdb
  - Peer authentication for local admin, SCRAM-SHA-256 for remote connections
  - Data checksums enabled, UTF-8 encoding
- Three provisioning scripts: 01_setup_pg_engine.sh, 02_runtime_pg_service.sh, 03_provision_pg_schema.sh
- Runtime service with sidecar configuration (custom_lab.conf)
  - Configurable performance settings
  - Version-aware feature flags for PG 18+
  - Health check with 60-second timeout
- Port management utility (port_manager.sh)
  - Registry-backed allocation for persistent lab identity
  - OS-level conflict detection
  - Idempotent: returns existing port if already assigned
- Schema provisioning with secure credential generation
  - Random password generation via openssl
  - Credentials persisted in secrets/generated.env
  - Medallion Architecture schemas: raw, staging, analytics
  - Role-based access for each schema
- Lab manifest generation (99_generate_lab_manifest.sh)
  - state.env, lab_entry.sh, lab_config.sh
- Expanded configuration template (settings.env.example)

### Architectural Decisions
- System binaries and per-lab data cluster: PostgreSQL engine at system level, data cluster per lab under LAB_HOME
- Lab owner as PostgreSQL superuser: OS user running factory becomes PG superuser, peer auth via Unix socket
- Application user for data access: dedicated role with password for application connections, no superuser
- Config sidecar pattern: lab config in separate file included into main config
- Port registry for multi-lab isolation: centralized port manager with CSV persistence
- Medallion Architecture as default: Bronze, Silver, Gold schemas provisioned automatically

---

## [0.1.0] — 2026-04-27 — Phase 1: Foundation

### Added
- Master orchestration script (run_setup.sh)
  - Sudo keepalive mechanism
  - Configuration handshake: settings.env priority over settings.env.example
  - Layered execution of provisioning scripts
  - Strict error handling (set -euo pipefail)
- Base environment setup (00_base_setup.sh)
  - System package installation: Python 3, Java, and build tools
  - Idempotent directory hierarchy under LAB_HOME
  - Platform .gitignore auto-generation
  - Secrets file generation with strict permissions (umask 077)
- Configuration template (settings.env.example)

### Architectural Decisions
- Factory pattern: single entry point provisions entire lab
- Absolute paths only: scripts work regardless of invocation directory
- Environment inheritance: variables forwarded via export, validated with fail-fast checks
- Idempotency everywhere: check-before-action on every operation
- Secrets isolation: single secrets file per lab, umask 077, excluded from version control
- Configuration handshake: settings.env takes priority over template
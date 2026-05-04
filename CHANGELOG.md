# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased] — Phase 3: Orchestration (Apache Airflow)

### In Progress (Code Complete — Review & Testing)

- Airflow 3.2.x installation in isolated Python virtual environment
- Dedicated Airflow metadata database on lab PostgreSQL
- Fernet key generation for connection encryption
- Automated `lab_postgres` connection seeding for DAG development
- Scheduler and webserver startup with health checks
- Port discovery via registry for Airflow webserver
- Lab shutdown script (`lab_shutdown.sh`) for graceful service termination
- Lab deletion utility (`utils/delete_lab.sh`) for complete teardown
- Cold state delivery: factory shuts down all services after provisioning
- `lab_entry.sh` startup: activates PostgreSQL and Airflow on demand
- Generator-based modular architecture (`scripts/generators/`)
- `98_assemble_lab.sh` and `99_finalize_lab.sh` replace monolithic manifest
- `run_setup.sh` extended with Airflow layer calls
- `settings.env.example` expanded with Airflow configuration variables

---

## [0.2.1] — 2026-05-05

### Added
- CHANGELOG.md to track all project changes, architectural decisions, and
  version history

### Changed
- README.md updated with accurate phase descriptions, requirements section,
  and project status
- Phase 3 status clarified as "IN PROGRESS" with implementation note
- Phase titles aligned with actual layer contents

---

## [0.2.0] — 2026-05-01 — Phase 2: Storage (PostgreSQL)

### Added
- PostgreSQL 18 installation from official PGDG repository
- Idempotent data cluster initialization with `initdb`
  - Peer authentication for local admin, SCRAM-SHA-256 for remote connections
  - Data checksums enabled, UTF-8 encoding
- Three new provisioning scripts:
  - `01_setup_pg_engine.sh` — PostgreSQL engine installation and cluster init
  - `02_runtime_pg_service.sh` — runtime configuration and service ignition
  - `03_provision_pg_schema.sh` — role, database, and schema provisioning
- Runtime service with sidecar configuration (`custom_lab.conf`)
  - Configurable performance settings (shared_buffers, max_connections)
  - Version-aware feature flags (async I/O for PG 18+)
  - Health check with 60-second timeout
- Port management utility (`port_manager.sh`)
  - Registry-backed allocation (`lab_registry.csv`) for persistent lab identity
  - OS-level conflict detection (ss/netstat fallback)
  - Idempotent: returns existing port if already assigned
  - Default port table for known services (postgres, airflow, kafka, spark)
- Schema provisioning with secure credential generation
  - Random password generation via `openssl rand -base64 12`
  - Credentials persisted in `secrets/generated.env`
  - Medallion Architecture schemas: `raw`, `staging`, `analytics`
  - Role-based access: each schema owned by dedicated lab role
- Lab manifest generation (`99_generate_lab_manifest.sh`)
  - `state.env` — internal lab state (regenerated every run)
  - `lab_entry.sh` — user entry point with connection details
  - `lab_config.sh` — user-editable config (generated once, never overwritten)
- `lab_registry.csv` for persistent port and service tracking across reboots
- Expanded configuration template (`settings.env.example`)
  - PostgreSQL version, data directory, user prefix, database name
  - Performance tuning: shared buffers, max connections

### Changed
- `run_setup.sh` extended to call Layer 2 provisioning scripts
- `00_base_setup.sh` now installs `uuid-runtime` for lab identity generation
- `.gitignore` updated to exclude `lab_registry.csv`

### Architectural Decisions
- **System binaries + per-lab data cluster:** PostgreSQL engine installed at
  the system level. Each lab gets its own isolated data cluster under
  `$LAB_HOME`. Multiple labs share one engine installation without
  interfering with each other.
- **Peer authentication for admin operations:** Superuser access uses OS-level
  peer authentication via local socket. No plaintext passwords for
  administrative tasks.
- **Application user for data access:** A dedicated role with generated
  password handles all application-level connections (DBeaver, future
  Airflow, pipelines). No superuser privileges for application access.
- **Config sidecar pattern:** Lab-specific configuration written to a separate
  file and included via `include` directive. The main PostgreSQL
  configuration file is never edited directly, making updates safe and
  isolated.
- **Port registry for multi-lab isolation:** All service ports allocated
  through a centralized manager, persisted in CSV format, and uniquely
  identified by lab name and service. Multiple labs can run simultaneously
  without port conflicts.
- **Medallion Architecture as default:** Bronze (raw), Silver (staging), and
  Gold (analytics) schemas provisioned automatically. Provides a structured
  data pipeline foundation out of the box without requiring user
  configuration.
- **Lab manifest generation:** Each lab receives generated entry point
  scripts, state files, and user configuration. The lab is self-documenting
  and self-contained after provisioning.

---

## [0.1.0] — 2026-04-27 — Phase 1: Foundation

### Added
- Master orchestration script (`run_setup.sh`)
  - Sudo keepalive mechanism for long-running privileged operations
  - Configuration handshake: `settings.env` > `settings.env.example` fallback
  - Layered execution of all provisioning scripts
  - Strict error handling (`set -euo pipefail`) throughout
- Base environment setup (`00_base_setup.sh`)
  - System package installation: Python 3, Java, and essential build tools
  - Idempotent directory hierarchy under `$LAB_HOME`:
    `bin/`, `configs/`, `data/`, `logs/`, `venvs/`, `secrets/`
  - Platform `.gitignore` auto-generation inside `$LAB_HOME`
  - Secrets file generation with strict permissions (`umask 077`) and
    environment identity: `ENV_NAME`, `STACK_ID`, `GEN_DATE`
- Configuration template (`settings.env.example`)
  - Environment identity, platform path, and PostgreSQL settings

### Architectural Decisions
- **Factory pattern:** A single entry point (`run_setup.sh`) provisions the
  entire lab. Each lab is a self-contained directory tree under `$LAB_HOME`.
- **Absolute paths only:** All directory references resolve to absolute paths,
  ensuring scripts work regardless of the invocation directory. No relative
  paths anywhere.
- **Environment inheritance:** Variables are passed forward via `export`.
  Each script validates required variables with fail-fast checks — execution
  stops immediately if a required variable is missing.
- **Idempotency everywhere:** Every operation checks current state before
  acting. Scripts can be rerun without side effects or state corruption.
- **Secrets isolation:** A single secrets file per lab, protected by strict
  permissions (owner read/write only), sourced at runtime, and excluded
  from version control. Credentials are never hardcoded.
- **Configuration handshake:** `settings.env` takes priority over
  `settings.env.example`. The template provides safe defaults for testing
  when no custom configuration exists.

---

## Versioning Scheme

| Version | Phase | Component |
|---------|-------|-----------|
| 0.1.0   | 1     | Foundation (Base Environment) |
| 0.2.0   | 2     | Storage (PostgreSQL) |
| 0.2.1   | —     | Documentation update |
| 0.3.0   | 3     | Orchestration (Airflow) — upcoming |
| 0.4.0   | 4     | Streaming (Kafka) — planned |
| 0.5.0   | 5     | Processing (Spark) — planned |
| 0.6.0   | 6     | Observability — planned |
| 1.0.0   | All   | Complete stack |

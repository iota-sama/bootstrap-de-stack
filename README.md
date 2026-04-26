# bootstrap-de-stack: Data Engineering tech stack bootstrap (IaC)

An idempotent, layered orchestration framework designed for automated deployment of a portable and reproducible Data Engineering lab. This stack provides a production-grade foundation for both batch and real-time streaming analytics.

## Architecture (The Layered Approach)
This platform follows a "Systems Engineering" philosophy, where each component is isolated into logical layers to ensure portability and high availability

### Phase 1: Core Foundation (COMPLETE)
*   **Layer 1 (Base Environment):** OS provisioning, Idempotent and absolute directory hierarchies, and secure identity/secrets initialization.

### Phase 2: Relational Data Store (IN PROGRESS)
*   **Layer 2 (PostgreSQL):** Deployment of a managed, portable database instance configured for both platform metadata and high-throughput data modeling.

### Phase 3: The Movement Layer (PLANNED)
*   **Layer 3 (Apache Airflow):** Deployment of a container-ready orchestration engine for scheduled DAG execution.
*   **Layer 4 (Confluent Kafka/KRaft):** High-throughput event backbone for real-time ingestion, including Schema Registry for data governance.

### Phase 4: Compute & Analytics (PLANNED)
*   **Layer 5 (PySpark):** Distributed compute engine for large-scale batch processing and historical research.
*   **Layer 6 (Observability):** Centralized logging and automated state-validation testing.

## Quick Start
1.  **Clone the repository:**
    `git clone https://github.com/iota-sama/bootstrap-de-stack.git`
2.  **Environment Configuration:**
    `cp settings.env.example settings.env` (Edit values as needed in settings.env)
3.  **Run Orchestrator:**
    `./run_setup.sh`

## 🛠️ Technical Highlights
**Idempotency**: "Check-before-Action" logic ensures scripts can be rerun without state corruption.
**Portability**: Decoupled from system paths using absolute directory mapping, allowing deployment across any Ubuntu/Debian environment.
**Security**: Strict file permissioning (umask 077) and automated .gitignore generation for platform secrets

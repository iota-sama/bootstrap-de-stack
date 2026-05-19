# Factory Behavior Contract

This document defines the behavioral guarantees of the bootstrap-de-stack factory (`run_setup.sh`). It describes what users can rely on and what constitutes expected versus undefined behavior.

This is not a legal warranty. The software is provided under the Apache 2.0 license, which disclaims all liability. This document describes design intent.

## Preconditions

The factory assumes the following are true before execution:

- P1: The host system runs Ubuntu 20.04+ or Debian 11+ with internet access.
- P2: The target LAB_HOME path does not contain a completed lab, unless `--force` is used.
- P3: The user has `sudo` privileges for system package installation.
- P4: The environment is a fresh shell session without leftover variables from prior factory runs.

## Guarantees

Numbered for reference in tests and debugging.

### Idempotency

- G1: Every provisioning script follows a check-before-act pattern.
- G2: Re-running the factory with the same configuration is safe. Completed steps are detected and skipped.
- G3: The factory will not corrupt an existing lab by re-running.

### Completion Detection

- G4: The factory writes a state file to `$LAB_HOME/configs/factory.state` tracking provisioning progress.
- G5: When provisioning completes successfully, the state file is marked `STATUS=complete`.
- G6: Subsequent runs without `--force` will refuse to reprovision a completed lab.

### Interrupted Provisioning

- G7: If the factory is interrupted, the state file remains marked `STATUS=in_progress`.
- G8: On the next run, the factory detects the interrupted state and resumes from the beginning.
- G9: Because every script is idempotent, completed work is skipped and only incomplete work is performed.

### Port Assignment

- G10: Service ports are allocated through a central registry (`lab_registry.csv`).
- G11: Once assigned, ports persist across factory reruns and system reboots.
- G12: Ports are validated against the operating system before use.
- G13: During provisioning, if a previously registered port for this lab is found to be occupied by an external process, the stale registration is removed and a new port is assigned. Registrations belonging to other labs are never modified.

### Lab Identity

- G14: If the requested lab name already exists in the registry, the factory automatically appends a numeric suffix to resolve the conflict.
- G15: The resolved lab name and path are displayed to the user before provisioning begins.

### Secrets Management

- G16: Credentials are generated once using cryptographically secure random generation.
- G17: Credentials are stored in `$LAB_HOME/secrets/generated.env` with owner-only file permissions (`umask 077`).
- G18: Re-running the factory will never overwrite existing credentials.

### Cold Delivery

- G19: A successfully provisioned lab is delivered in a cold state. All services are stopped.
- G20: The user starts the lab on demand using the generated `lab_entry.sh` script.

### Force Reprovisioning

- G21: When `--force` is used on a completed lab, the factory shuts down any running services before reprovisioning. 
- G22: Existing data, secrets, and port assignments are preserved during force reprovisioning.

## Prohibitions

The factory explicitly forbids these actions and will refuse to proceed:

- PROH-1: Provisioning over a completed lab without the `--force` flag.
- PROH-2: Running multiple instances of the factory simultaneously against the same lab directory.

## User Responsibilities

The factory's guarantees hold only when the user upholds these responsibilities:

- UR-1: The factory is run in a fresh terminal session.
- UR-2: `settings.env` is not modified between an interrupted run and its resumption.
- UR-3: The lab directory is not manually modified, moved, or deleted while provisioning is in progress.
- UR-4: The `--force` flag is used intentionally, with awareness that it reprovisions a completed lab.

## What Is NOT Guaranteed

### Manual Modifications

If a user manually modifies files within the lab directory after provisioning, the factory cannot guarantee correct behavior on re-run. This includes editing generated configs, deleting PID files, or changing file permissions.

### Configuration Changes Between Runs

Changing `settings.env` values between factory runs may produce undefined behavior. Version upgrades (e.g., changing KAFKA_VERSION from 4.0.0 to 4.0.2) will replace binaries but preserve data. Downgrades are not tested and may fail.

### Partial Service Operation

The lab is designed for all-services or no-services operation. Running PostgreSQL without the streaming stack while replication slots exist may cause WAL accumulation. Use `lab_shutdown.sh` for complete shutdown.

### Cross-Machine Portability

The lab is not guaranteed to function if copied to a different machine. Data directories are portable within the same OS and architecture, but system-level dependencies (PostgreSQL installation, Java version) may differ. The lab supports relocation to a different filesystem path on the same machine. Configuration files are automatically updated at startup.

## The --force Flag

Passing `--force` to `run_setup.sh` overrides the completion check. The factory shuts down any running services, then reprovisions the completed lab from the beginning. All scripts run idempotently. Existing data, secrets, and port assignments are preserved. This is useful for repairing a lab or applying configuration changes.

## State File

The factory maintains its progress in `$LAB_HOME/configs/factory.state`.

The state file persists after provisioning completes. It is the factory's record of the lab's completion status.

Users may inspect this file to understand their lab's provisioning status. Manual modification voids all behavioral guarantees.

## Versioning

This contract applies to bootstrap-de-stack v0.4.0 and later. Until v1.0.0, behavioral guarantees may evolve with each minor release. Breaking changes will be documented in the CHANGELOG. Starting at v1.0.0, breaking changes to this contract will be accompanied by a major version bump in accordance with semantic versioning.
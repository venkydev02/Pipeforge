# MVP Scope & Definition of Done

> **Document Location:** `docs/planning/mvp-scope.md`
> **Status:** Final & Frozen Scope
> **Index:** [Master Documentation Index](../../README.md)

---

## 1. Current Scope

### 1.1 Source
- CSV

### 1.2 Target
- SQLite
- PostgreSQL

### 1.3 Migration Scope
- Single primary entity per migration job
- 1:1 lookups
- N:1 lookups
- Single-attribute primary keys
- Single-attribute foreign keys
- Single-attribute unique keys

### 1.4 Configuration & Interaction
- The engine is consumed as a plain Ruby library, embedded directly in the consumer's application — no gem-shipped CLI in MVP (see §2 Post-MVP)
- One-time engine configuration through `engine.yml`
- Migration-specific input through `MigrationPlan`
- Programmatic (API-level) overrides where required, in place of CLI flags
- Mandatory human review of recommendations — review UI/workflow is consumer-owned (terminal, dashboard, or any presentation the consumer's application builds)

### 1.5 Migration Pipeline

1. Analyze source CSV
2. Discover target database schema
3. Generate deterministic mapping recommendations
4. Review and modify recommendations
5. Build validated migration plan
6. Stream source records
7. Project and transform records
8. Resolve relationships
9. Validate records
10. Load records into target
11. Produce migration report

### 1.6 Core Guarantees
- Deterministic recommendations
- Explainable recommendations
- No guessing on ambiguous relationships
- Explicit unresolved-reference handling
- Streaming CSV processing
- Capability-based target access
- Complete migration accounting

---

## 2. Post-MVP

The following capabilities are explicitly outside the MVP:

### 2.1 Source Formats
- JSON source support
- Parquet source support
- XML source support

### 2.2 Target Databases
- MySQL target support
- Oracle target support
- Microsoft SQL Server target support

### 2.3 Schema & Constraint Features
- Composite primary/foreign keys
- Many-to-many automatic relationship splitting
- Database `CHECK` constraint handling
- Partial/filtered indexes
- Generated/stored expressions (`GENERATED ALWAYS AS`)
- Triggers
- Table partitioning

### 2.4 Interaction & Execution Model
- Gem-shipped CLI (command-line entry point and interactive terminal reviewer)
- LLM / AI-assisted recommendations
- Dynamic scripting DSL
- Web / GUI interface
- Distributed migration execution
- Native C/Rust extensions

---

## 3. Call It Done

The MVP can be considered complete when:

1. A consumer can configure the engine and execute a migration from within their own Ruby application (no CLI required).
2. CSV files can be analyzed without loading the entire file into memory.
3. SQLite and PostgreSQL schemas can be discovered.
4. Deterministic migration recommendations can be generated.
5. A consumer can review and modify those recommendations through their own application code.
6. A valid `MigrationPlan` can be constructed from the reviewed decisions.
7. The migration runtime can process CSV data through transformation, relationship resolution, validation, and loading.
8. Relationship resolution correctly handles resolved, unresolved, and ambiguous references.
9. Target loading supports bulk inserts and row-level rejection fallback.
10. Failed/rejected records are captured and reported.
11. The final migration report accounts for every processed record.
12. Core architectural boundaries are verified by tests.

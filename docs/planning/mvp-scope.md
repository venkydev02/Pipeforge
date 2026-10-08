# MVP Scope & Definition of Done

> **Document Location:** `docs/planning/mvp-scope.md`
> **Status:** Draft v3.0 — rewritten 2026-10-08 (ADR-10, ADR-11)
> **Index:** [Master Documentation Index](../../README.md)

---

## 1. Current Scope

### 1.1 Source
- CSV

### 1.2 Target
- Rails applications using ActiveRecord
- PostgreSQL (first), SQLite
- Target named as a model class or a table

### 1.3 Migration Scope
- Single primary entity per migration job
- 1:1 and N:1 lookups
- Single-attribute primary, foreign and unique keys

### 1.4 Configuration & Interaction
- Consumed as a Ruby library inside a Rails application; no gem-shipped CLI in MVP
- One-time engine configuration through `engine.yml`; behavior is chosen by options, not code
- Migration-specific input: source, target, and the plan
- Programmatic overrides for individual runs
- Review is optional: the Planner's `PlanDraft` is runnable as-is; any editing UI or workflow is consumer-owned

### 1.5 Migration Pipeline
1. Analyze source CSV (concurrently with step 2)
2. Read target schema and model metadata
3. Generate deterministic recommendations as a `PlanDraft`
4. (Optional) Edit the draft
5. Build the validated, state-only `MigrationPlan`
6. Stream source records in chunks
7. Map and transform; pre-resolution validation
8. Resolve relationships
9. Post-resolution validation (4-state)
10. Load (bulk or per-record), with optional dry run
11. Produce the run report and dead-letter log

### 1.6 Core Guarantees
- Deterministic, explainable recommendations
- No guessing on ambiguous relationships
- Explicit unresolved-reference handling
- Streaming, bounded-memory processing
- Row access confined to the resolver and loader
- Complete accounting of every processed record

---

## 2. Post-MVP

- **Source formats:** JSON, Parquet, XML
- **Databases:** MySQL and other ActiveRecord adapters (not verified in MVP)
- **Schema features:** composite keys, many-to-many splitting, CHECK constraints, partial indexes, generated columns, triggers, partitioning
- **Load modes:** upsert / update (MVP is insert only)
- **Execution:** whole-job transactions, concurrency greater than 1, resume after partial load, distributed execution
- **Interaction:** gem-shipped CLI or rake tasks, interactive reviewer, web/GUI
- **Extensibility:** documented custom resolver/loader components
- **Other:** LLM-assisted recommendations, scripting DSL, native extensions

---

## 3. Call It Done

1. A Rails consumer can configure the engine and run a migration from their own code with only options and a source file.
2. CSV files are analyzed without loading the whole file into memory.
3. PostgreSQL and SQLite schemas and model metadata are read.
4. Deterministic recommendations are produced as a runnable `PlanDraft`.
5. A consumer can optionally edit the draft, or use it unchanged.
6. A valid state-only `MigrationPlan` is built from any `PlanDraft`; invalid drafts return errors naming each column and the reason.
7. The runtime processes CSV data through transformation, relationship resolution, validation and loading.
8. Resolved, unresolved and ambiguous references are handled correctly.
9. Loading supports bulk insert with row-level fallback, and per-record model-path loading.
10. Dry run reports outcomes without persisting.
11. Rejected records are captured with exact row numbers and reasons.
12. The final report accounts for every processed record.
13. Row-access boundaries are verified by tests.

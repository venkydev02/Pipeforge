# MVP Scope & Definition of Done

> **Document Location:** `docs/planning/mvp-scope.md`
> **Status:** Draft v4.0 — updated 2026-10-15 (ADR-14 to ADR-17)
> **Index:** [Master Documentation Index](../../README.md)

---

## 1. Current Scope

### 1.1 Source
- CSV (read with an offset and limit, optionally)

### 1.2 Target
- Rails applications using ActiveRecord, through the `pipeforge-activerecord` distribution (ADR-16)
- PostgreSQL (first), SQLite
- Target named by its table name (for example `"users"`); the ActiveRecord adapter requires a model for it (ADR-20)

### 1.3 Migration Scope
- Single primary entity per migration job
- Foreign key columns hold the parent's primary key; names are mapped to ids in the value stage (ADR-15)
- Single-attribute primary, foreign and unique keys

### 1.4 Configuration & Interaction
- Consumed as a Ruby library: the core gem comes with the adapter gem; no gem-shipped CLI in MVP
- One-time engine configuration through `pipeforge.yml`; behavior is chosen by options, not code
- Per-call input: the header and value results, the mode, and the optional offset, limit and loading options
- Review is the consumer's own step; the engine has no build step and no acknowledgement flag (ADR-14, ADR-17)

### 1.5 Migration Pipeline
1. `analyze_headers`: read the source header and the target model's metadata; rank by names only; return the best match for each target column, the metadata of each target column, and the columns left unmatched
2. The consumer reviews the matches and builds the mapped columns (target column => source column, with an optional value mapping)
3. `analyze_values(mapped_columns:)`: one streaming pass over the mapped columns; return facts and the editable value mapping
4. The consumer reviews and edits the value mapping, and may call `analyze_values` again
5. `run(mode: :dry_run)`: the contract check, then the batches inside one outer transaction that is rolled back
6. `run(mode: :run)`: the contract check, then the batches, each committed; checkpoint after each commit
7. Failed rows (JSON Lines) and the summary

### 1.6 Core Guarantees
- Deterministic, explainable recommendations (reproducible from column names alone)
- No guessing: a foreign key is never matched by name in the engine
- Streaming, bounded-memory processing
- Row access confined to the loader (ADR-15)
- Complete accounting of every processed row

---

## 2. Post-MVP

- **Source formats:** JSON, Parquet, XML
- **Databases:** MySQL and other ActiveRecord adapters (not verified in MVP); other adapters as their own distributions (ADR-16)
- **Relationships:** lookup of a foreign key by a parent column, and creating missing parents (ADR-15 defers both)
- **Schema features:** composite keys, many-to-many splitting, CHECK constraints, partial indexes, generated columns, triggers, partitioning
- **Load modes:** upsert / update (MVP is insert only)
- **Execution:** whole-job transactions (the dry run is the only outer transaction), concurrency greater than 1, distributed execution
- **Interaction:** gem-shipped CLI or rake tasks, interactive reviewer, web/GUI
- **Extensibility:** documented third-party adapters once Phase 1 freezes the adapter contract
- **Other:** LLM-assisted recommendations, scripting DSL, native extensions

---

## 3. Call It Done

1. A Rails consumer can configure the engine and run a migration from their own code with only options and a source file.
2. CSV files are analyzed without loading the whole file into memory.
3. The target model's columns and model metadata are read (PostgreSQL and SQLite).
4. `analyze_headers` returns the best match for each target column (a source column and a score) with the metadata of the target column, using names only.
5. `analyze_values` returns, per mapped column, the empty count, the type compatibility, the distinct values split into compatible and incompatible lists, and the value mapping.
6. The consumer can edit the mapped columns or a value mapping and call `analyze_values` again; the facts reflect the edit.
7. `run` refuses a value result that does not match the mapping, and reports every missing column or required column together.
8. A dry run reports the same failed rows as a real run against an unchanged database, and persists nothing.
9. Batches load with `insert_all!`, or row by row through the model; a failed batch is retried row by row.
10. Failed rows are written with exact row numbers, the source values and each error's stage, column and code.
11. A checkpoint is written after each committed batch, and a run from a checkpoint continues the row numbers.
12. The summary accounts for every processed row.
13. Row access is confined to the loader, and the core gem names no ActiveRecord class (tested).

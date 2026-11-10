# MVP Scope & Definition of Done

> **Document Location:** `docs/planning/mvp-scope.md`
> **Status:** Draft v4.0 — updated 2026-10-25 (ADR-14 to ADR-17; stages are independent and the fingerprints are removed, ADR-18 amendment of 2026-10-25)
> **Index:** [Master Documentation Index](../../README.md)

---

## 1. Current Scope

### 1.1 Source
- CSV (read from an offset, optionally)

### 1.2 Target
- Rails applications using ActiveRecord, through the `pipeforge-activerecord` gem, which carries the core (ADR-23)
- PostgreSQL (first), SQLite
- Target named by its model class (for example `"User"`); the ActiveRecord adapter finds the loaded model with that name and reads the table from it (ADR-26)

### 1.3 Migration Scope
- Single primary entity per migration job
- Foreign key columns hold the parent's primary key; names are mapped to ids in the column values stage (ADR-15)
- Single-attribute primary, foreign and unique keys

### 1.4 Configuration & Interaction
- Consumed as a Ruby library: the core comes inside the adapter's gem; no gem-shipped CLI in MVP
- One-time engine configuration through `pipeforge.yml`; behavior is chosen by options, not code
- Per-call input: the mapped columns with their value mappings, the mode, and the optional offset, chunk size and loading options (the stages do not depend on each other's output)
- Review is the consumer's own step; the engine has no build step and no acknowledgement flag (ADR-14, ADR-17)

### 1.5 Migration Pipeline
1. `analyze_headers`: read the source header and the target model's metadata; rank by names only; return the best match for each target column, the metadata of each target column, and the columns left unmatched
2. The consumer reviews the matches and builds the mapped columns (target column => source column, with an optional value mapping)
3. `analyze_column_values(mapped_columns:)`: one streaming pass over the mapped columns; return facts and the editable value mapping
4. The consumer reviews and edits the value mapping, and may call `analyze_column_values` again
5. `run(mode: :dry_run)`: the contract check, then each row is mapped, validated and written, in chunks and one row at a time, inside one outer transaction that is rolled back at the end (built); batch loading comes next
6. `run(mode: :run)`: the contract check, then the same validation and writing, each row in its own committed transaction (built); later in batches
7. Each chunk's failed rows go to the consumer's block as the chunk is done; `run` returns the totals

Now that row-by-row loading is built (post-load work): review which error codes the engine has to support, and add the missing ones, so that a dry run and a run report the same failures.

### 1.6 Core Guarantees
- Deterministic, explainable recommendations (reproducible from column names alone)
- No guessing: the engine never looks up a parent row by name; the consumer maps names to ids in the column values stage (ADR-15)
- Streaming, bounded-memory processing
- Row access confined to the loader (ADR-15)
- Complete accounting of every processed row

---

## 2. Post-MVP

- **Source formats:** JSON, Parquet, XML
- **Databases:** MySQL and other ActiveRecord adapters (not verified in MVP); other adapters as their own gems, each carrying the core (ADR-23)
- **Relationships:** lookup of a foreign key by a parent column, and creating missing parents (ADR-15 defers both)
- **Schema features:** composite keys, many-to-many splitting, CHECK constraints, partial indexes, generated columns, array columns, triggers, partitioning
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
5. `analyze_column_values` returns, per mapped column, the empty count, the type compatibility, the distinct values split into compatible and incompatible lists, and the value mapping.
6. The consumer can edit the mapped columns or a value mapping and call `analyze_column_values` again; the facts reflect the edit.
7. `run` reports every missing column and every unmapped required column together, before any row is read.
8. A dry run reports the same failed rows as a real run against an unchanged database, and persists nothing.
9. Batches load with `insert_all!`, or row by row through the model; a failed batch is retried row by row.
10. Failed rows are given to the consumer, a chunk at a time, with exact row numbers, the transformed values and each error's stage, column and code. The engine writes no file.
11. A run with `offset:` (the row number of the last processed row) continues the row numbers.
12. The totals account for every processed row (valid plus invalid).
13. Row access is confined to the loader, and the core names no ActiveRecord class (tested).

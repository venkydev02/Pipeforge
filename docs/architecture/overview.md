# Architecture Overview & System Topology

> **Document Location:** `docs/architecture/overview.md`
> **Status:** Draft v4.0 — updated 2026-10-25: stages are independent public calls and the fingerprints are removed (ADR-18 amendment of 2026-10-25); the inputs of `run` are still to be settled
> **Index:** [Master Documentation Index](../../README.md)

---

## 1. Foundational Principles

The **Relational Data Migration Engine** migrates data from a source file into a relational database. The consumer states *how a migration should behave*; the engine checks the source against the target, measures the values and loads the rows.

CSV is the **current MVP source format**. It is not the system identity; other source formats may be added later without changing the stage design.

The engine is split into a **framework-agnostic core** (`lib/pipeforge`) and one **adapter per database library** (`lib/pipeforge/adapters/activerecord` for the MVP). Each adapter is a gem with its own gemspec that carries the core, and the consumer installs only that gem (ADR-23).

### 1.1 Minimal Consumer Effort
The consumer does not write connections or loaders. They supply a source, name the target table, and set behavior options. The adapter is built in. Custom adapters are an advanced extension point (see `target-access.md`).

### 1.2 The Row-Access Boundary
Analysis must never depend on what is already in the target database.

* **Allowed everywhere (metadata only):** columns, types, nullability, defaults, primary and foreign keys, unique indexes, and model metadata (enums, associations, virtual attributes, validators).
* **Forbidden outside the loader:** reading existing target rows, value distributions of the target, or "is this table empty?" checks.
* **Row-access module:** only the adapter touches business rows: the **loader** writes them, and the model's own validations, which the run executes for every row, read the parents and the values they check (ADR-15). The header stage and the column values stage read only the source file and target metadata. The column values stage reads source values, which is not target access.

### 1.3 Schema Is Structural Truth, Not Business Truth
The catalog says `users.status` is a `VARCHAR(50)`; it does not say which values are allowed. Allowed values are known only from model metadata (for example an `enum` declaration), never inferred from stored data.

### 1.4 Staged Engine Methods (ADR-14, ADR-17)

```text
Engine.new(source_io:, target_model:)      the source and the target model, given once
analyze_headers                           → HeaderAnalysis      (names only, no values)
analyze_column_values(mapped_columns:)           → ColumnValueAnalyzer::Result (values, facts, value mappings)
run(mode:, mapped_columns:, offset:, chunk_size:) { |chunk_result| }
                                          → RunResult (totals); each chunk's failed rows go to the block
```

1. **`analyze_headers`** reads the source header and the target model's columns, and ranks source columns against target columns **by names only** (ADR-12). It returns the best matches, in table order, with the metadata of each target column, and the columns left unmatched.
2. **`analyze_column_values`** takes the mapping the consumer settled (target column => source column) and measures the mapped columns in one pass: empty counts, how many values fit the target type, distinct values, and the consumer's `value_mapping`. Calling it again after an edit shows the facts again.
3. **`run`** is the one public runtime entry point. It checks its input against the source and the target schema, then loads. `mode: :dry_run` rolls everything back; `mode: :run` commits. The stages are public calls that do not depend on each other's output (ADR-18 amendment of 2026-10-25), so a consumer may call `run` without the other two; its exact inputs (the mapped columns with their value mappings) are settled in the run contract.

There is no separate build step: the consumer already has the header and column values results, which show the plan. Review is the consumer's own step; the engine never prompts and never resets anything.

### 1.5 Results Are Plain Values
Each stage returns an immutable value object that can be stored, shown and passed back. Facts are regenerated each time; state (the mapping and the value mappings) is what the consumer edits.

### 1.6 Contracts Between Components
Stages communicate through explicit value objects (P1–P2, `HeaderAnalysis`, `ColumnValueAnalyzer::Result`, checkpoints) and not through shared mutable state or ad hoc hashes. Only artifacts that cross a process or storage boundary carry a `protocol_version`. See `protocols.md`.

### 1.7 Deterministic Core
Recommendations are **deterministic**, **explainable**, **reproducible** and **testable**. Identical inputs and configuration produce identical results. No LLM or external AI service participates in correctness.

---

## 2. System Topology

```mermaid
flowchart TD
    Source[Source: CSV]
    DB[(Target database)]
    Config[pipeforge.yml]

    subgraph Core["Core gem: pipeforge"]
        Headers["analyze_headers → HeaderAnalysis"]
        Values["analyze_column_values → ColumnValueAnalyzer::Result"]
        Runtime["run (dry run or run)"]
    end

    subgraph Adapter["Adapter gem: pipeforge-activerecord"]
        Schema["schema → TargetSchema (metadata only)"]
        Loader["Loader (transactions, insert_all!, save)"]
    end

    Consumer{{"Consumer review and edits"}}

    Source --> Headers
    DB -. "schema + model metadata" .-> Schema --> Headers
    Config --> Headers
    Headers -->|"matches"| Consumer
    Consumer -->|"mapped_columns"| Values
    Source --> Values
    Values -->|"value_mapping"| Consumer
    Consumer --> Runtime
    Runtime --> Loader
    Loader -. writes rows .-> DB
```

Source analysis and target schema reading are independent and may run concurrently.

---

## 3. Stage Responsibilities

### 3.1 `analyze_headers`
* **Input:** the source file and the target table (named by table name), both given to `Engine.new`.
* **Reads:** the source header row only, and the target model's metadata.
* **Output:** `HeaderAnalysis`: `matches`, a list in table order (target column, source column, score, `tied_with`, and the metadata of the target column, including its foreign key), `unmatched_source_columns`, and `unmatched_target_columns` (a list of target column and metadata; ADR-25). A source column is shared by the targets that have the same score for it, and the consumer chooses.
* **Non-responsibilities:** no values, no data-based ranking, no invented mappings.

### 3.2 `analyze_column_values`
* **Input:** the mapped columns, a plain Hash the consumer builds, keyed by target column (each entry names its source column and an optional value mapping). Every required target column needs an entry; a source column may feed several target columns. The type, size and precision of each target column are read from the target table's schema (ADR-18), never sent by the consumer.
* **Reads:** the mapped source columns only, in one pass, one row at a time, and the schema of the target table (metadata only).
* **Output:** `ColumnValueAnalyzer::Result`: per column, empty count, distinct values split into compatible and incompatible lists (every value is kept) with the number of values in each (`compatible_count` and `incompatible_count`), and the value mapping the facts were measured with.
* **Non-responsibilities:** no writes, no target rows, no changes to the mapping.

### 3.3 `run`
* **Input:** `mode`, the mapped columns with their value mappings (the same Hash as `analyze_column_values`; nothing from an earlier stage), and the optional `offset` (rows to skip) and `chunk_size` (rows per chunk; the `execution.chunk_size` setting when not given). A `mode`, `offset` or `chunk_size` that cannot be used stops the call with an `ArgumentError` before anything else happens. A block receives each chunk's result.
* **Checks first:** every mapped column exists in the source and the target; every required target column is mapped. All errors are reported at once, before any row is read.
* **Validates and loads, row by row (built):** streams the source in chunks. Each row is mapped (columns and values), then checked on two levels: the model's own validations, asked through the adapter's model record, and the schema checks the core makes from the `TargetSchema` (required, length, range, enum), on the values the model record holds after its validation. The parents a chunk needs are loaded once for the chunk. A mistake found on both levels is reported once. A row that passes is written at once (`load`, in its own transaction, with `save!(validate: false)`), before the next row is checked, so a later row sees the earlier ones. A row the database refuses is a failed row with `origin: :database`, and the run goes on. Later the valid rows will also be loaded in batches (`load_batch`, `insert_all!`), with a failed batch retried row by row.
* **Output:** the totals (`RunResult`: processed, valid and failed rows) and, for each chunk as it is done, a `ChunkResult` with its failed rows (row number, the transformed values, and each error's origin, column, code and message). The engine writes no file; what to do with the failed rows and the progress is the consumer's.
* **Dry run:** the same path, inside one outer transaction that is rolled back at the end, each row in a savepoint (`target-access.md` §4). The consumer's block runs inside that transaction, so it must not write to the target database.

### 3.4 The Consumer Boundary
The consumer owns: reviewing and editing the stage results, where they are stored, **when** to call each method, the choice of offset slices, and the decision to run during low traffic (the dry run holds locks). The engine never prompts and never becomes a web app. Progress is surfaced through consumer-supplied hooks, not terminal UI.

---

## 4. End-to-End Information Flow

```mermaid
sequenceDiagram
    autonumber
    participant Src as Source (CSV)
    participant Core as Core (pipeforge)
    participant Consumer as Consumer (review)
    participant Adapter as Adapter (pipeforge-activerecord)

    Note over Core: Stage 1: names
    Core->>Src: Read header row only
    Core->>Adapter: schema(target_model:)
    Adapter-->>Core: TargetSchema (metadata only)
    Core->>Consumer: HeaderAnalysis (matches, unmatched columns, metadata)

    Note over Consumer: Review the mapping
    Consumer->>Core: analyze_column_values(mapped_columns:)

    Note over Core: Stage 2: values
    Core->>Src: One pass, one row at a time; every distinct value is kept
    Core->>Consumer: ColumnValueAnalyzer::Result (facts, value_mapping)

    Note over Consumer: Review the values
    Consumer->>Core: run(mode: :dry_run, ...)

    Note over Core: Stage 3: run
    Core->>Core: Contract check (all errors at once)
    loop each chunk
        Src->>Core: Rows (chunk_size)
        Core->>Adapter: build_record for each row, preload_parents once
        Adapter-->>Core: Model records (valid? and errors for the model-level checks)
        Core->>Core: Schema-level checks, merge errors
        Core->>Adapter: load each valid row, one at a time
        Core->>Consumer: ChunkResult with its failed rows (to the block)
    end
    Note over Core,Adapter: Batch loading (load_batch) comes next
    Core->>Consumer: RunResult (totals)
```

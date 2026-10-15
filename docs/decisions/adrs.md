# Architecture Decision Records (ADRs)

> **Document Location:** `docs/decisions/adrs.md`  
> **Status:** ADR-01 through ADR-14. ADR-06 and ADR-08 are superseded by ADR-11. ADR-13 is superseded by ADR-14. ADR-01 and ADR-10 are partially superseded (see each entry; superseded parts are marked inline). Where entries disagree, the later ADR wins.  
> **Index:** [Master Documentation Index](../../README.md)

---

### ADR-01: Tripartite Architecture (Planner → Plan Builder → Runtime)
* **Status:** Accepted / Frozen. *Partially superseded (2026-10-10): the Planner now returns a JSON draft and not an initial `MigrationPlan` (ADR-10, ADR-13), and review is a required acknowledgement flag (ADR-13). The three-way split itself stands.*
* **Context:** Conflating recommendation, plan construction, and execution leads to tight coupling between heuristic analysis and streaming execution.
* **Decision:** Split planning and execution into three distinct domain responsibilities:
  1. `MigrationPlanner` (discovers, recommends, creates an initial `MigrationPlan`) **[now: returns a JSON draft; see ADR-13]**.
  2. `MigrationPlanBuilder` (constructs/reconstructs and validates `MigrationPlan` from consumer decisions) **[now: from the reviewed, acknowledged draft; see ADR-13]**.
  3. `MigrationRuntime` (streams and executes the valid `MigrationPlan`).
  `MigrationPlan` is the domain contract.
* **Consequences:** Separates recommendation from plan validation, supports unchanged recommendations cleanly (an unchanged draft still needs the acknowledgement flag, ADR-13), and isolates the Runtime from consumer UI or storage formats.

---

### ADR-02: Bounded Streaming & Chunk-Oriented Processing
* **Status:** Accepted / Frozen
* **Context:** Real-world migrations involve 100K to 10M+ records. Loading complete datasets into RAM exhausts memory.
* **Decision:** Stream CSV records in configurable chunks (default: 2,000 records). At no point is the entire file parsed into memory.
* **Consequences:** Guarantees constant $O(1)$ memory usage (< 100 MB RAM) regardless of source file size.

---

### ADR-03: Two-Stage Validation Pipeline & Pre-Resolution Safety
* **Status:** Accepted / Frozen
* **Context:** Checking final target types or NOT NULL on unresolved foreign keys before lookup causes false validation failures (string query key `"Acme"` flagged as incompatible with integer FK `company_id`).
* **Decision:** Split validation into Pre-Resolution (direct formats, types, required source fields) and Post-Resolution (foreign keys, integrity). Pre-resolution validation must never enforce target foreign key types on relationship-derived fields.
* **Consequences:** Eliminates premature type-incompatibility errors during lookup candidate extraction.

---

### ADR-04: Explicit Unresolved Reference Representation (Not NULL)
* **Status:** Accepted / Frozen
* **Context:** Setting failed relationship lookups to `nil` causes `NOT NULL` constraints to throw misleading errors, hiding the fact that the source value was present but missing in the target database.
* **Decision:** Failed relationship lookups produce an explicit `UnresolvedReference` domain object, never `nil`/`NULL`.
* **Consequences:** Post-resolution validation distinguishes true missing values (`NOT_NULL_VIOLATION`) from missing parent records (`UNRESOLVED_REFERENCE`).

---

### ADR-05: 4-State Validation Taxonomy & Ownership Separation
* **Status:** Accepted / Frozen
* **Context:** A simple valid/invalid boolean forces the engine to reject records that consumer application logic or ORM callbacks would otherwise make valid.
* **Decision:** Replace boolean validity with `VALID`, `HARD_FAILURE`, `DELEGATED`, and `UNRESOLVED`. The engine owns infrastructure validation; DB metadata provides structural constraints; the consumer/ORM owns business logic.
* **Consequences:** Prevents the engine from prematurely rejecting records that consumer domain logic would make valid.

---

### ADR-06: Loading Adapter Policy Ownership
* **Status:** Superseded by ADR-11 (2026-10-08). Historical record only.
* **Context:** Different deployment environments require different error-handling and persistence strategies (raw SQL vs. ORM models).
* **Decision:** The engine decides what it knows about a record; the **loader adapter** decides how to handle that result. Core defines the loader capability contract (`LoadRequest` / `LoadResult`). The gem may provide a generic `DbBulkLoader`. ORM, API, and application-specific loaders are **consumer-owned** and are not gem deliverables.
* **Consequences:** Keeps Core framework-agnostic while giving consumers full control over application-specific persistence.

---

### ADR-07: Direct vs. Relationship-Derived Mappings
* **Status:** Accepted / Frozen
* **Context:** Treating foreign key lookups as direct column copies creates confusion over whether source strings must convert directly to foreign keys.
* **Decision:** Explicitly classify mappings into `direct` and `relationship_derived`. Direct mappings validate conversion upfront; relationship-derived mappings evaluate resolution targets.
* **Consequences:** Eliminates conceptual confusion between direct column transfers and join resolutions.

---

### ADR-08: Framework & ORM Agnosticism
* **Status:** Superseded by ADR-11 (2026-10-08). Historical record only.
* **Context:** Coupling the core engine to Rails or ActiveRecord prevents standalone CLI usage and limits performance for high-throughput bulk SQL.
* **Decision:** Core engine is pure Ruby with zero required dependencies on Rails or ActiveRecord. The gem may ship generic SQL adapters (`DbRelationshipResolver`, `DbBulkLoader`). ActiveRecord/Sequel/API support lives in **consumer-owned** adapters, not in Core and not as mandatory gem features.
* **Consequences:** Maximum portability, testability, and high-performance loading without prescribing an ORM.

---

### ADR-09: One-Time Engine Configuration (`engine.yml`)
* **Status:** Accepted / Frozen
* **Context:** Requiring consumers to pass behavioral options (batch size, error strategies, timeouts, logging) for every migration invocation creates repetitive CLI flags and configuration drift.
* **Decision:** The consumer defines organizational policies once in `config/engine.yml`. All migrations inherit these defaults without requiring repetitive per-migration flags. Programmatic overrides act as surgical overrides (CLI flags only once a CLI ships, which is post-MVP).
* **Consequences:** Drastically reduces invocation complexity, prevents configuration drift, and cleanly separates engine-wide policies from migration-specific input.

---

### ADR-10: Single `PlanDraft` Input, Optional Review, State-Only `MigrationPlan`
* **Status:** Accepted (2026-10-08). **Partially superseded by ADR-12 and ADR-13 (2026-10-10).** Superseded: item 1 (the draft is now a JSON document with `findings`, `draft_plan` and `acknowledgement_flag`; no `state`/`facts` split, no `plan.to_draft`), item 4 (review is required again, as an acknowledgement flag), the gating wording in item 5 (ADR-12), and the idempotence property. Still in force: one input format, the state-only `MigrationPlan`, the Builder reads only the mapping state and never facts, `build` fails on uncovered required columns, and `build` reports all errors at once. It also superseded the "initial `MigrationPlan`" shape in ADR-01 (and removed the mandatory review there, which ADR-13 restored as a flag).
* **Context:** *(Historical; see ADR-13.)* The draft architecture made consumer review mandatory and left the Builder's input undefined (the "consumer decisions" had no contract). The design at the time was that the Planner's output is directly runnable, review and editing are optional, and the Runtime needs only *state*, never the *facts* (scores, evidence, warnings) behind it.
* **Decision:**
  1. **One input format: `PlanDraft`.** It has a required `state` section (mappings, transforms, lookups, defaults) and an optional `facts` section (scores, evidence, warnings, alternatives, keyed by mapping). The Planner produces a `PlanDraft`. A consumer may edit it, strip `facts`, hand-write one, or derive one from an existing plan (`plan.to_draft`). All are the same shape. **[Superseded by ADR-13: the draft is the JSON document described there.]**
  2. **One output format: `MigrationPlan` (P3).** It contains state only: no scores, evidence or review flags. It is the only thing `MigrationRuntime` accepts.
  3. **`MigrationPlanBuilder` is a pure function `PlanDraft -> BuildResult` (plan or structured errors).** It reads only `state`. `facts` never influence validation or output. The Planner uses the same builder methods the public API exposes, so both authors obey identical invariants. **[ADR-13 lists exactly which draft keys the Builder reads.]**
  4. **Review is optional and consumer-owned.** A consumer may pass the Planner's draft straight to `build` and then to the Runtime. The engine never requires, prompts for, or tracks a review step. **[Superseded by ADR-13: the Builder refuses any draft whose `acknowledgement_flag` is not `true`.]**
  5. **Planner safety without a gate.** The Planner includes in `state` only mappings at or above the configured confidence threshold; lower-confidence and hard-gated candidates appear only in `facts`. It never invents value mappings or guesses ambiguous lookups. `build` fails if a target column is `NOT NULL`, has no `default_expression`, is not auto-generated, and is not covered by the plan (a direct mapping, a relationship mapping's `target_fk_attribute`, or a plan `default_value`). Nullable columns, DB-defaulted columns, auto-generated keys and `SemanticSchema` virtual attributes are never failures. **[Gating wording superseded by ADR-12: pairs at or above the inclusion threshold go into the plan, below-threshold candidates are listed as doubtful, and there are no hard gates. `SemanticSchema` was removed by ADR-11.]**
  6. **`BuildResult` is success or errors, nothing else.** Success carries the `MigrationPlan`. Failure carries a list of errors, each with the affected column, a stable error code, and the reason it was rejected. All errors are reported at once. Errors are derived from `state` and the target schema only; the builder never reads `facts`, not even to suggest candidates (the consumer already has them in the draft's `facts`).
* **Required properties (testable):** determinism (same mapping state, same plan); fact-independence (editing or removing facts never changes the built plan); ~~idempotence (`build(plan.to_draft) == plan`)~~ *(dropped by ADR-13)*; no plan without the acknowledgement flag *(added by ADR-13)*.
* **Consequences:**
  * Removes the undefined "consumer decisions" input; the draft is the review surface.
  * Keeps P3 free of scoring and UI concerns; the Runtime stays unaware of the Planner.
  * Docs were updated to match on 2026-10-08, and again on 2026-10-10 when ADR-12 and ADR-13 changed review and the draft shape; see `docs/planning/roadmap-and-phases.md` Phase 1 for the remaining schema work.
  * Dry-run semantics become more important and must be defined in Phase 1.

---

### ADR-11: ActiveRecord-Based Engine with Built-in Target Access
* **Status:** Accepted (2026-10-08). **Supersedes ADR-06 and ADR-08**, and replaces the "adapter capability boundary" form of the zero-target-row-access rule with a module boundary.
* **Context:** The plain-Ruby, adapter-based design made every consumer write database connections, relationship resolvers and loaders. The project goal is to minimize consumer work: the consumer states how a migration should behave, and the engine does the rest. That needs direct, built-in access to the target database and to the application's model metadata.
* **Decision:**
  1. **The gem depends on ActiveRecord** (a declared runtime dependency). It targets Rails applications and works in any Ruby process with an ActiveRecord connection established.
  2. **Target access is built in:** schema and model metadata reading, relationship resolution, and loading. The consumer configures behavior through options (`engine.yml` and programmatic overrides), not through code.
  3. **Zero target-row access is kept as a module boundary.** The Planner, Builder, and all pre-resolution Runtime stages read only schema and model metadata (columns, keys, indexes, foreign keys, enums, associations, validators). They never read business rows, value distributions, or "is this table empty" state. Only the relationship resolver (reads) and the loader (writes) touch business rows. A test enforces this.
  4. **Internal seams stay.** The Runtime talks to the resolver and loader through in-process value objects (P5a/P5b, P7/P8). This keeps the Runtime testable with fakes and allows a custom component as an advanced extension point. Replacing them is never required.
  5. **Model metadata is part of `TargetSchema` (P2).** Enums, associations, virtual attributes and validators are introspected from the model; the separate `SemanticSchema` (P2-Ext) contract is removed.
  6. **Behavior options** (model validations, callbacks, timestamps, load strategy, transactions, error handling) are configuration, with defined defaults. See `docs/architecture/configuration.md`.
  7. **The Runtime owns dead-lettering.** The loader returns a per-record outcome; the Runtime writes dead-letter records and the report.
  8. **Removed:** the consumer-supplied SQL executor, the `adapters` config section, `protocol_version` on in-process objects, `unresolved_policy: defer`, `transaction_mode: whole_job`, and `concurrency > 1` (MVP is serial).
* **Retained from earlier ADRs:** ADR-01 (as amended by ADR-10 and ADR-13), ADR-02 through ADR-05, ADR-07, ADR-09, and the 4-state validation taxonomy.
* **Consequences:**
  * Much less consumer effort; Rails users configure behavior and run.
  * The engine is no longer framework-independent; non-Rails, non-ActiveRecord consumers are out of scope.
  * Open items (supported ActiveRecord/Ruby versions, standalone use outside Rails, MySQL, resume after partial load) are tracked in `docs/planning/roadmap-and-phases.md`.

---

### ADR-12: Recommendations Are Ranked by Column Names Only; Values Feed Value Mappings
* **Status:** Accepted (2026-10-10). Details and reasoning: `docs/architecture/recommendation-name-matching.md` (D1 to D16). *Refined by ADR-14 (2026-10-11): ranking, assignment and thresholds are unchanged; the value scan of item 3 now runs in its own stage, after the column mapping is settled, and only for the mapped columns.*
* **Context:** The earlier design scored pairs with a weighted formula (name 0.45, type 0.25, values 0.20, structure 0.10) and used hard gates on types and values. That let data outvote names, hid contributions in one number, and meant a few dirty values could delete the obviously right column.
* **Decision:**
  1. **Ranking uses column names only.** Names are tokenized into words (separators, camelCase, digits, acronym runs; singularized; table-name prefix stripped from targets). A pair of words scores `shorter / longer` when the shorter is a full prefix of the longer, otherwise 0. A pair of columns scores `2 x (sum of word scores) / (target words + source words)`, each word used at most once, minus a fixed penalty (10 points proposed) when matched words appear in a different order. For real foreign-key columns only, a trailing `id` is ignored as a reference marker.
  2. **Assignment is greedy and one-to-one.** All pairs are sorted best-first with a fixed tie-break order (score, more perfectly matched words, fewer leftover source words, source column position, target column position); each source and each target column is used at most once.
  3. **Values never change the ranking and never remove a pair.** The source scan is a full streaming pass with bounded memory. It reports per source column the non-empty and empty counts and the distinct values with counts (capped at 1,000, configurable), plus a cheap type-compatibility count per mapping. Distinct values exist to let the customer configure value mappings; whether data will load is answered by the dry run.
  4. **Abbreviations and synonyms are configured by the customer** in `engine.yml` (global word synonyms and per-target-column aliases). No built-in vocabulary. Safe value-mapping suggestions only: exact matches to the model's allowed values ignoring case, spaces and punctuation, and a small fixed boolean word list.
  5. **Columns the database fills or refuses to write** (auto-numbered keys, generated, virtual, read-only) are never recommended and are shown in the facts.
  6. **Reference columns:** the source column is ranked by name like any other; the **lookup column** in the parent table is chosen by the customer and never guessed. A mapping without a lookup uses the source values as ids directly.
  7. **Inclusion threshold:** pairs at or above it (default 55, configurable) go into the plan; below-threshold candidates are listed as doubtful and enter the plan only when the customer adopts them. Pairs with a 0 name score are not candidates.
* **Consequences:** Rankings are reproducible from the names alone. When names tie, only the tie-break order decides, not the data. A pair with a clear data mismatch can be recommended; the facts flag it and the dry run and run-time validation catch the rows. Supersedes the weighted scoring formula and hard gates in `docs/architecture/recommendation-and-validation.md` (rewritten).

---

### ADR-13: Acknowledgement Flag Required to Build; Draft as a JSON Response
* **Status:** Accepted (2026-10-10). **Partially supersedes ADR-10** (optional review; draft shape). **Superseded by ADR-14 (2026-10-11):** the single JSON draft is replaced by a header result and a value result, and the acknowledgement flag is removed. The list of what the Builder reads (item 3) and the build errors (item 4, except the acknowledgement error) carry over.
* **Context:** With ranking by names only and weak candidates visible but unmapped, a recommended plan can still be wrong, and review is the safeguard. A conditional gate based on confidence tiers was judged more complex and unreliable.
* **Decision:**
  1. **The Planner returns a JSON draft** with three parts: `findings` (visibility: source columns with non-empty/empty counts and distinct values; target columns with type, constraints, enums, and for reference columns the parent table and its columns), `draft_plan.column_mapping` (one entry per writable target column, keyed by target column name, each with `source_column`, `value_mapping`, optional `lookup`, and the facts `confidence`, `reason`, `type_compatibility`), and `acknowledgement_flag`.
  2. **`MigrationPlanBuilder` accepts a draft only if `acknowledgement_flag` is `true`.** Missing or `false` means `build` fails. No thresholds or tiers are involved. Resetting the flag after later edits is the consumer's responsibility; the engine never resets it.
  3. **The Builder reads only `source_column`, `value_mapping`, `lookup` and `acknowledgement_flag`.** Everything else (`findings`, `confidence`, `reason`, `type_compatibility`) is a fact and is ignored, even if edited or stale.
  4. **Build errors** include: acknowledgement missing; a required target column (`NOT NULL`, no default, not filled by the database) with no `source_column`; a `source_column` or `lookup` column that does not exist. All errors are returned at once.
  5. "No changes" remains valid: the consumer sets the flag without editing anything.
* **Consequences:** Review is mandatory again, but as a plain flag and not a workflow. `MigrationPlan` (P3) stays state-only and the Runtime never sees facts. `overview.md`, `protocols.md`, `mvp-scope.md`, the README and the test strategy were updated to match. *(Superseded by ADR-14.)*

---

### ADR-14: Staged Engine Methods; Every Stage Boundary Is a Contract; Acknowledgement Flag Removed
* **Status:** Accepted (2026-10-11). **Supersedes ADR-13.** Restores ADR-10 item 4 (review is optional and consumer-owned). Refines ADR-12 item 3 (when the value scan runs). Ranking, assignment, thresholds and the row-access boundary (ADR-11, ADR-12) are unchanged.
* **Context:** One draft that mixed column names, values and a review flag meant the value scan ran before anyone knew whether the column mapping was right, and the consumer had no clear place to see facts again after editing. Since ranking depends on names only (ADR-12), name matching and value analysis are separate pieces of work and can be separate steps. The acknowledgement flag existed to mark "someone looked at the draft"; with explicit steps, the consumer's call to the next step is that mark, and a consumer could always set the flag from code anyway.
* **Decision:**
  1. **The engine exposes one method per stage.** `Engine.new(config_path:, source_path:)` is given the configuration and the source once. Then, in order: `analyze_headers`, `analyze_values`, `build_plan`, `dry_run`, `run`. Each method is a function of its arguments (plus the configuration and the source path); the engine keeps no stage state between calls.
  2. **Header stage (column mapping).** Reads only the source header row and the target schema (P2); never values. Returns a `HeaderAnalysis` with facts (source columns, target columns, unmatched columns on both sides, per-target candidates, doubtful candidates) and the editable state `column_mapping` (per writable target column: `source_column`, optional `lookup`). Names rank, as in ADR-12.
  3. **Value stage.** Takes the (possibly edited) column mapping and the type of each mapped target column (from `TargetSchema`), and scans the source once, only for the mapped source columns. Returns a value result (`ValueAnalyzer::Result`) keyed by source column with, per column: the `target_column` it is mapped to, its position, the `empty` count, `type_compatibility` (`fits` and `total`: how many non-empty values fit the target type, by strict rules of our own and not ActiveRecord's lenient cast), and the distinct values split into `compatible` and `incompatible` lists, each with counts and its own cap (configurable); plus the editable state `value_mapping`. A target type with no fit rule yet fits every value. Values never change the column mapping.
  4. **Recompute is the same method called again with the consumer's edits.** There is no separate "reanalyze" method: `analyze_values(mapped_columns:)` takes one parameter: for each mapped source column, its target column, its type information and, when it has one, its `value_mapping`. With a `value_mapping`, each value is measured as the value it maps to (a value that maps to nil or a blank counts as empty), so the facts show what would be loaded; the mapping comes back in the result, inside the column, to be edited and passed in again. Because the value mapping lives in the column's entry, it can never be given for a column that is not mapped. The file is read again each time, and nothing is kept in the engine's memory. The header stage follows the same pattern for its editable state.
  5. **`build_plan(header_analysis, value_analysis)` returns a `BuildResult`:** a `MigrationPlan` (P3, state only) or all errors at once, each with the column, a stable code and the reason. It reads only `source_column`, `lookup` and `value_mapping`; facts are ignored, even if edited or stale. Errors: a required target column (`NOT NULL`, no default, not filled by the database) with no `source_column`; a `source_column` or `lookup` column that does not exist; a `value_mapping` for a target column that is not mapped; a stale value result (item 6).
  6. **Staleness rule.** For every source column in the value result, the `target_column` it was computed for must equal the target column that source column is mapped to in the current column mapping; otherwise `build_plan` fails for that column. Nothing else (such as the source file) is compared.
  7. **No acknowledgement flag.** Calling `build_plan` is the consumer's explicit step. Review is consumer-owned; the engine never prompts or tracks it. The dry run is the answer to "will this load".
  8. **Every stage boundary is a named contract.** An engine method takes and returns only contracts: value objects with documented fields that serialize to and from plain JSON (`to_h` and a hash constructor), so a consumer can store, show, edit and pass them back. A component depends on the contract, not on another component's class. Each contract is documented in `docs/architecture/protocols.md` with its producer, its consumers, and which fields are facts (regenerated, never read by the next stage) and which are state (editable, read by the next stage).

    | Contract | Produced by | Consumed by | Consumer edits |
    |---|---|---|---|
    | `SourceHeaders` | header read (Source) | header stage | none |
    | `TargetSchema` (P2) | target schema reader | header stage, value stage (column types), `build_plan` | none |
    | `HeaderAnalysis` (header result) | `analyze_headers` | `analyze_values`, `build_plan` | `column_mapping` |
    | `ValueAnalyzer::Result` (value result, P1) | `analyze_values` | `build_plan` | `value_mapping` |
    | `BuildResult` / `MigrationPlan` (P3) | `build_plan` | `dry_run`, `run` | none |
    | P4 to P8 | Runtime stages | Runtime stages | none |
    | `RunReport` | `dry_run`, `run` | consumer | none |

    The value result is what `ValueAnalyzer` returns and replaces the earlier `SourceSchema`. Names and numbering of `SourceHeaders` and `HeaderAnalysis` are provisional until Phase 1 freezes the contracts.
  9. **Unchanged:** the Runtime accepts only `MigrationPlan`; the order of Runtime stages; the dry run (rolled-back transactions, `target-access.md`); only the resolver and the loader touch business rows.
* **Consequences:**
  * The consumer sees column mapping first and value work second; a wrong column match costs no value scan.
  * Facts can be refreshed after any edit without losing the edits.
  * Going back is allowed; a value result made for an older column mapping is refused at build.
  * A consumer can call `build_plan` on unreviewed recommendations. The build errors and the dry run are the safety net.
  * The Source Analyzer needs a header-only read and a scan restricted to a list of columns, in addition to the full scan.
  * The acknowledgement flag, its error code and ADR-13's single draft JSON are removed. Affected documents (`overview.md`, `protocols.md`, `mvp-scope.md` Definition of Done items 5 and 6, `testing-strategy.md`, `recommendation-name-matching.md` D8 and the draft JSON decisions, the README) are updated in the same change as this ADR is applied.
  * **Open:** a `version` field on the stored stage results (ADR-11 removed `protocol_version` from in-process objects, but these are persisted by consumers between sessions); whether `analyze_values` may be limited to a subset of target columns; whether `reanalyze_headers` keeps a `lookup` when its `source_column` is changed.

### ADR-15: Foreign Keys Are Plain Columns; Lookup Deferred; Row-by-Row Validated Saves Through the Model
* **Status:** Accepted (2026-10-14). **Narrows ADR-11** (built-in relationship resolution, P5a/P5b) and **ADR-10 item 6 and ADR-14 items 2 and 5** (`lookup`) for the MVP. Supersedes nothing else; the row-access boundary and the stage order are unchanged.
* **Context:** The consumer already edits `value_mapping` in the value stage, so a name in the source (`"Acme Corp"`) can be mapped to the id of the parent row (`42`) without any engine feature. The engine cannot create a parent row that is missing, so a lookup that fails is an error whether the engine looked it up or the consumer mapped it. The lookup therefore adds convenience, not capability, and it is the only part that reads parent rows. The target model already checks that a required `belongs_to` parent exists when it validates a record.
* **Decision:**
  1. **A foreign key column is an ordinary target column.** Its source values are the primary key of the parent row. A consumer who has names maps them to ids with `value_mapping`, which the value stage already measures and returns. The MVP has no `lookup` in `column_mapping` or in the `MigrationPlan`, and no resolver (P5a/P5b).
  2. **The loader saves one record at a time, through the model**, so the model's validations run. Bulk inserts that skip validations (`insert_all`, `upsert_all`) are not supported in the MVP.
  3. **Parent existence is checked by the model at load time.** A required `belongs_to` adds the error `"<Association> must exist"` when the parent row is not found; the record is dead-lettered with that message. An association marked `optional: true` is not checked by the model, and the database foreign key constraint, if any, is the last guard. The engine does not change the model's settings.
  4. **The header facts describe foreign keys from model metadata only:** for each target column that is the foreign key of a `belongs_to`, the association name, the parent model, and whether it is required. No rows are read.
  5. **The value stage's type rules apply to the foreign key column** like any other column, so a name given where an id is expected is flagged before load.
* **Consequences:**
  * The MVP engine is smaller: no resolver, no `UnresolvedReference` (ADR-04) and no `lookup` build errors. Only the loader reads business rows, and it does so inside the model's validation.
  * The error for a missing parent arrives at load, per record, with the model's message, and not before. The dry run (rolled-back transactions) shows it without writing.
  * Each record costs one extra read for the existence check. The loader may turn on the ActiveRecord query cache to avoid repeats.
  * A consumer whose model has no required association gets no existence check beyond the database constraint.
  * Deferred, not excluded: lookup by a parent column, creating missing parents, and bulk loading. Each would be a new ADR.
  * Affected documents (`overview.md`, `protocols.md`, `target-access.md`, `mvp-scope.md`, `testing-strategy.md`, `recommendation-name-matching.md` reference-column decisions, CLAUDE.md principles 1 and 3 and the flow diagram) are updated when this ADR is applied.
  * **Open:** whether the Runtime's relationship-resolution stage is removed from the stage order or stays as a no-op; whether the post-resolution validation (ADR-03, ADR-05) still runs as a separate stage when it has nothing to resolve.

### ADR-16: Framework-Agnostic Core; One Distribution per Adapter
* **Status:** Accepted (2026-10-15). **Narrows ADR-11 item 2 and CLAUDE.md principle 4** for packaging: target access is still built in and still needs no consumer code, but it ships as an adapter distribution, not inside the core. Implements ADR-08.
* **Context:** The engine should not depend on one database library. The first adapter is ActiveRecord; Sequel or others may follow. Each adapter has its own schema reader, loader and error mapping, and the rest of the engine is the same for all of them.
* **Decision:**
  1. **Two gems from one repository.** The core gem (`pipeforge`) has no database library in its gemspec. An adapter gem (`pipeforge-activerecord`) depends on the core. A consumer installs only the adapter gem; the core comes with it.
  2. **Core owns:** `Configuration`, `Engine`, the contracts (P1–P8 value objects), `ValueAnalyzer` and `TypeChecker`, the source reading (CSV), the runtime loop, batch splitting, error collection, `Utilities`.
  3. **Adapter owns:** the target schema (P2), the loader (P7/P8), transaction scopes, the pre-check rules derived from the schema, and the mapping of database errors to codes.
  4. **Adapter contract** (names provisional until Phase 1 freezes the contracts):
     * `schema(target_model:)` returns `TargetSchema` (P2). `target_model` is a class-name string; the adapter resolves it.
     * `transaction(scope:) { ... }`, where `scope` is `:run`, `:batch` or `:row`. A nested scope is a savepoint, so an exception rolls back only that scope.
     * `load_batch(rows:)` and `load_row(row:)` return a per-row outcome.
     * `precheck_rules(target_column:)` returns rules the adapter can state with certainty, or none.
     * `map_error(error)` returns the stage and the code (ADR-17 item 9).
     The core calls these methods; it never names an ActiveRecord class.
  5. **Boundary test.** A spec fails if any core file references `ActiveRecord`. The runtime is tested with a fake adapter that follows the same contract.
* **Consequences:**
  * A second adapter needs no change to the core, only a new gem that implements the contract.
  * The consumer's setup is one gem line for the adapter. The core's gemspec has no Rails or ActiveRecord dependency.
  * The adapter contract is a public API from the first release, so changing it is a breaking change.
  * **Open:** the final method names; whether `schema` is one call or split into columns and associations.

### ADR-17: One Runtime Entry Point; Checkpoints; Dry Run and Run Share One Path
* **Status:** Accepted (2026-10-15). **Supersedes ADR-13, and ADR-14 items 1 (the `dry_run` method), 5 (`build_plan`) and 9 (the runtime accepts only `MigrationPlan`).** **Narrows ADR-15 items 2 and 3:** batch loading (`insert_all!`) is now allowed, and the model-level save is the row path. **Deviates from CLAUDE.md principle 6** for `offset` and `limit` on purpose (item 3).
* **Context:** A separate `build_plan` step added a stage that the consumer could not act on, because the header and value results already show the plan. The runtime is the public API, so it should take the two stage results directly, check them, and do the work. A large file that fails midway needs a way to continue, and a dry run that holds locks needs a time limit the consumer can see.
* **Decision:**
  1. **One method for the runtime:** `Engine#run(mode:, header_analysis:, value_analysis:, offset: nil, limit: nil, skip_callbacks: nil, strategy: nil, failed_rows:, report:)`. `mode` is `:dry_run` or `:run`. `offset`, `limit`, `skip_callbacks` and `strategy` given to the call override the engine configuration for that call. `failed_rows` and `report` are IO-like objects (item 12). `build_plan` and `dry_run` are removed.
  2. **Contract check first, all errors at once.** Before any row is read, `run` checks: the value result matches the header analysis for every mapped column (ADR-14 item 6); each mapped source column is in the file header; each mapped target column is in the target schema; every required target column (`NOT NULL`, no default, not filled by the database) is mapped. Errors are collected and reported together (CLAUDE.md rule 22).
  3. **`offset` and `limit` belong to the engine, not to a migration.** `Engine.new(config_path:, source_path:, offset: nil, limit: nil)` sets them for both `analyze_values` and `run`, because the value stage and the runtime must read the same slice. This departs from CLAUDE.md principle 6, which puts per-migration intent in the migration input; the decision is deliberate, and the call-level override in item 1 keeps the per-run choice available.
  4. **`offset` is a checkpoint, not a plain number.** It is the pair `{byte_offset:, row_number:}` from an earlier run's checkpoint (item 5). A run without it starts at the top of the file. Seeking to a byte offset needs `seek` on the source IO (item 12).
  5. **Checkpoint after every batch.** After each batch is committed, the report records the last processed row's `row_number` and `byte_offset`. A dry run never commits, so its checkpoint is a progress marker, not a resume point.
  6. **Row numbers are absolute.** A row number is its 1-based data record number in the whole file, header excluded, so failed rows keep the same number after a resume. A quoted field can span lines, so it is not the line number. Blank and all-empty rows are not counted, as in `ValueAnalyzer`.
  7. **One code path, two transaction layouts.**
     * **Dry run:** one `:run` transaction around everything, rolled back at the end. Each batch runs in a `:batch` scope inside it.
     * **Run:** each batch is its own `:batch` transaction, committed on success.
     * **Batch failure, in either mode:** the batch scope is rolled back and its rows are retried one by one, each in a `:row` scope.
  8. **Load strategy.** `strategy: auto | batch | per_record` in `engine.yml`, overridable per call. `batch` uses `insert_all!`, which raises on a duplicate; plain `insert_all` would skip duplicates silently and count them as loaded. `per_record` calls `save`. `auto` picks `batch` only when callbacks are skipped and the model has no validators.
  9. **Error codes are a subject plus what is wrong.** The adapter's `map_error` returns one of: `value_not_unique`, `value_too_long`, `value_wrong_type`, `value_missing`, `parent_missing`, `value_breaks_check`, or `database_error` (which keeps the native code and message). Each error records its `stage`: `precheck` or `database`. These codes are proposed here and need rows in the codes table in `protocols.md`.
  10. **Pre-checks.** The adapter supplies rules derived from the schema, applied after type casting. A rule is returned only when the adapter is certain; otherwise the row goes to the database. The value stage (ADR-14) may be stricter than the pre-check, because it only reports facts.
  11. **Callbacks.** `skip_callbacks: true | false` in `engine.yml`, overridable per call. `batch` always skips validations and callbacks; `strategy: batch` with `skip_callbacks: false` is refused before the run, with its own code.
  12. **IO-like objects.** Each option takes any object that has the methods it needs, and the engine checks them at construction or call time, collecting every missing method: the source needs `read`, `rewind` and `seek`; `report` and `failed_rows` need `write`. Error codes name the object and method, for example `source_io_missing_seek`.
  13. **Dry run lock timeout.** `dry_run.lock_timeout` in `engine.yml`, in seconds, is set by the adapter on the dry run's transaction. A dry run holds its row locks, and the share locks that foreign key checks take on parent rows, until it ends; `configuration.md` and the operations notes document this so the consumer can choose full or offset runs when traffic is low.
  14. **Result.** `run` returns a summary `{mode:, loaded_rows_count:, failed_rows_count:, checkpoint:}`. The failed rows go to `failed_rows` as JSON Lines, one failed row per line: row number, the original source values, and every error with `stage`, `column`, `code` and `message`.
  15. **Determinism.** The same input, mapping and options give the same summary and the same failed rows, in file order.
* **Consequences:**
  * The consumer makes one call for each mode. The dry run is the only preview of what a run will do.
  * A checkpoint allows a restart after a crash, but only with an unchanged file and mapping. The consumer checks that; the engine does not (consumer-owned, per the decision that file changes are not the engine's concern).
  * A dry run with an offset starts from the same state as a run with that offset, so the two report the same failures when the database is unchanged.
  * Model-level saves through `per_record` remain the only path that runs callbacks and validations; `batch` is the fast path for tables without them.
  * **Open:**
    * **Cast behavior (accepted).** ActiveRecord casts a value before it writes it: `"abc"` for an integer column becomes `0` and loads. The adapter does not reject it, because the database never receives the original text and so has nothing to reject. The value stage reports the mismatch before the run, and the consumer decides. This is documented for the ActiveRecord distribution, and a spec pins the behavior (`"abc"` loads as `0`) so a change in Rails shows up as a failure. Other adapters decide for themselves under the pre-check rule in item 10.
    * **Checkpoint shape.** Passing the checkpoint pair as `offset:` is less friendly than a plain number. A plain byte offset plus a separate `row_number:` would also work.
    * **Stage order.** Whether the post-resolution validation (ADR-03, ADR-05) stays as a stage now that there is no resolver (ADR-15).

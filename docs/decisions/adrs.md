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
  1. **Ranking uses column names only.** Names are tokenized into words (separators, camelCase, digits, acronym runs). A pair of words scores `shorter / longer` when the shorter is a full prefix of the longer, otherwise 0. A pair of columns scores `2 x (sum of word scores) / (target words + source words)`, each word used at most once, minus a fixed penalty (10 points proposed) when matched words appear in a different order. For real foreign-key columns only, a trailing `id` is ignored as a reference marker.
  2. **Assignment is greedy, one match per target column.** All pairs are sorted best-first by score; pairs with the same score are ordered by target column name and then source column name. The sorted pairs are walked down to the inclusion threshold: a target that already has a match is skipped, a source that was matched with a different score is skipped, and any other pair is a match. A source can be shared by targets that have the same score for it (see the amendment of 2026-10-23 below).
  3. **Values never change the ranking and never remove a pair.** The source scan is a full streaming pass with bounded memory. It reports per source column the non-empty and empty counts and the distinct values with counts (capped at 1,000, configurable), plus a cheap type-compatibility count per mapping. Distinct values exist to let the customer configure value mappings; whether data will load is answered by the dry run.
  4. **Abbreviations and synonyms are configured by the customer** in `engine.yml` (global word synonyms and per-target-column aliases). No built-in vocabulary. Safe value-mapping suggestions only: exact matches to the model's allowed values ignoring case, spaces and punctuation, and a small fixed boolean word list.
  5. **Columns the database fills or refuses to write** (auto-numbered keys, generated, virtual, read-only) are never recommended and are shown in the facts.
  6. **Reference columns:** the source column is ranked by name like any other; the **lookup column** in the parent table is chosen by the customer and never guessed. A mapping without a lookup uses the source values as ids directly.
  7. **Inclusion threshold:** pairs at or above it (default 55, a positive whole number, configurable) are matches; every other column is unmatched (amendment of 2026-10-23 below). Pairs with a 0 name score are not candidates.
* **Consequences:** Rankings are reproducible from the names alone. When names tie, the data does not decide: a source shared by tied targets is left to the consumer, and a tie inside one target is decided by the column names and shown in `tied_with` (amendment of 2026-10-23 below). A pair with a clear data mismatch can be recommended; the facts flag it and the dry run and run-time validation catch the rows. Supersedes the weighted scoring formula and hard gates in `docs/architecture/recommendation-and-validation.md` (rewritten).
* **Amendment (2026-10-21, superseded by the amendment of 2026-10-23): tied pairs are doubtful.** A pair that ties with another on score, exact matches and unmatched source tokens, and competes with it for the same source or target column, is no longer locked by the column position (which gave `Name` to `last_name` for no reason in the names). None of the competing pairs is a match; they are listed as doubtful, every tied candidate of a target is listed, and their columns stay free of lower pairs. The positions only fix the order of the output. A tied pair with no rival is still a match.
* **Amendment (2026-10-21): words are not singularized.** The tokenizer used to turn plurals into singulars with a short built-in rule list. It was removed: no short list is right for every English word, and a wrong cut can make two different words equal. Words are kept as written (lowercased), so `name` against `names` scores 80% by the prefix rule instead of 100%. The table-name prefix is not removed from target column names (a rule for it was built and taken out for now, because without singularizing it also stripped words that only start the table word, such as `use_count` on `users`).
* **Amendment (2026-10-23): matches by target, no doubtful list.** *Supersedes the rules of item 7 and the amendment of 2026-10-21 above, and changes the header result.* The header stage gives the consumer the possible best matches and the state (metadata) of the target columns. Pairs are scored as before and sorted by score alone; pairs with the same score are ordered by target column name and then source column name, so the result is deterministic and does not depend on where the columns sit in the file or the table. The sorted pairs are walked down to the inclusion threshold: a target that already has a match is skipped; a source column that was matched with a different score is skipped (the target with the better score keeps it); any other pair is a match. A source column matched with the **same** score by an earlier pair is shared, so one source can appear in the matches of several targets when they tie, and the consumer chooses which to keep. Sharing looks at the score only. Everything else is unmatched: there is no `doubtful` list. The result is `matches`, keyed by target column in table order (`source_column`, `score`, `metadata`), `unmatched_source_columns`, and `unmatched_target_columns` as `{name:, metadata:}`. The metadata of a target column is its schema entry (type, sql type, limit, max length, precision, scale, nullable, default, foreign key), and replaces the separate `foreign_keys` list. `column_mapping` and the `reason` (ordered or unordered) are no longer part of the result; the consumer builds `mapped_columns` for `analyze_values` from `matches`. The reorder penalty is kept in the score. A trailing `id` is an ordinary word: `company_id` matches `Company Id` fully and `Company` less well (the reference-marker rule of D16 is removed). `inclusion_threshold` is a positive whole number. A tie inside one target (`Phone 1` and `Phone 2` for `phone`) is decided by the column names (`Phone 1` is the match), and the other source columns that had the same score for that target and were free to take it are listed in the match's `tied_with` (`["Phone 2"]`), so the consumer can see the tie; `tied_with` is an empty list when nothing tied.

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
  * **Amendment (2026-10-23): the header facts of a foreign key no longer say whether it is required.** *Changes item 4.* The metadata of a foreign key column is its association name and its parent table. The `required` field of the foreign key is removed, and so is `nullable` from the target column: the one answer to "can this column be left without a source column" is the column's own `required`, which the adapter sets (from NOT NULL and the default, see the last amendment of 2026-10-24 in ADR-18). A second answer on the foreign key could disagree with it, and nothing in the engine reads it. The model still checks parent existence at load, as items 3 states.
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
* **Amendment (2026-10-17): how the core finds the adapter.**
  * **The core's one door.** The core has a module, `Pipeforge::TargetAdapter`, with one method for each operation of the adapter contract (`TargetAdapter.schema(target_table:)` today). The core only ever calls these methods. It never holds, creates or receives an adapter.
  * **The adapter gem installs the real adapter, once.** When the gem is loaded it calls `Pipeforge::TargetAdapter.install(adapter: Pipeforge::ActiveRecordAdapter.new)`. Each call on the module then goes to that installed adapter. A consumer who installed `pipeforge-activerecord` writes nothing about it, and `Engine.new` takes no adapter argument. If two adapter gems are loaded, the last one installed is used.
  * **The installed adapter is shared** by every engine, so it keeps no state of its own. Specs stub `TargetAdapter.schema`, or install a fake adapter object the same way.
  * **No adapter.** `Engine.new` checks that an adapter is installed (`TargetAdapter.ensure_installed`) before anything else, and stops with `target_adapter_not_installed` if none is. The engine cannot be built without an adapter gem.
  * **Naming.** The target is the table (`target_table:`, ADR-20). The target adapter is the interface to it.
* **Amendment (2026-10-17): the two gems are separate folders.** The repository holds `pipeforge/` (the core: `lib/`, `spec/`, its own gemspec) and `pipeforge-activerecord/` (the adapter, with its own gemspec, `lib/` and `spec/`); a root `Gemfile` points at both. The core's only runtime dependency is `smarter_csv`: it has no database library and no ActiveSupport, and a spec loads it in a fresh process to prove it. The adapter gem has its own version (`Pipeforge::ActiveRecordAdapter::VERSION`), apart from the core's. It states the range of core versions whose adapter contract it follows (now `>= 0.0.0, < 0.1`), and depends on `activerecord`. Each gem's specs run on their own.

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

### ADR-18: Stage Input Is Validated Against Current Truth; Types Come from the Schema
* **Status:** Accepted (2026-10-16). **Amends ADR-14 item 4** (the consumer no longer sends a type for each mapped column) and **ADR-14 item 3** (the value stage takes no type). Drift detection is decided in part (item 10): each reader owns its fingerprint. Extends ADR-14 item 6 (staleness) with new error codes.
* **Context:** Each request builds a new `Engine`, so a stage's input is a hash the consumer may have edited, stored, or produced by an older gem version. The engine must check that input against the current source and target schema on every call, and must not trust types or facts sent back to it.
* **Decision:**
  1. **State and facts.** The consumer sends state only: `source_column` per target column, `value_mapping`, and any split (item 5). Facts (types, constraints, enums, counts, confidence, reasons, compatibility) are never read from input; they are recomputed on every call. Edited facts have no effect.
  2. **Types come from the target schema.** `analyze_values` takes `target_column` and optional `value_mapping`. The engine looks up the type, limit, length, precision and scale from the current `TargetSchema` on each call. The consumer cannot send a type.
  3. **Two validation layers, shape first.** Shape validation (required keys, JSON types, a supported `version`, no unknown keys) runs before any file or database access. Semantic validation runs next, against the current source headers and the current `TargetSchema`.
  4. **Unknown keys are rejected.** A typo in a key is reported, not ignored.
  5. **One source column may feed several target columns only with a split** *(relaxed by the amendment of 2026-10-23: a source column may feed several target columns, each measured on its own).* Each such entry names the separator and the index of the piece it takes (for example `{ source_column: "Name", separator: " ", index: 0 }`). A source column used without a split may feed only one target column. A split piece is measured like any other mapped value (its measurement rules are open, see below).
  6. **Mapped-to values are not validated.** The value stage reports which values fit the target type (`TypeChecker`), and the consumer fixes the rest. A value that does not fit is a fact, not an error.
  7. **Errors carry a `path`.** Each error entry has `path` (for example `column_mapping.email.source_column`), `code`, `message` and the fields that locate it. The `path` is added to the error table in `protocols.md`.
  8. **Every stage validates its own input** through one shared validator, so the rules are identical in every stage.
  9. **`run` requires both results** and checks them as ADR-17 item 2 describes, with the new codes. All errors are returned together.
  10. **Each reader owns its fingerprint.** The source reader produces `source_fingerprint` (SHA-256 of the file's raw bytes, computed while streaming), only when `source.fingerprint` is on (item 11). The target schema reader (the adapter's `schema`, ADR-16) produces `schema_fingerprint` (a stable hash of the relevant columns, types and constraints, independent of column order). Each stage result carries the fingerprints of the inputs it was built from. A stage compares the fingerprint it receives with the one its reader computes now, and reports `source_changed` or `schema_changed` (with `path`) on mismatch. A stage never computes a fingerprint for an input it does not read.
  11. **The source fingerprint is optional, set in `engine.yml`** (`source.fingerprint: true | false`). The engine does not decide it per call.
      * **Off (default, proposed):** no source fingerprint is computed or compared. The consumer owns the question of whether the file changed (ADR-17). The value result has no `source_fingerprint`.
      * **On:** the value stage builds the SHA-256 batch by batch during its existing pass, over each parsed row serialized as a JSON array of its values in header order, one row per line, and returns `source_fingerprint` at the end. No extra read is needed for that. `run` then makes a first pass that parses every row and builds the same fingerprint, before any batch is loaded, and compares it with the value result's. The load is the second pass. A mismatch stops the run with `source_changed` before any row is loaded. If the value result has no fingerprint, `run` refuses with `source_fingerprint_missing`.
      * The schema fingerprint is checked on every call whichever way the option is set, because it is cheap.
* **Amendment (2026-10-21): item 2 is built, and the table is given to the engine once.** *(The shape of `mapped_columns` and the codes of the validator were changed by the amendment of 2026-10-23 below.)* `Engine.new(source_io:, target_table:)` takes the target table, because every stage works on the same table; `analyze_headers` takes no argument and `analyze_values(mapped_columns:)` reads only `target_column` and an optional `value_mapping` from each entry (a `type` sent with a column is ignored); the value mapping lives in the column's entry, so it can never be given for a column that is not mapped. The engine reads the schema of the table on each call and passes the type, limit, length, precision and scale of each mapped target column to the value stage. One validator in the engine, `MappedDataValidator`, checks the mapped data against the file header and the schema and raises every mistake together in one `InvalidMappedColumnsError` (renamed from `IncompleteColumnsError`): `mapped_column_not_in_file` (it replaces `Source::MissingColumnError`, which is gone), `column_missing_target_column`, `target_column_not_in_schema` (the column does not exist, or it is the primary key, an ignored or a generated column) and `target_column_has_several_sources` (two or more source columns are mapped to one target column, which holds one value per row). The engine turns the keys of a value mapping into text before the value stage runs, because the values of the file are text (`1` and `"1"` are the same key); two keys that give the same text become one key, and the later one is used. The value stage no longer validates; `run` will call the same validator. The engine reads the schema of the target table once and keeps it, like the header of the source, because an engine is built for one source and one table. `column_missing_type` is gone. The engine builds one `Source::CsvReader` when it is created and gives it to every stage; the source is not expected to change while the engine exists, so the reader reads the header once and keeps it, and reads the rows again on every pass.
* **Amendment (2026-10-23): mapped columns are keyed by target column, and the required columns are checked.** *Changes the input shape of items 2 and 5 and the codes of the amendment above.* `analyze_values(mapped_columns:)` is keyed by target column, like the `matches` of the header result, and each entry names its `source_column` and optionally a `value_mapping`: `{"email" => {source_column: "Mail"}}`. The consumer can pass `header_analysis.matches` (or the part they keep) as it is, because the other keys are ignored. The value result is keyed by target column too; each summary has its `source_column` and the `position` of that column in the file, and does not repeat the target column. A source column may be mapped to several target columns: that is the consumer's choice and not a mistake, so the restriction of item 5 (one source column for one target column without a split) no longer applies, and the source column is measured once for each target column. `MappedDataValidator` checks only what the engine needs to be correct: the shape of the input (`mapped_columns_not_name_value_entries` when the mapped columns are not a Hash, which stops at once; `mapped_column_not_name_value_entries` when an entry is not a Hash; `value_mapping_not_name_value_entries` when a given value mapping is not a Hash; the keys and values of a value mapping are not checked), then `target_column_not_in_schema`, `column_missing_source_column` (an entry names no source column), `mapped_column_not_in_file`, and `required_column_unmapped` (a required target column has no entry). `column_missing_target_column` and `target_column_has_several_sources` are gone. `analyze_values` uses the check and so will `run`. A target column is required when the adapter says so: `TargetColumn` has a `required` field, set by the adapter because it knows what its framework fills in. The ActiveRecord adapter follows the database definition only, because the database is the source of truth: it sets it for a NOT NULL column with no default or default function, leaving out the columns Rails fills itself (the timestamps of a model that records them). The model is not consulted: a `belongs_to` the model requires on a column that accepts NULL does not make the column required, and a migration that disagrees with its model is for the app to fix. `required` is part of the metadata in the header result.
* **Amendment (2026-10-23): the model decides what a column is, not the database.** *Supersedes the statement in the amendment above that the database definition is the source of truth.* The application loads through its own model (ADR-15 item 3, ADR-17), so a model that disagrees with its table fails in the application too, and the engine does not guard against it. The ActiveRecord adapter therefore reads every attribute of a target column from the model: the type, size, precision, scale and default from the model's attribute (`type_for_attribute`, `column_defaults`), which can differ from the table when the model overrides them, and `sql_type` from the model's column list. A column is `required` when the model has an unconditional presence validation for it (a validation with `if`, `unless` or `on` does not count, because it is not certain), or for the `belongs_to` that uses it as its foreign key (Rails puts that validation on the association name, which the adapter maps back to the column), and the model gives it no default. `NOT NULL` in the database is not consulted, and the exception for the timestamps Rails fills is gone, because no validation requires them. A `NOT NULL` column that the model does not require is not asked for, and a row without it fails at load with the database's error, per row. The columns the model ignores are not in its column list, and generated columns are still left out.
* **Amendment (2026-10-24): `required` is NOT NULL and no default; the types stay the model's.** *Supersedes the rule for `required` in the amendment above; its rule for types stands.* A column is `required` when it refuses an empty value (`null` is false) and has no default: not in the table (a value or a default function, read from the column object) and not in the model (`column_defaults`). The model's presence validations and its `belongs_to` settings are not looked at: a column is made NOT NULL on purpose, and nobody leaves a column nullable when the model needs it. The exception for the timestamps Rails fills is not brought back, so a NOT NULL `created_at` or `updated_at` without a default is required and the consumer maps a source column to it (one source column may feed both). The type, limit, precision and scale still come from the model's attribute (`type_for_attribute`), so an `attribute` override counts, and so does `default`, which is the model's (`column_defaults`: a default only the model sets counts, and an enum shows its label). `TargetColumn` gains `enum_values`, `nil` or the label => stored value pairs from `defined_enums`, so the header result shows them. The value stage reads them too: a value in an enum column fits when it is one of the labels or one of the stored values (as text), whatever the stored type is, because the model accepts both and rejects anything else. The loader casts a stored value written as text (`"1"`) to the stored type before it loads, because `save` accepts the integer `1` and the label but rejects the text `"1"`; `insert_all!` accepts both.
* **Amendment (2026-10-24): the timestamps a model fills count as a default.** *Supersedes the sentence about the timestamps in the amendment above.* A column is not `required` when the model records timestamps (`record_timestamps`) and the column is one of the timestamp attributes it fills on save (`all_timestamp_attributes_in_model`, for example `created_at` and `updated_at`): the model supplies the value, which is a default in effect, and a consumer should not have to invent a source column for it. This is the only case where the model's code, and not a declared default, is read for `required`; a callback that sets any other column, or a validation, is still not looked at. On a model that does not record timestamps, a NOT NULL timestamp without a default is required like any other column. A consumer may still map a source column to the timestamps to load the original values.
* **Error codes (proposed):** `version_not_supported`, `key_not_known`, `key_missing`, `value_wrong_json_type`, `source_column_not_in_file`, `target_column_not_in_schema`, `target_column_not_writable`, `source_column_used_without_split`, `split_separator_missing`, `split_index_not_whole_number`, `value_mapping_for_unmapped_column`, `value_mapping_not_text`, `required_column_unmapped`, `value_result_out_of_date`.
* **Consequences:**
  * The UI can store the results as plain JSON and send them back, and the engine rejects anything that no longer matches the file or the schema.
  * Types can no longer be wrong, because the consumer does not send them.
  * A split adds a mapping shape the value stage must measure. Its rules are part of the open items.
  * **Open:**
    * **Default for `source.fingerprint`:** shipped as off (proposed). Confirm in Phase 1.
    * **Fingerprint input (decided):** the parsed rows, not the raw bytes. Whitespace trimming, quoting, line endings and dropped blank rows are applied before the rows are fingerprinted, so edits that cannot change the loaded values do not count as changes. JSON keeps the values of each row separate: a comma inside a value cannot be mistaken for a separator. Empty cells are `null`, and a newline inside a value is written as `\n`.
    * **Split measurement:** whether each piece's values are measured after the split, and how the `index` counts (from 0 or from 1).
    * **Version rules:** which versions the engine accepts, and what happens to results from an older gem.

### ADR-19: Source and Target Adapters Own Their Input and Their Fingerprints
* **Status:** Accepted (2026-10-16); the refactor moves the reader without new behavior. **Extends ADR-16** with a source side. An adapter gives the core a common interface to the data (source rows, source headers, the target schema). Adapters do not validate; all validation and fingerprinting stay in the core. Naming: the option, the value and the error use `fingerprint` (ADR-18 item 11), not `checksum`.
* **Context:** The header stage, the value stage and the run each read the source file, and the run also reads the target schema. Today the chunk reader lives inside `ValueAnalyzer`, and each stage would otherwise re-implement the reading and the checks.
* **Decision:**
  1. **Source reader** (one class per source format; CSV for the MVP). It is the only object that reads the file, and it gives the core this interface:
     * `headers`: the trimmed header names in file order.
     * `each_chunk`: the chunks of raw rows, as the current chunk reader gives them. The chunk reader moves out of `ValueAnalyzer` to this shared place, so the header stage, the value stage and the run use the same reading code.
     * `raw_lines`: the raw lines of the file, exactly as read, for the core to fingerprint. Used only when `source.fingerprint` is on.
  2. **Target adapter** (per distribution, ADR-16). It provides:
     * `schema(target_model:)`: the `TargetSchema` (ADR-16 contract).
     * The core computes the schema fingerprint from this schema, so the adapter does not compute it.
  3. **The core does all validation.** Column checks (source and target), fingerprint computation and comparison, and the errors all live in the core. Adapters never validate; they only give access to data. This keeps each rule in one place for every adapter.
  4. **Every stage uses the core's readers.** The header stage reads `headers`; the value stage reads `each_chunk`; `run` fingerprints `raw_lines` (when on) and compares it before any batch, then reads `each_chunk` for the rows.
* **Consequences:**
  * One place reads the source, so the rules about trimming, blank rows, row numbers and malformed rows hold for every stage.
  * A new target adapter must supply the schema, and nothing else.
  * The core stays free of database libraries; the source side has no database dependency.
  * **Decided:** one class per source format, sharing one interface (`headers`, and `each_chunk`, which takes a block and returns the number of data rows), so a new format is a new class (open/closed, CLAUDE.md rule 15). The CSV class is `Pipeforge::Source::CsvReader`.
  * **Open:** `raw_lines` and the fingerprint are not built by this refactor; they come with the source fingerprint work (ADR-18 item 11).

### ADR-20: The Target Is a Table Name; the Adapter Finds the Model
* **Status:** Accepted (2026-10-16). **Replaces `target_model:` with `target_table:`** in ADR-16 item 4 and ADR-19 item 2 (`schema(target_table:)`), and reverses the earlier choice to name the target by model class.
* **Context:** The core is framework agnostic (ADR-16). A model class is an ActiveRecord idea, but every database library has tables. A table name is the one name every adapter understands, so the core and the stage results name the target by its table.
* **Decision:**
  1. **The consumer names the target by its table**, for example `target_table: "users"`. The core, the stage results and the error entries use that name.
  2. **The adapter turns the table into whatever it loads through.** The ActiveRecord adapter finds the application model whose `table_name` is that table, and builds record instances from it. Validations, callbacks, enums, `belongs_to` checks and `ignored_columns` therefore always apply. If it finds no model, it stops with `active_record_model_not_found`. If several models share the table (single table inheritance), it uses the base class. There is no anonymous-model fallback: this rule belongs to the ActiveRecord adapter, and another adapter decides for itself.
  3. **`TargetSchema` names the model it was read from** (`model`: the class name), because with the ActiveRecord adapter a model always exists.
  4. **Codes that belong to one adapter carry its name as a prefix.** The core does not know them. A concept that only one adapter has, such as a model, gets a prefixed code: `active_record_model_not_found` (field `table`). A concept every adapter has, such as a missing table, keeps a plain code: `target_table_not_found` (field `table`). The prefix is the adapter's name (`active_record_`, and for example `sequel_` for a future adapter), so a consumer can tell which adapter an error came from.
* **Consequences:**
  * The core never names a model class, so a second adapter has nothing to translate.
  * With the ActiveRecord adapter, the parent-existence check at `save` (ADR-15 item 3) and the callbacks always apply, because a model always exists. A table with no model cannot be loaded by this adapter until the application defines one.
  * `strategy: auto` (ADR-17 item 8) picks `batch` when the model has no validators.
  * Affected docs (`protocols.md`, `configuration.md`, `target-access.md`, `overview.md`) replace `target_model` with `target_table` when this is applied.
  * **Decided in the build:** the ActiveRecord adapter finds the model by scanning `ActiveRecord::Base.descendants` for a non-abstract class with that `table_name`. It never loads models: the consumer does (amended 2026-10-21; the adapter first called `Rails.application.eager_load!` itself, which loaded the whole application on every schema read and the consumer's code without being asked). With single table inheritance it uses the base class; with several unrelated models on one table it uses the one whose class name comes first, and the schema names it. A table that is missing gives `target_table_not_found`, and a table with no model gives `active_record_model_not_found`, both raised as `TargetSchemaError`.
  * **Open:** the prefix rule for codes an adapter adds beyond the shared ones, and whether a table with several unrelated models should be an error instead of a choice.

### ADR-21: The Configuration File Is Found by Convention
* **Status:** Accepted (2026-10-17). **Amends ADR-09** (the file was `engine.yml`, and its path was passed to the engine) and the loading search described in `configuration.md`.
* **Context:** A path that every consumer has to pass says nothing the consumer can choose in a useful way. Tools such as RSpec and Bundler find their files by name and place, and the consumer just writes the file.
* **Decision:**
  1. **The file is `config/pipeforge.yml`**, relative to the directory the program runs in (the root of a Rails application when run from the console, a runner or a rake task). The constant is `Pipeforge::Configuration::DEFAULT_PATH`. Wherever older text says `engine.yml`, this file is meant.
  2. **A missing file is not an error.** Every setting has a default, so the engine works with no file. A file that is there but cannot be used is still an error (`config_file_not_valid_yaml`, `config_file_not_name_value_entries`, and the others). The code `config_file_not_found` is removed.
  3. **No override.** `Engine.new` takes only the source (`source_io:`); there is no `config_path:`, no environment variable and no search.
  4. **`Pipeforge::Configuration` is one module, reached from the class itself.** `Configuration.execution`, `.source`, `.recommendation` and `.path` give the settings, for example `Configuration.source.distinct_values_cap`. Reading the file and checking every value are private methods of the module; there is no separate settings class and no instance.
  5. **The settings are read once, when the gem is loaded.** `Configuration.load` takes no arguments: it reads `config/pipeforge.yml` and keeps the result, and `require "pipeforge"` calls it, so a file that cannot be used stops the application as it boots. The settings are shared by the whole process. If a later `load` fails, the settings from before stay.
  6. **Each part reads the settings it needs from `Configuration`.** The reader, the two analyzers and the chunk analyzer have no `config:` argument, and the engine builds and passes no configuration. Specs write a `config/pipeforge.yml` in a temporary project directory and call `load`; no method exists only to reset it.
* **Consequences:**
  * A consumer writes one file in a known place and passes nothing to say where it is.
  * A misspelled file name is silently ignored and the defaults are used. This is the cost of treating a missing file as the defaults.
  * One configuration per process: two engines in one process read the same settings, and a change to the file is seen only after the process restarts.
  * The parts depend on a global (`Configuration`) in place of an argument; their specs load the settings they need.
  * The file is read when the gem is required, so the working directory must be the project's at that moment.

### ADR-22: The Schema Holds Only the Columns That Can Be Given a Source Column
* **Status:** Accepted (2026-10-17). **Amends D7 and D10** in `recommendation-name-matching.md` (a column the database fills or refuses to write was listed in the facts with a status) and the `writable` and `unwritable_reason` fields of the `TargetSchema` column in ADR-16.
* **Context:** The core only needs the columns it can match and load into. Whether a column is filled by the database, ignored by the model or generated is knowledge of one adapter, and nothing in the core used the list of the others: the header result only echoed it.
* **Decision:**
  1. **The target adapter returns only the columns that can be given a source column.** The ActiveRecord adapter leaves out the primary key, the columns the model ignores, and generated columns. Timestamps stay.
  2. **`TargetColumn` loses `writable`, `unwritable_reason` and `primary_key`.** The header result loses `not_writable_target_columns`. The matcher scores every column it is given.
  3. **A column that is not in the schema cannot be mapped,** whether the engine or the consumer proposes it.
* **Consequences:**
  * A smaller schema, a smaller result and no status to explain.
  * A consumer cannot keep their old ids by mapping a source column to the primary key; that use of D10's "add it by hand" is gone, and would need a new decision.
  * A target column that looks forgotten is simply one the engine cannot load. The result no longer says which ones.
  * Another adapter decides for itself which of its columns to offer.

* **Amendment to ADR-19 (2026-10-18): the source reader checks the header.** `Source::CsvReader#headers` is the one way to get the column names: it reads the first line only, keeps the real names, and raises `source_empty`, `source_header_blank` or `source_header_duplicated` (the last two together in one `InvalidHeaderError`). The reader is part of the core, so ADR-19's rule that the core does all validation holds. The header stage and the value stage both read the header through it, so a repeated or blank column name stops the value stage as well, even for a column that is not mapped. This replaces ADR-14's rule that the value stage trusts the header stage, for the header only. A row with more cells than the header also stops the read, with `source_row_too_long` and the line (smarter_csv `missing_headers: :raise`): such a row is usually a broken file, for example an unquoted comma that shifts the cells after it, and the extra cells would otherwise be dropped without a word. A row with fewer cells is filled with empty values.


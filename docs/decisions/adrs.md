# Architecture Decision Records (ADRs)

> **Document Location:** `docs/decisions/adrs.md`  
> **Status:** ADR-01 through ADR-13. ADR-10 partially supersedes ADR-01; ADR-11 supersedes ADR-06 and ADR-08; ADR-13 partially supersedes ADR-10.  
> **Index:** [Master Documentation Index](../../README.md)

---

### ADR-01: Tripartite Architecture (Planner → Plan Builder → Runtime)
* **Status:** Accepted / Frozen. *Partially superseded by ADR-10 (mandatory review, initial-plan shape).*
* **Context:** Conflating recommendation, plan construction, and execution leads to tight coupling between heuristic analysis and streaming execution.
* **Decision:** Split planning and execution into three distinct domain responsibilities:
  1. `MigrationPlanner` (discovers, recommends, creates initial `MigrationPlan`).
  2. `MigrationPlanBuilder` (constructs/reconstructs and validates `MigrationPlan` from consumer decisions).
  3. `MigrationRuntime` (streams and executes the valid `MigrationPlan`).
  `MigrationPlan` is the domain contract.
* **Consequences:** Separates recommendation from plan validation, supports unchanged recommendations cleanly, and isolates the Runtime from consumer UI or storage formats.

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
* **Decision:** The consumer defines organizational policies once in `config/engine.yml`. All migrations inherit these defaults without requiring repetitive per-migration flags. CLI flags act as surgical overrides.
* **Consequences:** Drastically reduces invocation complexity, prevents configuration drift, and cleanly separates engine-wide policies from migration-specific input.

---

### ADR-10: Single `PlanDraft` Input, Optional Review, State-Only `MigrationPlan`
* **Status:** Accepted (2026-10-08). **Partially superseded by ADR-13 (2026-10-10):** review is again required, as an acknowledgement flag, and the draft's JSON shape changed. The rest (one input format, state-only plan, builder reads only state, `build` reports all errors) stands. **Supersedes** the "mandatory consumer review" and "Planner emits an immutable initial `MigrationPlan`" parts of ADR-01. The rest of ADR-01 (Planner recommends, Builder validates, Runtime executes) stands.
* **Context:** The draft architecture made consumer review mandatory and left the Builder's input undefined (the "consumer decisions" had no contract). The intended design is that the Planner's output is directly runnable, review and editing are optional, and the Runtime needs only *state*, never the *facts* (scores, evidence, warnings) behind it.
* **Decision:**
  1. **One input format: `PlanDraft`.** It has a required `state` section (mappings, transforms, lookups, defaults) and an optional `facts` section (scores, evidence, warnings, alternatives, keyed by mapping). The Planner produces a `PlanDraft`. A consumer may edit it, strip `facts`, hand-write one, or derive one from an existing plan (`plan.to_draft`). All are the same shape.
  2. **One output format: `MigrationPlan` (P3).** It contains state only: no scores, evidence or review flags. It is the only thing `MigrationRuntime` accepts.
  3. **`MigrationPlanBuilder` is a pure function `PlanDraft -> BuildResult` (plan or structured errors).** It reads only `state`. `facts` never influence validation or output. The Planner uses the same builder methods the public API exposes, so both authors obey identical invariants.
  4. **Review is optional and consumer-owned.** A consumer may pass the Planner's draft straight to `build` and then to the Runtime. The engine never requires, prompts for, or tracks a review step.
  5. **Planner safety without a gate.** The Planner includes in `state` only mappings at or above the configured confidence threshold; lower-confidence and hard-gated candidates appear only in `facts`. It never invents value mappings or guesses ambiguous lookups. `build` fails if a target column is `NOT NULL`, has no `default_expression`, is not auto-generated, and is not covered by the plan (a direct mapping, a relationship mapping's `target_fk_attribute`, or a plan `default_value`). Nullable columns, DB-defaulted columns, auto-generated keys and `SemanticSchema` virtual attributes are never failures.
  6. **`BuildResult` is success or errors, nothing else.** Success carries the `MigrationPlan`. Failure carries a list of errors, each with the affected column, a stable error code, and the reason it was rejected. All errors are reported at once. Errors are derived from `state` and the target schema only; the builder never reads `facts`, not even to suggest candidates (the consumer already has them in the draft's `facts`).
* **Required properties (testable):** determinism (same state, same plan); idempotence (`build(plan.to_draft) == plan`); fact-independence (stripping `facts` never changes the built plan).
* **Consequences:**
  * Removes the undefined "consumer decisions" input; the draft is the review surface.
  * Keeps P3 free of scoring and UI concerns; the Runtime stays unaware of the Planner.
  * Docs that still say "mandatory review" (CLAUDE.md principle 3, `overview.md` §1.3/§3.2, `mvp-scope.md` §1.4 and DoD item 5, README tagline, `engine.yml` `safety.confirm_plan_execution`) were updated to match on 2026-10-08; see `docs/planning/roadmap-and-phases.md` Phase 1 for the remaining schema work.
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
* **Retained from earlier ADRs:** ADR-01 (as amended by ADR-10), ADR-02 through ADR-05, ADR-07, ADR-09, and the 4-state validation taxonomy.
* **Consequences:**
  * Much less consumer effort; Rails users configure behavior and run.
  * The engine is no longer framework-independent; non-Rails, non-ActiveRecord consumers are out of scope.
  * Open items (supported ActiveRecord/Ruby versions, standalone use outside Rails, MySQL, resume after partial load) are tracked in `docs/planning/roadmap-and-phases.md`.

---

### ADR-12: Recommendations Are Ranked by Column Names Only; Values Feed Value Mappings
* **Status:** Accepted (2026-10-10). Details and reasoning: `docs/architecture/recommendation-name-matching.md` (D1 to D14, D16).
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
* **Status:** Accepted (2026-10-10). **Partially supersedes ADR-10** (optional review; draft shape).
* **Context:** With ranking by names only and weak candidates visible but unmapped, a recommended plan can still be wrong, and review is the safeguard. A conditional gate based on confidence tiers was judged more complex and unreliable.
* **Decision:**
  1. **The Planner returns a JSON draft** with three parts: `findings` (visibility: source columns with non-empty/empty counts and distinct values; target columns with type, constraints, enums, and for reference columns the parent table and its columns), `draft_plan.column_mapping` (one entry per writable target column, keyed by target column name, each with `source_column`, `value_mapping`, optional `lookup`, and the facts `confidence`, `reason`, `type_compatibility`), and `acknowledgement_flag`.
  2. **`MigrationPlanBuilder` accepts a draft only if `acknowledgement_flag` is `true`.** Missing or `false` means `build` fails. No thresholds or tiers are involved. Resetting the flag after later edits is the consumer's responsibility; the engine never resets it.
  3. **The Builder reads only `source_column`, `value_mapping`, `lookup` and `acknowledgement_flag`.** Everything else (`findings`, `confidence`, `reason`, `type_compatibility`) is a fact and is ignored, even if edited or stale.
  4. **Build errors** include: acknowledgement missing; a required target column (`NOT NULL`, no default, not filled by the database) with no `source_column`; a `source_column` or `lookup` column that does not exist. All errors are returned at once.
  5. "No changes" remains valid: the consumer sets the flag without editing anything.
* **Consequences:** Review is mandatory again, but as a plain flag and not a workflow. `MigrationPlan` (P3) stays state-only and the Runtime never sees facts. CLAUDE.md principles 2 and 3, `overview.md`, `protocols.md`, `mvp-scope.md`, the README and the test strategy were updated to match.

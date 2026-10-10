# Recommendation: Name Matching Decisions

> **Document Location:** `docs/architecture/recommendation-name-matching.md`
> **Status:** Decision record (D1 to D16, 2026-10-09 to 2026-10-10), applied to the other docs on 2026-10-10 (section 3). Small details remain open (section 4).
> **Index:** [Master Documentation Index](../../README.md)

---

## 1. Goal and scope

For each **target column**, recommend **at most one source column**, deterministically and with an explanation a person can read. Source-column names are the **highest-priority signal**; every other signal only adjusts the result.

Scope of this record: **ordinary columns**. Reference columns (`company_id`, foreign keys, lookups) are deferred to their own topic.

Available inputs: source column names and observed values; target column names, types, constraints (`NOT NULL`, `UNIQUE`, defaults) and references.

## 2. Decisions and why

### D1. Tokenization
Split a column name into lowercase tokens:
- split on spaces, `_`, `-`, `.` and other non-alphanumerics;
- split camelCase, digit boundaries and acronym runs (`HTTPServer` -> `http`, `server`; `address2` -> `address`, `2`);
- singularize tokens with ActiveSupport (`companies` -> `company`);
- strip the table-name prefix from target columns (`users.user_email` -> `email`);
- no stop words for now.

**Why.** This is how identifier-splitting tools work and how schema-matching systems normalize names. Both sides must use the same process or tokens will not line up. Stop words (`no`, `of`, `number`) are easy to get wrong, so they are left out until a real need appears.
**Gap closed after research:** the first draft missed acronym runs.

### D2. Token-pair score: full prefix only
For a target token `t` and a source token `s`: if the shorter is a **full prefix** of the longer, score = `length(shorter) / length(longer)`; otherwise 0.

| Target | Source | Score | Reason |
|---|---|---|---|
| first | first | 100% | identical |
| first | f | 20% | 1 / 5 |
| address | addr | 57% | 4 / 7 |
| number | num | 50% | 3 / 6 |
| name | names | 100% | identical after singularizing |
| name | namesake | 50% | 4 / 8, extra letters penalized |
| name | username | 0% | not a prefix |
| phone | photo | 0% | only `pho` shared |
| quantity | qty | 0% | not a prefix; needs a synonym (D3) |

**Why.** It reproduces the original example (`First` vs `F` = 20%) exactly. Measuring against the *longer* token (not only the target token) stops `name` from scoring 100% against `namesake`. Requiring a full prefix stops mid-word accidents (`name` inside `username`, `id` inside `video`).
**Considered and not chosen for v1:** suffix matching (would catch `phone` inside `telephone`) and character n-gram / Jaro-Winkler fuzzy scores (catch typos and compounds). Research shows strong systems combine several measures, but fuzzy scores are harder to explain. Prefix-only was chosen for explainability; revisit if real data needs more.

### D3. Abbreviations and synonyms are configured by the customer
No built-in abbreviation dictionary. The customer declares synonyms in `engine.yml` at two levels: global token synonyms (`qty` -> `quantity`) and optional per-target-column aliases (`users.first_name: [fname, given name]`).

**Why.** Abbreviations vary by business and data source. The open-source importers surveyed (react-spreadsheet-import `alternateMatches`, tableflow `suggested_mappings`, Dromo aliases) all use alias lists declared by whoever owns the target fields, and no open-source library ships a general column-name synonym dictionary. Research on automatic abbreviation expansion mines large code bases and is neither small nor deterministic enough for this engine.
**Consequence.** Out of the box `qty` will not match `quantity`. The draft's facts must list unmatched source and target columns so the customer can see what to add, then re-plan. One-off cases can be fixed by editing the draft.

### D4. Aggregation: symmetric score
Name score = `2 x (sum of best token-pair scores) / (target tokens + source tokens)`. Each source token can be used for at most one target token.

| Target | Source | Score |
|---|---|---|
| First Name | First Name | 100% |
| First Name | F Name | 60% |
| First Name | User Name | 50% |
| Name | Name | 100% |
| Name | User Name | 67% |
| Name | Company Name | 67% |

**Why.** A sum over the target's tokens only means extra source tokens are free, so `Name`, `User Name` and `Company Name` all tie at 100 for target `Name`. The symmetric form keeps the original ranking (`First Name` > `F Name` > `User Name`), always stays between 0 and 100%, and is comparable across targets.

### D5. Ties and conflicts: fixed tie-break order, greedy one-to-one
Tie-break order: (1) higher score; (2) more exactly matched tokens; (3) fewer unmatched source tokens; (4) source column position in the file; (5) target column position in the table definition.
Assignment: sort all eligible pairs by that order and assign best-first; each source and each target is used at most once. Losing candidates appear in the facts as alternatives.

**Why.** A plain `Name` source scores 67% against `first_name`, `last_name` and `full_name`, so independent per-target ranking would give one source to all three. Greedy best-first is deterministic and easy to explain ("the highest score claimed it first"). Optimal assignment (Hungarian) can score higher in rare cases but is harder to explain, and allowing reuse risks mapping one column twice by default.

### D6. Ranking depends only on the column-name match score
Which source column is recommended for a target column is decided **only** by the name match score (D1 to D5, D9). Observed values, types and constraints never remove a pair and never change the ranking. Their only use is to support value mappings and cheap hints (see D11); whether the data will load is answered by the dry run, not by the Planner.

**Why.** It keeps the ranking simple, predictable and fully explainable: the customer can reproduce any recommendation from the column names alone, and nothing is hidden in an adjustment. A single dirty value in a million (for example `twenty` in an `Age` column) must not remove or demote the obviously right column. The earlier idea (hard gates plus capped adjustments of about +-15 points from types and values) and the old weighted formula (0.45 name, 0.25 type, 0.20 values, 0.10 structure) are both dropped.
**Consequences accepted.**
- When two pairs tie on names (`Name` against `first_name` and `last_name`), the data cannot break the tie; only the fixed tie-break order does (D5).
- A pair with a clear data mismatch (a column of emails into a whole-number column) can still be recommended if the names match. The facts must flag it prominently. At run time those records fail individually and go to the dead-letter log; nothing loads silently wrong.

### D7. Every target column is visible in the facts
The draft's facts contain one row per target column: best candidate, score, reasons, status (matched / weak guess / none), plus the lists of unmatched source and target columns.

**Why.** A target column with no recommendation looks as if the engine forgot it. Visibility lives in the facts and does not depend on whether the candidate is in the plan state.
**Open:** whether weak candidates (below the configurable inclusion threshold, default 0.55) also go into the state (section 4).

### D8. Acknowledgement flag is required to build
`PlanDraft.state` carries an acknowledgement flag. The Planner emits it as `false`. `MigrationPlanBuilder` accepts a draft **only if the flag is `true`**; if it is missing or `false`, `build` fails with an error (suggested code `ACKNOWLEDGEMENT_MISSING`). The flag is the single source of truth. There is no threshold logic. When to set or reset the flag after edits is the consumer's responsibility; the engine does not reset it automatically.

**Why.** Review is the safeguard against weak or wrong recommendations, and a plain required flag is simple and reliable. A conditional gate based on confidence tiers was rejected as more complex and because a lowered inclusion threshold could remove the gate exactly when it is most needed. "No changes" remains valid: the consumer sets the flag without editing anything.
**Trade-off accepted.** A stale acknowledgement after a later edit is the consumer's responsibility, not the engine's.

### D9. Word order: small fixed penalty for reordering
Words are paired anywhere (as in D4), but if the matched words appear in a different left-to-right order on the two sides, the match score loses a fixed amount, applied once per pair of columns (proposed: 10 points; the exact value is open and could be configurable).

| Target | Source | Without penalty | With penalty |
|---|---|---|---|
| First Name | First Name | 100% | 100% |
| First Name | Name First | 100% | 90% |
| Birth Date | Date of Birth | 80% | 70% |

**Why.** The same meaning is often written in a different order (`Date of Birth` / `Birth Date`, `Mobile Phone` / `Phone Mobile`), so ignoring order would be forgiving but would also let a reordered name tie with the exact one. Strict order (matched words must stay in order or earn nothing) was rejected because it scores harmless reorderings far too low (`Birth Date` against `Date of Birth` would drop to 40%) and could push the right column under the inclusion threshold. A small penalty keeps reordered names matching well while the same-order column always wins a tie.
**Open:** the penalty size (10 points proposed) and whether it is configurable in `engine.yml`.

### D10. Columns the database fills or refuses to write are never recommended
Target columns that are **filled by the database** (auto-numbered keys, identity columns) or **not writable** (generated, virtual, read-only columns) never receive a source column. The facts show them with a status such as "filled by the database" or "not writable", so they are still visible (D7).

**Why.** It is the safest default: a generated column rejects every row, and an auto-numbered key can clash with ids the database hands out later. This is a structural property of the target column, not a judgement about the data, so it does not conflict with D6.
**Consequence accepted.** A customer who wants to keep their old ids must add that mapping by hand when editing the draft. The Builder therefore must not refuse a deliberate mapping to an auto-numbered key; it is only never *recommended*.

### D11. The value scan exists for value mappings; loadability comes from the dry run
The scan lists the **distinct values** of each source column (with how often each occurs, up to a cap) so the customer can configure **value mappings** (for example `A` -> `active`, `Y` -> `true`). A cheap type hint (for example "all values look like whole numbers") may be added if it costs almost nothing in the same pass; it is informational only.

Whether the data will actually load is answered by the **dry run** of the final plan (with all value mappings and transforms applied), not by the Planner.

**Why.** At planning time the customer has not yet configured value mappings or transforms, so a "loadable / doubtful" percentage on raw values can mislead: `twenty` looks like a failure now, but a mapping added later may fix it. The dry run already exists in the design and is the only truthful answer. This replaces the earlier "loadable / doubtful" facts idea.
**Open:** the cap on distinct values per column, what is shown next to them (counts, the target column's allowed values), and how value mappings are suggested (section 4).

### D12. Distinct values: capped at 1,000 per column, configurable
For each source column the scan keeps up to **1,000 distinct values**, each with how often it appears. Beyond the cap the column is marked "too many distinct values to list". The cap is a setting in `engine.yml`.

**Why.** Value mappings only matter for columns with few distinct values (statuses, countries, categories); 1,000 covers every realistic code list. Listing every distinct email or id would grow memory with the data and break the bounded-memory promise (ADR-02). A smaller cap (100) would cut off country or category lists; no cap is not bounded.

### D13. Value-mapping suggestions: safe ones only
The Planner suggests a value mapping automatically only when it is certain:
- a source value equals an **allowed value** of the target column once case, spaces and punctuation are ignored (`INACTIVE` -> `inactive`); allowed values come from the model (for example an `enum` declaration), and a column without allowed values needs no mapping;
- the source values are words from a small **fixed boolean list** (`Y`, `yes`, `true`, `t`, `1` -> true; `N`, `no`, `false`, `f`, `0` -> false) and the target column is a yes/no column.

Everything else is listed as **unmapped** next to the target's allowed values, for the customer to map. The Planner never guesses (no "`A` starts like `active`").

**Why.** A wrong guess can slip through if nobody checks, and a wrong value mapping corrupts data silently, while an unmapped value is visible and the dry run shows what happens to it. The boolean list is small, standard and fixed, so it does not go against D3 (no built-in vocabulary): it is part of reading yes/no values, not a business vocabulary.
**Open:** exactly which words are in the boolean list, and how mappings are written in the draft.

### D14. Draft layout: mappings with confidence and their own facts; doubtful candidates listed separately
The draft is a list of **mappings** (`target column <- source column`). Each mapping shows its **confidence** (the name match score) and, directly underneath, its **facts**, such as the **type fit** (the share of the source column's values that fit the target column's type, measured on the raw values before any value mappings or transforms).

- **In the plan (state):** mappings at or above the inclusion threshold (default 55%, configurable in `engine.yml`), the "okay-ish" ones. These will run once the draft is acknowledged (D8).
- **Doubtful (facts only):** candidates below the threshold. They are shown with their facts but are not in the state unless the customer adopts one with an explicit call. Pairs with a 0% name score are not candidates.
- **Required target columns with no mapping** (`NOT NULL`, no default, not filled by the database) make `build` fail with an error naming the column, so the Runtime never receives such a plan.

```text
IN THE PLAN (will run)
  age   <- Age        confidence 100%
      facts: type fit 99.9999% whole numbers (1 value is not)
DOUBTFUL (not in the plan unless adopted)
  phone <- col3       confidence 0%
NOT MAPPED, REQUIRED -> build fails until fixed
  last_name (NOT NULL, no default)
```

**Why.** It gives the customer one place to read each recommendation: the mapping, how confident the name match is, and what the data looks like, with every target column visible (D7). Only reasonably confident mappings run by default, and the acknowledgement flag (D8) means someone has looked at the whole draft. Type fit is included because it is cheap to compute in the same pass as the distinct values (D11); the real answer on whether data will load still comes from the dry run.
**Open:** the exact threshold default (55% proposed), whether it applies to the name score only (yes, per D6), and the name of the call that adopts a doubtful candidate.

### D15. The Planner's JSON response (the draft)
The Planner returns one JSON document (no UI is involved). The consumer edits it (remap a column, add value mappings) and sends it back to the Builder.

```json
{
  "findings": {
    "source_columns": [
      { "name": "Status", "non_empty": 1000000, "empty": 0,
        "distinct_values": { "capped": false,
          "values": [ { "value": "Active", "count": 600000 }, { "value": "A", "count": 100000 } ] } }
    ],
    "target_columns": [
      { "name": "status", "type": "integer",
        "constraints": { "nullable": false, "unique": false },
        "enums": { "active": 1, "inactive": 2, "suspended": 3 } }
    ]
  },
  "draft_plan": {
    "column_mapping": {
      "status": {
        "source_column": "Status",
        "value_mapping": { "Active": "active", "INACTIVE": "inactive" },
        "confidence": 100,
        "reason": "Status = status (all words identical)",
        "type_compatibility": { "fits": 1000000, "total": 1000000 }
      },
      "phone": {
        "source_column": null,
        "confidence": 0,
        "reason": "No word of any source column name fits; best remaining candidate col3 (0%)"
      }
    }
  },
  "acknowledgement_flag": false
}
```

- **`findings`** is for visibility only: what the source and the target contain. Source columns carry `non_empty` and `empty` counts and their distinct values (D12). Target columns carry type, constraints (nullable, unique, primary key, default, maximum length, filled by the database) and enums.
- **`draft_plan.column_mapping`** has one entry per **writable target column**, keyed by target column name. So each target column has at most one source column by construction. A mapped entry has a `source_column`; an unmapped entry has `source_column: null` and shows its best candidate and confidence as facts (the doubtful candidates of D14). Database-filled and not-writable columns are not listed as mappable (D10).
- **Edits:** the consumer remaps by changing `source_column`, adds `value_mapping` entries, and sets `acknowledgement_flag` to `true`.
- **What the Builder reads (state):** only `source_column` and `value_mapping` of each entry, and `acknowledgement_flag`. Everything else (`confidence`, `reason`, `type_compatibility`, all of `findings`) is a fact and is ignored, even if edited or stale.
- **Build errors:** the acknowledgement flag not `true`; a required target column (`NOT NULL`, no default, not filled by the database) whose `source_column` is `null`; a `source_column` that does not exist in the file.

**Why.** One document with a clear split between what the consumer can see (`findings`), what will run (`draft_plan`), and the confirmation (`acknowledgement_flag`). Distinct values sit once per source column so they stay correct after a remap, and source columns that are not mapped yet still show theirs. Listing every writable target column keeps all of them visible (D7) and turns "map this column" into filling one field. `type_compatibility` is two numbers so it is easy to read from code; it is measured on raw values before value mappings (D11).
**Open:** the exact `constraints` fields, the wording of `reason`, and `value_mapping` handling for values that map to several targets or to null.

### D16. Reference columns: ranked by name like other columns; the customer chooses the lookup column
A **reference column** is a target column that points to a row in another (parent) table, i.e. a real foreign key such as `users.company_id`.

1. **Which source column feeds it** is ranked by name with the same rules as every other column (D1 to D5, D9, D14), with one adjustment: for reference columns only, a trailing `id` is a **reference marker** and is ignored. It is dropped from the target name and from each source name before matching. Ordinary columns keep their `id` (`external_id`).
2. **The lookup column** (the column of the parent table used to find the row, for example `companies.code`) is **chosen by the customer**. The Planner never picks it.
3. **In the JSON (extends D15):**
   - `findings.target_columns` shows, for each reference column, its parent table and the parent's columns with a flag for unique ones, so the customer can choose.
   - A mapping entry may carry `"lookup": { "table": "companies", "column": "code" }`. The table comes from the foreign key; the customer sets the column.
   - **With a `lookup`:** each source value is looked up in the parent table (a relationship mapping, resolved at run time).
   - **Without a `lookup`:** the source values are used as the ids directly (a direct mapping, for files that already hold the ids).

| `company_id` against | Keep `id` as a word | `id` as a reference marker |
|---|---|---|
| Company Id | 100% | 100% |
| Company | 67% | 100% |
| Company Code | 50% | 67% |
| Company Name | 50% | 67% |

**Why.** The names alone cannot say whether a source column holds ids (`42`), codes (`ACME`) or names (`Acme Inc`), and the lookup column is a business decision where a wrong guess silently attaches rows to the wrong parent. Treating `id` as an ordinary word would favour the id-holding column (`Company Id` 100% versus `Company Code` 50%), which is an unstated assumption about the values; the marker compares on the entity word (`company`) alone and stays neutral. Choosing the lookup column stays with the customer, consistent with D6 (no guessing).
**Open:**
- optional hint fact on the mapping: "all values are whole numbers" (suggests ids), from the cheap type check;
- warning when the chosen lookup column is not unique (lookups may match more than one parent row);
- `build` error when the lookup column does not exist in the parent table;
- a source column named only `Id` becomes empty after the marker is dropped (scores 0 for reference columns);
- unsupported cases: composite foreign keys, polymorphic references.

## 3. Where these decisions were applied (2026-10-10)
- **ADR-12** (ranking by names only; values feed value mappings) and **ADR-13** (acknowledgement flag; JSON draft) in `docs/decisions/adrs.md`; ADR-10 marked partially superseded.
- **protocols.md:** P1 and P2 rewritten, the draft JSON, `BuildResult` codes and P3.
- **recommendation-and-validation.md:** recommendation sections rewritten (name matching, draft contents, value mappings).
- **configuration.md:** `inclusion_threshold`, `reorder_penalty`, `distinct_values_cap`, `synonyms`, `column_aliases`.
- **overview.md, mvp-scope.md, README.md** (tracked, on the branch `docs-apply-name-matching-decisions`), **testing-strategy.md** (required name-matching scenarios), **roadmap-and-phases.md**, **CLAUDE.md** (principles 2 and 3, flow, doc table).
- **Research sources:** [Cupid](https://www.microsoft.com/en-us/research/publication/generic-schema-matching-with-cupid/), [COMA](https://old.dbs.uni-leipzig.de/file/vldb01.pdf), [Valentine benchmark](https://arxiv.org/pdf/2010.07386), [XML matchers survey](https://arxiv.org/pdf/1407.2845), [react-spreadsheet-import](https://docsearch.algolia.com/mcp/docs/repo/ugnissoftware/react-spreadsheet-import), [tableflow csv-import](https://docsearch.algolia.com/mcp/docs/repo/tableflowhq/csv-import), [Dromo mapping guide](https://dromo.io/blog/data-mapping-best-practices-csv-imports), [AMAP](https://sites.udel.edu/se-research/2008/05/05/amap-automatically-mining-abbreviation-expansions-in-programs/).

## 4. Open items for the next brainstorm
1. ~~Targets that cannot be written~~ Decided: D10 (never recommended; shown in facts).
2. ~~Distinct-value listing~~ Decided: D12 (cap 1,000, configurable). Still open: what is shown next to each value besides the count (for example the target column's allowed values).
3. ~~Value-mapping suggestions~~ Decided: D13 (safe ones only). Still open: the boolean word list and the draft syntax for mappings.
4. ~~Reference columns~~ Decided: D16. Still open: the hint fact, non-unique lookup warning, missing-lookup-column error, source column named only `Id`, composite and polymorphic references.
5. ~~Name required?~~ and 6. ~~Weak candidates in state?~~ Decided: D14 (below-threshold candidates are doubtful facts; 0% pairs are not candidates).
7. **Penalty size for reordered words** (D9) and whether it is configurable.
8. ~~Explanation format~~ Mostly decided: D15 (JSON shape). Still open: exact constraint fields, reason wording, value-mapping edge cases (null, one value to several targets).

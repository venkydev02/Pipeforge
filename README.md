# Pipeforge

Pipeforge tells you what a CSV migration will do before it writes a single row. Give it a file and the name of a model in your application. It reads both, returns the answers as plain data, and then loads the rows through your model, as a dry run first and for real once you are happy.

It is a relational data migration library that you drive. It is not a service that runs by itself and not a web app. The core knows no framework and no database library; an adapter connects it to one ORM. The first adapter is for ActiveRecord, and it is the one this README uses.

Version 0.0.0. The design is settled and the three steps work end to end, but nothing is published to RubyGems yet.

## The problem

A customer sends `users.csv`, and it has to be in your `users` table by Friday. Before you write any code, somebody has to answer a few questions.

Which column is which? Is `Company` the `company_id`? Which values will not fit, for example a 34-character status in a column that holds 20? Which cells hold a name where the table stores an id? Which rows will fail, and why?

Usually a developer finds out by reading the schema, reading the model, and running a script until it stops complaining. I built Pipeforge because those answers end up in one developer's head, while the person who understands the data never sees them. Pipeforge reads the file and the model's metadata and hands the answers back as data, so a screen can show them to the right person and nobody has to open the database to look.

## Words used below

Target model: the model class the rows are loaded through, given by name, for example `"User"`. Its table is the target table. What counts as a model is the adapter's decision; for the ActiveRecord adapter it is an ActiveRecord class.

Mapped columns: a plain Hash you build, keyed by target column, that says which source column fills it, for example `{"age" => {source_column_name: "Age"}}`. The source is the CSV file, and a source column is one of its header names.

Distinct values: each different value found in a column, with how many times it appears.

Value mapping: an optional part of one entry that rewrites values from the file before they load, for example `{"Initech" => "3"}`.

Dry run: the same checks and writes as a real run, inside one transaction that is rolled back at the end.

Failed row: a row that did not load, with its row number, the attributes its record held as plain JSON values, and each mistake with a stable `code`.

## What it answers

| Your question | The call | What comes back |
|---|---|---|
| Which column is which? | `analyze_headers` | a match for each target column with a score from 0 to 100, the file columns that matched nothing, and for each target column its type, whether it is required, its default, its enum labels and the table a foreign key points to |
| Which values will not fit? | `analyze_column_values` | for each mapped column, how many cells are empty, how many values fit, and the values that do not |
| Which values need translating? | `analyze_column_values` | every distinct value of the file with its count, ready to become a value mapping; measure again after an edit and each value shows what it would load as |
| Will each row load, in this model and this database? | `run` | every failed row with the layer that refused it (see the three layers below) |
| What would a run do? | `run(mode: :dry_run)` | the same failed rows and totals as a real run, with the target left unchanged |

Matching uses names only, with no language model. The same names and settings always give the same scores, so you can explain every match.

## A migration in four steps

The example below uses a `User` model that belongs to a `Company`, and a CSV file `users.csv` with a header row. Use your own model and file. The ActiveRecord adapter finds the model you name among the models that are already loaded; it never loads one itself, so load your models first (a Rails application has loaded them already). A name that no loaded model has stops with `active_record_model_not_found`.

### 1. Match the columns

```ruby
engine = Pipeforge::Engine.new(
  source_io: File.open("users.csv"),
  target_model_name: "User"
)
header_analysis = engine.analyze_headers
header_analysis.matches.each { |match| puts "#{match[:target_column_name]} <- #{match[:source_column_name]} (#{match[:score]})" }
# email <- Email (100.0)
# first_name <- First Name (100.0)
# ...
# company_id <- Company (66.67)

header_analysis.unmatched_source_column_names   # => []
header_analysis.unmatched_target_columns   # created_at and updated_at: the model fills them
```

`Company` against `company_id` scores 66.67 because one of the two words in `company_id` matches. The primary key, columns the model ignores and generated columns are not offered at all. Pipeforge cannot load into them, so it does not pretend it can.

### 2. Measure the values

You build `mapped_columns` yourself, from the matches or from your own knowledge. Every required column needs an entry: a NOT NULL column with no default in the table or the model.

```ruby
mapped_columns = {
  "email" => {source_column_name: "Email"},
  "first_name" => {source_column_name: "First Name"},
  "last_name" => {source_column_name: "Last Name"},
  "company_id" => {source_column_name: "Company"},
  "age" => {source_column_name: "Age"},
  "balance" => {source_column_name: "Balance"},
  "status" => {source_column_name: "Status"},
  "active" => {source_column_name: "Active"}
}
value_analysis = engine.analyze_column_values(mapped_columns: mapped_columns)

value_analysis.column_summaries["status"].distinct_values.compatible_count     # => 4
value_analysis.column_summaries["status"].distinct_values.incompatible_count   # => 1
too_long = value_analysis.column_summaries["status"].distinct_values.incompatible.first
too_long.value    # => "this status is far too long to fit"
too_long.count    # => 1
too_long.reason   # => :value_too_long

value_analysis.column_summaries["company_id"].distinct_values.compatible.map { |listed| [listed.value, listed.casted_to] }
# => [["1", 1], ["2", 2], ["Initech", 0], ["4", 4]]
```

Look at `Initech`. It sits in a column of ids, and its `casted_to` of 0 says what the text is cast to (every listed value has `casted_to`): the cast of the ActiveRecord model reads text that is not a number as 0, so the value counts as fitting and would load as company 0. The same goes for `forty` in an age column. Call this the cast trap. Pipeforge follows the model's cast on purpose, because a dry run has to report what a real run does. Compare `casted_to` with `value` before you trust a count.

### 3. Fix values with a value mapping

```ruby
mapped_columns["company_id"][:value_mapping] = {"Initech" => "3"}
```

The keys are texts as they appear in the file. A value that maps to `nil` or to an empty text is loaded as empty. The file is read again on every call, so you can edit a mapping and measure again. Pipeforge never looks up a parent row by name; you decide that `Initech` is company 3, with the list of distinct values in front of you. Measure again and the list still shows `Initech`, the text of the file, now with `mapped_value` `"3"` (what it would load as) and `casted_to` 3. A `mapped_value` keeps the shape you gave it: a number, `false`, or a Hash for a json column. A text mapped into a json column is read as JSON, so to load the JSON string `unknown` write `"\"unknown\""`. `mapping_applied` says whether your mapping had an entry for the text: a value that does not fit and has `mapping_applied` false still needs a mapping, and one with it true has a mapping that does not fit.

### 4. Dry run, then run

```ruby
totals = engine.run(mode: :dry_run, mapped_columns: mapped_columns) do |chunk_result|
  chunk_result.failed_rows.each do |failed_row|
    puts "row #{failed_row.row_number}: #{failed_row.errors.map { |error| error[:code] }.inspect}"
  end
end
# row 4: [:value_too_long]
# row 5: [:value_missing]

totals
# => #<data Pipeforge::RunProcessor::RunResult processed_rows_count=5, valid_rows_count=3, failed_rows_count=2>

User.count   # => 10, unchanged
```

Change the mode to `:run` and each valid row is written in its own transaction and kept. A row the database refuses becomes a failed row and the run goes on. The totals match the dry run, and `users` ends with 13 rows here.

The file is read in chunks (2000 rows by default), and each chunk's result goes to your block as soon as it is done. Pipeforge writes no report file and keeps one chunk in memory; storing the failed rows is your decision. Pass `offset:` to skip rows already handled: the `row_number` of the last row of an earlier run is where the next one continues. The block of a dry run runs inside the transaction that is rolled back, so it must not write to the target database.

Before it reads a single row, `run` checks your mapping against the file and the schema: a mapped column that is not in the file, a target column that cannot be loaded, a required column with no source. All of them come back in one error, so you fix them in one round.

## The three layers

Every row goes through three checks, and the report says which one refused it.

| Origin | Who looks | What it catches | Example codes |
|---|---|---|---|
| `schema` | Pipeforge, from the table and the model's enum declarations | an empty value in a NOT NULL column, a string longer than its column, an integer outside its size, a decimal with too many digits, an enum label that does not exist | `value_missing`, `value_too_long`, `value_out_of_range`, `value_not_allowed` |
| `model` | your model's validations and callbacks | whatever your validators say; parents are loaded once for each chunk, not once for each row | whatever your validators report |
| `database` | the database, when it refuses the write | a duplicate in a unique index, a parent row that does not exist | `value_not_unique`, `parent_missing` |

The first layer matters most when the model says nothing. `User` has no validations at all, and the dry run above still refused the 34-character status, because the table says 20. Without that layer nothing would stop it. PostgreSQL would refuse the row too, but only when it is written.

## Behind a screen

Pipeforge never prompts and never draws anything; the review between the steps is yours. What it gives you is the data for that review. The header result and the value result convert to plain hashes with `to_h`, so they go straight to JSON. This is one match from `analyze_headers`, with the less useful metadata fields left out:

```json
{
  "target_column_name": "company_id",
  "source_column_name": "Company",
  "score": 66.67,
  "tied_source_column_names": [],
  "metadata": {
    "type": "integer",
    "required": true,
    "enum_labels": null,
    "foreign_key": {"association_name": "company", "parent_table_name": "companies"}
  }
}
```

A mapping screen can mark `company_id` as required, show that it points to `companies`, and list the other source columns that scored the same (`tied_source_column_names`), without anyone querying the database. This is one column from `analyze_column_values`, which a value-mapping screen is built on:

```json
{
  "source_column_name": "Status",
  "position": 6,
  "empty": 0,
  "distinct_values": {
    "compatible_count": 4,
    "compatible": [
      {"value": "active", "count": 2, "mapping_applied": false, "mapped_value": "active", "casted_to": "active"},
      {"value": "inactive", "count": 1, "mapping_applied": false, "mapped_value": "inactive", "casted_to": "inactive"},
      {"value": "suspended", "count": 1, "mapping_applied": false, "mapped_value": "suspended", "casted_to": "suspended"}
    ],
    "incompatible_count": 1,
    "incompatible": [
      {
        "value": "this status is far too long to fit",
        "count": 1,
        "mapping_applied": false,
        "mapped_value": "this status is far too long to fit",
        "casted_to": "this status is far too long to fit",
        "reason": "value_too_long"
      }
    ]
  },
  "value_mapping": {}
}
```

And one failed row from a run, with the attributes the record held (the columns you mapped, in the order of your mapping, cast to their types, as JSON values), never the raw line:

```json
{
  "row_number": 4,
  "attributes": {"email": "noah.fox@example.com", "company_id": 4, "status": "this status is far too long to fit"},
  "errors": [
    {
      "origin": "schema",
      "code": "value_too_long",
      "message": "status: the value has 34 characters, more than the 20 allowed",
      "target_column_name": "status"
    }
  ]
}
```

Write your screens against the `code`, never against the message text. The codes are stable; the wording is not.

## What it costs

Each choice buys something and costs something. These are the ones that will matter to you.

| Choice | What you get | What it costs |
|---|---|---|
| Match by names only | the same names always give the same scores, and every match can be explained | synonyms and abbreviations are missed: `Mail`, `Fname`, `Surname` and `Addr` all stayed unmatched against `User`, so a person picks them on the mapping screen |
| Follow the model's cast | a dry run reports what a real run does | the cast trap: text that is not a number loads as 0, so you read `casted_to` |
| Load one row at a time | exact row numbers, and a refused row never takes a batch down with it | slower than batch loading, which is planned and not built |
| Keep every distinct value | complete lists to build value mappings from | memory grows with the number of distinct values, not with rows; a free-text column with a million different values is the costly case. `run` holds one chunk |
| Never look up a parent by name | no silent wrong guess | you write the value mapping that turns names into ids |

## What it will not do

Each migration targets one model and inserts rows; it does not update or upsert. The source is CSV only. Keys are single-column: a composite foreign key is not described as a foreign key. The primary key is left to the database, so you cannot keep your old ids by mapping them. PostgreSQL array columns and MySQL are not supported.

The header and value stages never read existing rows of the target. Only the loader writes, and your model's validations read the parent rows and the values they check. And nothing in Pipeforge uses a language model.

## Install

The gem is `pipeforge-activerecord`, the ActiveRecord adapter. It already contains the core (the part with no database library), so there is one gem to add. It needs Ruby 3.3 or later and ActiveRecord 8.0 or later (below 9); ActiveRecord does not require Rails. An adapter for another ORM would be another gem that carries the same core; none exists yet. Until the first release, take it from the repository:

```ruby
gem "pipeforge-activerecord", github: "venkydev02/Pipeforge"
```

Then `require "pipeforge-activerecord"`. The first release targets PostgreSQL. Credentials stay in your application's own database configuration (ActiveRecord's, for this adapter); Pipeforge never asks for them.

## Settings

Behaviour that stays the same across migrations lives in `config/pipeforge.yml`, read once when the gem is required. The file is optional; every setting has a default, and a setting you leave out keeps it.

```yaml
execution:
  chunk_size: 2000          # rows read, checked and given to your block at a time
recommendation:
  inclusion_threshold: 55   # the lowest score (a whole number, 1 or more) a pair needs to count as a match
  reorder_penalty: 10       # points taken off (0 to 100) when matched words come in a different order
```

A file in the wrong place is ignored. A file in the right place that is not valid YAML, or that holds an unknown setting or a value out of range, stops the application at boot with one `ArgumentError` that lists every mistake. Per-call input (the mapped columns, the mode, `offset:`, and a `chunk_size:` that overrides the setting) goes to the call, not to the file.

## Errors

Two kinds, handled differently.

A mistake in your data (the mapped columns, the source file, the target) raises a `Pipeforge::Error` subclass. It answers `codes`, and `errors` gives one entry for each mistake with a `code`, a `message` and the fields that locate it. Every mistake is listed together. `InvalidMappedColumnsError` covers the mapping (`mapped_column_not_in_file`, `required_column_unmapped`, `target_column_not_in_schema`); `TargetSchemaError` covers a missing model or table; the `Source::` errors cover an empty file, a blank or repeated header name, and a row that cannot be parsed.

A mistake in the call itself (a mode that is not `:dry_run` or `:run`, a negative `offset:`) or in `pipeforge.yml` is a plain `ArgumentError` with the sentence in its message and no code.

## For reviewers

If you are here to judge the work and not to use it, these are the things worth checking.

Each step hands over a value object, not a shared Hash: `HeaderAnalysis`, `ColumnValueAnalyzer::Result`, `RunResult`. The steps do not depend on each other's output, so `run` works without the other two. The core has no database library; the ActiveRecord adapter is the only code that names ActiveRecord, and a second adapter would be a second gem that carries the same core. Analysis reads only the source and metadata, never target rows.

Every decision is in `docs/decisions/adrs.md` with its context, its consequences and what it replaced, including the ones that reversed an earlier choice. The target is named by its model class (ADR-26); matching uses names only (ADR-12); a dry run and a run report the same failures (ADR-17); the schema offers only columns that can be loaded (ADR-22); one repository folder with one gem per adapter (ADR-23).

Every line and branch of `lib/` is run by an example, and `script/coverage.rb` reports the ones that are not. The specs are in two folders: `spec/unit` has one spec file for each class, with its collaborators replaced by doubles, and the header stage's specs were also checked by breaking the code on purpose to see that they fail; `spec/integration` runs real parts together, for example a consumer's program in a new process. Specs written before that split are still in `spec/pipeforge`.

## Developing

From the repository root:

| Task | Command |
|---|---|
| Install dependencies | `bundle install` |
| Run the tests | `bundle exec rspec` |
| Run the linter (StandardRB) | `bundle exec standardrb` |
| Run the tests with coverage of `lib/` | `bundle exec ruby script/coverage.rb` |

The adapter specs need a running PostgreSQL with two empty databases, which you create once: `createdb pipeforge_test` and `createdb pipeforge_test_secondary` (the second one is for the examples of a model kept in another database). The specs reach PostgreSQL through the Unix socket as the user who runs them; the `PG` environment variables (`PGHOST`, `PGUSER`, `PGPASSWORD`) apply when they are set.

CI starts a PostgreSQL, creates the two databases, then runs the linter and the tests on every pull request to `master`.

## Documentation

`docs/architecture/overview.md` has the system topology, the stage contracts and the end-to-end sequence. `docs/architecture/recommendation-name-matching.md` explains how names are matched and why. `docs/decisions/adrs.md` holds every decision. `docs/planning/mvp-scope.md` says what the first release contains.

## The rule it is built around

A dry run is only worth running if it fails in exactly the places the real run would. Everything else in Pipeforge, from following the model's cast to checking the table's limits when the model is silent, serves that one rule.

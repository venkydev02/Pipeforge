# Relational Data Migration Engine

> An assisted relational data migration engine that helps discover, map, validate, transform, and migrate data between relational systems — with deterministic recommendations and human review before execution.

## About

Most of my backend work has involved data migrations that were never as simple as "read a CSV, insert rows." I've handled large customer migrations — some north of 10 lakh records — built from customer-provided CSV and JSON exports, API-based migrations, and incremental syncs that had to run safely long after the initial load. Each one came with its own friction: fields that didn't map cleanly onto the target schema, the same value showing up in three different forms across customers, records that were invalid, missing, or silently blocked, and foreign keys that only resolved correctly against the real state of the target database.

The hard part was never parsing the input. It was everything around it: understanding both the source and target schema well enough to map between them, being able to explain *why* a mapping was chosen before trusting it, catching bad or inconsistent data before it ever reached the database, resolving relationships and constraints correctly, keeping large volumes practical, running migrations in reviewed phases with customer sign-off before execution, and supporting customer-specific rules without rebuilding the pipeline each time. In practice, this meant writing a new one-off script for every migration — tightly coupled to a specific Rails app, ORM, or customer, impossible to reuse, and giving no real visibility into why a decision was made before it ran.

That's the realization this project comes from: the real problem was never CSV parsing — it was the absence of a reusable system that understands source data and target schema, recommends mappings you can review before anything executes, validates and transforms the data, resolves relationships deliberately, and only then runs the migration, in a controlled and repeatable way, independent of any one application or ORM. This engine is the result: a **framework-independent, plain-Ruby, contract-first relational data migration engine**, built around explicit stages for schema discovery, mapping/recommendation, validation, transformation, relationship resolution, and execution.

## Architecture

![Architecture diagram: Source Input and Target Database feed Source Analysis (P1) and Target Catalog Discovery (P2); both flow into MigrationPlanner, which produces recommendations for Mandatory Consumer Review; reviewed decisions go to MigrationPlanBuilder, which builds a plan for MigrationRuntime (extract → map → transform → pre-resolution validation → relationship resolution → post-resolution validation → load); the Runtime dispatches to Capability Adapters, the only components permitted to touch real target rows.](assets/architecture-diagram.png)

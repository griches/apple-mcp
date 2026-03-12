# MojoSolo Operating Brain

## Executive Summary

This corpus is the canonical operating brain for MojoSolo.

It defines:

- the three inbox personas
- the signal domains and source rules used for mail intelligence
- the output targets for Daily Intel
- Laravel as the primary application and API layer

## Layer Model

1. `knowledge-corpus` is the source of truth.
2. `mail-intelligence` is the live sensor layer that reads Apple Mail and writes Daily Intel.
3. Laravel is the primary application layer that should expose the brain through config, database tables, and HTTP routes.
4. Apple Notes is the default output sink for daily briefs, not the canonical database.

## Personas

- The Author: curated creative and intellectual intake via `mojosolo@mac.com` on the `iCloud` Mail account.
- The Operator: primary human-facing account via `david@mojosolo.com`.
- The Machine: catch-all workflow and campaign account via `info@mojosolo.com`.

## Laravel Role

Laravel should project this brain into:

- `config/brain.php`
- database tables for personas, domains, source rules, and output targets
- seeders so the brain can be hydrated deterministically
- HTTP routes for overview, personas, domains, source rules, and output targets

The corpus stays authoritative; Laravel consumes and serves it.

# Mammoth Search Watch

[![Gem Version](https://badge.fury.io/rb/mammoth-search-watch.svg)](https://badge.fury.io/rb/mammoth-search-watch)
[![CI](https://github.com/kanutocd/mammoth-search-watch/workflows/CI/badge.svg)](https://github.com/kanutocd/mammoth-search-watch/actions)
[![Ruby Version](https://img.shields.io/badge/ruby-%3E%3D%204.0-ruby.svg)](https://www.ruby-lang.org/en/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Mammoth Search Watch observes SERP/search API request-response activity, persists normalized observation facts into PostgreSQL, and lets Mammoth deliver resulting changes through WAL-backed delivery.

**Mammoth Search Watch** is a SERP observation and drift-capture service built on the Mammoth data plane.

It captures SERP request/response observations, persists them as PostgreSQL facts, and lets Mammoth carry the resulting changes through PostgreSQL WAL, replication slots, and reliable downstream delivery.

SearchAPI is the first supported provider adapter.

```text
Tiny observer / adapter
        ↓
Mammoth Search Watch
        ↓
PostgreSQL facts
        ↓
PostgreSQL WAL + replication slot
        ↓
Mammoth
        ↓
Webhook / downstream delivery
```

Mammoth Search Watch is intentionally **PostgreSQL-first**, **WAL-centric**, and **operationally boring**. It is not a generic HTTP event bus, not a scraper, and not an SEO dashboard.

## Status

Early development. The public contract and storage model may change before `1.0`.

## Core idea

A SERP API endpoint returns observable search state. Mammoth Search Watch records that state as durable PostgreSQL facts and emits only meaningful changes through Mammoth.

```text
SERP API endpoint interaction
        ↓
request observed
response observed
        ↓
watch key + result hash
        ↓
PostgreSQL insert
        ↓
Mammoth delivery
```

## Intended audiences

Mammoth Search Watch is useful for two related audiences:

1. **SERP API company itself** — product telemetry, support evidence, parser regression detection, compliance trails, and drift analytics.
2. **SERP API company customers** — durable search-change events without rewriting business logic around polling and diffing.

## Architecture boundary

Mammoth Search Watch creates PostgreSQL facts. Mammoth operates and delivers them.

```text
Mammoth Search Watch
  owns: observation ingestion, normalization, retention, drift fact persistence

Mammoth
  owns: WAL consumption, replication slot handling, delivery, retries, dead letters, health, metrics
```

This keeps Mammoth Search Watch true to the Mammoth model:

```text
PostgreSQL table
      ↓
WAL
      ↓
replication slot
      ↓
Mammoth data plane
```

## Fragile ingress table

The first integration boundary is intentionally simple: a fragile, retention-managed PostgreSQL table for observed HTTP activity.

Example shape:

```sql
CREATE TYPE activity_type AS ENUM ('request', 'response');

CREATE TABLE activities (
  id BIGSERIAL PRIMARY KEY,
  tenant_id TEXT NOT NULL,
  observation_id TEXT NOT NULL,
  activity_type activity_type NOT NULL,
  payload JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

The `activities` table is an ingress ledger, not canonical long-term history. Rows may be deleted after the configured retention period.

Consumers that want to retain full history may configure a longer retention period or replicate the table elsewhere.

## Multi-tenancy

Mammoth Search Watch is designed to be multi-tenant aware.

A PostgreSQL Row-Level Security policy can isolate tenant data:

```sql
ALTER TABLE activities ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation_policy
ON activities
USING (tenant_id = current_setting('app.current_tenant_id', true))
WITH CHECK (tenant_id = current_setting('app.current_tenant_id', true));
```

Example usage:

```sql
BEGIN;
SET LOCAL app.current_tenant_id = 'tenant_abc_123';

INSERT INTO activities (
  tenant_id,
  observation_id,
  activity_type,
  payload
)
VALUES (
  'tenant_abc_123',
  'obs_123',
  'request',
  '{"engine":"google_rank_tracking","q":"ruby jobs"}'::jsonb
);

COMMIT;
```

## Watch key and result hash

Mammoth Search Watch separates request identity from response identity.

```text
watch_key / observation_id
  deterministic identity derived from the normalized request shape

sample_id
  unique identity for a specific request/response instance

result_hash
  deterministic hash of the normalized SERP API result
```

The practical deduplication rule is:

```text
same watched query + same result hash
  = no new durable search state

same watched query + new result hash
  = new PostgreSQL fact
  = new WAL event
  = Mammoth delivery
```

A derived table may use a uniqueness rule like:

```sql
UNIQUE (observation_id, result_hash)
```

## Tiny observer principle

Observers should have a very small footprint.

They should:

1. copy selected request data,
2. derive or receive an observation id,
3. pass the request through,
4. copy selected response data,
5. pass the response through unchanged,
6. enqueue or insert the observation payload.

Observers should not own drift analytics, Mammoth delivery, retention policy, or long-term product behavior.

## Installation

Add the gem to your application:

```bash
bundle add mammoth-search-watch
```

Or install directly:

```bash
gem install mammoth-search-watch
```

## Docker

Planned image:

```text
ghcr.io/kanutocd/mammoth-search-watch:latest
ghcr.io/kanutocd/mammoth-search-watch:v0.1.0
```

A typical local deployment uses separate containers for PostgreSQL, Mammoth, Mammoth Search Watch, and a webhook receiver.

```yaml
services:
  postgres:
    image: postgres:17

  mammoth:
    image: ghcr.io/kanutocd/mammoth:latest
    environment:
      MAMMOTH_CONFIG: /config/mammoth.yml
    volumes:
      - ./config/mammoth.yml:/config/mammoth.yml:ro
      - mammoth_data:/app/.sqlite3
    depends_on:
      - postgres

  search-watch:
    image: ghcr.io/kanutocd/mammoth-search-watch:latest
    environment:
      DATABASE_URL: postgres://mammoth_search_watch:secret@postgres:5432/search_watch
      SEARCH_WATCH_RETENTION: 24h
    ports:
      - "9292:9292"
    depends_on:
      - postgres

volumes:
  mammoth_data:
  postgres_data:
```

## Kubernetes and Helm

Mammoth Search Watch should reuse the Mammoth deployment model where possible.

A dedicated Helm chart should only be introduced when Search Watch needs distinct deployment variants, such as:

- observer ingress service,
- tenant-specific configuration,
- retention jobs,
- RLS/bootstrap migrations,
- separate service accounts,
- separate secrets,
- hosted-vs-customer-pod profiles.
        
## Non-goals

Mammoth Search Watch is not:

- a browser scraper,
- a proxy-rotation system,
- an SEO dashboard,
- a generic HTTP event bus,
- a replacement for a SERP API,
- a replacement for Mammoth.

## Development

After checking out the repository:

```bash
bin/setup
bundle exec rake test
```

Use the console for local exploration:

```bash
bin/console
```

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting with this project is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

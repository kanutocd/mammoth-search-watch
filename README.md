<div align="center">
  <img src="docs/assets/logo/mammoth-horizontal-with-white-background.png" alt="Mammoth PostgreSQL CDC Data Plane">
  
  <h1>Mammoth Search Watch</h1>
  <p><strong>A concrete implementation of the Mammoth OSS Data Plane for Search Observability</strong></p>
</div>

---

# Mammoth Search Watch

[![Gem Version](https://badge.fury.io/rb/mammoth-search-watch.svg)](https://badge.fury.io/rb/mammoth-search-watch)
[![CI](https://github.com/kanutocd/mammoth-search-watch/workflows/CI/badge.svg)](https://github.com/kanutocd/mammoth-search-watch/actions)
[![Ruby Version](https://img.shields.io/badge/ruby-%3E%3D%204.0-ruby.svg)](https://www.ruby-lang.org/en/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)


## 🌐 Part of the Mammoth Platform

**Mammoth Search Watch** is a concrete production implementation of the open-source **Mammoth Data Plane**. 

While this data plane remains fully open-source (MIT) for local high-throughput tracking, it natively integrates with the commercial **Mammoth Platform** ecosystem:
* **Mammoth Control Plane:** Centralized cluster management, global analytics dashboarding, and alerting.
* **Mammoth Control Agent:** Lightweight telemetry and remote configuration sync.
* **High-End Extensions:** Advanced predictive drift modeling and automated schema patching.


> **PostgreSQL-native Search Observability built on the Mammoth data plane.**

**Observe**. **Persist**. **Prove**.

Mammoth Search Watch transforms SERP/search API interactions into durable PostgreSQL facts carried through Mammoth's WAL data plane.

Unlike traditional rank trackers, SEO dashboards, and search monitoring tools, Mammoth Search Watch is designed as a **Search Observability Platform**.

Its philosophy is simple:

> **Observe reality. Persist facts. Deliver changes.**

---

## Why Mammoth Search Watch?

Search providers tell you **what search results look like now**.

Mammoth Search Watch helps you understand:

- **what was searched**
- **what was returned**
- **what changed**
- **when it changed**
- **and proves it with durable PostgreSQL facts.**

### Designed to enable

- 🔍 Search Observability
- 📈 SERP Drift Detection
- 🕒 Historical Search Intelligence
- 📋 Compliance & Audit Trails
- ⚖️ Conflict Resolution
- 🔄 Replayable Search Events
- 📊 Search Analytics
- 🧠 AI-ready Search Data
- 💰 Search Budget Optimization
- 🏢 Multi-tenant Operation

These capabilities are built on a single principle:

> **Observation first. Inference later.**

Search observations become durable PostgreSQL facts.

Everything else—drift detection, analytics, dashboards, AI, replay, compliance, competitive intelligence, and operational intelligence—is derived from those facts.

---

Mammoth Search Watch observes SERP/search API request-response activity, persists normalized observation facts into PostgreSQL, and embeds Mammoth by default to deliver resulting changes through WAL-backed delivery.

**Mammoth Search Watch** is a SERP observation and drift-capture service built on the Mammoth data plane.

It captures SERP request/response observations, persists them as PostgreSQL facts, and embeds Mammoth so the resulting changes can move through PostgreSQL WAL, replication slots, and reliable downstream delivery.

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

Mammoth Search Watch is intentionally **PostgreSQL-first**, **WAL-centric**, and **operationally boring**. It is not a generic HTTP event bus, not a scraper, and not an SEO dashboard. Sink-only mode is available when you opt out of the embedded Mammoth runtime.

## Status

**Project Status:** Early development.

The current implementation focuses on establishing the PostgreSQL-first observation pipeline and Mammoth integration.

The capabilities described in this document represent the long-term vision of Mammoth Search Watch and will be delivered incrementally as the project evolves toward `1.0`.

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

## Who is it for?

Mammoth Search Watch is useful for two related audiences:

1. **SERP API company itself** — product telemetry, support evidence, parser regression detection, compliance trails, and drift analytics.
2. **SERP API company customers** — durable search-change events without rewriting business logic around polling and diffing.

## Architecture boundary

Mammoth Search Watch creates PostgreSQL facts. Mammoth operates and delivers them, either embedded by default or as an external service in sink-only mode.

```text
Mammoth Search Watch
  owns: observation ingestion, normalization, retention, drift fact persistence, embedded Mammoth runtime

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

If the deployment is not multi-tenant, configure a global tenant id and
use it for every insert. The table still stores `tenant_id` on each row;
the value just comes from deployment configuration instead of request
context.

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

The default local deployment keeps Mammoth embedded in the Search Watch
process.

```yaml
services:
  postgres:
    image: postgres:17

  search-watch:
    image: ghcr.io/kanutocd/mammoth-search-watch:latest
    environment:
      DATABASE_URL: postgres://mammoth_search_watch:secret@postgres:5432/search_watch
      SEARCH_WATCH_CONFIG: /config/search_watch.yml
      MAMMOTH_CONFIG: /config/mammoth.yml
    ports:
      - "9292:9292"
    volumes:
      - ./config/search_watch.yml:/config/search_watch.yml:ro
      - ./config/mammoth.yml:/config/mammoth.yml:ro
      - mammoth_data:/app/.sqlite3
    depends_on:
      - postgres

volumes:
  mammoth_data:
  postgres_data:
```

Concrete deployment manifests are available in [docker-compose.yml](./docker-compose.yml) and the split Kubernetes manifests under `k8s/` folder.

```bash
docker compose up -d
kubectl apply -k k8s
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
bundle exec bin/setup
bundle exec rake test
```

To bootstrap the PostgreSQL schema:

```bash
bundle exec mammoth-search-watch bootstrap config/search_watch.yml
```

To run retention cleanup:

```bash
bundle exec mammoth-search-watch retention-cleanup config/search_watch.yml
```

`mammoth-search-watch start` bootstraps the schema automatically unless
`lifecycle.bootstrap_on_start` is set to `false`.

In Docker images, the container entrypoint should call `mammoth-search-watch start`.

For a long-running periodic cleanup worker, use:

```bash
bundle exec mammoth-search-watch retention-scheduler config/search_watch.yml
```

Use the console for local exploration:

```bash
bundle exec bin/console
```

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting with this project is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

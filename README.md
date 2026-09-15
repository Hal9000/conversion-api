# ECAPI conversion attribution — V0

This repository is the starting point for Adgentek's ECAPI-compatible
conversion receiver and click-conversion attribution service.

The original working notes are retained unchanged in
[old-README.md](old-README.md). This document is the authoritative V0 build
contract when the two documents differ.

## Scope

V0 attributes e-commerce conversions to Adgentek **internal campaigns** after
a click. It does not support view-through attribution.

- Attribution window: 14 days from click time.
- Initial conversion event: `purchase`.
- Other ECAPI event types may be accepted and retained, but are not
  attribution or optimization inputs until explicitly enabled.
- A conversion marked `mmt_only: true` is retained for measurement and
  attribution, but must not be used for optimization.

## Click identifier

`agclid` is the canonical browser-facing click identifier. `click_id` in an
ECAPI event is the same value.

1. On a qualifying click, the ad server creates a click record linked to its
   impression.
2. It generates an opaque, signed `agclid` that references that click.
3. It appends `agclid` to the destination URL.
4. The e-commerce store returns that exact value in
   `user_data.click_id`.
5. The receiver verifies the signature and resolves the click, impression,
   campaign, and advertiser.

The identifier must not expose a raw `ad_id`, `auction_id`, or
`impression_id`. These are internal identifiers and are not a replacement for
`agclid`.

## Event API

The receiver exposes:

```http
POST /v1/events
Authorization: Bearer <advertiser credential>
Content-Type: application/json
```

It accepts an ECAPI 1.0 event object, an array of event objects, or an object
containing an `events` array. The initial required fields for each event are:

- `data_set_id`
- `id`
- `timestamp` (Unix seconds)
- `event_type`
- `source`

`purchase` additionally requires a non-negative `value` and ISO 4217
`currency_code`. `custom` events require `custom_event`.

The receiver must reject malformed payloads, unauthenticated requests, and
events whose `data_set_id` does not belong to the credential. It must return a
stable request/result identifier so senders can safely retry.

## Authentication and tenancy

Each advertiser receives a distinct bearer credential. A credential is bound
to one advertiser and its permitted `data_set_id` values. Authentication and
dataset authorization happen before event persistence or attribution.

The receiver uses a dedicated, least-privilege database role. Production role
provisioning and operational controls are documented in
[docs/database-security.md](docs/database-security.md).

## Storage and idempotency

The receiver persists every accepted request and normalized event in durable
storage. It must not rely on process memory or log tailing for correctness.

The idempotency key is:

```text
data_set_id + event id
```

Retries with the same key must not create a second conversion. If a repeated
event contains additional fields, the raw receipt is retained and the
normalized record may be enriched without changing its attribution result.

At minimum, storage needs:

- raw event receipts and validation outcome;
- normalized ECAPI events;
- click-to-impression lookup data from `clicks` and `pub_impressions`;
- attributed conversions; and
- campaign/date conversion aggregates.

## Attribution rules

An event is attributable only when all of these are true:

1. It has a valid `click_id` / `agclid`.
2. The identifier resolves to a recorded click and impression.
3. The click belongs to the event's authorized advertiser and an internal
   campaign.
4. The event timestamp is no more than 14 days after the click.
5. No prior attribution exists for the same idempotency key.

An unattributable event can still be retained as a receipt, with an explicit
reason such as `missing_click_id`, `invalid_click_id`, `expired_click`, or
`external_campaign`.

## Privacy

V0 does not attempt IP-address plus user-agent matching. In particular, it
does not use that combination to infer view-through or click attribution in
the EU.

Hash-based identity fields may be stored and processed only after their
normalization, consent, permitted-purpose, access-control, and retention
rules are defined. They are not an attribution fallback in V0.

## Local testing

Tests run against a disposable PostgreSQL database:

```bash
docker compose -f docker-compose.test.yml up -d
export DATABASE_URL=postgres://postgres:postgres@127.0.0.1:54329/ecapi_test
bundle install
bundle exec rake test
docker compose -f docker-compose.test.yml down -v
```

The test suite applies the production migrations before running and deletes
test rows between cases. Do not point `DATABASE_URL` at a shared, development,
or production database when running tests.

Pull requests run the same suite against an ephemeral PostgreSQL 16 GitHub
Actions service container. CI does not require a database to be running in a
Cloud Agent.

## Deployment

Build and run the receiver with the included container image:

```bash
docker build -t ecapi .
docker run --rm --publish 9292:9292 \
  --env RACK_ENV=production \
  --env DATABASE_URL='postgres://.../?sslmode=verify-full' \
  ecapi
```

The application runs Puma on `PORT` (default `9292`). In production,
`DATABASE_URL` must use PostgreSQL certificate verification
(`sslmode=verify-full`); startup fails otherwise. `GET /health` returns `200`
only when the database accepts a query, otherwise it returns `503`.

## Delivery order

1. Define database migrations and the advertiser credential model.
2. Implement signed `agclid` generation and click-record persistence in the
   ad-server click flow.
3. Implement the authenticated, validating, durable `POST /v1/events`
   receiver.
4. Implement database-backed idempotency and raw-event auditing.
5. Implement click-through attribution and campaign/date aggregates.
6. Add end-to-end tests for valid, invalid, expired, duplicate, and
   `mmt_only` events.

## Open decisions

- Final public hostname for the receiver.
- Credential provisioning and rotation mechanism.
- Exact signing-key management and `agclid` format.
- Raw PII retention period and access controls.
- Whether partial refunds and future non-purchase events affect conversion
  aggregates.

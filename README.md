# Conversion API

Demo Event & Conversion API (IAB Tech Lab [ECAPI 1.0](https://github.com/InteractiveAdvertisingBureau/ecapi/blob/main/ecapi_1.0.md)).

Ruby + Roda. In-memory store. Not wired to Supabase or at-1 yet.

## Run

```bash
bundle install
CONVERSION_API_KEY=demo bundle exec puma
```

Listens on `PORT` (default 9292).

```bash
bundle exec rake test
```

## Demo

Auth is `Authorization: Bearer $CONVERSION_API_KEY` or `X-Api-Key`. Default key is `demo`.

Single purchase:

```bash
curl -s -X POST http://127.0.0.1:9292/v1/events \
  -H 'Authorization: Bearer demo' \
  -H 'Content-Type: application/json' \
  -d '{
    "data_set_id": "acct_demo",
    "id": "evt_001",
    "timestamp": 1746558464,
    "event_type": "purchase",
    "value": 49.99,
    "currency_code": "USD",
    "source": "website",
    "user_data": { "click_id": "clk_abc" },
    "properties": { "transaction_id": "ord_1001" }
  }'
```

Same `data_set_id` + `id` is merged (pixel + CAPI style). Omit `id` to force a new record.

Batch:

```bash
curl -s -X POST http://127.0.0.1:9292/v1/events \
  -H 'Authorization: Bearer demo' \
  -H 'Content-Type: application/json' \
  -d '{"events":[{...},{...}]}'
```

Inspect:

```bash
curl -s http://127.0.0.1:9292/health
curl -s http://127.0.0.1:9292/v1/events -H 'Authorization: Bearer demo'
curl -s http://127.0.0.1:9292/v1/events/acct_demo/evt_001 -H 'Authorization: Bearer demo'
```

## Contract

Required on each event: `data_set_id`, `timestamp` (unix epoch integer), `event_type`.

Conditionally required: `custom_event` if `event_type` is `custom`; `currency_code` (ISO 4217) if `value` is set.

Status codes: `200`, `400`, `401`, `404`.

Next: persist into `conversion_events_raw` and run on at-1.

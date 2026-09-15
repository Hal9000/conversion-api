# ecapi
Views are for influencers. Conversions are for adults.

https://github.com/InteractiveAdvertisingBureau/ecapi/blob/main/ecapi_1.0.md


All, please edit this brutally - anything missing

## Minimal spec, until we are on GCP

think of it as something that has to work before Sep 25;

we will fine-tune it afterwards to scale better (hello alloy).

## tables

use table pub_impressions, clicks

## general

Conversions are only relevant for internal campaigns.

In V0, we only worry about click-conversion;
We also force the conversion window to be 14 days to get started;
(later we use the value from the UI)

## tracking, what we pass to the e-commerce store

The ad-server passes &agclid=#{ad_id}_#{auction_id} in the  adgentek click_url as part of the &d= destination_url. This is implemented when the dump from the DB happens;

We only do this for internal campaigns.

Currently it is:
--
  https://api.adgentek.ai/functions/v1/click-redirect 
    ?adv=adv_3f9c1a7e2b...                 advertiser id (real UUID for internal, adv_<hash of adomain> for external)
    &cmp=cmp_8d2e4b91c0...                 campaign id (campaigns.id for internal, bid.cid or cmp_<hash of seat|adomain>
  for external)
    &cr=bswx_crid_12345                    creative id (bid.crid, falls back to auction id)
    &cv=<creative_version_uuid>            only for internal creatives
    &d=https%253A%252F%252Fadvertiser.com%252Flanding   destination, double-encoded
    &ds=<demand_source_uuid>               only for RTB wins
    &li=<line item id>                     bid.ext.line_item_id, else bid.adid, else auction id
    &mk=<metrics key>
    &pub_org=<publisher org uuid>
    &slot=<publisher_slots.id uuid>        
    &t=1757665200000                       ms timestamp
    &sig=<hmac-sha256 hex>                 signs all params above, sorted by key
    &ctry=US&rgn=CA&cty=San+Jose&zp=95112&lat=37.33&lon=-121.89   geo, unsigned
    &cpd=<base64 custom params>            unsigned
--


We set the agclid to the impression_id; from that we get the user_id and can check if we had a click; Realistically we can't track view-thru conversions

## What the e-commerce store sends us

Hal, setup a simple robust server on server at-3 that logs all;
(simple puma or even just nginx will do; probably easiest to coordinate with Diane to get nginx running on conversions.adgentek.ai or whatever; for testing simple run puma on a port or similar )

todo: log-rotate, 

A process that tails the log and when we get a hit, check if it is one of our conversions or not;
it should be robust, not to generate double conversions if restarted, etc;
For conversions, update the DB (we want to know how many conversions and type per campaign and date) let's make a new table to be on the safe side;
(there are conversions in the system, but what we do is different)

Let's focus on e-commerce buy events for the demo;

Sample ecapi receiving side calls - generated with claude

Nothing in memory covers "ecapi" directly, so let me check past chats.Assuming the receiver is something like `POST https://capi.adgentek.ai/v1/events` with a bearer token per advertiser (the spec leaves endpoint and auth to the platform, so that part is yours to define). All PII fields are SHA256 of normalized values; I've written `sha256(...)` as shorthand. `data_set_id` is the Adgentek advertiser/account id you hand out; `click_id` is the click id your ad server appends to the landing URL.

**1. Purchase after an ad click (the main one)**

```http
POST /v1/events HTTP/1.1
Host: capi.adgentek.ai
Authorization: Bearer agk_live_9f3k...
Content-Type: application/json
Accept: application/json

{
  "data_set_id": "adv_7c21",
  "id": "order_118342",
  "timestamp": 1789203411,
  "event_type": "purchase",
  "value": 1498.00,
  "currency_code": "NOK",
  "source": "website",
  "user_data": {
    "email_address": ["sha256(kari.nordmann@example.no)"],
    "phone_numbers": ["sha256(4791234567)"],
    "click_id": "agk_clk_Z8mP2q",
    "event_ip_address": "84.208.12.55",
    "event_user_agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 19_0 ...)",
    "address": [{
      "first_name": "sha256(kari)",
      "last_name": "sha256(nordmann)",
      "city": "oslo",
      "country_code": "no",
      "postal_code": "sha256(0150)",
      "address_type": 2
    }],
    "gpp_string": "DBABMA~CPXxRfAPXxRfAAfKABENB-CgAAAAAAAAAAYgAAAAAAAA",
    "gpp_sid": [2]
  },
  "properties": {
    "transaction_id": "order_118342",
    "items": [
      { "id": "SKU-4471", "name": "Merino base layer", "price": 749.00, "quantity": 2, "brand": "Devold", "category": "Apparel > Base Layers", "cattax": 7 }
    ],
    "shipping": 0.0,
    "tax": 299.60,
    "coupon": ["AUTUMN10"],
    "payment_type": ["vipps"]
  }
}
```

**2. Same purchase, sent again from the browser pixel (dedupe case)**

Same `data_set_id` + `id` as #1, thinner payload. Your receiver should merge, not create a second record.

```json
{
  "data_set_id": "adv_7c21",
  "id": "order_118342",
  "timestamp": 1789203409,
  "event_type": "purchase",
  "value": 1498.00,
  "currency_code": "NOK",
  "source": "website",
  "user_data": {
    "click_id": "agk_clk_Z8mP2q",
    "event_ip_address": "84.208.12.55",
    "event_user_agent": "Mozilla/5.0 (iPhone; ...)"
  },
  "properties": { "transaction_id": "order_118342", "page_url": "https://shop.example.no/checkout/thanks" }
}
```

**3. Add to cart**

```json
{
  "data_set_id": "adv_7c21",
  "id": "evt_a1f9c2",
  "timestamp": 1789201877,
  "event_type": "add_to_cart",
  "value": 749.00,
  "currency_code": "NOK",
  "source": "website",
  "user_data": {
    "click_id": "agk_clk_Z8mP2q",
    "event_ip_address": "84.208.12.55",
    "event_user_agent": "Mozilla/5.0 (iPhone; ...)"
  },
  "properties": {
    "page_url": "https://shop.example.no/p/merino-base-layer",
    "items": [{ "id": "SKU-4471", "name": "Merino base layer", "price": 749.00, "quantity": 1, "item_variant": "black/L" }]
  }
}
```

**4. Product page view (no PII, click id only)**

```json
{
  "data_set_id": "adv_7c21",
  "id": "evt_b7e044",
  "timestamp": 1789201790,
  "event_type": "viewed_item",
  "source": "website",
  "user_data": {
    "click_id": "agk_clk_Z8mP2q",
    "event_ip_address": "84.208.12.55",
    "event_user_agent": "Mozilla/5.0 (iPhone; ...)"
  },
  "properties": {
    "page_url": "https://shop.example.no/p/merino-base-layer",
    "referrer": "https://shop.example.no/c/base-layers",
    "items": [{ "id": "SKU-4471", "name": "Merino base layer", "price": 749.00 }]
  }
}
```

**5. Begin checkout — measurement-only (user consented to analytics, not ad optimization)**

```json
{
  "data_set_id": "adv_7c21",
  "id": "evt_c31d8a",
  "timestamp": 1789203102,
  "event_type": "begin_checkout",
  "value": 1498.00,
  "currency_code": "NOK",
  "source": "website",
  "user_data": {
    "click_id": "agk_clk_Z8mP2q",
    "mmt_only": true,
    "gpp_string": "DBABMA~CPXxRfAPXxRfAAfKABENB-CgAAAAAAAAAAYgAAAAAAAA",
    "gpp_sid": [2]
  },
  "properties": {
    "items": [{ "id": "SKU-4471", "quantity": 2, "price": 749.00 }]
  }
}
```

**6. Refund (partial)**

Spec doesn't say whether `value` is signed for refunds; I'd document "positive amount refunded" and let `event_type` carry the sign.

```json
{
  "data_set_id": "adv_7c21",
  "id": "refund_118342_1",
  "timestamp": 1789460000,
  "event_type": "refund",
  "value": 749.00,
  "currency_code": "NOK",
  "source": "system_generated",
  "user_data": {
    "email_address": ["sha256(kari.nordmann@example.no)"],
    "customer_identifier": "sha256(cust_55021)"
  },
  "properties": {
    "transaction_id": "order_118342",
    "items": [{ "id": "SKU-4471", "quantity": 1, "price": 749.00 }]
  }
}
```

**7. Account sign-up (lead-ish, no monetary value)**

```json
{
  "data_set_id": "adv_7c21",
  "id": "signup_u_88120",
  "timestamp": 1789202450,
  "event_type": "sign_up",
  "source": "website",
  "user_data": {
    "email_address": ["sha256(ola@example.no)"],
    "click_id": "agk_clk_Q1vT7n",
    "event_ip_address": "2a01:799:1c2:9400::1",
    "event_user_agent": "Mozilla/5.0 (Macintosh; ...)",
    "customer_segments": ["newsletter"]
  },
  "properties": {
    "page_url": "https://shop.example.no/account/new",
    "ad_source": "adgentek",
    "login_method": "email"
  }
}
```

**8. Subscription renewal (no click, matched on hashed identifiers only)**

```json
{
  "data_set_id": "adv_7c21",
  "id": "sub_2231_2026-09",
  "timestamp": 1789171200,
  "event_type": "subscribe",
  "value": 199.00,
  "currency_code": "NOK",
  "source": "system_generated",
  "user_data": {
    "email_address": ["sha256(ola@example.no)"],
    "phone_numbers": ["sha256(4798765432)"],
    "customer_identifier": "sha256(cust_2231)"
  },
  "properties": {
    "transaction_id": "inv_2026_09_2231",
    "items": [{ "id": "PLAN-PRO-M", "name": "Pro monthly", "price": 199.00, "quantity": 1 }]
  }
}
```

**9. Batch of in-store purchases uploaded from a POS system**

Batching is receiver-defined; a JSON array body under the same auth is the simplest.

```json
[
  {
    "data_set_id": "adv_7c21",
    "id": "pos_oslo1_00931",
    "timestamp": 1789134600,
    "event_type": "purchase",
    "value": 2290.00,
    "currency_code": "NOK",
    "source": "physical_store",
    "user_data": { "email_address": ["sha256(member1@example.no)"], "customer_segments": ["gold_member"] },
    "properties": {
      "transaction_id": "pos_oslo1_00931",
      "items": [{ "id": "SKU-9010", "name": "Down jacket", "price": 2290.00, "quantity": 1, "item_location_id": "store_oslo_1", "affiliation": "Oslo Sentrum" }]
    }
  },
  {
    "data_set_id": "adv_7c21",
    "id": "pos_bergen2_00412",
    "timestamp": 1789139900,
    "event_type": "purchase",
    "value": 449.00,
    "currency_code": "NOK",
    "source": "physical_store",
    "user_data": { "phone_numbers": ["sha256(4745678901)"] },
    "properties": {
      "transaction_id": "pos_bergen2_00412",
      "items": [{ "id": "SKU-1120", "name": "Wool socks 3-pack", "price": 449.00, "quantity": 1, "item_location_id": "store_bergen_2" }]
    }
  }
]
```

**10. Custom event with an Adgentek extension**

```json
{
  "data_set_id": "adv_7c21",
  "id": "evt_d90f11",
  "timestamp": 1789204000,
  "event_type": "custom",
  "custom_event": "size_guide_opened",
  "source": "app",
  "user_data": {
    "ifa": "6D92078A-8246-4BA4-AE5B-76104861E7DC",
    "click_id": "agk_clk_Z8mP2q",
    "uids": [{ "id": "sha256(app_user_4471)", "source": "shop.example.no", "atype": 1 }]
  },
  "properties": {
    "items": [{ "id": "SKU-4471" }],
    "ext": { "adgentek": { "campaign_id": "cmp_3391", "creative_id": "cr_0082", "sdk_version": "1.4.2" } }
  }
}
```

A few receiver-side implications that fall out of these: #1/#2 and #6 both key on `data_set_id + id`, so that lookup is your hot path; #5 needs `mmt_only` to gate optimization but still count for attribution; #8 and #9 have no `click_id` at all, so identity matching on hashed email/phone is what makes them attributable; and #10's `ext` should be schema-tolerant, since senders will send whatever you told them to. I can sketch the per-event response body shape to pair with these if useful.

## the might UI

We need to update the might UI to reflect the new numbers, etc;

Let's ask Stefan Meyer, once we have the tables populated - he is our fastest vibe coder

## Questions

- How can we track view thru conversions? We don't have hashed emails, etc; like Google has
  Can we do better than probabilistic ip+UA match; if not truncated, might work well

- We can only do ip+ua and that is a no-go in EU;




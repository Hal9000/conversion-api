-- Run as the schema owner after migrations, with a role named ecapi_runtime
-- already created by the database administrator. This script intentionally
-- does not create a LOGIN role or set its password.

REVOKE ALL ON SCHEMA ecapi FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA ecapi FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA ecapi FROM PUBLIC;

GRANT USAGE ON SCHEMA ecapi TO ecapi_runtime;

GRANT SELECT ON ecapi.advertiser_credentials, ecapi.credential_data_sets TO ecapi_runtime;
GRANT SELECT, INSERT ON ecapi.events, ecapi.event_receipts TO ecapi_runtime;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA ecapi TO ecapi_runtime;

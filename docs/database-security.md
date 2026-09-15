# Production database security

The application connection must use a dedicated `ecapi_runtime` database role.
It must not use a database owner, a migration role, or a Supabase service-role
credential.

## Provisioning

1. The database administrator creates the `ecapi_runtime` LOGIN role with
   `NOINHERIT`, `NOSUPERUSER`, `NOCREATEDB`, `NOCREATEROLE`, and
   `NOREPLICATION`.
2. The administrator stores that role's password or connection credential in
   the deployment platform's secret manager. Do not commit it or place it in a
   shell history.
3. A separate migration role creates the `ecapi` schema and runs
   `bundle exec ruby db/migrate.rb`.
4. The schema owner runs `psql "$DATABASE_URL" -f db/runtime-role.sql`.
5. Set the receiver's `DATABASE_URL` from the secret manager with TLS required
   by the managed PostgreSQL provider.

`db/runtime-role.sql` limits the runtime role to reading credentials and
dataset bindings, and reading/inserting ECAPI event records. Attribution-table
permissions must be added later as narrowly scoped grants after the exact
lookup queries are implemented.

## Operational controls

- Keep production, staging, CI, and local databases separate.
- Do not expose the database to browsers or public network ranges.
- Enable managed backups and encryption features offered by the database
  provider.
- Define and enforce retention for raw event receipts before production use.
- Restrict raw receipt queries to audited operator access; they can contain
  hashed identifiers, IP addresses, and user agents.
- Rotate runtime credentials and revoke inactive advertiser credentials.

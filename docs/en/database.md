# Database (Postgres + migris + Prisma)

> Português: [../pt-BR/database.md](../pt-BR/database.md)

## Decisions

- **Server:** the shared local Postgres container `pottmayer-postgres` (Postgres 18, host port **5433**, managed via `pottmayer-pgadmin` at http://localhost:15432). linkly gets its own database, `linkly`, next to the other projects'. No Postgres in a linkly docker-compose.
- **Schema changes:** [migris](https://github.com/leonardopottmayer/migris), plain `.sql` migrations, same layout as pandora. **Prisma Migrate is not used.**
- **Prisma:** only the **client** (typed queries). Its `schema.prisma` is generated from the database with `prisma db pull` (database-first).
- **Prisma lives only in `apps/api`.** The Next app never talks to the database; it calls the API.

Flow for every schema change:

```
write up.sql/down.sql → migris apply local → prisma db pull → prisma generate
```

## Conventions (same as pandora)

- One **schema per module** (`identity`, `links`, …), one migris module per schema.
- Tables carry a **module code prefix**: `identity.idt001_user`, `links.lnk001_link`.
- Constraint names: `pk_<code>`, `uq_<code>_<column>`, `fk_<code>_<column>`.
- Primary keys: `uuid DEFAULT uuidv7()`. Postgres 18 has `uuidv7()` built in, so linkly doesn't need pandora's `pgcrypto` + `uuid_generate_v7()` function.
- Enum-like values stored with hyphens (`pending-confirmation`), columns in `snake_case`.

## 1. Create the database

```bash
docker exec pottmayer-postgres psql -U postgres -c "CREATE DATABASE linkly;"
```

Runs `psql` inside the container as the `postgres` superuser. Same as creating it in pgAdmin. Local only: the dev database uses the superuser, like pandora.

## 2. Set up migris

Everything database-related lives in `migrations/` at the repo root:

```
migrations/
  config.json           → real credentials (gitignored)
  config.example.json   → template (committed)
  migrations/<module>/<timestamp>-<name>/...
  seed/                 → local seed data (*.local.* gitignored)
```

From the repo root:

```bash
mkdir migrations
cd migrations
migris init
```

`migris init` (no environment) only creates the `config.json` template and the `migrations/` folder. Replace `config.json` with:

```json
{
  "environments": {
    "local": {
      "host": "localhost",
      "port": 5433,
      "user": "postgres",
      "password": "postgres",
      "database": "linkly"
    }
  }
}
```

Copy it to `config.example.json` (committed, so a fresh clone knows the shape). Then create migris's control table in the database:

```bash
migris init local
```

Add to the root `.gitignore`:

```
migrations/config.json
migrations/seed/*.local.*
```

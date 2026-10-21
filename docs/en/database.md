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

The empty `migrations/migrations/` folder isn't committed (git doesn't track empty folders); it shows up with the first migration.

## 3. First migrations: `identity` module

From `migrations/`:

```bash
migris create create-schema-identity --module identity
migris create create-table-idt001-user --module identity
```

The first `--module` on an empty project switches migris to **modular mode** (every migration lives under a module folder from now on, and `--module` becomes required). Each command creates `migrations/identity/<timestamp>-<name>/` with empty `.up.sql`/`.down.sql`.

`create-schema-identity`:

```sql
-- up
CREATE SCHEMA IF NOT EXISTS identity;

-- down
DROP SCHEMA IF EXISTS identity;
```

`create-table-idt001-user`:

```sql
-- up
CREATE TABLE identity.idt001_user (
	id UUID NOT NULL DEFAULT uuidv7(),
	username VARCHAR(30) NOT NULL,
	email VARCHAR(255) NOT NULL,
	password_hash TEXT NOT NULL,
	name VARCHAR(150) NOT NULL,
	created_at TIMESTAMPTZ NOT NULL DEFAULT current_timestamp,
	updated_at TIMESTAMPTZ NULL
);

ALTER TABLE identity.idt001_user
ADD CONSTRAINT pk_idt001 PRIMARY KEY (id);

ALTER TABLE identity.idt001_user
ADD CONSTRAINT uq_idt001_username UNIQUE (username);

ALTER TABLE identity.idt001_user
ADD CONSTRAINT uq_idt001_email UNIQUE (email);

ALTER TABLE identity.idt001_user
ADD CONSTRAINT ck_idt001_username CHECK (username ~ '^[a-z0-9_-]{3,30}$');

-- down
DROP TABLE identity.idt001_user;
```

- `username` is the public page URL (`linkly/leo`), so the `CHECK` keeps it lowercase and URL-safe **in the database**, whatever the app does. Reserved names (`dashboard`, `r`, …) are an app rule, not a DB one.
- The API lowercases emails before saving, so a plain `UNIQUE` is enough.
- No `created_by`/`updated_by` (pandora has them): users sign themselves up, there's no other author.
- Profile data (bio, avatar, theme) is not here; it belongs to the links module.

## 4. Apply

```bash
migris status local
migris apply local
```

`status` lists pending migrations; `apply` runs them in timestamp order, as one batch. To check in the database:

```bash
docker exec pottmayer-postgres psql -U postgres -d linkly -c "\d identity.idt001_user"
```

Undo the last batch (only while developing): `migris rollback local`.

## 5. Install Prisma

Prisma 7.10 at the time of writing. Pin the major (`@7`): npm's `latest` tag for `prisma` pointed at an 8.0 release candidate while `@prisma/client`/`@prisma/adapter-pg` were on 7.

```bash
pnpm --filter api add -D prisma@7 dotenv
```

- `prisma` (dev): the CLI (`init`, `db pull`, `generate`)
- `dotenv`: Prisma 7 no longer loads `.env` by itself; the generated config file imports `dotenv/config`

This fails with `ERR_PNPM_IGNORED_BUILDS` for `@prisma/engines` and `prisma` (they download the schema engine binary used by `db pull`). Approve both and reinstall, as in [setup.md](setup.md#err_pnpm_ignored_builds):

```bash
pnpm approve-builds
pnpm install
```

Runtime packages:

```bash
pnpm --filter api add @prisma/client@7 @prisma/adapter-pg@7
```

- `@prisma/client`: runtime used by the generated client
- `@prisma/adapter-pg`: since Prisma 7 the client talks to Postgres through a JS **driver adapter** (`pg`) instead of a Rust query engine

## 6. `prisma init`

```bash
pnpm --filter api exec prisma init --datasource-provider postgresql --no-skills --output ../src/generated/prisma
```

- `exec`: runs the `prisma` binary installed in `api`, with `apps/api` as working directory
- `--no-skills`: since 7.x `init` also installs AI-agent "skills" (`.claude/`, `.windsurf/`, `.agents/`, `skills-lock.json`). Not wanted here
- `--output ../src/generated/prisma`: where `generate` writes the client (relative to `prisma/schema.prisma`). Inside `src/` so Nest compiles it with the rest

Generated in `apps/api`:

| File | Purpose |
|---|---|
| `prisma/schema.prisma` | generator + datasource (models come from `db pull`) |
| `prisma7.config.ts` | Prisma CLI config: schema path and `DATABASE_URL` (loads `.env` via `dotenv/config`). The CLI finds it by this name |
| `.env` | `DATABASE_URL` (gitignored) |
| `.gitignore` | ignores `.env` and `/src/generated/prisma` |

In `prisma7.config.ts`, delete the `migrations: { path: "prisma/migrations" }` block: it's for Prisma Migrate, which linkly doesn't use.

In `apps/api/.env`:

```
DATABASE_URL="postgresql://postgres:postgres@localhost:5433/linkly"
```

Copy it to `apps/api/.env.example` (committed).

## 7. Adjust `schema.prisma`

```prisma
generator client {
  provider     = "prisma-client"
  output       = "../src/generated/prisma"
  moduleFormat = "cjs"
}

datasource db {
  provider = "postgresql"
  schemas  = ["identity"]
}
```

- `moduleFormat = "cjs"`: the API compiles to CommonJS (see [setup.md](setup.md)), so the generated client must too
- `schemas`: which Postgres schemas Prisma sees. Without it Prisma only reads `public`, where the only table is migris's `migrations` control table. Add each new module schema here

## 8. `db pull` and naming

```bash
pnpm --filter api exec prisma db pull
```

Introspects the database and writes the models into `schema.prisma`:

```prisma
model idt001_user {
  id            String    @id(map: "pk_idt001") @default(dbgenerated("uuidv7()")) @db.Uuid
  username      String    @unique(map: "uq_idt001_username") @db.VarChar(30)
  email         String    @unique(map: "uq_idt001_email") @db.VarChar(255)
  password_hash String
  name          String    @db.VarChar(150)
  created_at    DateTime  @default(now()) @db.Timestamptz(6)
  updated_at    DateTime? @db.Timestamptz(6)

  @@schema("identity")
}
```

Models and fields mirror the database names. Rename them to what the TypeScript code should use, keeping the DB names in `@@map`/`@map`:

```prisma
model User {
  id           String    @id(map: "pk_idt001") @default(dbgenerated("uuidv7()")) @db.Uuid
  username     String    @unique(map: "uq_idt001_username") @db.VarChar(30)
  email        String    @unique(map: "uq_idt001_email") @db.VarChar(255)
  passwordHash String    @map("password_hash")
  name         String    @db.VarChar(150)
  createdAt    DateTime  @default(now()) @map("created_at") @db.Timestamptz(6)
  updatedAt    DateTime? @updatedAt @map("updated_at") @db.Timestamptz(6)

  @@map("idt001_user")
  @@schema("identity")
}
```

- `@@map`/`@map`: TS name ↔ DB name, like `ToTable()`/`HasColumnName()` in EF Core
- `@updatedAt`: Prisma fills `updatedAt` on every update (the DB has no trigger for it)
- **Renames survive the next `db pull`**: Prisma reuses `@map`/`@@map`/`@updatedAt` from the existing schema and prints a warning listing what it "enriched". Expected, not an error
- `dbgenerated("uuidv7()")`: the DB generates the id; Prisma just omits it on insert

## 9. Generate the client

```bash
pnpm --filter api exec prisma generate
```

Writes the typed client to `apps/api/src/generated/prisma/` (gitignored: it's a build output). So a fresh clone gets it after `pnpm install`, add to `apps/api/package.json` scripts:

```json
"postinstall": "prisma generate"
```

`generate` is offline (reads only `schema.prisma`), so it works without the database running.

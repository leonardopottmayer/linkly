# Banco de dados (Postgres + migris + Prisma)

> English: [../en/database.md](../en/database.md)

## Decisões

- **Servidor:** o container local compartilhado `pottmayer-postgres` (Postgres 18, porta **5433** no host, gerenciado pelo `pottmayer-pgadmin` em http://localhost:15432). O linkly ganha um banco próprio, `linkly`, ao lado dos outros projetos. Nada de Postgres num docker-compose do linkly.
- **Mudanças de schema:** [migris](https://github.com/leonardopottmayer/migris), migrations em `.sql` puro, mesmo layout do pandora. **O Prisma Migrate não é usado.**
- **Prisma:** só o **client** (queries tipadas). O `schema.prisma` é gerado a partir do banco com `prisma db pull` (database-first).
- **O Prisma fica só em `apps/api`.** O app Next nunca acessa o banco; ele chama a API.

Fluxo para toda mudança de schema:

```
escrever up.sql/down.sql → migris apply local → prisma db pull → prisma generate
```

## Convenções (as mesmas do pandora)

- Um **schema por módulo** (`identity`, `links`, …), um módulo do migris por schema.
- Tabelas com **prefixo de código do módulo**: `identity.idt001_user`, `links.lnk001_link`.
- Nomes de constraints: `pk_<código>`, `uq_<código>_<coluna>`, `fk_<código>_<coluna>`.
- Chaves primárias: `uuid DEFAULT uuidv7()`. O Postgres 18 já tem `uuidv7()` nativo, então o linkly não precisa do `pgcrypto` + função `uuid_generate_v7()` do pandora.
- Valores tipo enum gravados com hífen (`pending-confirmation`), colunas em `snake_case`.

## 1. Criar o banco

```bash
docker exec pottmayer-postgres psql -U postgres -c "CREATE DATABASE linkly;"
```

Roda o `psql` dentro do container como o superusuário `postgres`. Equivale a criar pelo pgAdmin. Só local: o banco de dev usa o superusuário, como no pandora.

## 2. Configurar o migris

Tudo que é de banco fica em `migrations/` na raiz do repo:

```
migrations/
  config.json           → credenciais reais (no .gitignore)
  config.example.json   → template (versionado)
  migrations/<módulo>/<timestamp>-<nome>/...
  seed/                 → dados de seed locais (*.local.* no .gitignore)
```

Na raiz do repo:

```bash
mkdir migrations
cd migrations
migris init
```

O `migris init` (sem ambiente) só cria o template do `config.json` e a pasta `migrations/`. Substitua o `config.json` por:

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

Copie para `config.example.json` (versionado, para quem clonar saber o formato). Depois crie a tabela de controle do migris no banco:

```bash
migris init local
```

Adicione ao `.gitignore` da raiz:

```
migrations/config.json
migrations/seed/*.local.*
```

A pasta `migrations/migrations/` vazia não entra no commit (o git não versiona pastas vazias); ela aparece junto com a primeira migration.

## 3. Primeiras migrations: módulo `identity`

Dentro de `migrations/`:

```bash
migris create create-schema-identity --module identity
migris create create-table-idt001-user --module identity
```

O primeiro `--module` num projeto vazio coloca o migris em **modo modular** (daqui em diante toda migration fica dentro da pasta de um módulo, e o `--module` passa a ser obrigatório). Cada comando cria `migrations/identity/<timestamp>-<nome>/` com `.up.sql`/`.down.sql` vazios.

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

- O `username` é a URL da página pública (`linkly/leo`), então o `CHECK` garante minúsculas e caracteres seguros para URL **no banco**, independente do que a app fizer. Nomes reservados (`dashboard`, `r`, …) são regra da app, não do banco.
- A API converte o email para minúsculas antes de salvar, então um `UNIQUE` simples basta.
- Sem `created_by`/`updated_by` (o pandora tem): o próprio usuário se cadastra, não existe outro autor.
- Dados de perfil (bio, avatar, tema) não ficam aqui; pertencem ao módulo de links.

## 4. Aplicar

```bash
migris status local
migris apply local
```

O `status` lista as migrations pendentes; o `apply` roda todas em ordem de timestamp, como um lote (batch). Para conferir no banco:

```bash
docker exec pottmayer-postgres psql -U postgres -d linkly -c "\d identity.idt001_user"
```

Desfazer o último lote (só durante o desenvolvimento): `migris rollback local`.

## 5. Instalar o Prisma

Prisma 7.10 quando este doc foi escrito. Fixe a major (`@7`): a tag `latest` do `prisma` no npm apontava para um release candidate da 8.0, enquanto `@prisma/client`/`@prisma/adapter-pg` estavam na 7.

```bash
pnpm --filter api add -D prisma@7 dotenv
```

- `prisma` (dev): o CLI (`init`, `db pull`, `generate`)
- `dotenv`: o Prisma 7 não carrega mais o `.env` sozinho; o arquivo de config gerado importa `dotenv/config`

Isso falha com `ERR_PNPM_IGNORED_BUILDS` para `@prisma/engines` e `prisma` (eles baixam o binário da schema engine usado pelo `db pull`). Aprove os dois e reinstale, como no [setup.md](setup.md#err_pnpm_ignored_builds):

```bash
pnpm approve-builds
pnpm install
```

Pacotes de runtime:

```bash
pnpm --filter api add @prisma/client@7 @prisma/adapter-pg@7
```

- `@prisma/client`: runtime usado pelo client gerado
- `@prisma/adapter-pg`: desde o Prisma 7 o client fala com o Postgres por um **driver adapter** em JS (`pg`), e não mais por uma query engine em Rust

## 6. `prisma init`

```bash
pnpm --filter api exec prisma init --datasource-provider postgresql --no-skills --output ../src/generated/prisma
```

- `exec`: roda o binário `prisma` instalado no `api`, com `apps/api` como diretório de trabalho
- `--no-skills`: desde a 7.x o `init` também instala "skills" para agentes de IA (`.claude/`, `.windsurf/`, `.agents/`, `skills-lock.json`). Não queremos isso aqui
- `--output ../src/generated/prisma`: onde o `generate` escreve o client (relativo a `prisma/schema.prisma`). Fica dentro de `src/` para o Nest compilar junto com o resto

Gerado em `apps/api`:

| Arquivo | Para quê |
|---|---|
| `prisma/schema.prisma` | generator + datasource (os models vêm do `db pull`) |
| `prisma7.config.ts` | config do CLI do Prisma: caminho do schema e `DATABASE_URL` (carrega o `.env` via `dotenv/config`). O CLI o encontra por esse nome |
| `.env` | `DATABASE_URL` (no .gitignore) |
| `.gitignore` | ignora `.env` e `/src/generated/prisma` |

No `prisma7.config.ts`, apague o bloco `migrations: { path: "prisma/migrations" }`: ele é do Prisma Migrate, que o linkly não usa.

No `apps/api/.env`:

```
DATABASE_URL="postgresql://postgres:postgres@localhost:5433/linkly"
```

Copie para `apps/api/.env.example` (versionado).

## 7. Ajustar o `schema.prisma`

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

- `moduleFormat = "cjs"`: a API compila para CommonJS (ver [setup.md](setup.md)), então o client gerado também precisa
- `schemas`: quais schemas do Postgres o Prisma enxerga. Sem isso ele só lê o `public`, onde a única tabela é a `migrations` de controle do migris. Adicione aqui cada schema de módulo novo

## 8. `db pull` e nomes

```bash
pnpm --filter api exec prisma db pull
```

Inspeciona o banco e escreve os models no `schema.prisma`:

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

Models e campos espelham os nomes do banco. Renomeie para os nomes que o código TypeScript vai usar, mantendo os nomes do banco em `@@map`/`@map`:

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

- `@@map`/`@map`: nome no TS ↔ nome no banco, como `ToTable()`/`HasColumnName()` no EF Core
- `@updatedAt`: o Prisma preenche `updatedAt` em todo update (o banco não tem trigger para isso)
- **Os renomes sobrevivem ao próximo `db pull`**: o Prisma reaproveita `@map`/`@@map`/`@updatedAt` do schema existente e mostra um aviso listando o que ele "enriqueceu". É esperado, não é erro
- `dbgenerated("uuidv7()")`: o banco gera o id; o Prisma só omite o campo no insert

## 9. Gerar o client

```bash
pnpm --filter api exec prisma generate
```

Escreve o client tipado em `apps/api/src/generated/prisma/` (no .gitignore: é saída de build). Para quem clonar o repo ter o client depois do `pnpm install`, adicione aos scripts do `apps/api/package.json`:

```json
"postinstall": "prisma generate"
```

O `generate` é offline (só lê o `schema.prisma`), então funciona sem o banco rodando.

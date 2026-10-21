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

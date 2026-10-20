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

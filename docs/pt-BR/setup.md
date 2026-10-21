# Setup inicial

Como o monorepo do linkly foi criado, passo a passo.

> English: [../en/setup.md](../en/setup.md)

## Pré-requisitos

- Node.js 24+
- Docker
- pnpm (instalado no passo 1)

## 1. Instalar o pnpm

```bash
npm i -g pnpm
pnpm -v
```

O pnpm guarda cada versão de pacote uma única vez num store global e cria hard links nos projetos (como a `~/.nuget/packages`). Além disso, um projeto só consegue importar o que o próprio `package.json` declara.

## 2. Inicializar a raiz do monorepo

Dentro de `linkly/`:

```bash
git init
pnpm init
```

A raiz não é um app, ela só coordena os apps. Edite o `package.json` gerado:

- adicione `"private": true` (impede publicar a raiz no npm por acidente)
- apague o campo `"main"` (a raiz não exporta nada)

O pnpm 12 também adiciona `packageManager`/`devEngines`, que fixam a versão do pnpm para quem clonar o repo. Pode deixar. O `"type": "module"` só afeta arquivos `.js` da raiz; cada app tem o próprio `package.json`.

Efeito colateral do `devEngines`: rodar `npm` dentro do repo falha com `EBADDEVENGINES`. É intencional; use `pnpm` (ex.: `pnpm view <pacote> version` no lugar de `npm view`).

## 3. Declarar o workspace

Crie o `pnpm-workspace.yaml` na raiz:

```yaml
packages:
  - "apps/*"
  - "packages/*"
```

Toda pasta dentro de `apps/` ou `packages/` com um `package.json` vira um projeto do workspace (o papel que o `.slnx` tem no .NET).

## 4. `.gitignore`

Crie o `.gitignore` na raiz:

```
node_modules
dist
.next
.env
.turbo
*.tsbuildinfo
```

O `*.tsbuildinfo` é o cache de build incremental do TypeScript (criado no primeiro `nest build`/`start:dev`).

## 5. Criar a API (Nest)

Dentro de `linkly/`:

```bash
pnpm dlx @nestjs/cli new api --directory apps/api --package-manager pnpm --skip-git --strict
```

- `pnpm dlx`: executa o CLI do Nest sem instalar globalmente (o `npx` do pnpm)
- `new api`: projeto chamado `api`
- `--directory apps/api`: cria dentro do workspace em vez de `./api`
- `--skip-git`: não roda outro `git init` (o repo já existe na raiz)
- `--strict`: TypeScript estrito (`strictNullChecks` etc.), parecido com o `<Nullable>enable</Nullable>` do .NET

O CLI pergunta se quer configurar o `@nestjs/observe` (SaaS de tracing/métricas da própria Nest). Responda **n**: é um serviço externo com limite no plano grátis, e observabilidade pode entrar depois com OpenTelemetry, se for preciso.

Ele também pergunta o sistema de módulos: **CJS**. O código-fonte usa `import`/`export` de qualquer jeito; isso só muda a saída compilada. Com CJS não é preciso colocar `.js` nos imports relativos nem configurar o Jest para ESM, e a maioria dos docs/exemplos do Nest assume CJS. Pacotes só-ESM continuam funcionando porque o Node 24 suporta `require()` de ESM.

### `ERR_PNPM_IGNORED_BUILDS`

O pnpm 12 bloqueia scripts de instalação das dependências por padrão e **falha** a instalação quando algum é pulado. Os arquivos do projeto são gerados, só a instalação falha:

```
Ignored build scripts: @parcel/watcher@2.6.0, unrs-resolver@1.12.2
```

Os dois vêm do Jest (`pnpm why @parcel/watcher unrs-resolver` mostra isso): um file watcher nativo e um resolvedor de módulos nativo. Aprove e reinstale:

```bash
pnpm approve-builds
pnpm install
```

O `approve-builds` é interativo (espaço seleciona, enter confirma) e grava a lista de permitidos no `pnpm-workspace.yaml`, então fica versionado e ninguém precisa aprovar de novo:

```yaml
allowBuilds:
  '@parcel/watcher': true
  unrs-resolver: true
```
 Só aprove pacotes que você reconhece: bloquear scripts de instalação é uma defesa contra ataques de supply chain.

## 6. Rodar a API

```bash
pnpm --filter api start:dev
```

O `--filter api` roda o script `start:dev` só no projeto `api`. Abra http://localhost:3000 → `Hello World!`.

O que o CLI gerou está explicado em [nest-basics.md](nest-basics.md).

## 7. Mudar a API para a porta 3001

O Next também usa a 3000 por padrão. Em `apps/api/src/main.ts`:

```ts
await app.listen(process.env.PORT ?? 3001);
```

## 8. Mover o `.gitattributes` para a raiz

O CLI criou `apps/api/.gitattributes` (`* text=auto eol=lf`), que só vale dentro de `apps/api`. Mova para a raiz para que o repo inteiro seja gravado com quebras de linha LF (importa no Windows).

Como o arquivo ainda não está versionado, basta movê-lo pelo explorer, ou:

```bash
mv apps/api/.gitattributes .gitattributes
```

## 9. `.editorconfig` e formatação

Crie o `.editorconfig` na raiz para que todo editor (VS Code, Visual Studio, Rider…) grave os arquivos do jeito que o Prettier espera:

```ini
root = true

[*]
charset = utf-8
end_of_line = lf
indent_style = space
indent_size = 2
insert_final_newline = true
trim_trailing_whitespace = true
```

Por quê: no Windows os arquivos foram gravados com quebra de linha CRLF e alguns com indentação de 4 espaços. O git guarda tudo em LF de qualquer forma (`.gitattributes`), mas o Prettier verifica os arquivos no disco e acusa. Para corrigir os arquivos existentes:

```bash
pnpm --filter api format
```

(O VS Code precisa da extensão *EditorConfig*; Visual Studio e Rider suportam nativamente.)

## Estrutura alvo

```
apps/web         → Next (App Router)
apps/api         → Nest + Prisma
packages/shared  → schemas zod compartilhados entre web e api
migrations/      → migrations SQL do migris (ver database.md)
```

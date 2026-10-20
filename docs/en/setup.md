# Initial setup

How the linkly monorepo was bootstrapped, step by step.

> Português: [../pt-BR/setup.md](../pt-BR/setup.md)

## Prerequisites

- Node.js 24+
- Docker
- pnpm (installed in step 1)

## 1. Install pnpm

```bash
npm i -g pnpm
pnpm -v
```

pnpm keeps each package version once in a global store and hard-links it into projects (like `~/.nuget/packages`), and only lets a project import what its own `package.json` declares.

## 2. Initialize the monorepo root

From `linkly/`:

```bash
git init
pnpm init
```

The root is not an app, it only coordinates the apps. Edit the generated `package.json`:

- add `"private": true` (prevents accidentally publishing the root to npm)
- remove the `"main"` field (the root exports nothing)

pnpm 12 also writes `packageManager`/`devEngines`, pinning the pnpm version for anyone who clones the repo. Keep them. `"type": "module"` only affects `.js` files at the root; each app has its own `package.json`.

Side effect of `devEngines`: running `npm` inside the repo fails with `EBADDEVENGINES`. That's intended; use `pnpm` (e.g. `pnpm view <pkg> version` instead of `npm view`).

## 3. Declare the workspace

Create `pnpm-workspace.yaml` at the root:

```yaml
packages:
  - "apps/*"
  - "packages/*"
```

Any folder under `apps/` or `packages/` with a `package.json` becomes a workspace project (the role a `.slnx` plays in .NET).

## 4. `.gitignore`

Create `.gitignore` at the root:

```
node_modules
dist
.next
.env
.turbo
*.tsbuildinfo
```

`*.tsbuildinfo` is TypeScript's incremental build cache (created by the first `nest build`/`start:dev`).

## 5. Create the API (Nest)

From `linkly/`:

```bash
pnpm dlx @nestjs/cli new api --directory apps/api --package-manager pnpm --skip-git --strict
```

- `pnpm dlx`: runs the Nest CLI without installing it globally (pnpm's `npx`)
- `new api`: project named `api`
- `--directory apps/api`: creates it inside the workspace instead of `./api`
- `--skip-git`: no nested `git init` (the repo already lives at the root)
- `--strict`: strict TypeScript (`strictNullChecks` etc.), like `<Nullable>enable</Nullable>` in .NET

The CLI asks whether to set up `@nestjs/observe` (Nest's hosted tracing/metrics SaaS). Answer **n**: it's a third-party service with a free-tier limit, and observability can be added later with OpenTelemetry if needed.

It also asks for the module system: **CJS**. The source is written with `import`/`export` either way; this only changes the compiled output. CJS avoids `.js` extensions in relative imports and Jest ESM config, and most Nest docs/examples assume it. ESM-only packages still work because Node 24 supports `require()` of ESM.

### `ERR_PNPM_IGNORED_BUILDS`

pnpm 12 blocks dependency install scripts by default and **fails** the install when one is skipped. The project files are generated, only the install fails:

```
Ignored build scripts: @parcel/watcher@2.6.0, unrs-resolver@1.12.2
```

Both come from Jest (`pnpm why @parcel/watcher unrs-resolver` shows it): a native file watcher and a native module resolver. Approve them and reinstall:

```bash
pnpm approve-builds
pnpm install
```

`approve-builds` is interactive (space to select, enter to confirm) and records the allow-list in `pnpm-workspace.yaml`, so it's versioned and nobody has to approve again:

```yaml
allowBuilds:
  '@parcel/watcher': true
  unrs-resolver: true
```
 Only approve packages you recognize: blocking install scripts is a defense against supply-chain attacks.

## 6. Run the API

```bash
pnpm --filter api start:dev
```

`--filter api` runs the `start:dev` script only in the `api` project. Open http://localhost:3000 → `Hello World!`.

What the CLI generated is explained in [nest-basics.md](nest-basics.md).

## 7. Move the API to port 3001

Next also defaults to 3000. In `apps/api/src/main.ts`:

```ts
await app.listen(process.env.PORT ?? 3001);
```

## 8. Move `.gitattributes` to the root

The CLI created `apps/api/.gitattributes` (`* text=auto eol=lf`), which only applies inside `apps/api`. Move it to the root so the whole repo is stored with LF line endings (matters on Windows).

The file isn't tracked yet, so just move it in the explorer, or:

```bash
mv apps/api/.gitattributes .gitattributes
```

## Target layout

```
apps/web         → Next (App Router)
apps/api         → Nest + Prisma
packages/shared  → zod schemas shared by web and api
migrations/      → migris SQL migrations (see database.md)
```

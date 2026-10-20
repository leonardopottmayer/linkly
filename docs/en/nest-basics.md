# Nest basics

What `nest new` generated in `apps/api` and how the pieces fit, with .NET analogies.

> Português: [../pt-BR/nest-basics.md](../pt-BR/nest-basics.md)

Versions at creation: Nest 12, TypeScript 6, Jest 30, oxlint.

## The building blocks

```
src/
  main.ts            → entry point (Program.cs)
  app.module.ts      → module: groups controllers + providers
  app.controller.ts  → HTTP endpoints
  app.service.ts     → business logic (injectable)
  app.controller.spec.ts → unit test
test/
  app.e2e-spec.ts    → end-to-end test (boots the app, calls HTTP via supertest)
```

### `main.ts`

```ts
const app = await NestFactory.create(AppModule);
await app.listen(process.env.PORT ?? 3001);
```

Builds the app from the **root module** and starts the HTTP server (Express underneath, via `@nestjs/platform-express`). Equivalent to `WebApplication.CreateBuilder()` + `app.Run()`. Global things (validation pipe, CORS, prefix) get configured here.

### Module (`@Module`)

```ts
@Module({
  imports: [],                 // other modules whose exported providers I use
  controllers: [AppController],
  providers: [AppService],     // registered in this module's DI container
})
export class AppModule {}
```

The unit of organization. Every feature becomes a module (`LinksModule`, `AuthModule`…) imported by `AppModule`. Closest .NET analogy: an `AddLinksModule(this IServiceCollection)` extension, but with **encapsulation**: a provider is private to its module unless listed in `exports`.

### Controller (`@Controller`)

```ts
@Controller()            // route prefix, e.g. @Controller('links')
export class AppController {
  constructor(private readonly appService: AppService) {}

  @Get()                 // GET /
  getHello(): string { ... }
}
```

Same role as an ASP.NET controller. `private readonly appService` in the constructor is TypeScript shorthand: declares the field and assigns it.

### Provider (`@Injectable`)

`AppService` is a provider: a class the DI container creates and injects. Default lifetime is **singleton** (one instance for the whole app), unlike ASP.NET where scoped is the common choice.

Nest resolves dependencies by the **constructor parameter type**. That only works because of `emitDecoratorMetadata` in `tsconfig.json` + the `reflect-metadata` package: TypeScript erases types at runtime, and the decorator metadata keeps them.

## Generated config

| File | Purpose |
|---|---|
| `nest-cli.json` | CLI config (`sourceRoot`, delete `dist` before build) |
| `tsconfig.json` | `strict: true` from `--strict`; `experimentalDecorators` + `emitDecoratorMetadata` required by Nest; `module: nodenext` → format comes from the nearest `package.json` (no `"type"` there → CJS) |
| `tsconfig.build.json` | what `nest build` compiles (excludes tests) |
| `.oxlintrc.json` | linter config. Recent Nest uses **oxlint** (Rust, much faster) instead of ESLint |
| `.prettierrc` | formatter config |
| `jest.config.ts` | unit test config |

## Scripts (`apps/api/package.json`)

Run from the root with `pnpm --filter api <script>`:

- `start:dev`: watch mode, recompiles and restarts on save
- `build`: compiles to `dist/`
- `test` / `test:e2e`: unit / end-to-end tests
- `lint`: oxlint

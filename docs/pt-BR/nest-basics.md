# Fundamentos do Nest

O que o `nest new` gerou em `apps/api` e como as peças se encaixam, com analogias ao .NET.

> English: [../en/nest-basics.md](../en/nest-basics.md)

Versões na criação: Nest 12, TypeScript 6, Jest 30, oxlint.

## As peças

```
src/
  main.ts            → ponto de entrada (Program.cs)
  app.module.ts      → módulo: agrupa controllers + providers
  app.controller.ts  → endpoints HTTP
  app.service.ts     → lógica de negócio (injetável)
  app.controller.spec.ts → teste unitário
test/
  app.e2e-spec.ts    → teste end-to-end (sobe a app e chama HTTP via supertest)
```

### `main.ts`

```ts
const app = await NestFactory.create(AppModule);
await app.listen(process.env.PORT ?? 3001);
```

Monta a app a partir do **módulo raiz** e sobe o servidor HTTP (Express por baixo, via `@nestjs/platform-express`). Equivale ao `WebApplication.CreateBuilder()` + `app.Run()`. Configurações globais (validation pipe, CORS, prefixo) entram aqui.

### Módulo (`@Module`)

```ts
@Module({
  imports: [],                 // outros módulos cujos providers exportados eu uso
  controllers: [AppController],
  providers: [AppService],     // registrados no container de DI deste módulo
})
export class AppModule {}
```

A unidade de organização. Cada feature vira um módulo (`LinksModule`, `AuthModule`…) importado pelo `AppModule`. A analogia mais próxima no .NET é uma extensão `AddLinksModule(this IServiceCollection)`, mas com **encapsulamento**: um provider é privado do módulo, a menos que esteja em `exports`.

### Controller (`@Controller`)

```ts
@Controller()            // prefixo de rota, ex.: @Controller('links')
export class AppController {
  constructor(private readonly appService: AppService) {}

  @Get()                 // GET /
  getHello(): string { ... }
}
```

Mesmo papel do controller do ASP.NET. O `private readonly appService` no construtor é um atalho do TypeScript: declara o campo e já atribui.

### Provider (`@Injectable`)

`AppService` é um provider: uma classe que o container de DI cria e injeta. O lifetime padrão é **singleton** (uma instância para a app toda), diferente do ASP.NET, onde scoped é o mais comum.

O Nest resolve as dependências pelo **tipo do parâmetro do construtor**. Isso só funciona por causa do `emitDecoratorMetadata` no `tsconfig.json` + o pacote `reflect-metadata`: o TypeScript apaga os tipos em runtime, e os metadados dos decorators os preservam.

## Configuração gerada

| Arquivo | Para quê |
|---|---|
| `nest-cli.json` | config do CLI (`sourceRoot`, apagar `dist` antes do build) |
| `tsconfig.json` | `strict: true` vindo do `--strict`; `experimentalDecorators` + `emitDecoratorMetadata` exigidos pelo Nest; `module: nodenext` → o formato vem do `package.json` mais próximo (sem `"type"` lá → CJS) |
| `tsconfig.build.json` | o que o `nest build` compila (exclui testes) |
| `.oxlintrc.json` | config do linter. O Nest recente usa **oxlint** (em Rust, bem mais rápido) no lugar do ESLint |
| `.prettierrc` | config do formatador |
| `jest.config.ts` | config dos testes unitários |

## Scripts (`apps/api/package.json`)

Rode da raiz com `pnpm --filter api <script>`:

- `start:dev`: modo watch, recompila e reinicia ao salvar
- `build`: compila para `dist/`
- `test` / `test:e2e`: testes unitários / end-to-end
- `lint`: oxlint

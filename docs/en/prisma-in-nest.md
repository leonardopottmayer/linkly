# Prisma in Nest

How the API reaches the database: config loading, a `PrismaService` shared by every module, and a first query.

> Português: [../pt-BR/prisma-in-nest.md](../pt-BR/prisma-in-nest.md)

Prerequisite: [database.md](database.md) (database, migrations, generated client).

## 1. Load `.env` at runtime: `@nestjs/config`

`prisma7.config.ts` loads `.env` only for the Prisma **CLI**. The running API needs `DATABASE_URL` too.

```bash
pnpm --filter api add @nestjs/config
```

In `src/app.module.ts`:

```ts
import { ConfigModule } from '@nestjs/config';

@Module({
  imports: [ConfigModule.forRoot({ isGlobal: true })],
  ...
})
```

- `forRoot()` reads `.env` into `process.env` and registers `ConfigService`
- `isGlobal: true`: `ConfigService` can be injected anywhere without importing `ConfigModule` again
- Same role as `IConfiguration` in .NET. Plain Node alternative: `process.loadEnvFile()`; `@nestjs/config` is the Nest idiom and gives an injectable service

## 2. `PrismaModule` + `PrismaService`

Generate with the Nest CLI (it creates the files and wires them up):

```bash
pnpm --filter api exec nest g module prisma
pnpm --filter api exec nest g service prisma --no-spec
```

- `g module prisma` → `src/prisma/prisma.module.ts`, added to `AppModule.imports`
- `g service prisma` → `src/prisma/prisma.service.ts`, added to `PrismaModule.providers`
- `--no-spec`: no test file (nothing to unit test in a thin wrapper)

`src/prisma/prisma.service.ts`:

```ts
import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from '../generated/prisma/client';

@Injectable()
export class PrismaService
  extends PrismaClient
  implements OnModuleInit, OnModuleDestroy
{
  constructor(config: ConfigService) {
    super({
      adapter: new PrismaPg({
        connectionString: config.getOrThrow<string>('DATABASE_URL'),
      }),
    });
  }

  async onModuleInit() {
    await this.$connect();
  }

  async onModuleDestroy() {
    await this.$disconnect();
  }
}
```

- `extends PrismaClient`: the service **is** the client, so modules call `this.prisma.user.findMany()` directly. Like injecting a `DbContext`
- `PrismaPg`: the Prisma 7 driver adapter (a `pg` connection pool underneath)
- `getOrThrow`: fails at startup if `DATABASE_URL` is missing, instead of on the first query
- `onModuleInit` / `$connect`: connects at boot so a wrong URL or a stopped database fails fast. Without it Prisma connects lazily on the first query
- `onModuleDestroy` / `$disconnect`: closes the pool on shutdown
- Singleton (Nest's default lifetime): one client and one pool for the whole app

`src/prisma/prisma.module.ts`:

```ts
import { Global, Module } from '@nestjs/common';
import { PrismaService } from './prisma.service';

@Global()
@Module({
  providers: [PrismaService],
  exports: [PrismaService],
})
export class PrismaModule {}
```

- `exports`: providers are private to their module unless exported
- `@Global()`: feature modules can inject `PrismaService` without listing `PrismaModule` in their `imports`. Use sparingly; infrastructure like the DB client is the classic case

## 3. First query: `GET /users/count`

```bash
pnpm --filter api exec nest g module users
pnpm --filter api exec nest g controller users --no-spec
pnpm --filter api exec nest g service users --no-spec
```

`src/users/users.service.ts`:

```ts
import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class UsersService {
  constructor(private readonly prisma: PrismaService) {}

  count() {
    return this.prisma.user.count();
  }
}
```

`src/users/users.controller.ts`:

```ts
import { Controller, Get } from '@nestjs/common';
import { UsersService } from './users.service';

@Controller('users')
export class UsersController {
  constructor(private readonly usersService: UsersService) {}

  @Get('count')
  count() {
    return this.usersService.count();
  }
}
```

- `this.prisma.user`: the delegate for the `User` model (lowercase model name). Typed from `schema.prisma`
- The controller returns a `Promise<number>`; Nest awaits it and serializes the result

## 4. Run

```bash
pnpm --filter api start:dev
```

Open http://localhost:3001/users/count → `0`.

### Pitfall: forgetting `return`

```ts
async count() {
  this.prisma.user.count(); // query runs, result is discarded
}
```

The method returns `undefined`, so Nest answers `200` with an empty body. The linter catches it (`typescript/no-floating-promises` is on in `.oxlintrc.json`):

```bash
pnpm --filter api lint
```

Run it before testing by hand.

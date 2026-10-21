# Prisma no Nest

Como a API chega no banco: carregamento de config, um `PrismaService` compartilhado por todos os módulos e uma primeira query.

> English: [../en/prisma-in-nest.md](../en/prisma-in-nest.md)

Pré-requisito: [database.md](database.md) (banco, migrations, client gerado).

## 1. Carregar o `.env` em runtime: `@nestjs/config`

O `prisma7.config.ts` carrega o `.env` só para o **CLI** do Prisma. A API rodando também precisa do `DATABASE_URL`.

```bash
pnpm --filter api add @nestjs/config
```

Em `src/app.module.ts`:

```ts
import { ConfigModule } from '@nestjs/config';

@Module({
  imports: [ConfigModule.forRoot({ isGlobal: true })],
  ...
})
```

- `forRoot()` lê o `.env` para o `process.env` e registra o `ConfigService`
- `isGlobal: true`: o `ConfigService` pode ser injetado em qualquer lugar sem importar o `ConfigModule` de novo
- Mesmo papel do `IConfiguration` no .NET. Alternativa só com Node: `process.loadEnvFile()`; o `@nestjs/config` é o jeito idiomático do Nest e entrega um serviço injetável

## 2. `PrismaModule` + `PrismaService`

Gere com o CLI do Nest (ele cria os arquivos e já faz as ligações):

```bash
pnpm --filter api exec nest g module prisma
pnpm --filter api exec nest g service prisma --no-spec
```

- `g module prisma` → `src/prisma/prisma.module.ts`, adicionado em `AppModule.imports`
- `g service prisma` → `src/prisma/prisma.service.ts`, adicionado em `PrismaModule.providers`
- `--no-spec`: sem arquivo de teste (não há o que testar unitariamente num wrapper fino)

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

- `extends PrismaClient`: o serviço **é** o client, então os módulos chamam `this.prisma.user.findMany()` direto. Como injetar um `DbContext`
- `PrismaPg`: o driver adapter do Prisma 7 (um pool de conexões do `pg` por baixo)
- `getOrThrow`: falha na subida se o `DATABASE_URL` não existir, em vez de falhar na primeira query
- `onModuleInit` / `$connect`: conecta na subida, então uma URL errada ou um banco parado falha cedo. Sem isso o Prisma conecta de forma preguiçosa, na primeira query
- `onModuleDestroy` / `$disconnect`: fecha o pool no desligamento
- Singleton (o lifetime padrão do Nest): um client e um pool para a app toda

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

- `exports`: providers são privados do módulo, a menos que sejam exportados
- `@Global()`: os módulos de feature podem injetar o `PrismaService` sem listar o `PrismaModule` nos `imports`. Use com moderação; infraestrutura como o client do banco é o caso clássico

## 3. Primeira query: `GET /users/count`

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

- `this.prisma.user`: o delegate do model `User` (nome do model em minúscula). Tipado a partir do `schema.prisma`
- O controller retorna uma `Promise<number>`; o Nest espera a promise e serializa o resultado

## 4. Rodar

```bash
pnpm --filter api start:dev
```

Abra http://localhost:3001/users/count → `0`.

### Armadilha: esquecer o `return`

```ts
async count() {
  this.prisma.user.count(); // a query roda, o resultado é descartado
}
```

O método retorna `undefined`, então o Nest responde `200` com corpo vazio. O linter pega isso (`typescript/no-floating-promises` está ligado no `.oxlintrc.json`):

```bash
pnpm --filter api lint
```

Rode antes de testar na mão.

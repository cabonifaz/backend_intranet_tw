# AGENTS.md

This file provides guidance to AI coding agents (Claude Code, GitHub Copilot, Codex, and others) when working with code in this repository.

## Project Status

`ms-facturacion` is a newly scaffolded ASP.NET Core 10 Web API (single commit, default `dotnet new webapi` template). It has no custom business logic yet — only the template's `WeatherForecastController`. It is part of the broader Maximilian3.0 project, presumably intended to become the invoicing ("facturación") microservice, but no domain code, database access, or auth has been implemented yet. This project does **not** follow a Controller/Handler/DAO layering — see Architecture below for the layering to use here instead.

## Naming Conventions

- Name variables, classes, and functions/methods in **Spanish** (e.g., `ClienteRepositorio`, `CalcularTotalFactura`, not `CustomerRepository`, `CalculateInvoiceTotal`).
- Never use a reserved keyword of the language as an identifier name.

## Architecture

Hexagonal (Ports & Adapters) / Clean Architecture, expressed with modern .NET 10 idioms (this project targets `net10.0` with nullable + implicit usings already enabled):

- **Entidades (Entities)** — plain C# classes with identity, no dependency on ASP.NET Core, EF Core, or any package outside the BCL. Use `record`/`record struct` for value objects and DTOs instead, since those want structural equality.
- **Casos de Uso (Use Cases)** — one class per use case. Depend only on **Puertos (Ports)** — interfaces injected via constructor (use C# primary constructors). No reference to `Microsoft.AspNetCore.*` or a concrete infrastructure package. Methods are `async Task<T>` and accept a `CancellationToken`.
- **Puertos (Ports)** — interfaces in the application layer defining what a use case needs (repositories, gateways, clock, external services). Adapters implement these; use cases never see a concrete adapter type.
- **Adaptadores (Adapters)**:
  - *Driving/primary*: ASP.NET Core Controllers — translate HTTP ↔ use case input/output only, no business logic.
  - *Driven/secondary*: EF Core / ADO.NET repositories, HTTP/S3 clients, etc. — implement the port interfaces.
- Wiring happens in `Program.cs` via the built-in DI container (`builder.Services.AddScoped<IPuerto, Adaptador>()`) — no third-party DI container needed. Controllers and use cases only ever depend on the registered interface.
- As the codebase grows past a single project, split along these boundaries (e.g. `ms_facturacion.Dominio`, `.Aplicacion` [casos de uso + puertos], `.Infraestructura` [adaptadores], and the existing `ms-facturacion` Web API project for controllers), so the dependency direction (Infraestructura → Aplicacion → Dominio) is enforced by project references, not just convention.

## Database Access

- **Being migrated to MySQL** — the persistence Adaptadores are being ported from `Microsoft.Data.SqlClient` to `MySqlConnector`; the rest of this section still describes the SQL Server-era setup until that migration is complete.
- SQL Server is the only supported database.
- All database access goes through **stored procedures** — never write plain/inline SQL in C# (no `SELECT`, `INSERT`, `UPDATE`, `DELETE` statements in code).
- Every query or command is a stored procedure call, e.g. `EXEC SP_ObtenerFactura`, `EXEC SP_InsertarFactura`, executed with `CommandType.StoredProcedure` (ADO.NET `SqlCommand`/`Microsoft.Data.SqlClient`). If EF Core is used, only via mapped stored-procedure calls (`FromSqlRaw("EXEC SP_...")`/`ExecuteSqlRaw`) — never `DbSet` LINQ queries that generate ad-hoc SQL.
- Stored procedure names follow `SP_<Verbo><Entidad>` (Spanish, per Naming Conventions), e.g. `SP_ObtenerFacturasPorCliente`.
- Only the persistence **Adaptador** (the driven adapter implementing a repository **Puerto**) may reference `Microsoft.Data.SqlClient`/ADO.NET or issue stored procedure calls — Casos de Uso and Puertos stay unaware of SQL Server specifics.

### Table Schema

- Every table uses soft delete (`SoftDelete BIT NOT NULL DEFAULT 0`) plus an audit block: `UsuCre`, `FchCre`, `UsuMod`, `FchMod`.
- `CREATE TABLE` scripts declare **only** the `PRIMARY KEY CLUSTERED` on the identity column. No `FOREIGN KEY`, no `UNIQUE` constraint, no `CREATE INDEX`/`CREATE NONCLUSTERED INDEX`.
  - No FKs/indexes: relational integrity and query performance are handled at the stored-procedure/app layer, not enforced by SQL Server.
  - No `UNIQUE` on business keys (RUC, Serie, Código, etc.): because rows are soft-deleted rather than removed, a DB-level `UNIQUE` would block reusing a business key whose only prior row was soft-deleted. Instead, the inserting/updating stored procedure checks for duplicates itself, scoped to `WHERE SoftDelete = 0`.

### Response Envelope

Every stored procedure follows the same response contract, and the persistence Adaptador must honor it consistently:

- The first result set returned by the stored procedure always has exactly two columns: `IdTipoMensaje` (int) and `Mensaje` (string). `IdTipoMensaje` is `1` for a business rule violation, `2` for success, `3` for a system/uncontrolled error.
- The Adaptador reads this header row first. Only when `IdTipoMensaje == 2` does it advance to subsequent result sets to read actual data; on `1` or `3`, no further result sets are read and the data payload stays empty/default.
- If the stored procedure returns no header row at all, the Adaptador defaults to `IdTipoMensaje = 3` with a fixed fallback message — a missing header must never be treated as success.
- Any ADO.NET exception (connection failure, cast error, etc.) is caught inside the Adaptador and mapped to `IdTipoMensaje = 3, Mensaje = ex.Message` — the Adaptador never lets a raw exception escape to the Caso de Uso.
- Casos de Uso and controllers forward this envelope (`IdTipoMensaje`/`Mensaje`/data) as-is; they never invent or override `IdTipoMensaje` themselves — that value always originates from the stored procedure or from the Adaptador's own fallback/exception handling.

## Commands

```bash
cd ms-facturacion
dotnet restore
dotnet build
dotnet run --project ms-facturacion    # runs on http://localhost:5221 (https://localhost:7164)
dotnet watch --project ms-facturacion  # hot-reload dev server
dotnet publish -c Release
```

No test project exists in the solution yet.

## Structure

- `ms-facturacion.sln` — single-project solution.
- `ms-facturacion/ms-facturacion.csproj` — targets `net10.0`, nullable + implicit usings enabled, root namespace `ms_facturacion`.
- `ms-facturacion/Program.cs` — minimal hosting model; registers controllers and OpenAPI (`/openapi` in Development via `MapOpenApi()`), no auth/CORS/DB wiring configured.
- `ms-facturacion/Controllers/` — API controllers (currently only the template's `WeatherForecastController`).
- `ms-facturacion/appsettings.json` / `appsettings.Development.json` — only default logging config; no connection strings or external service settings yet.
- `ms-facturacion/ms-facturacion.http` — REST Client scratch file for manual endpoint testing.

## Git

Commit messages follow Conventional Commits (`type: description`) — single-line, one sentence summarizing the change. Write the description in Spanish; only the description, keep the conventional-commit type (`feat`, `fix`, etc.) untranslated. Do not add a Claude/AI co-author trailer.

### Branching

Three principal branches, in ascending order of stability: `staging` (development), `preprod`, and `main` (production).

- Never commit or push directly to `main` or `preprod`.
- `staging` is the base branch for ongoing development.
- To work on a ticket, create a branch named after the assigned ticket off `staging`, push it, and open a pull request targeting `staging`.
- Before pushing, always update the branch from `staging` first.

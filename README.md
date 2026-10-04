# MCP Meets Database: ShiftSwap

Demo app for the talk *Give Your App a Database Brain*. Employees schedule vacation and swap shifts. SQL Server holds the rules in stored procedures; Data API builder exposes them as GraphQL and MCP tools; a Blazor app and an AI agent both use the same tools.

Start with [`plan.md`](plan.md).

```
sql/   schema, seed, procedures, grants       run in order
dab/   Data API builder config                dab start
web/   Blazor Server app with chat agent      dotnet run
```

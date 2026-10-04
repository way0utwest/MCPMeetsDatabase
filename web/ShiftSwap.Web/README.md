# ShiftSwap.Web

Blazor Server (.NET 8). Talks to Data API builder only; never to SQL Server directly.

## Run locally (no Entra, DAB in Simulator mode)

1. Start SQL Server and run `sql/*.sql` (see `/plan.md`).
2. `cd dab && dab configure --runtime.host.authentication.provider Simulator && dab start`
3. Set Azure OpenAI secrets:
   ```
   dotnet user-secrets set "AzureOpenAI:Endpoint" "https://<res>.openai.azure.com/"
   dotnet user-secrets set "AzureOpenAI:ApiKey" "<key>"
   ```
4. `appsettings.Development.json` sets `Dev:FakeEmail` to `alice.chen@contoso.com`. Change it to act as someone else (try `maria.lopez@contoso.com` for a manager; in Simulator mode also pass `X-MS-API-ROLE: manager`, which the app does when the fake user is in the manager role — for dev, set `Dev:FakeIsManager` if you add it, or test approvals through MCP Inspector).
5. `dotnet run`, open https://localhost:7101.

When `Dev:FakeEmail` is set the app skips Entra token acquisition and `[Authorize]` still applies, so for a fully anonymous dev loop also remove `@attribute [Authorize]` from `_Imports.razor` or add a dev auth handler. Simplest: keep Entra on and only use `FakeEmail` to override which employee you act as.

## Run with Entra

Fill `AzureAd` and `Dab:Scope` in `appsettings.json`, set `AzureAd:ClientSecret` via user-secrets, clear `Dev:FakeEmail`, and run DAB with the `EntraId` provider.

## Where things are

| File | Role |
|---|---|
| `Services/CurrentUser.cs` | Email and role from the token. The only place identity is read. |
| `Services/DabGraphQlClient.cs` | GraphQL calls to DAB, one helper per stored procedure, email pinned. |
| `Services/ShiftAgent.cs` | MCP client to DAB, tools wrapped with email pinned, Azure OpenAI with function invocation, tool-call log. |
| `Components/Pages/*.razor` | Schedule, TeamSchedule, Vacations, Approvals, Swaps, Chat. |

## Not yet done

- No compile has been run on this scaffold. Package versions are wildcards; the MCP C# SDK is preview and its type names (`HttpClientTransport`, `McpClient.CreateAsync`, `McpClientTool.CallAsync`) may have shifted. Fix against the current README.
- `PinnedEmailTool` overrides `AIFunction` directly. If your `Microsoft.Extensions.AI` version has `DelegatingAIFunction`, use that instead.
- Chat history lives in the scoped `ShiftAgent` for the life of the circuit. Persist it if you need it across reloads.
- Rate limiting on `/chat` and Application Insights wiring are listed in the plan, not implemented.

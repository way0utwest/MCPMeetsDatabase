# Data API builder for ShiftSwap

DAB 2.0+ is required (custom MCP tools from stored procedures). Install: `dotnet tool install -g Microsoft.DataApiBuilder`.

## Environment

| Variable | Example |
|---|---|
| `SHIFTSWAP_CONN` | `Server=localhost;Database=ShiftSwap;User Id=dab_app;Password=Dab_strong_Passw0rd;TrustServerCertificate=True` |
| `SHIFTSWAP_API_AUDIENCE` | `api://<dab-api-app-registration-client-id>` |
| `SHIFTSWAP_ISSUER` | `https://login.microsoftonline.com/<tenant-id>/v2.0` |

## Run

```bash
dab validate
dab start
```

Endpoints: `http://localhost:5000/api`, `/graphql`, `/mcp`.

## Entra ID setup

Two app registrations:

1. **ShiftSwap API** (this DAB instance). Expose an API scope `access_as_user`. Define app roles `ShiftSwap.Manager`. Application ID URI becomes `SHIFTSWAP_API_AUDIENCE`.
2. **ShiftSwap Web** (the Blazor app). Delegated permission to `ShiftSwap API / access_as_user`. The web app acquires a token for that scope and forwards it as `Authorization: Bearer` on every GraphQL and MCP call.

Roles: DAB assigns `authenticated` to any valid token. To act as `manager`, the client must send `X-MS-API-ROLE: manager` and the token must carry that role claim. The Blazor app sets the header only when the user has the `ShiftSwap.Manager` app role.

## Local development without Entra

```bash
dab configure --runtime.host.authentication.provider Simulator
dab start --mcp-stdio role:authenticated      # or role:manager
```

With the Simulator provider every request is treated as authenticated; use `X-MS-API-ROLE` to pick the role. Set `Dev:FakeEmail` in the web app's `appsettings.Development.json` so the app has an email to pin.

## Test with MCP Inspector

```bash
npx -y @modelcontextprotocol/inspector http://localhost:5000/mcp
```

Expect `describe_entities`, `read_records`, and the eleven `snake_case` custom tools. With `anonymous` nothing is listed; with `authenticated` everything except `vacation_approve`; with `manager` all of them.

## Notes

- `inputSchema.properties` is currently empty for custom tools in DAB 2.0; agents rely on the `description` plus `describe_entities` to learn parameters. Descriptions in `dab-config.json` therefore name every parameter and its format.
- `execute-entity` is disabled globally so the generic proc runner is not exposed; only named custom tools are.
- Table write tools are disabled globally. The only way to change data is through a procedure.

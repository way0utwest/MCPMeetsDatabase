using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Identity.Web;

namespace ShiftSwap.Web.Services;

/// <summary>
/// Thin GraphQL client over Data API builder. Forwards the user's bearer token and role header,
/// and pins the acting employee's email into every procedure call.
/// </summary>
public sealed class DabGraphQlClient
{
    private readonly HttpClient _http;
    private readonly CurrentUser _user;
    private readonly ITokenAcquisition _tokens;
    private readonly IConfiguration _cfg;
    private readonly ILogger<DabGraphQlClient> _log;

    public DabGraphQlClient(HttpClient http, CurrentUser user, ITokenAcquisition tokens, IConfiguration cfg, ILogger<DabGraphQlClient> log)
    {
        _http = http; _user = user; _tokens = tokens; _cfg = cfg; _log = log;
    }

    // ---------- public typed helpers ----------

    public Task<JsonArray> ScheduleGetAsync(DateOnly? from = null, DateOnly? to = null) =>
        ExecAsync("Schedule_Get", new { Email = _user.Email, FromDate = from?.ToString("yyyy-MM-dd"), ToDate = to?.ToString("yyyy-MM-dd") },
            "ShiftId ShiftDate DayName StartTime EndTime Location JobName InPendingSwap");

    public Task<JsonArray> ScheduleGetTeamAsync(DateOnly? from = null, DateOnly? to = null) =>
        ExecAsync("Schedule_GetTeam", new { Email = _user.Email, FromDate = from?.ToString("yyyy-MM-dd"), ToDate = to?.ToString("yyyy-MM-dd") },
            "ShiftId ShiftDate DayName StartTime EndTime Location JobName AssignedEmail AssignedName IsOpen IsMine InPendingSwap");

    public Task<JsonArray> VacationListAsync(bool includeTeam = false) =>
        ExecAsync("Vacation_List", new { Email = _user.Email, IncludeTeam = includeTeam },
            "VacationId EmployeeEmail DisplayName StartDate EndDate Status Reason RequestedAt DecidedBy DecidedAt DecisionNotes IsMine");

    public Task<JsonArray> VacationRequestAsync(DateOnly start, DateOnly end, string? reason) =>
        ExecAsync("Vacation_Request", new { Email = _user.Email, StartDate = start.ToString("yyyy-MM-dd"), EndDate = end.ToString("yyyy-MM-dd"), Reason = reason },
            "VacationId StartDate EndDate Status", mutation: true);

    public Task<JsonArray> VacationCancelAsync(int vacationId) =>
        ExecAsync("Vacation_Cancel", new { Email = _user.Email, VacationId = vacationId }, "VacationId Status", mutation: true);

    public Task<JsonArray> VacationApproveAsync(int vacationId, bool approve, string? notes) =>
        ExecAsync("Vacation_Approve", new { ManagerEmail = _user.Email, VacationId = vacationId, Approve = approve, Notes = notes },
            "VacationId EmployeeEmail Status DecidedAt", mutation: true);

    public Task<JsonArray> SwapListAsync() =>
        ExecAsync("Swap_List", new { Email = _user.Email },
            "SwapId Status MyRole RequesterApproved CounterpartyApproved RequesterName RequesterShiftDate RequesterStart RequesterEnd CounterpartyName CounterpartyShiftDate CounterpartyStart CounterpartyEnd JobName CreatedAt");

    public Task<JsonArray> SwapRequestAsync(int myShiftId, int theirShiftId) =>
        ExecAsync("Swap_Request", new { Email = _user.Email, MyShiftId = myShiftId, TheirShiftId = theirShiftId }, "SwapId Status", mutation: true);

    public Task<JsonArray> SwapApproveAsync(int swapId) =>
        ExecAsync("Swap_Approve", new { Email = _user.Email, SwapId = swapId }, "SwapId Status RequesterApproved CounterpartyApproved", mutation: true);

    public Task<JsonArray> SwapDeclineAsync(int swapId) =>
        ExecAsync("Swap_Decline", new { Email = _user.Email, SwapId = swapId }, "SwapId Status", mutation: true);

    public Task<JsonArray> SwapCancelAsync(int swapId) =>
        ExecAsync("Swap_Cancel", new { Email = _user.Email, SwapId = swapId }, "SwapId Status", mutation: true);

    // ---------- plumbing ----------

    /// <summary>
    /// DAB exposes a stored procedure entity "Foo" as query/mutation "executeFoo(args)" returning a list of rows.
    /// </summary>
    private async Task<JsonArray> ExecAsync(string entity, object args, string fields, bool mutation = false)
    {
        var argsJson = JsonSerializer.SerializeToNode(args, new JsonSerializerOptions { DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull })!.AsObject();
        var argList = string.Join(", ", argsJson.Select(kv => $"{kv.Key}: {kv.Value!.ToJsonString()}"));
        var op = mutation ? "mutation" : "query";
        var gql = $"{op} {{ execute{entity}({argList}) {{ {fields} }} }}";

        var data = await PostAsync(gql);
        return data?[$"execute{entity}"]?.AsArray() ?? new JsonArray();
    }

    private async Task<JsonObject?> PostAsync(string query, object? variables = null)
    {
        var req = new HttpRequestMessage(HttpMethod.Post, "/graphql")
        {
            Content = JsonContent.Create(new { query, variables })
        };

        if (string.IsNullOrEmpty(_cfg["Dev:FakeEmail"]))
        {
            var token = await _tokens.GetAccessTokenForUserAsync(new[] { _cfg["Dab:Scope"]! });
            req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        }
        req.Headers.Add("X-MS-API-ROLE", _user.DabRole);

        var resp = await _http.SendAsync(req);
        var body = await resp.Content.ReadFromJsonAsync<JsonObject>();

        if (body?["errors"] is JsonArray errors && errors.Count > 0)
        {
            var msg = errors[0]?["message"]?.GetValue<string>() ?? "GraphQL error";
            _log.LogWarning("DAB error for {User}: {Message}", _user.Email, msg);
            throw new DabException(msg);
        }
        resp.EnsureSuccessStatusCode();
        return body?["data"]?.AsObject();
    }
}

public sealed class DabException : Exception
{
    public DabException(string message) : base(message) { }
}

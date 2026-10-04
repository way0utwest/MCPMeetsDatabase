using System.Security.Claims;

namespace ShiftSwap.Web.Services;

/// <summary>
/// The single source of "who is acting". Email comes from the Entra token, never from user input.
/// Every call to DAB (GraphQL or MCP) pins this email into the procedure's Email parameter.
/// </summary>
public sealed class CurrentUser
{
    private readonly IHttpContextAccessor _http;
    private readonly IConfiguration _cfg;

    public CurrentUser(IHttpContextAccessor http, IConfiguration cfg)
    {
        _http = http;
        _cfg = cfg;
    }

    private ClaimsPrincipal? Principal => _http.HttpContext?.User;

    public bool IsAuthenticated => Principal?.Identity?.IsAuthenticated == true || !string.IsNullOrEmpty(_cfg["Dev:FakeEmail"]);

    public string Email
    {
        get
        {
            var fake = _cfg["Dev:FakeEmail"];
            if (!string.IsNullOrEmpty(fake)) return fake;

            var p = Principal ?? throw new InvalidOperationException("No signed-in user.");
            return p.FindFirst("preferred_username")?.Value
                ?? p.FindFirst(ClaimTypes.Email)?.Value
                ?? p.FindFirst("email")?.Value
                ?? throw new InvalidOperationException("Token has no email claim.");
        }
    }

    public string DisplayName => Principal?.FindFirst("name")?.Value ?? Email;

    public bool IsManager => Principal?.IsInRole("ShiftSwap.Manager") == true;

    /// <summary>Role name DAB expects in X-MS-API-ROLE.</summary>
    public string DabRole => IsManager ? "manager" : "authenticated";
}

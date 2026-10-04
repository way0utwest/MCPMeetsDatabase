using Azure.AI.OpenAI;
using Microsoft.AspNetCore.Authentication.OpenIdConnect;
using Microsoft.Extensions.AI;
using Microsoft.Identity.Web;
using Microsoft.Identity.Web.UI;
using ShiftSwap.Web.Components;
using ShiftSwap.Web.Services;

var builder = WebApplication.CreateBuilder(args);
var cfg = builder.Configuration;

// ---- Auth: Entra ID sign-in, plus on-behalf-of token for the DAB API scope ----
builder.Services
    .AddAuthentication(OpenIdConnectDefaults.AuthenticationScheme)
    .AddMicrosoftIdentityWebApp(cfg.GetSection("AzureAd"))
    .EnableTokenAcquisitionToCallDownstreamApi(new[] { cfg["Dab:Scope"]! })
    .AddInMemoryTokenCaches();

builder.Services.AddAuthorization(o =>
{
    o.AddPolicy("Manager", p => p.RequireRole("ShiftSwap.Manager"));
});
builder.Services.AddCascadingAuthenticationState();
builder.Services.AddControllersWithViews().AddMicrosoftIdentityUI();

// ---- Blazor ----
builder.Services.AddRazorComponents().AddInteractiveServerComponents();
builder.Services.AddHttpContextAccessor();

// ---- App services ----
builder.Services.AddScoped<CurrentUser>();
builder.Services.AddHttpClient<DabGraphQlClient>(c => c.BaseAddress = new Uri(cfg["Dab:BaseUrl"]!));
builder.Services.AddScoped<ShiftAgent>();

// ---- Model client (Azure OpenAI through Microsoft.Extensions.AI) ----
builder.Services.AddSingleton<IChatClient>(sp =>
{
    var endpoint = new Uri(cfg["AzureOpenAI:Endpoint"]!);
    var deployment = cfg["AzureOpenAI:Deployment"]!;
    var apiKey = cfg["AzureOpenAI:ApiKey"];

    AzureOpenAIClient aoai = string.IsNullOrEmpty(apiKey)
        ? new AzureOpenAIClient(endpoint, new Azure.Identity.DefaultAzureCredential())
        : new AzureOpenAIClient(endpoint, new System.ClientModel.ApiKeyCredential(apiKey));

    return aoai.GetChatClient(deployment).AsIChatClient()
        .AsBuilder()
        .UseFunctionInvocation()      // the agent loop: model picks tool -> we call MCP -> result back -> repeat
        .UseLogging(sp.GetRequiredService<ILoggerFactory>())
        .Build();
});

var app = builder.Build();

if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Error", createScopeForErrors: true);
    app.UseHsts();
}

app.UseHttpsRedirection();
app.UseStaticFiles();
app.UseAntiforgery();
app.UseAuthentication();
app.UseAuthorization();

app.MapControllers();
app.MapRazorComponents<App>().AddInteractiveServerRenderMode();

app.Run();

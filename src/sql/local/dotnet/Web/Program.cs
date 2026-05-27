using Microsoft.AspNetCore.Components.Web;
using Microsoft.AspNetCore.Components.WebAssembly.Hosting;
using Microsoft.FluentUI.AspNetCore.Components;
using ZavaLiveSite.Web;

var builder = WebAssemblyHostBuilder.CreateDefault(args);
builder.RootComponents.Add<App>("#app");
builder.RootComponents.Add<HeadOutlet>("head::after");

builder.Services.AddScoped(sp => new HttpClient { BaseAddress = new Uri(builder.HostEnvironment.BaseAddress) });

// HTTP client targeting the DAB REST endpoint. Blazor WASM runs in the
// browser, so it cannot read Aspire's server-injected service discovery
// env vars. We pin DAB to host port 8765 in apphost.cs and default to it.
//
// Beat 5 swaps the active DAB by URL query string ?dab=local|cloud.
// Local maps to DabBaseUrl (default http://localhost:8765).
// Cloud maps to DabBaseUrl_Cloud (default http://localhost:8766) -- the
// second DAB pointed at Hyperscale + AOAI. Until that DAB is provisioned
// (P3 in the source notes), `?dab=cloud` will simply 404 against :8766; the
// page still renders correctly because the polling loop swallows network
// errors and the footer flips to the cloud branding.
var dabLocal = builder.Configuration["DabBaseUrl"]       ?? "http://localhost:8765";
var dabCloud = builder.Configuration["DabBaseUrl_Cloud"] ?? "http://localhost:8766";
builder.Services.AddSingleton(new DabEndpoints(dabLocal, dabCloud));
builder.Services.AddHttpClient("dab", c => c.BaseAddress = new Uri(dabLocal));

builder.Services.AddFluentUIComponents();

await builder.Build().RunAsync();

/// <summary>
/// Holds the two DAB base URLs the page can switch between via ?dab=local|cloud.
/// Injected into pages so they can pick the active URL on each fetch.
/// </summary>
public sealed record DabEndpoints(string Local, string Cloud);

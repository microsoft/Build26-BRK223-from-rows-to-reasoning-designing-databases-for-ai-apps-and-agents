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
// env vars. We pin DAB to host port 8765 in apphost.cs and default to it
// for local runs. Cloud hosting sets DabBaseUrl via appsettings.Production.json.
var dabBaseUrl = builder.Configuration["DabBaseUrl"] ?? "http://localhost:8765";
builder.Services.AddHttpClient("dab", c => c.BaseAddress = new Uri(dabBaseUrl));

builder.Services.AddFluentUIComponents();

await builder.Build().RunAsync();

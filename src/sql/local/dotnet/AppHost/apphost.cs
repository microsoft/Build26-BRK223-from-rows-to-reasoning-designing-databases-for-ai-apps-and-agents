#:sdk Aspire.AppHost.Sdk@13.2.4

// Dashboard disabled — demo shows the Blazor `web` resource on stage,
// not the Aspire orchestration UI. Launch via `dotnet run apphost.cs`
// (the `aspire` CLI insists on a dashboard URL and exits if disabled).
var builder = DistributedApplication.CreateBuilder(new DistributedApplicationOptions
{
    Args = args,
    DisableDashboard = true
});

// SQL connection string for the DAB container. Targets the azsql-zavalivesite
// container via host.docker.internal on a non-default port (14330) chosen
// to avoid the Windows MSSQLSERVER DAC listener on 1434. Works from any
// docker network (including Aspire's per-run session network) because it
// routes through the host gateway.
//
// Read from $env:BRK223_SQL_CONNECTION_STRING so no credentials are
// checked into source. Set before `dotnet run apphost.cs`, e.g.:
//   $env:BRK223_SQL_CONNECTION_STRING =
//     "Server=host.docker.internal,14330;Database=zavalivesitedb;" +
//     "User Id=sqladmin;Password=<from env>;TrustServerCertificate=True;" +
//     "Encrypt=True;Command Timeout=180"
//
// Command Timeout=180 — raised from the SqlClient default of 30s because
// dbo.usp_GenerateMitigation calls sp_invoke_external_rest_endpoint to a
// local phi-4-mini composer that takes ~95s end-to-end. With the default
// 30s timeout, the MCP tool call from the Copilot CLI fails before the
// composer returns, and the agent falls back to reading stale
// ProposedMitigation. Microsoft.Data.SqlClient honors `Command Timeout`
// as a connection-string keyword since v2.1; sets the default
// SqlCommand.CommandTimeout for every command opened on the connection.
var sqlConnValue = Environment.GetEnvironmentVariable("BRK223_SQL_CONNECTION_STRING")
    ?? throw new InvalidOperationException(
        "BRK223_SQL_CONNECTION_STRING is not set. Set it before launching AppHost. " +
        "See the comment above this line for the expected format.");
var sqlConn = builder.AddParameter("sqlconn", sqlConnValue, secret: true);

// Data API Builder — single container serves REST (/api/*) for the Web app
// and MCP (/mcp) for the VS Code agent. dab-config.json is bind-mounted
// from the AppHost folder to /App/dab-config.json (DAB's default path).
var dab = builder.AddContainer("dab", "mcr.microsoft.com/azure-databases/data-api-builder", "2.0.0-rc")
    .WithEnvironment("MSSQL_CONNECTION_STRING", sqlConn)
    .WithBindMount("dab-config.json", "/App/dab-config.json", isReadOnly: true)
    .WithHttpEndpoint(port: 8765, targetPort: 5000, name: "http")
    .WithEndpoint("http", e => { e.Port = 8765; e.TargetPort = 5000; e.IsProxied = false; });

// Blazor WASM standalone front-end. WithReference injects the DAB http
// endpoint URL into configuration as services:dab:http:0, which Program.cs
// reads to set the HttpClient base address. WithHttpEndpoint pins the
// web port to 8080 so demo.md / fallback recordings reference a stable URL.
// Newer Aspire auto-creates an "http" endpoint for AddProject from
// launchSettings, so we override that endpoint's port instead of adding
// a second one (which throws "Endpoint with name 'http' already exists").
builder.AddProject("web", "../Web/ZavaLiveSite.Web.csproj")
    .WithReference(dab.GetEndpoint("http"))
    .WithEndpoint("http", e => { e.Port = 8080; e.IsProxied = false; });

builder.Build().Run();

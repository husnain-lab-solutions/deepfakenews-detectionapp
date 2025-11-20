using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using System.Text;
using WebApplication1.Data;
using WebApplication1.Models;
using WebApplication1.Services;

var builder = WebApplication.CreateBuilder(args);

// Add services
builder.Services.Configure<JwtOptions>(builder.Configuration.GetSection("Jwt"));
builder.Services.Configure<PythonServiceOptions>(builder.Configuration.GetSection("PythonService"));

builder.Services.AddDbContext<ApplicationDbContext>(options =>
    options.UseSqlite(builder.Configuration.GetConnectionString("DefaultConnection")));

builder.Services.AddIdentity<ApplicationUser, IdentityRole>()
    .AddEntityFrameworkStores<ApplicationDbContext>()
    .AddDefaultTokenProviders();

builder.Services.AddScoped<IJwtTokenService, JwtTokenService>();
builder.Services.AddHttpClient<IPythonPredictionClient, PythonPredictionClient>(client =>
{
    // Allow slower ML responses / first-load warmup without tripping client timeouts
    client.Timeout = TimeSpan.FromSeconds(180);
});

var jwtSection = builder.Configuration.GetSection("Jwt").Get<JwtOptions>();
// Allow overriding JWT key via environment variable JWT_KEY (for CI/secrets)
var envJwtKey = Environment.GetEnvironmentVariable("JWT_KEY");
if (!string.IsNullOrWhiteSpace(envJwtKey) && jwtSection != null)
{
    jwtSection.Key = envJwtKey;
    // Ensure IOptions<JwtOptions> seen by JwtTokenService also reflects override
    builder.Services.PostConfigure<JwtOptions>(opts => opts.Key = envJwtKey);
}
var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtSection!.Key));

builder.Services.AddAuthentication(options =>
{
    options.DefaultAuthenticateScheme = JwtBearerDefaults.AuthenticationScheme;
    options.DefaultChallengeScheme = JwtBearerDefaults.AuthenticationScheme;
}).AddJwtBearer(options =>
{
    options.TokenValidationParameters = new TokenValidationParameters
    {
        ValidateIssuer = true,
        ValidateAudience = true,
        ValidateIssuerSigningKey = true,
        ValidIssuer = jwtSection.Issuer,
        ValidAudience = jwtSection.Audience,
        IssuerSigningKey = key
    };
});

// Require authentication by default for controllers/endpoints. Individual actions can opt-out
// using [AllowAnonymous]. This enforces auth on API endpoints (and endpoints-based routing)
// while static files are protected client-side by the auth-guard script below.
builder.Services.AddAuthorization(options =>
{
    options.FallbackPolicy = new Microsoft.AspNetCore.Authorization.AuthorizationPolicyBuilder()
        .RequireAuthenticatedUser()
        .Build();
});
builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();
builder.Services.AddCors(opts =>
{
    opts.AddPolicy("AllowAll", policy =>
        policy.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod());
});

var app = builder.Build();

using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
    db.Database.EnsureCreated(); // For demo; use migrations later
}

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseCors("AllowAll");
// Serve static files from wwwroot (e.g., /demo/index.html)
app.UseDefaultFiles();
app.UseStaticFiles();
// Only force HTTPS outside Development; in dev this can cause noisy warnings when no HTTPS port is configured.
if (!app.Environment.IsDevelopment())
{
    app.UseHttpsRedirection();
}
app.UseAuthentication();
app.UseAuthorization();

app.MapControllers();

// Redirect root to demo page for convenience
// Serve the new landing page at root
// Keep root publicly redirecting to index (static page guarded client-side)
app.MapGet("/", () => Results.Redirect("/index.html")).AllowAnonymous();

app.Run();

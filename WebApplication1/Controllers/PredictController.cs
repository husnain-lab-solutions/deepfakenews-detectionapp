using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using System.Net.Http;
using System.Security.Claims;
using WebApplication1.Data;
using WebApplication1.DTOs;
using WebApplication1.Models;
using WebApplication1.Services;

namespace WebApplication1.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class PredictController : ControllerBase
{
    private readonly IPythonPredictionClient _python;
    private readonly ApplicationDbContext _db;
    private readonly string _mlBaseUrl;
    private readonly IHttpClientFactory _httpClientFactory;

    public PredictController(IPythonPredictionClient python, ApplicationDbContext db, IOptions<PythonServiceOptions> opts, IHttpClientFactory httpClientFactory)
    {
        _python = python;
        _db = db;
        _mlBaseUrl = opts.Value.BaseUrl?.TrimEnd('/') ?? string.Empty;
        _httpClientFactory = httpClientFactory;
    }

    private string GetUserId() => User.FindFirstValue(ClaimTypes.NameIdentifier) ?? User.FindFirstValue(ClaimTypes.Name) ?? "";

    [HttpPost("text")]
    public async Task<ActionResult<PredictionResponse>> PredictText([FromBody] TextPredictRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Text)) return BadRequest("Text is required");
        // Pre-flight ML health (short timeout); if not healthy, fail fast to avoid long retries downstream.
        if (!await MlHealthyAsync())
        {
            return StatusCode(503, new PredictionResponse("ServiceUnavailable: ML health check failed", 0f));
        }
        PredictionResponse? result = null;
        try
        {
            result = await _python.PredictTextAsync(request.Text);
        }
        catch (Exception ex)
        {
            // Log and return a helpful error for CI diagnostics
            Console.WriteLine($"PredictText error: {ex}");
            var msg = string.IsNullOrWhiteSpace(ex.Message) ? ex.GetType().Name : $"{ex.GetType().Name}: {ex.Message}";
            return StatusCode(503, new PredictionResponse($"ServiceUnavailable: {msg}", 0f));
        }
        var userId = GetUserId();
        await SavePrediction(userId, "text", request.Text.Length > 128 ? request.Text[..128] : request.Text, result);
        return Ok(result);
    }

    [HttpPost("image")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(10_000_000)]
    public async Task<ActionResult<PredictionResponse>> PredictImage([FromForm] ImagePredictRequest request)
    {
        var file = request.File;
        if (file == null || file.Length == 0) return BadRequest("Image file is required");
        using var stream = file.OpenReadStream();
        if (!await MlHealthyAsync())
        {
            return StatusCode(503, new PredictionResponse("ServiceUnavailable: ML health check failed", 0f));
        }
        PredictionResponse? result = null;
        try
        {
            result = await _python.PredictImageAsync(stream, file.FileName);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"PredictImage error: {ex}");
            var msg = string.IsNullOrWhiteSpace(ex.Message) ? ex.GetType().Name : $"{ex.GetType().Name}: {ex.Message}";
            return StatusCode(503, new PredictionResponse($"ServiceUnavailable: {msg}", 0f));
        }
        var userId = GetUserId();
        await SavePrediction(userId, "image", file.FileName, result);
        return Ok(result);
    }

    private async Task SavePrediction(string userId, string contentType, string? input, PredictionResponse result)
    {
        var pred = new Prediction
        {
            UserId = userId,
            ContentType = contentType,
            InputPathOrText = input,
            Result = result.Label,
            Confidence = result.Confidence,
            Timestamp = DateTime.UtcNow
        };
        _db.Predictions.Add(pred);
        await _db.SaveChangesAsync();
    }

    private async Task<bool> MlHealthyAsync()
    {
        if (string.IsNullOrWhiteSpace(_mlBaseUrl)) return false;
        try
        {
            var client = _httpClientFactory.CreateClient();
            client.Timeout = TimeSpan.FromSeconds(3);
            var resp = await client.GetAsync(_mlBaseUrl + "/health");
            return resp.IsSuccessStatusCode;
        }
        catch { return false; }
    }
}

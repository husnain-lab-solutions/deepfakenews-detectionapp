using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Options;
using WebApplication1.DTOs;

namespace WebApplication1.Services;

public class PythonServiceOptions
{
    public string BaseUrl { get; set; } = string.Empty;
}

public interface IPythonPredictionClient
{
    Task<PredictionResponse> PredictTextAsync(string text);
    Task<PredictionResponse> PredictImageAsync(Stream imageStream, string fileName);
}

public class PythonPredictionClient : IPythonPredictionClient
{
    private readonly HttpClient _httpClient;

    private async Task<HttpResponseMessage> PostWithRetriesAsync(string path, HttpContent content, int maxAttempts = 5, int initialDelayMs = 500)
    {
        Exception? lastEx = null;
        for (int attempt = 1; attempt <= maxAttempts; attempt++)
        {
            try
            {
                var resp = await _httpClient.PostAsync(path, content);
                return resp; // May still be non-success; caller will EnsureSuccessStatusCode()
            }
            catch (HttpRequestException ex)
            {
                lastEx = ex;
                // Brief health probe before next retry (except final attempt)
                if (attempt < maxAttempts)
                {
                    try
                    {
                        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(2));
                        using var healthResp = await _httpClient.GetAsync("/health", cts.Token);
                        // If health succeeds we still retry the original POST immediately
                    }
                    catch { }
                    await Task.Delay(initialDelayMs * attempt); // Linear backoff
                }
            }
        }
        throw lastEx ?? new HttpRequestException("Unknown connection failure to ML service.");
    }

    public PythonPredictionClient(HttpClient httpClient, IOptions<PythonServiceOptions> opts)
    {
        _httpClient = httpClient;
        _httpClient.BaseAddress = new Uri(opts.Value.BaseUrl);
    }

    public async Task<PredictionResponse> PredictTextAsync(string text)
    {
        var payload = new { text };
        var content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");
        var resp = await PostWithRetriesAsync("/predict-text", content);
        resp.EnsureSuccessStatusCode();
        var json = await resp.Content.ReadAsStringAsync();
        var result = JsonSerializer.Deserialize<PredictionResponse>(json, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
        return result ?? new PredictionResponse("Unknown", 0f);
    }

    public async Task<PredictionResponse> PredictImageAsync(Stream imageStream, string fileName)
    {
        using var form = new MultipartFormDataContent();
        var streamContent = new StreamContent(imageStream);
        streamContent.Headers.ContentType = new MediaTypeHeaderValue("image/jpeg");
        form.Add(streamContent, "file", fileName);
        var resp = await PostWithRetriesAsync("/predict-image", form);
        resp.EnsureSuccessStatusCode();
        var json = await resp.Content.ReadAsStringAsync();
        var result = JsonSerializer.Deserialize<PredictionResponse>(json, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
        return result ?? new PredictionResponse("Unknown", 0f);
    }
}

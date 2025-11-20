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

    public PythonPredictionClient(HttpClient httpClient, IOptions<PythonServiceOptions> opts)
    {
        _httpClient = httpClient;
        _httpClient.BaseAddress = new Uri(opts.Value.BaseUrl);
    }

    public async Task<PredictionResponse> PredictTextAsync(string text)
    {
        var payload = new { text };
        var content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");
        HttpResponseMessage resp;
        try
        {
            resp = await _httpClient.PostAsync("/predict-text", content);
        }
        catch (HttpRequestException)
        {
            // Brief retry in case ML service is still warming up
            await Task.Delay(TimeSpan.FromSeconds(2));
            resp = await _httpClient.PostAsync("/predict-text", content);
        }
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
        HttpResponseMessage resp;
        try
        {
            resp = await _httpClient.PostAsync("/predict-image", form);
        }
        catch (HttpRequestException)
        {
            await Task.Delay(TimeSpan.FromSeconds(2));
            resp = await _httpClient.PostAsync("/predict-image", form);
        }
        resp.EnsureSuccessStatusCode();
        var json = await resp.Content.ReadAsStringAsync();
        var result = JsonSerializer.Deserialize<PredictionResponse>(json, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
        return result ?? new PredictionResponse("Unknown", 0f);
    }
}

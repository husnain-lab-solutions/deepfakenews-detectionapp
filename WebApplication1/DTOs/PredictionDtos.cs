using Microsoft.AspNetCore.Http;

namespace WebApplication1.DTOs;

public record TextPredictRequest(string Text);
public record PredictionResponse(string Label, float Confidence);

// For multipart/form-data image upload so Swagger can generate a schema
public class ImagePredictRequest
{
	public IFormFile File { get; set; } = default!;
}

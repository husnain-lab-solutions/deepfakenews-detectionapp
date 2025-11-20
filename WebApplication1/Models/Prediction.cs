using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace WebApplication1.Models;

public class Prediction
{
    [Key]
    public int PredictionId { get; set; }

    [Required]
    public string UserId { get; set; } = default!;

    [Required]
    public string ContentType { get; set; } = default!; // text | image | video

    // For demo, store only short snippet or file path (optional)
    public string? InputPathOrText { get; set; }

    [Required]
    public string Result { get; set; } = default!; // Real | Fake

    public float Confidence { get; set; }

    public DateTime Timestamp { get; set; } = DateTime.UtcNow;
}

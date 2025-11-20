using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using System.Security.Claims;
using WebApplication1.Data;

namespace WebApplication1.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class HistoryController : ControllerBase
{
    private readonly ApplicationDbContext _db;

    public HistoryController(ApplicationDbContext db)
    {
        _db = db;
    }

    private string GetUserId() => User.FindFirstValue(ClaimTypes.NameIdentifier) ?? User.FindFirstValue(ClaimTypes.Name) ?? "";

    [HttpGet]
    public async Task<IActionResult> Get()
    {
        var userId = GetUserId();
        var items = await _db.Predictions
            .Where(p => p.UserId == userId)
            .OrderByDescending(p => p.Timestamp)
            .Select(p => new
            {
                p.PredictionId,
                p.ContentType,
                p.Result,
                p.Confidence,
                p.Timestamp,
                p.InputPathOrText
            })
            .ToListAsync();
        return Ok(items);
    }
}

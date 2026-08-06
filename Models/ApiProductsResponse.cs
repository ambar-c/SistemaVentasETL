using System.Text.Json.Serialization;

namespace SistemaVentasETL.Models;

public class ApiProductsResponse
{
    [JsonPropertyName("products")]
    public List<ApiProduct> Products { get; set; } = [];

    [JsonPropertyName("total")]
    public int Total { get; set; }

    [JsonPropertyName("skip")]
    public int Skip { get; set; }

    [JsonPropertyName("limit")]
    public int Limit { get; set; }
}
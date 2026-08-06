using System.Text.Json.Serialization;

namespace SistemaVentasETL.Models;

public class ApiProduct
{
    [JsonPropertyName("id")]
    public int ProductID { get; set; }

    [JsonPropertyName("title")]
    public string ProductName { get; set; } = string.Empty;

    [JsonPropertyName("category")]
    public string Category { get; set; } = string.Empty;

    [JsonPropertyName("price")]
    public decimal Price { get; set; }

    [JsonPropertyName("stock")]
    public int Stock { get; set; }
}
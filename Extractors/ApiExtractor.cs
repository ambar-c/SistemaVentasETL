using SistemaVentasETL.Interfaces;
using SistemaVentasETL.Models;
using System.Net.Http.Json;

namespace SistemaVentasETL.Extractors;

public class ApiExtractor : IExtractor<ApiProduct>
{
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly IConfiguration _configuration;
    private readonly ILogger<ApiExtractor> _logger;

    public ApiExtractor(
        IHttpClientFactory httpClientFactory,
        IConfiguration configuration,
        ILogger<ApiExtractor> logger)
    {
        _httpClientFactory = httpClientFactory;
        _configuration = configuration;
        _logger = logger;
    }

    public async Task<IReadOnlyList<ApiProduct>> ExtractAsync(
        CancellationToken cancellationToken = default)
    {
        string endpoint =
            _configuration["ApiSettings:ProductsEndpoint"]
            ?? throw new InvalidOperationException(
                "No se encontró ApiSettings:ProductsEndpoint.");

        _logger.LogInformation(
            "Iniciando extracción de productos desde la API REST.");

        try
        {
            HttpClient client =
                _httpClientFactory.CreateClient("ProductsApi");

            using HttpResponseMessage response =
                await client.GetAsync(
                    endpoint,
                    cancellationToken);

            _logger.LogInformation(
                "La API respondió con el código HTTP {StatusCode}.",
                (int)response.StatusCode);

            response.EnsureSuccessStatusCode();

            ApiProductsResponse? apiResponse =
                await response.Content
                    .ReadFromJsonAsync<ApiProductsResponse>(
                        cancellationToken: cancellationToken);

            if (apiResponse is null)
            {
                throw new InvalidOperationException(
                    "La API devolvió una respuesta vacía.");
            }

            IReadOnlyList<ApiProduct> products =
                apiResponse.Products;

            _logger.LogInformation(
                "Extracción desde API completada. Se recibieron {RecordCount} productos.",
                products.Count);

            return products;
        }
        catch (OperationCanceledException)
        {
            _logger.LogWarning(
                "La extracción desde la API fue cancelada.");

            throw;
        }
        catch (HttpRequestException ex)
        {
            _logger.LogError(
                ex,
                "Ocurrió un error HTTP al consumir la API de productos.");

            throw;
        }
        catch (Exception ex)
        {
            _logger.LogError(
                ex,
                "Ocurrió un error durante la extracción desde la API.");

            throw;
        }
    }
}
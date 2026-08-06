using CsvHelper;
using CsvHelper.Configuration;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using SistemaVentasETL.Interfaces;
using SistemaVentasETL.Models;
using System.Globalization;

namespace SistemaVentasETL.Extractors;

public class CsvExtractor<T> : IExtractor<T>
{
    private readonly IConfiguration _configuration;
    private readonly ILogger<CsvExtractor<T>> _logger;

    public CsvExtractor(
        IConfiguration configuration,
        ILogger<CsvExtractor<T>> logger)
    {
        _configuration = configuration;
        _logger = logger;
    }

    public async Task<IReadOnlyList<T>> ExtractAsync(
        CancellationToken cancellationToken = default)
    {
        string filePath = GetFilePath();

        if (string.IsNullOrWhiteSpace(filePath))
        {
            throw new InvalidOperationException(
                $"No se encontró una ruta configurada para {typeof(T).Name}.");
        }

        if (!File.Exists(filePath))
        {
            throw new FileNotFoundException(
                $"No se encontró el archivo CSV: {filePath}");
        }

        _logger.LogInformation(
            "Iniciando extracción del archivo {FilePath}.",
            filePath);

        try
        {
            var records = new List<T>();

            var csvConfiguration = new CsvConfiguration(
                CultureInfo.InvariantCulture)
            {
                TrimOptions = TrimOptions.Trim,
                PrepareHeaderForMatch = args => args.Header.Trim()
            };

            using var reader = new StreamReader(filePath);
            using var csv = new CsvReader(reader, csvConfiguration);

            await foreach (
                T record in csv
                    .GetRecordsAsync<T>()
                    .WithCancellation(cancellationToken))
            {
                records.Add(record);
            }

            _logger.LogInformation(
                "Extracción completada. Se leyeron {RecordCount} registros de {FilePath}.",
                records.Count,
                filePath);

            return records;
        }
        catch (OperationCanceledException)
        {
            _logger.LogWarning(
                "La extracción del archivo {FilePath} fue cancelada.",
                filePath);

            throw;
        }
        catch (Exception ex)
        {
            _logger.LogError(
                ex,
                "Ocurrió un error al extraer los datos de {FilePath}.",
                filePath);

            throw;
        }
    }

    private string GetFilePath()
    {
        string configurationKey = typeof(T).Name switch
        {
            nameof(Product) => "CsvFiles:Products",
            nameof(Customer) => "CsvFiles:Customers",
            nameof(Order) => "CsvFiles:Orders",
            nameof(OrderDetail) => "CsvFiles:OrderDetails",

            _ => throw new NotSupportedException(
                $"No existe una configuración CSV para el modelo {typeof(T).Name}.")
        };

        return _configuration[configurationKey] ?? string.Empty;
    }
}
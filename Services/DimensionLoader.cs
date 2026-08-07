using Microsoft.Data.SqlClient;
using SistemaVentasETL.Interfaces;
using System.Data;
using System.Diagnostics;

namespace SistemaVentasETL.Services;

public class DimensionLoader : IDimensionLoader
{
    private readonly IConfiguration _configuration;
    private readonly ILogger<DimensionLoader> _logger;

    public DimensionLoader(
        IConfiguration configuration,
        ILogger<DimensionLoader> logger)
    {
        _configuration = configuration;
        _logger = logger;
    }

    public async Task LoadDimensionsAsync(
        CancellationToken cancellationToken = default)
    {
        string connectionString =
            _configuration.GetConnectionString("DataWarehouse")
            ?? throw new InvalidOperationException(
                "No se encontró la conexión DataWarehouse.");

        var stopwatch = Stopwatch.StartNew();

        _logger.LogInformation(
            "Iniciando carga de las dimensiones del Data Warehouse.");

        try
        {
            await using var connection =
                new SqlConnection(connectionString);

            await connection.OpenAsync(cancellationToken);

            await using var command =
                new SqlCommand(
                    "etl.usp_CargarDimensiones",
                    connection);

            command.CommandType =
                CommandType.StoredProcedure;

            command.CommandTimeout = 180;

            await command.ExecuteNonQueryAsync(
                cancellationToken);

            stopwatch.Stop();

            _logger.LogInformation(
                "Carga de dimensiones completada correctamente en {ElapsedMilliseconds} ms.",
                stopwatch.ElapsedMilliseconds);
        }
        catch (OperationCanceledException)
        {
            stopwatch.Stop();

            _logger.LogWarning(
                "La carga de dimensiones fue cancelada después de {ElapsedMilliseconds} ms.",
                stopwatch.ElapsedMilliseconds);

            throw;
        }
        catch (SqlException ex)
        {
            stopwatch.Stop();

            _logger.LogError(
                ex,
                "Ocurrió un error de SQL durante la carga de dimensiones después de {ElapsedMilliseconds} ms.",
                stopwatch.ElapsedMilliseconds);

            throw;
        }
        catch (Exception ex)
        {
            stopwatch.Stop();

            _logger.LogError(
                ex,
                "Ocurrió un error inesperado durante la carga de dimensiones después de {ElapsedMilliseconds} ms.",
                stopwatch.ElapsedMilliseconds);

            throw;
        }
    }
}
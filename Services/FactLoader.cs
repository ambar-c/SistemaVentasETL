using Microsoft.Data.SqlClient;
using SistemaVentasETL.Interfaces;
using System.Data;
using System.Diagnostics;

namespace SistemaVentasETL.Services
{
    public class FactLoader : IFactLoader
    {
        private readonly IConfiguration _configuration;
        private readonly ILogger<FactLoader> _logger;

        public FactLoader(
            IConfiguration configuration,
            ILogger<FactLoader> logger)
        {
            _configuration = configuration;
            _logger = logger;
        }

        public async Task LoadFactsAsync(
            CancellationToken cancellationToken)
        {
            var stopwatch = Stopwatch.StartNew();

            try
            {
                _logger.LogInformation(
                    "Iniciando limpieza y carga de tablas de hechos...");

                var connectionString =
                    _configuration.GetConnectionString("DataWarehouse");

                if (string.IsNullOrWhiteSpace(connectionString))
                {
                    throw new InvalidOperationException(
                        "No se encontró la cadena de conexión 'DataWarehouse'.");
                }

                await using var connection =
                    new SqlConnection(connectionString);

                await connection.OpenAsync(cancellationToken);

                await using var command =
                    new SqlCommand(
                        "etl.usp_CargarFacts",
                        connection);

                command.CommandType = CommandType.StoredProcedure;
                command.CommandTimeout = 300;

                await command.ExecuteNonQueryAsync(cancellationToken);

                stopwatch.Stop();

                _logger.LogInformation(
                    "Carga de tablas de hechos completada correctamente en {ElapsedMilliseconds} ms.",
                    stopwatch.ElapsedMilliseconds);
            }
            catch (OperationCanceledException)
            {
                stopwatch.Stop();

                _logger.LogWarning(
                    "La carga de tablas de hechos fue cancelada después de {ElapsedMilliseconds} ms.",
                    stopwatch.ElapsedMilliseconds);

                throw;
            }
            catch (SqlException ex)
            {
                stopwatch.Stop();

                _logger.LogError(
                    ex,
                    "Error de SQL Server durante la carga de tablas de hechos.");

                throw;
            }
            catch (Exception ex)
            {
                stopwatch.Stop();

                _logger.LogError(
                    ex,
                    "Error inesperado durante la carga de tablas de hechos.");

                throw;
            }
        }
    }
}
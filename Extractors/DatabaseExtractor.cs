using Microsoft.Data.SqlClient;
using SistemaVentasETL.Interfaces;
using SistemaVentasETL.Models;

namespace SistemaVentasETL.Extractors;

public class DatabaseExtractor<T> : IExtractor<T>
{
    private readonly IConfiguration _configuration;
    private readonly ILogger<DatabaseExtractor<T>> _logger;

    public DatabaseExtractor(
        IConfiguration configuration,
        ILogger<DatabaseExtractor<T>> logger)
    {
        _configuration = configuration;
        _logger = logger;
    }

    public async Task<IReadOnlyList<T>> ExtractAsync(
        CancellationToken cancellationToken = default)
    {
        string connectionString =
            _configuration.GetConnectionString("SourceDatabase")
            ?? throw new InvalidOperationException(
                "No se encontró la conexión SourceDatabase.");

        if (typeof(T) == typeof(HistoricalOrder))
        {
            IReadOnlyList<HistoricalOrder> orders =
                await ExtractOrdersAsync(
                    connectionString,
                    cancellationToken);

            return (IReadOnlyList<T>)(object)orders;
        }

        if (typeof(T) == typeof(HistoricalOrderDetail))
        {
            IReadOnlyList<HistoricalOrderDetail> details =
                await ExtractOrderDetailsAsync(
                    connectionString,
                    cancellationToken);

            return (IReadOnlyList<T>)(object)details;
        }

        throw new NotSupportedException(
            $"El tipo {typeof(T).Name} no está configurado para extracción desde base de datos.");
    }

    private async Task<IReadOnlyList<HistoricalOrder>>
        ExtractOrdersAsync(
            string connectionString,
            CancellationToken cancellationToken)
    {
        const string query = """
            SELECT
                PedidoId,
                ClienteId,
                FechaPedido,
                Estado,
                FechaCreacion
            FROM dbo.Pedidos
            ORDER BY PedidoId;
            """;

        var orders = new List<HistoricalOrder>();

        _logger.LogInformation(
            "Iniciando extracción de pedidos desde VentasTransaccional.dbo.Pedidos.");

        try
        {
            await using var connection =
                new SqlConnection(connectionString);

            await connection.OpenAsync(cancellationToken);

            await using var command =
                new SqlCommand(query, connection)
                {
                    CommandTimeout = 120
                };

            await using SqlDataReader reader =
                await command.ExecuteReaderAsync(cancellationToken);

            while (await reader.ReadAsync(cancellationToken))
            {
                orders.Add(new HistoricalOrder
                {
                    OrderID = reader.GetInt32(
                        reader.GetOrdinal("PedidoId")),

                    CustomerID = reader.GetInt32(
                        reader.GetOrdinal("ClienteId")),

                    OrderDate = reader.GetDateTime(
                        reader.GetOrdinal("FechaPedido")),

                    Status = reader.GetString(
                        reader.GetOrdinal("Estado")),

                    CreatedAt = reader.GetDateTime(
                        reader.GetOrdinal("FechaCreacion"))
                });
            }

            _logger.LogInformation(
                "Extracción completada. Se leyeron {RecordCount} pedidos desde la base de datos.",
                orders.Count);

            return orders;
        }
        catch (OperationCanceledException)
        {
            _logger.LogWarning(
                "La extracción de pedidos desde la base de datos fue cancelada.");

            throw;
        }
        catch (Exception ex)
        {
            _logger.LogError(
                ex,
                "Ocurrió un error al extraer pedidos desde la base de datos.");

            throw;
        }
    }

    private async Task<IReadOnlyList<HistoricalOrderDetail>>
        ExtractOrderDetailsAsync(
            string connectionString,
            CancellationToken cancellationToken)
    {
        const string query = """
            SELECT
                DetallePedidoId,
                PedidoId,
                ProductoId,
                Cantidad,
                PrecioUnitario,
                PrecioTotal,
                FechaCreacion
            FROM dbo.DetallesPedido
            ORDER BY DetallePedidoId;
            """;

        var details = new List<HistoricalOrderDetail>();

        _logger.LogInformation(
            "Iniciando extracción de detalles desde VentasTransaccional.dbo.DetallesPedido.");

        try
        {
            await using var connection =
                new SqlConnection(connectionString);

            await connection.OpenAsync(cancellationToken);

            await using var command =
                new SqlCommand(query, connection)
                {
                    CommandTimeout = 120
                };

            await using SqlDataReader reader =
                await command.ExecuteReaderAsync(cancellationToken);

            while (await reader.ReadAsync(cancellationToken))
            {
                details.Add(new HistoricalOrderDetail
                {
                    OrderDetailID = reader.GetInt64(
                        reader.GetOrdinal("DetallePedidoId")),

                    OrderID = reader.GetInt32(
                        reader.GetOrdinal("PedidoId")),

                    ProductID = reader.GetInt32(
                        reader.GetOrdinal("ProductoId")),

                    Quantity = reader.GetInt32(
                        reader.GetOrdinal("Cantidad")),

                    UnitPrice = reader.GetDecimal(
                        reader.GetOrdinal("PrecioUnitario")),

                    TotalPrice = reader.GetDecimal(
                        reader.GetOrdinal("PrecioTotal")),

                    CreatedAt = reader.GetDateTime(
                        reader.GetOrdinal("FechaCreacion"))
                });
            }

            _logger.LogInformation(
                "Extracción completada. Se leyeron {RecordCount} detalles desde la base de datos.",
                details.Count);

            return details;
        }
        catch (OperationCanceledException)
        {
            _logger.LogWarning(
                "La extracción de detalles desde la base de datos fue cancelada.");

            throw;
        }
        catch (Exception ex)
        {
            _logger.LogError(
                ex,
                "Ocurrió un error al extraer detalles desde la base de datos.");

            throw;
        }
    }
}
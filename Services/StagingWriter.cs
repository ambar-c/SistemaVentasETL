using Microsoft.Data.SqlClient;
using SistemaVentasETL.Interfaces;
using SistemaVentasETL.Models;
using System.Data;
using System.Globalization;

namespace SistemaVentasETL.Services;

public class StagingWriter : IStagingWriter
{
    private readonly IConfiguration _configuration;
    private readonly ILogger<StagingWriter> _logger;

    public StagingWriter(
        IConfiguration configuration,
        ILogger<StagingWriter> logger)
    {
        _configuration = configuration;
        _logger = logger;
    }

    public async Task WriteAsync<T>(
        IReadOnlyCollection<T> records,
        CancellationToken cancellationToken = default)
    {
        if (records.Count == 0)
        {
            _logger.LogWarning(
                "No existen registros de {RecordType} para insertar en staging.",
                typeof(T).Name);

            return;
        }

        string connectionString =
            _configuration.GetConnectionString("DataWarehouse")
            ?? throw new InvalidOperationException(
                "No se encontró la conexión DataWarehouse.");

        (string tableName, DataTable dataTable) =
            CreateDataTable(records);

        _logger.LogInformation(
            "Iniciando carga de {RecordCount} registros en {TableName}.",
            records.Count,
            tableName);

        try
        {
            await using var connection =
                new SqlConnection(connectionString);

            await connection.OpenAsync(cancellationToken);

            // Se limpia la tabla staging para evitar duplicados
            string truncateSql = $"TRUNCATE TABLE {tableName};";

            await using (var command =
                new SqlCommand(truncateSql, connection))
            {
                await command.ExecuteNonQueryAsync(cancellationToken);
            }

            using var bulkCopy = new SqlBulkCopy(connection)
            {
                DestinationTableName = tableName,
                BatchSize = 5000,
                BulkCopyTimeout = 120,
                EnableStreaming = true
            };

            foreach (DataColumn column in dataTable.Columns)
            {
                bulkCopy.ColumnMappings.Add(
                    column.ColumnName,
                    column.ColumnName);
            }

            await bulkCopy.WriteToServerAsync(
                dataTable,
                cancellationToken);

            _logger.LogInformation(
                "Carga completada. Se insertaron {RecordCount} registros en {TableName}.",
                records.Count,
                tableName);
        }
        catch (OperationCanceledException)
        {
            _logger.LogWarning(
                "La carga en {TableName} fue cancelada.",
                tableName);

            throw;
        }
        catch (Exception ex)
        {
            _logger.LogError(
                ex,
                "Ocurrió un error al cargar datos en {TableName}.",
                tableName);

            throw;
        }
    }

    private static (string TableName, DataTable Data)
        CreateDataTable<T>(IReadOnlyCollection<T> records)
    {
        if (typeof(T) == typeof(Product))
        {
            return CreateProductsTable(
                records.Cast<Product>());
        }

        if (typeof(T) == typeof(Customer))
        {
            return CreateCustomersTable(
                records.Cast<Customer>());
        }

        if (typeof(T) == typeof(Order))
        {
            return CreateOrdersTable(
                records.Cast<Order>());
        }

        if (typeof(T) == typeof(OrderDetail))
        {
            return CreateOrderDetailsTable(
                records.Cast<OrderDetail>());
        }

        if (typeof(T) == typeof(HistoricalOrder))
        {
            return CreateHistoricalOrdersTable(
                records.Cast<HistoricalOrder>());
        }

        if (typeof(T) == typeof(HistoricalOrderDetail))
        {
            return CreateHistoricalOrderDetailsTable(
                records.Cast<HistoricalOrderDetail>());
        }

        if (typeof(T) == typeof(ApiProduct))
        {
            return CreateApiProductsTable(
                records.Cast<ApiProduct>());
        }

        throw new NotSupportedException(
            $"No existe una tabla staging para {typeof(T).Name}.");
    }

    private static (string, DataTable) CreateProductsTable(
        IEnumerable<Product> records)
    {
        var table = new DataTable();

        table.Columns.Add("ProductID", typeof(string));
        table.Columns.Add("ProductName", typeof(string));
        table.Columns.Add("Category", typeof(string));
        table.Columns.Add("Price", typeof(string));
        table.Columns.Add("Stock", typeof(string));

        foreach (Product product in records)
        {
            table.Rows.Add(
                product.ProductID.ToString(
                    CultureInfo.InvariantCulture),
                product.ProductName,
                product.Category,
                product.Price.ToString(
                    CultureInfo.InvariantCulture),
                product.Stock.ToString(
                    CultureInfo.InvariantCulture));
        }

        return ("[stg].[Productos]", table);
    }

    private static (string, DataTable) CreateCustomersTable(
        IEnumerable<Customer> records)
    {
        var table = new DataTable();

        table.Columns.Add("CustomerID", typeof(string));
        table.Columns.Add("FirstName", typeof(string));
        table.Columns.Add("LastName", typeof(string));
        table.Columns.Add("Email", typeof(string));
        table.Columns.Add("Phone", typeof(string));
        table.Columns.Add("City", typeof(string));
        table.Columns.Add("Country", typeof(string));

        foreach (Customer customer in records)
        {
            table.Rows.Add(
                customer.CustomerID.ToString(
                    CultureInfo.InvariantCulture),
                customer.FirstName,
                customer.LastName,
                customer.Email,
                customer.Phone,
                customer.City,
                customer.Country);
        }

        return ("[stg].[Clientes]", table);
    }

    private static (string, DataTable) CreateOrdersTable(
        IEnumerable<Order> records)
    {
        var table = new DataTable();

        table.Columns.Add("OrderID", typeof(string));
        table.Columns.Add("CustomerID", typeof(string));
        table.Columns.Add("OrderDate", typeof(string));
        table.Columns.Add("Status", typeof(string));

        foreach (Order order in records)
        {
            table.Rows.Add(
                order.OrderID.ToString(
                    CultureInfo.InvariantCulture),
                order.CustomerID.ToString(
                    CultureInfo.InvariantCulture),
                order.OrderDate.ToString(
                    "yyyy-MM-dd",
                    CultureInfo.InvariantCulture),
                order.Status);
        }

        return ("[stg].[Ordenes]", table);
    }

    private static (string, DataTable) CreateOrderDetailsTable(
        IEnumerable<OrderDetail> records)
    {
        var table = new DataTable();

        table.Columns.Add("OrderID", typeof(string));
        table.Columns.Add("ProductID", typeof(string));
        table.Columns.Add("Quantity", typeof(string));
        table.Columns.Add("TotalPrice", typeof(string));

        foreach (OrderDetail detail in records)
        {
            table.Rows.Add(
                detail.OrderID.ToString(
                    CultureInfo.InvariantCulture),
                detail.ProductID.ToString(
                    CultureInfo.InvariantCulture),
                detail.Quantity.ToString(
                    CultureInfo.InvariantCulture),
                detail.TotalPrice.ToString(
                    CultureInfo.InvariantCulture));
        }

        return ("[stg].[DetallesOrden]", table);
    }

    private static (string, DataTable) CreateHistoricalOrdersTable(
    IEnumerable<HistoricalOrder> records)
    {
        var table = new DataTable();

        table.Columns.Add("PedidoId", typeof(string));
        table.Columns.Add("ClienteId", typeof(string));
        table.Columns.Add("FechaPedido", typeof(string));
        table.Columns.Add("Estado", typeof(string));
        table.Columns.Add("FechaCreacion", typeof(string));

        foreach (HistoricalOrder order in records)
        {
            table.Rows.Add(
                order.OrderID.ToString(
                    CultureInfo.InvariantCulture),

                order.CustomerID.ToString(
                    CultureInfo.InvariantCulture),

                order.OrderDate.ToString(
                    "yyyy-MM-dd",
                    CultureInfo.InvariantCulture),

                order.Status,

                order.CreatedAt.ToString(
                    "yyyy-MM-dd HH:mm:ss.fffffff",
                    CultureInfo.InvariantCulture));
        }

        return ("[stg].[PedidosBD]", table);
    }

    private static (string, DataTable)
    CreateHistoricalOrderDetailsTable(
        IEnumerable<HistoricalOrderDetail> records)
    {
        var table = new DataTable();

        table.Columns.Add("DetallePedidoId", typeof(string));
        table.Columns.Add("PedidoId", typeof(string));
        table.Columns.Add("ProductoId", typeof(string));
        table.Columns.Add("Cantidad", typeof(string));
        table.Columns.Add("PrecioUnitario", typeof(string));
        table.Columns.Add("PrecioTotal", typeof(string));
        table.Columns.Add("FechaCreacion", typeof(string));

        foreach (HistoricalOrderDetail detail in records)
        {
            table.Rows.Add(
                detail.OrderDetailID.ToString(
                    CultureInfo.InvariantCulture),

                detail.OrderID.ToString(
                    CultureInfo.InvariantCulture),

                detail.ProductID.ToString(
                    CultureInfo.InvariantCulture),

                detail.Quantity.ToString(
                    CultureInfo.InvariantCulture),

                detail.UnitPrice.ToString(
                    CultureInfo.InvariantCulture),

                detail.TotalPrice.ToString(
                    CultureInfo.InvariantCulture),

                detail.CreatedAt.ToString(
                    "yyyy-MM-dd HH:mm:ss.fffffff",
                    CultureInfo.InvariantCulture));
        }

        return ("[stg].[DetallesPedidoBD]", table);
    }

    private static (string, DataTable) CreateApiProductsTable(
    IEnumerable<ApiProduct> records)
    {
        var table = new DataTable();

        table.Columns.Add("ProductID", typeof(string));
        table.Columns.Add("ProductName", typeof(string));
        table.Columns.Add("Category", typeof(string));
        table.Columns.Add("Price", typeof(string));
        table.Columns.Add("Stock", typeof(string));

        foreach (ApiProduct product in records)
        {
            table.Rows.Add(
                product.ProductID.ToString(
                    CultureInfo.InvariantCulture),

                product.ProductName,

                product.Category,

                product.Price.ToString(
                    CultureInfo.InvariantCulture),

                product.Stock.ToString(
                    CultureInfo.InvariantCulture));
        }

        return ("[stg].[ProductosAPI]", table);
    }
}
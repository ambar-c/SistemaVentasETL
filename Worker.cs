using SistemaVentasETL.Interfaces;
using SistemaVentasETL.Models;
using System.Diagnostics;

namespace SistemaVentasETL;

public class Worker : BackgroundService
{
    private readonly ILogger<Worker> _logger;

    // Extractores CSV
    private readonly IExtractor<Product> _productExtractor;
    private readonly IExtractor<Customer> _customerExtractor;
    private readonly IExtractor<Order> _orderExtractor;
    private readonly IExtractor<OrderDetail> _orderDetailExtractor;

    // Extractores de la base de datos relacional
    private readonly IExtractor<HistoricalOrder>
        _historicalOrderExtractor;

    private readonly IExtractor<HistoricalOrderDetail>
        _historicalOrderDetailExtractor;

    // Extractor de la API REST
    private readonly IExtractor<ApiProduct> _apiProductExtractor;

    private readonly IStagingWriter _stagingWriter;
    private readonly IHostApplicationLifetime _hostApplicationLifetime;

    public Worker(
        ILogger<Worker> logger,
        IExtractor<Product> productExtractor,
        IExtractor<Customer> customerExtractor,
        IExtractor<Order> orderExtractor,
        IExtractor<OrderDetail> orderDetailExtractor,
        IExtractor<HistoricalOrder> historicalOrderExtractor,
        IExtractor<HistoricalOrderDetail> historicalOrderDetailExtractor,
        IExtractor<ApiProduct> apiProductExtractor,
        IStagingWriter stagingWriter,
        IHostApplicationLifetime hostApplicationLifetime)
    {
        _logger = logger;

        _productExtractor = productExtractor;
        _customerExtractor = customerExtractor;
        _orderExtractor = orderExtractor;
        _orderDetailExtractor = orderDetailExtractor;

        _historicalOrderExtractor = historicalOrderExtractor;
        _historicalOrderDetailExtractor =
            historicalOrderDetailExtractor;

        _apiProductExtractor = apiProductExtractor;

        _stagingWriter = stagingWriter;
        _hostApplicationLifetime = hostApplicationLifetime;
    }

    protected override async Task ExecuteAsync(
        CancellationToken stoppingToken)
    {
        var totalStopwatch = Stopwatch.StartNew();

        _logger.LogInformation(
            "Iniciando extracción desde CSV, base de datos y API REST.");

        try
        {
            var extractionStopwatch = Stopwatch.StartNew();

            // Extracción desde archivos CSV
            Task<IReadOnlyList<Product>> productsTask =
                _productExtractor.ExtractAsync(stoppingToken);

            Task<IReadOnlyList<Customer>> customersTask =
                _customerExtractor.ExtractAsync(stoppingToken);

            Task<IReadOnlyList<Order>> ordersTask =
                _orderExtractor.ExtractAsync(stoppingToken);

            Task<IReadOnlyList<OrderDetail>> orderDetailsTask =
                _orderDetailExtractor.ExtractAsync(stoppingToken);

            // Extracción desde VentasTransaccional
            Task<IReadOnlyList<HistoricalOrder>>
                historicalOrdersTask =
                    _historicalOrderExtractor.ExtractAsync(
                        stoppingToken);

            Task<IReadOnlyList<HistoricalOrderDetail>>
                historicalOrderDetailsTask =
                    _historicalOrderDetailExtractor.ExtractAsync(
                        stoppingToken);

            // Extracción desde la API REST
            Task<IReadOnlyList<ApiProduct>> apiProductsTask =
                _apiProductExtractor.ExtractAsync(stoppingToken);

            // Las siete extracciones se ejecutan simultáneamente
            await Task.WhenAll(
                productsTask,
                customersTask,
                ordersTask,
                orderDetailsTask,
                historicalOrdersTask,
                historicalOrderDetailsTask,
                apiProductsTask);

            IReadOnlyList<Product> products =
                await productsTask;

            IReadOnlyList<Customer> customers =
                await customersTask;

            IReadOnlyList<Order> orders =
                await ordersTask;

            IReadOnlyList<OrderDetail> orderDetails =
                await orderDetailsTask;

            IReadOnlyList<HistoricalOrder> historicalOrders =
                await historicalOrdersTask;

            IReadOnlyList<HistoricalOrderDetail>
                historicalOrderDetails =
                    await historicalOrderDetailsTask;

            IReadOnlyList<ApiProduct> apiProducts =
                await apiProductsTask;

            extractionStopwatch.Stop();

            _logger.LogInformation(
                "Extracción de las tres fuentes completada en {ElapsedMilliseconds} ms.",
                extractionStopwatch.ElapsedMilliseconds);

            _logger.LogInformation(
                "CSV - Productos extraídos: {Count}.",
                products.Count);

            _logger.LogInformation(
                "CSV - Clientes extraídos: {Count}.",
                customers.Count);

            _logger.LogInformation(
                "CSV - Órdenes extraídas: {Count}.",
                orders.Count);

            _logger.LogInformation(
                "CSV - Detalles extraídos: {Count}.",
                orderDetails.Count);

            _logger.LogInformation(
                "BD - Pedidos históricos extraídos: {Count}.",
                historicalOrders.Count);

            _logger.LogInformation(
                "BD - Detalles históricos extraídos: {Count}.",
                historicalOrderDetails.Count);

            _logger.LogInformation(
                "API - Productos extraídos: {Count}.",
                apiProducts.Count);

            var stagingStopwatch = Stopwatch.StartNew();

            // Carga de los CSV
            Task productsLoadTask =
                _stagingWriter.WriteAsync(
                    products,
                    stoppingToken);

            Task customersLoadTask =
                _stagingWriter.WriteAsync(
                    customers,
                    stoppingToken);

            Task ordersLoadTask =
                _stagingWriter.WriteAsync(
                    orders,
                    stoppingToken);

            Task orderDetailsLoadTask =
                _stagingWriter.WriteAsync(
                    orderDetails,
                    stoppingToken);

            // Carga de la base relacional
            Task historicalOrdersLoadTask =
                _stagingWriter.WriteAsync(
                    historicalOrders,
                    stoppingToken);

            Task historicalOrderDetailsLoadTask =
                _stagingWriter.WriteAsync(
                    historicalOrderDetails,
                    stoppingToken);

            // Carga de la API REST
            Task apiProductsLoadTask =
                _stagingWriter.WriteAsync(
                    apiProducts,
                    stoppingToken);

            // Las siete cargas usan tablas distintas
            await Task.WhenAll(
                productsLoadTask,
                customersLoadTask,
                ordersLoadTask,
                orderDetailsLoadTask,
                historicalOrdersLoadTask,
                historicalOrderDetailsLoadTask,
                apiProductsLoadTask);

            stagingStopwatch.Stop();
            totalStopwatch.Stop();

            _logger.LogInformation(
                "Carga de las tres fuentes en staging completada en {ElapsedMilliseconds} ms.",
                stagingStopwatch.ElapsedMilliseconds);

            _logger.LogInformation(
                "Proceso ETL de extracción finalizado correctamente en {ElapsedMilliseconds} ms.",
                totalStopwatch.ElapsedMilliseconds);
        }
        catch (OperationCanceledException)
            when (stoppingToken.IsCancellationRequested)
        {
            _logger.LogWarning(
                "El proceso de extracción fue cancelado.");
        }
        catch (Exception ex)
        {
            _logger.LogError(
                ex,
                "Ocurrió un error durante la extracción o carga en staging.");
        }
        finally
        {
            totalStopwatch.Stop();
            _hostApplicationLifetime.StopApplication();
        }
    }
}
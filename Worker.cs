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

    // Servicios de carga
    private readonly IStagingWriter _stagingWriter;
    private readonly IDimensionLoader _dimensionLoader;
    private readonly IFactLoader _factLoader;

    private readonly IHostApplicationLifetime
        _hostApplicationLifetime;
    
    public Worker(
        ILogger<Worker> logger,
        IExtractor<Product> productExtractor,
        IExtractor<Customer> customerExtractor,
        IExtractor<Order> orderExtractor,
        IExtractor<OrderDetail> orderDetailExtractor,
        IExtractor<HistoricalOrder> historicalOrderExtractor,
        IExtractor<HistoricalOrderDetail>
            historicalOrderDetailExtractor,
        IExtractor<ApiProduct> apiProductExtractor,
        IStagingWriter stagingWriter,
        IDimensionLoader dimensionLoader,
        IFactLoader factLoader,
        IHostApplicationLifetime hostApplicationLifetime)
    {
        _logger = logger;

        _productExtractor = productExtractor;
        _customerExtractor = customerExtractor;
        _orderExtractor = orderExtractor;
        _orderDetailExtractor = orderDetailExtractor;

        _historicalOrderExtractor =
            historicalOrderExtractor;

        _historicalOrderDetailExtractor =
            historicalOrderDetailExtractor;

        _apiProductExtractor = apiProductExtractor;

        _stagingWriter = stagingWriter;
        _dimensionLoader = dimensionLoader;
        _factLoader = factLoader;

        _hostApplicationLifetime =
            hostApplicationLifetime;
    }

    protected override async Task ExecuteAsync(
        CancellationToken stoppingToken)
    {
        var totalStopwatch = Stopwatch.StartNew();

        _logger.LogInformation(
            "Iniciando proceso ETL desde CSV, base de datos y API REST.");

        try
        {
            /* =================================================
               1. EXTRACCIÓN
               ================================================= */

            var extractionStopwatch =
                Stopwatch.StartNew();

            // Extracción desde archivos CSV
            Task<IReadOnlyList<Product>> productsTask =
                _productExtractor.ExtractAsync(
                    stoppingToken);

            Task<IReadOnlyList<Customer>> customersTask =
                _customerExtractor.ExtractAsync(
                    stoppingToken);

            Task<IReadOnlyList<Order>> ordersTask =
                _orderExtractor.ExtractAsync(
                    stoppingToken);

            Task<IReadOnlyList<OrderDetail>>
                orderDetailsTask =
                    _orderDetailExtractor.ExtractAsync(
                        stoppingToken);

            // Extracción desde la base de datos relacional
            Task<IReadOnlyList<HistoricalOrder>>
                historicalOrdersTask =
                    _historicalOrderExtractor.ExtractAsync(
                        stoppingToken);

            Task<IReadOnlyList<HistoricalOrderDetail>>
                historicalOrderDetailsTask =
                    _historicalOrderDetailExtractor
                        .ExtractAsync(stoppingToken);

            // Extracción desde la API REST
            Task<IReadOnlyList<ApiProduct>>
                apiProductsTask =
                    _apiProductExtractor.ExtractAsync(
                        stoppingToken);

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

            IReadOnlyList<HistoricalOrder>
                historicalOrders =
                    await historicalOrdersTask;

            IReadOnlyList<HistoricalOrderDetail>
                historicalOrderDetails =
                    await historicalOrderDetailsTask;

            IReadOnlyList<ApiProduct> apiProducts =
                await apiProductsTask;

            extractionStopwatch.Stop();

            _logger.LogInformation(
                "Extracción completada en {ElapsedMilliseconds} ms.",
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


            /* =================================================
               2. CARGA EN STAGING
               ================================================= */

            var stagingStopwatch =
                Stopwatch.StartNew();

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

            // Carga de la base de datos relacional
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

            // Cada carga utiliza una tabla staging diferente
            await Task.WhenAll(
                productsLoadTask,
                customersLoadTask,
                ordersLoadTask,
                orderDetailsLoadTask,
                historicalOrdersLoadTask,
                historicalOrderDetailsLoadTask,
                apiProductsLoadTask);

            stagingStopwatch.Stop();

            _logger.LogInformation(
                "Carga de staging completada en {ElapsedMilliseconds} ms.",
                stagingStopwatch.ElapsedMilliseconds);


            /* =================================================
               3. TRANSFORMACIÓN Y CARGA DE DIMENSIONES
               ================================================= */

            var dimensionsStopwatch =
                Stopwatch.StartNew();

            _logger.LogInformation(
                "Iniciando transformación y carga de dimensiones.");

            await _dimensionLoader.LoadDimensionsAsync(
                stoppingToken);

            dimensionsStopwatch.Stop();

            _logger.LogInformation(
            "Transformación y carga de dimensiones completada en {ElapsedMilliseconds} ms.",
            dimensionsStopwatch.ElapsedMilliseconds);

            /* ============================================================
               4. LIMPIEZA Y CARGA DE TABLAS DE HECHOS
               ============================================================ */

            _logger.LogInformation(
                "Iniciando proceso de carga de tablas de hechos...");

            await _factLoader.LoadFactsAsync(stoppingToken);

            _logger.LogInformation(
                "Proceso de carga de tablas de hechos finalizado correctamente.");


            /* =================================================
               5. FINALIZACIÓN
               ================================================= */

            totalStopwatch.Stop();

            _logger.LogInformation(
                "Proceso ETL completo finalizado correctamente en {ElapsedMilliseconds} ms.",
                totalStopwatch.ElapsedMilliseconds);
        }
        catch (OperationCanceledException)
            when (stoppingToken.IsCancellationRequested)
        {
            _logger.LogWarning(
                "El proceso ETL fue cancelado.");
        }
        catch (Exception ex)
        {
            _logger.LogError(
                ex,
                "Ocurrió un error durante el proceso ETL.");
        }
        finally
        {
            totalStopwatch.Stop();

            _hostApplicationLifetime
                .StopApplication();
        }
    }
}
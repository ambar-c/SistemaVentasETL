using SistemaVentasETL;
using SistemaVentasETL.Extractors;
using SistemaVentasETL.Interfaces;
using SistemaVentasETL.Models;
using SistemaVentasETL.Services;

var builder = Host.CreateApplicationBuilder(args);

// Cliente HTTP para la API REST
string apiBaseUrl =
    builder.Configuration["ApiSettings:BaseUrl"]
    ?? throw new InvalidOperationException(
        "No se encontró ApiSettings:BaseUrl.");

builder.Services.AddHttpClient(
    "ProductsApi",
    client =>
    {
        client.BaseAddress = new Uri(apiBaseUrl);
        client.Timeout = TimeSpan.FromSeconds(30);
    });

// Extractores de archivos CSV
builder.Services.AddSingleton<IExtractor<Product>, CsvExtractor<Product>>();
builder.Services.AddSingleton<IExtractor<Customer>, CsvExtractor<Customer>>();
builder.Services.AddSingleton<IExtractor<Order>, CsvExtractor<Order>>();
builder.Services.AddSingleton<IExtractor<OrderDetail>, CsvExtractor<OrderDetail>>();

// Extractores de la base de datos relacional
builder.Services.AddSingleton<
    IExtractor<HistoricalOrder>,
    DatabaseExtractor<HistoricalOrder>>();

builder.Services.AddSingleton<
    IExtractor<HistoricalOrderDetail>,
    DatabaseExtractor<HistoricalOrderDetail>>();

// Extractor de la API REST
builder.Services.AddSingleton<
    IExtractor<ApiProduct>,
    ApiExtractor>();

// Servicio encargado de escribir en las tablas staging
builder.Services.AddSingleton<IStagingWriter, StagingWriter>();

// Servicio encargado de cargar las dimensiones
builder.Services.AddSingleton<IDimensionLoader, DimensionLoader>();

// Worker Service
builder.Services.AddHostedService<Worker>();

var host = builder.Build();
host.Run();
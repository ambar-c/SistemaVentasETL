\# Sistema de Análisis de Ventas con Proceso ETL



Este proyecto implementa la arquitectura base y el proceso de extracción de un sistema ETL multifuente mediante un Worker Service desarrollado en .NET 8.



\## Fuentes de datos



\- Archivos CSV: productos, clientes, órdenes y detalles de órdenes.

\- Base de datos relacional: SQL Server, base de datos VentasTransaccional.

\- API REST externa: productos obtenidos desde DummyJSON.



\## Tecnologías utilizadas



\- .NET 8

\- Worker Service

\- CsvHelper

\- Microsoft.Data.SqlClient

\- IHttpClientFactory

\- SqlBulkCopy

\- SQL Server

\- ILogger

\- Stopwatch



\## Componentes principales



\- `CsvExtractor<T>`: extracción desde archivos CSV.

\- `DatabaseExtractor<T>`: extracción desde SQL Server.

\- `ApiExtractor`: consumo de la API REST.

\- `IExtractor<T>`: contrato común de los extractores.

\- `StagingWriter`: carga masiva en tablas staging.

\- `Worker.cs`: coordinación del proceso mediante tareas asíncronas.



\## Resultados



Durante la ejecución final se procesaron correctamente:



\- 2,000 productos desde CSV.

\- 5,000 clientes desde CSV.

\- 20,000 órdenes desde CSV.

\- 60,161 detalles de órdenes desde CSV.

\- 20,000 pedidos desde SQL Server.

\- 60,157 detalles de pedidos desde SQL Server.

\- 194 productos desde la API REST.



Total procesado: \*\*167,512 registros\*\*.



\## Almacenamiento



Los datos extraídos fueron almacenados en las tablas del esquema `stg` de la base de datos `DW\_SistemaVentas`, utilizando el filegroup `FG\_STAGING`.



\## Configuración



Las rutas de los archivos, cadenas de conexión y dirección de la API se encuentran centralizadas en `appsettings.json`.



Para ejecutar el proyecto en otro equipo, deben actualizarse las rutas y cadenas de conexión según el entorno local.



\## Documentación



La carpeta `Documentacion` contiene:



\- Diagrama de arquitectura.

\- Diagrama de flujo del proceso de extracción.

\- Documento técnico de la implementación.


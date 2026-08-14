# Sistema de Análisis de Ventas con Proceso ETL

Este proyecto implementa la arquitectura y el proceso ETL multifuente de un Sistema de Análisis de Ventas mediante un Worker Service desarrollado en .NET 8 y SQL Server.

## Fuentes de datos

- Archivos CSV: productos, clientes, órdenes y detalles de órdenes.
- Base de datos relacional: SQL Server, base de datos `VentasTransaccional`.
- API REST externa: productos obtenidos desde DummyJSON.

## Tecnologías utilizadas

- .NET 8
- Worker Service
- CsvHelper
- Microsoft.Data.SqlClient
- IHttpClientFactory
- SqlBulkCopy
- SQL Server
- ILogger
- Stopwatch

## Componentes principales

- `CsvExtractor<T>`: extracción desde archivos CSV.
- `DatabaseExtractor<T>`: extracción desde SQL Server.
- `ApiExtractor`: consumo de la API REST.
- `IExtractor<T>`: contrato común de los extractores.
- `StagingWriter`: carga masiva en tablas staging.
- `IDimensionLoader`: contrato para la carga de dimensiones.
- `DimensionLoader`: ejecución de la carga dimensional desde .NET.
- `IFactLoader`: contrato para la carga de tablas de hechos.
- `FactLoader`: ejecución de la limpieza y carga de hechos desde .NET.
- `Worker.cs`: coordinación del proceso mediante tareas asíncronas.

## Resultados de extracción

Durante la ejecución se procesaron correctamente:

- 2,000 productos desde CSV.
- 5,000 clientes desde CSV.
- 20,000 órdenes desde CSV.
- 60,161 detalles de órdenes desde CSV.
- 20,000 pedidos desde SQL Server.
- 60,157 detalles de pedidos desde SQL Server.
- 194 productos desde la API REST.

Total procesado: **167,512 registros**.

## Almacenamiento en staging

Los datos extraídos son almacenados en las tablas del esquema `stg` de la base de datos `DW_SistemaVentas`.

La carga hacia staging utiliza `SqlBulkCopy`, procesamiento por lotes y tablas independientes para cada fuente, permitiendo una carga eficiente y escalable.

## Configuración

Las rutas de los archivos, cadenas de conexión y dirección de la API se encuentran centralizadas en `appsettings.json`.

Para ejecutar el proyecto en otro equipo, deben actualizarse las rutas y cadenas de conexión según el entorno local.

## Carga incremental de dimensiones

En esta etapa se implementó la transformación y carga automática de las dimensiones del Data Warehouse, integrándola con el Worker Service desarrollado en .NET 8.

El flujo ejecutado es el siguiente:

`
Fuentes CSV, API REST y base de datos externa
                    ↓
          Extractores en .NET 8
                    ↓
          Tablas del esquema stg
                    ↓
       Procedimientos almacenados SQL
                    ↓
          Dimensiones del esquema dw
                    ↓
        Registro en etl.ControlCarga
`

## Dimensiones cargadas

- `dw.DimFuenteDatos`
- `dw.DimEstadoPedido`
- `dw.DimFecha`
- `dw.DimCliente`
- `dw.DimProducto`

## Procedimientos almacenados

Los procedimientos se encuentran documentados en la carpeta `BaseDatos`:

- `etl.usp_CargarDimFuenteDatos`
- `etl.usp_CargarDimEstadoPedido`
- `etl.usp_CargarDimFecha`
- `etl.usp_CargarDimCliente`
- `etl.usp_CargarDimProducto`
- `etl.usp_CargarDimensiones`

El procedimiento `etl.usp_CargarDimensiones` funciona como orquestador y ejecuta las dimensiones respetando su orden lógico de carga.

## Estrategia utilizada

La solución utiliza una estrategia híbrida entre .NET 8 y SQL Server.

**.NET 8** se encarga de:

- Extracción desde las diferentes fuentes.
- Orquestación del proceso ETL.
- Carga masiva hacia staging.
- Ejecución de la carga dimensional.
- Registro de logs.
- Medición de tiempos.
- Manejo de errores.

**SQL Server** se encarga de:

- Validación de datos.
- Limpieza y normalización.
- Conversión segura de tipos.
- Eliminación de duplicados.
- Comparación de registros existentes.
- Inserción y actualización por conjuntos.
- Registro de auditoría.

Esta separación permite mantener una solución escalable y mantenible, utilizando cada tecnología en las tareas para las cuales ofrece mejor rendimiento.

## Resultados de las dimensiones

| Dimensión | Total de registros |
|---|---:|
| `DimFuenteDatos` | 4 |
| `DimEstadoPedido` | 5 |
| `DimFecha` | 732 |
| `DimCliente` | 5,001 |
| `DimProducto` | 2,195 |

La dimensión `DimProducto` integra:

- 2,000 productos provenientes de archivos CSV.
- 194 productos provenientes de la API REST.
- 1 miembro desconocido utilizado por el modelo dimensional.

## Carga multifuente

La procedencia de los registros se mantiene mediante `FuenteDatosKey`.

Esto permite diferenciar registros con un mismo identificador de origen cuando pertenecen a sistemas diferentes.

Por ejemplo, un producto con identificador `1` proveniente del CSV puede coexistir con un producto con identificador `1` proveniente de la API sin generar conflictos.

## Carga incremental e idempotencia

Los procedimientos fueron diseñados para poder ejecutarse repetidamente sin generar registros duplicados.

Durante las pruebas finales, una reejecución completa obtuvo:

- 47,194 filas leídas.
- 0 filas insertadas.
- 0 filas actualizadas.
- 0 filas rechazadas.
- Estado `Completada`.

Esto demuestra que el proceso reconoce los datos previamente procesados y evita volver a insertarlos.

## Auditoría del proceso

La tabla `etl.ControlCarga` registra información de cada ejecución dimensional, incluyendo:

- Fuente de datos.
- Nombre del proceso.
- Fecha de inicio.
- Fecha de finalización.
- Estado de la carga.
- Filas leídas.
- Filas insertadas.
- Filas actualizadas.
- Filas rechazadas.
- Mensaje de error.

Los estados utilizados permiten identificar cargas iniciadas, completadas, completadas con errores o fallidas.

## Validaciones realizadas

Se realizaron consultas de validación para comprobar:

- Cero grupos duplicados en `DimFuenteDatos`.
- Cero grupos duplicados en `DimEstadoPedido`.
- Cero grupos duplicados en `DimFecha`.
- Cero grupos duplicados en `DimCliente`.
- Cero grupos duplicados en `DimProducto`.
- Cero cargas inconclusas.
- Integridad de los registros cargados.
- Correcta diferenciación de productos según su fuente.
- Ejecuciones repetidas sin duplicación.

## Scripts SQL

La carpeta `BaseDatos` contiene:

### `01_Carga_Dimensiones.sql`

Contiene los procedimientos individuales encargados de transformar y cargar las cinco dimensiones.

### `02_Orquestacion_Carga_Dimensiones.sql`

Contiene el procedimiento general `etl.usp_CargarDimensiones`, encargado de coordinar la ejecución y registrar las métricas en `etl.ControlCarga`.

### `03_Validacion_Dimensiones.sql`

Contiene las consultas utilizadas para verificar:

- Población de las dimensiones.
- Conteos de registros.
- Distribución por fuente.
- Ausencia de duplicados.
- Estado de las ejecuciones.

## Ejecución del proceso

Para ejecutar el proyecto:

1. Crear los procedimientos almacenados mediante los scripts de la carpeta `BaseDatos`.
2. Configurar las rutas y cadenas de conexión en `appsettings.json`.
3. Compilar el proyecto en .NET 8.
4. Ejecutar el Worker Service.

El Worker realiza automáticamente el siguiente flujo:

```
Extracción multifuente
        ↓
Carga en staging
        ↓
Transformación y carga de dimensiones
        ↓
Limpieza de FactVenta
        ↓
Carga de FactVenta
        ↓
Registro en etl.ControlCarga
        ↓
Finalización del ETL
```

## Documentación

La carpeta `Documentacion` contiene la documentación técnica correspondiente a las diferentes etapas del proyecto.

# Carga de tablas de hechos

En esta etapa se implementó la limpieza, transformación y carga automática de la tabla de hechos del Data Warehouse, integrándola con el Worker Service desarrollado en .NET 8.

El flujo implementado es el siguiente:

```
Fuentes CSV, API REST y base de datos externa
                    ↓
          Extractores en .NET 8
                    ↓
          Tablas del esquema stg
                    ↓
          Carga de dimensiones
                    ↓
        Limpieza de dw.FactVenta
                    ↓
     Transformación y deduplicación
                    ↓
          Carga de dw.FactVenta
                    ↓
        Registro en etl.ControlCarga
```

## Tabla de hechos cargada

* `dw.FactVenta`

La tabla almacena una fila por producto incluido en una orden y contiene las claves de las dimensiones relacionadas con fecha, cliente, producto, estado del pedido y fuente de datos.

Las principales medidas almacenadas son:

* `Cantidad`
* `PrecioUnitarioVenta`
* `ImporteTotal`

`NumeroOrdenOrigen` se conserva como identificador de la orden de procedencia.

## Proceso de limpieza

Antes de cada carga se ejecuta el procedimiento:

* `etl.usp_LimpiarFactVenta`

Este procedimiento elimina los registros existentes de `dw.FactVenta` mediante `TRUNCATE TABLE`, permitiendo realizar una recarga completa y evitando la acumulación de registros de ejecuciones anteriores.

El proceso incluye manejo transaccional y control de errores mediante `TRY/CATCH`.

## Transformación y carga

La carga de la tabla de hechos se realiza mediante:

* `etl.usp_CargarFactVenta`

Durante el proceso se realizan las siguientes operaciones:

* Conversión y validación de tipos de datos.
* Eliminación de registros duplicados mediante `ROW_NUMBER()`.
* Relación de los detalles con las órdenes correspondientes.
* Resolución de las claves de `DimFecha`, `DimCliente`, `DimProducto` y `DimEstadoPedido`.
* Asignación de la fuente de datos.
* Cálculo del precio unitario de venta.
* Carga final en `dw.FactVenta`.

Durante la validación se identificaron 60,161 registros en `stg.DetallesOrden`. Se detectaron cuatro registros duplicados, por lo que fueron cargadas 60,157 filas únicas en `dw.FactVenta`.

## Validación entre fuentes

También se compararon los datos de ventas procedentes de los archivos CSV con los registros obtenidos desde la base de datos histórica externa.

Se comprobó que:

* Los CSV contienen 60,157 detalles únicos.
* La base de datos histórica contiene 60,157 detalles.
* Los 60,157 registros coinciden entre ambas fuentes.
* Las 20,000 órdenes también coinciden.

Por esta razón, se utiliza el CSV como fuente prioritaria para la carga de `FactVenta`, evitando duplicar las mismas ventas provenientes de dos fuentes diferentes.

## Orquestación de Facts

El procedimiento:

* `etl.usp_CargarFacts`

funciona como orquestador de la etapa y ejecuta automáticamente:

```
etl.usp_CargarFacts
        ↓
etl.usp_LimpiarFactVenta
        ↓
etl.usp_CargarFactVenta
        ↓
etl.ControlCarga
```

De esta forma, la limpieza siempre se realiza antes de la carga de la tabla de hechos.

## Control de carga

La ejecución se registra en `etl.ControlCarga`.

En la ejecución final se obtuvo:

* Filas leídas: 60,161
* Filas insertadas: 60,157
* Filas descartadas por duplicidad: 4
* Estado: `Completada`
* Claves dimensionales desconocidas: 0

## Integración con .NET

Se agregaron los siguientes componentes:

* `IFactLoader`: contrato para ejecutar la carga de tablas de hechos.
* `FactLoader`: servicio encargado de ejecutar `etl.usp_CargarFacts` desde .NET.
* `Worker.cs`: actualizado para ejecutar la carga de hechos después de la carga de dimensiones.
* `Program.cs`: actualizado para registrar `IFactLoader` y `FactLoader` mediante inyección de dependencias.

El flujo final automatizado del Worker Service es:

```
Extracción multifuente
        ↓
Carga a staging
        ↓
Carga de dimensiones
        ↓
Limpieza de FactVenta
        ↓
Carga de FactVenta
        ↓
Registro de control
        ↓
Finalización del ETL
```

La ejecución integrada final del proceso ETL terminó correctamente en aproximadamente **17.987 segundos**.

## Scripts SQL de Facts

Los scripts correspondientes a esta etapa se encuentran en:

`BaseDatos/Facts`

* `01_etl.usp_LimpiarFactVenta.sql`
* `02_etl.usp_CargarFactVenta.sql`
* `03_etl.usp_CargarFacts.sql`
* `04_Validacion_Carga_FactVenta.sql`


## Repositorio

Proyecto disponible en:

https://github.com/ambar-c/SistemaVentasETL
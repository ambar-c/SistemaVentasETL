USE DW_SistemaVentas;
GO

/* ============================================================
   PROCEDIMIENTO: etl.usp_CargarDimFuenteDatos

   Descripción:
   Mantiene actualizado el catálogo de fuentes utilizadas
   por el proceso ETL.

   Características:
   - Carga incremental.
   - No elimina registros existentes.
   - No duplica fuentes.
   - Puede ejecutarse varias veces de forma segura.
   ============================================================ */

CREATE OR ALTER PROCEDURE etl.usp_CargarDimFuenteDatos
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @FilasInsertadas INT = 0;
    DECLARE @FilasActualizadas INT = 0;

    DECLARE @Fuentes TABLE
    (
        NombreFuente  NVARCHAR(150) NOT NULL PRIMARY KEY,
        TipoFuente    NVARCHAR(50)  NOT NULL,
        SistemaOrigen NVARCHAR(150) NULL,
        Descripcion   NVARCHAR(300) NULL
    );

    INSERT INTO @Fuentes
    (
        NombreFuente,
        TipoFuente,
        SistemaOrigen,
        Descripcion
    )
    VALUES
    (
        N'Archivos CSV del proyecto',
        N'CSV',
        N'products.csv, customers.csv, orders.csv y order_details.csv',
        N'Archivos iniciales proporcionados para el proyecto.'
    ),
    (
        N'API REST externa',
        N'API REST',
        N'Servicio externo de clientes y productos',
        N'Fuente destinada a actualizar información de clientes y productos.'
    ),
    (
        N'Base de datos histórica externa',
        N'Base de datos',
        N'SQL Server o MySQL externo',
        N'Fuente destinada a integrar ventas históricas de una base de datos externa.'
    );

    BEGIN TRY
        BEGIN TRANSACTION;

        /* Actualizar únicamente cuando algún dato haya cambiado. */
        UPDATE destino
        SET
            destino.TipoFuente = origen.TipoFuente,
            destino.SistemaOrigen = origen.SistemaOrigen,
            destino.Descripcion = origen.Descripcion
        FROM dw.DimFuenteDatos AS destino
        INNER JOIN @Fuentes AS origen
            ON destino.NombreFuente = origen.NombreFuente
        WHERE
               destino.TipoFuente <> origen.TipoFuente
            OR ISNULL(destino.SistemaOrigen, N'')
                <> ISNULL(origen.SistemaOrigen, N'')
            OR ISNULL(destino.Descripcion, N'')
                <> ISNULL(origen.Descripcion, N'');

        SET @FilasActualizadas = @@ROWCOUNT;

        /* Insertar solamente las fuentes que todavía no existen. */
        INSERT INTO dw.DimFuenteDatos
        (
            NombreFuente,
            TipoFuente,
            SistemaOrigen,
            Descripcion,
            FechaRegistro
        )
        SELECT
            origen.NombreFuente,
            origen.TipoFuente,
            origen.SistemaOrigen,
            origen.Descripcion,
            SYSDATETIME()
        FROM @Fuentes AS origen
        WHERE NOT EXISTS
        (
            SELECT 1
            FROM dw.DimFuenteDatos AS destino
            WHERE destino.NombreFuente = origen.NombreFuente
        );

        SET @FilasInsertadas = @@ROWCOUNT;

        COMMIT TRANSACTION;

        SELECT
            N'DimFuenteDatos' AS Dimension,
            @FilasInsertadas AS FilasInsertadas,
            @FilasActualizadas AS FilasActualizadas,
            N'Completada' AS EstadoCarga;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;
GO

--
CREATE OR ALTER PROCEDURE etl.usp_CargarDimEstadoPedido
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @FilasInsertadas INT = 0;
    DECLARE @FilasActualizadas INT = 0;
    DECLARE @EstadosNoReconocidos INT = 0;

    /* ========================================================
       1. Reunir los estados encontrados en staging
       ======================================================== */

    DECLARE @EstadosOrigen TABLE
    (
        EstadoOriginal NVARCHAR(50) NOT NULL
    );

    INSERT INTO @EstadosOrigen
    (
        EstadoOriginal
    )
    SELECT
        LTRIM(RTRIM(Status))
    FROM stg.Ordenes
    WHERE Status IS NOT NULL
      AND LTRIM(RTRIM(Status)) <> N''

    UNION ALL

    SELECT
        LTRIM(RTRIM(Estado))
    FROM stg.PedidosBD
    WHERE Estado IS NOT NULL
      AND LTRIM(RTRIM(Estado)) <> N'';


    /* ========================================================
       2. Definir las reglas de negocio de cada estado
       ======================================================== */

    DECLARE @CatalogoEstados TABLE
    (
        Estado            NVARCHAR(50)  NOT NULL PRIMARY KEY,
        EsVentaValida     BIT           NOT NULL,
        EsVentaCompletada BIT           NOT NULL,
        Descripcion       NVARCHAR(250) NULL
    );

    INSERT INTO @CatalogoEstados
    (
        Estado,
        EsVentaValida,
        EsVentaCompletada,
        Descripcion
    )
    VALUES
    (
        N'Pending',
        0,
        0,
        N'Orden pendiente de procesamiento.'
    ),
    (
        N'Delivered',
        1,
        1,
        N'Orden entregada y completada.'
    ),
    (
        N'Cancelled',
        0,
        0,
        N'Orden cancelada; no representa ingreso válido.'
    ),
    (
        N'Shipped',
        1,
        0,
        N'Orden enviada y considerada venta activa.'
    );


    /* ========================================================
       3. Normalizar los estados encontrados
       ======================================================== */

    DECLARE @EstadosDetectados TABLE
    (
        Estado NVARCHAR(50) NOT NULL PRIMARY KEY
    );

    INSERT INTO @EstadosDetectados
    (
        Estado
    )
    SELECT DISTINCT
        CASE UPPER(LTRIM(RTRIM(EstadoOriginal)))
            WHEN N'PENDING'   THEN N'Pending'
            WHEN N'DELIVERED' THEN N'Delivered'
            WHEN N'CANCELLED' THEN N'Cancelled'
            WHEN N'CANCELED'  THEN N'Cancelled'
            WHEN N'SHIPPED'   THEN N'Shipped'
        END
    FROM @EstadosOrigen
    WHERE UPPER(LTRIM(RTRIM(EstadoOriginal))) IN
    (
        N'PENDING',
        N'DELIVERED',
        N'CANCELLED',
        N'CANCELED',
        N'SHIPPED'
    );


    /* ========================================================
       4. Contar estados que no tienen una regla definida
       ======================================================== */

    SELECT
        @EstadosNoReconocidos = COUNT(*)
    FROM
    (
        SELECT DISTINCT
            UPPER(LTRIM(RTRIM(EstadoOriginal))) AS Estado
        FROM @EstadosOrigen
        WHERE UPPER(LTRIM(RTRIM(EstadoOriginal))) NOT IN
        (
            N'PENDING',
            N'DELIVERED',
            N'CANCELLED',
            N'CANCELED',
            N'SHIPPED'
        )
    ) AS EstadosSinRegla;


    /* ========================================================
       5. Actualizar e insertar la dimensión
       ======================================================== */

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE destino
        SET
            destino.EsVentaValida =
                catalogo.EsVentaValida,

            destino.EsVentaCompletada =
                catalogo.EsVentaCompletada,

            destino.Descripcion =
                catalogo.Descripcion
        FROM dw.DimEstadoPedido AS destino
        INNER JOIN @CatalogoEstados AS catalogo
            ON destino.Estado = catalogo.Estado
        INNER JOIN @EstadosDetectados AS detectado
            ON catalogo.Estado = detectado.Estado
        WHERE
               destino.EsVentaValida
                    <> catalogo.EsVentaValida

            OR destino.EsVentaCompletada
                    <> catalogo.EsVentaCompletada

            OR ISNULL(destino.Descripcion, N'')
                    <> ISNULL(catalogo.Descripcion, N'');

        SET @FilasActualizadas = @@ROWCOUNT;


        INSERT INTO dw.DimEstadoPedido
        (
            Estado,
            EsVentaValida,
            EsVentaCompletada,
            Descripcion,
            FechaCarga
        )
        SELECT
            catalogo.Estado,
            catalogo.EsVentaValida,
            catalogo.EsVentaCompletada,
            catalogo.Descripcion,
            SYSDATETIME()
        FROM @CatalogoEstados AS catalogo
        INNER JOIN @EstadosDetectados AS detectado
            ON catalogo.Estado = detectado.Estado
        WHERE NOT EXISTS
        (
            SELECT 1
            FROM dw.DimEstadoPedido AS destino
            WHERE destino.Estado = catalogo.Estado
        );

        SET @FilasInsertadas = @@ROWCOUNT;

        COMMIT TRANSACTION;


        /* Resultado de control del procedimiento */

        SELECT
            N'DimEstadoPedido' AS Dimension,

            (
                SELECT COUNT(*)
                FROM @EstadosDetectados
            ) AS EstadosReconocidos,

            @EstadosNoReconocidos
                AS EstadosNoReconocidos,

            @FilasInsertadas
                AS FilasInsertadas,

            @FilasActualizadas
                AS FilasActualizadas,

            N'Completada'
                AS EstadoCarga;
    END TRY

    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;
GO

/* ============================================================
   PRUEBA: carga de la dimensión EstadoPedido
   ============================================================ */

EXEC etl.usp_CargarDimEstadoPedido;
GO

SELECT
    EstadoPedidoKey,
    Estado,
    EsVentaValida,
    EsVentaCompletada,
    Descripcion,
    FechaCarga
FROM dw.DimEstadoPedido
ORDER BY EstadoPedidoKey;
GO


/* ============================================================
   PRUEBA: carga de la dimensión Fecha
   ============================================================ */

EXEC etl.usp_CargarDimFecha;
GO

SELECT TOP (10)
    FechaKey,
    FechaCompleta,
    DiaMes,
    DiaSemana,
    NombreDia,
    SemanaAnio,
    Mes,
    NombreMes,
    Trimestre,
    Anio,
    AnioMes,
    EsFinDeSemana
FROM dw.DimFecha
WHERE FechaKey <> 0
ORDER BY FechaCompleta;
GO

SELECT
    COUNT(*) AS TotalRegistrosDimFecha
FROM dw.DimFecha;
GO

/* ============================================================
   PROCEDIMIENTO: etl.usp_CargarDimCliente

   Descripción:
   Extrae los clientes almacenados en staging, valida y
   normaliza sus datos, y mantiene actualizada la dimensión
   dw.DimCliente.

   Fuente:
   - stg.Clientes

   Estrategia:
   - Carga incremental.
   - Actualización tipo SCD 1.
   - Eliminación de duplicados por ClienteIDOrigen.
   - Conversión segura de datos con TRY_CONVERT.
   - Uso de operaciones por conjuntos.
   ============================================================ */

CREATE OR ALTER PROCEDURE etl.usp_CargarDimCliente
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @FuenteDatosKey SMALLINT;
    DECLARE @FilasLeidas INT = 0;
    DECLARE @FilasValidas INT = 0;
    DECLARE @FilasInvalidas INT = 0;
    DECLARE @FilasDuplicadas INT = 0;
    DECLARE @FilasInsertadas INT = 0;
    DECLARE @FilasActualizadas INT = 0;

    /* ========================================================
       1. Obtener la clave de la fuente CSV
       No se codifica directamente el valor 1.
       ======================================================== */

    SELECT
        @FuenteDatosKey = FuenteDatosKey
    FROM dw.DimFuenteDatos
    WHERE NombreFuente = N'Archivos CSV del proyecto';

    IF @FuenteDatosKey IS NULL
    BEGIN
        THROW 50001,
              'No se encontró la fuente Archivos CSV del proyecto.',
              1;
    END;


    /* ========================================================
       2. Contabilizar los registros recibidos
       ======================================================== */

    SELECT
        @FilasLeidas = COUNT(*)
    FROM stg.Clientes;


    /* ========================================================
       3. Identificar registros con identificador inválido
       ======================================================== */

    SELECT
        @FilasInvalidas = COUNT(*)
    FROM stg.Clientes
    WHERE TRY_CONVERT
          (
              INT,
              NULLIF(LTRIM(RTRIM(CustomerID)), N'')
          ) IS NULL;


    /* ========================================================
       4. Identificar identificadores repetidos en staging
       ======================================================== */

    SELECT
        @FilasDuplicadas =
            COUNT(*) -
            COUNT
            (
                DISTINCT TRY_CONVERT
                (
                    INT,
                    NULLIF(LTRIM(RTRIM(CustomerID)), N'')
                )
            )
    FROM stg.Clientes
    WHERE TRY_CONVERT
          (
              INT,
              NULLIF(LTRIM(RTRIM(CustomerID)), N'')
          ) IS NOT NULL;


    /* ========================================================
       5. Crear estructura temporal para la transformación

       Se utiliza una tabla temporal en lugar de procesar cada
       registro individualmente desde C#.
       ======================================================== */

    CREATE TABLE #ClientesTransformados
    (
        ClienteIDOrigen   INT           NOT NULL,
        Nombre            NVARCHAR(100) NOT NULL,
        Apellido          NVARCHAR(100) NOT NULL,
        NombreCompleto    NVARCHAR(250) NOT NULL,
        Email             NVARCHAR(200) NULL,
        Telefono          NVARCHAR(100) NULL,
        Ciudad            NVARCHAR(150) NOT NULL,
        Region            NVARCHAR(150) NOT NULL,
        Pais              NVARCHAR(150) NOT NULL,
        SegmentoCliente   NVARCHAR(100) NOT NULL,
        FuenteDatosKey    SMALLINT      NOT NULL,

        CONSTRAINT PK_Temporal_Clientes
            PRIMARY KEY
            (
                ClienteIDOrigen,
                FuenteDatosKey
            )
    );


    /* ========================================================
       6. Limpiar, normalizar y eliminar duplicados
       ======================================================== */

    ;WITH ClientesPreparados AS
    (
        SELECT
            TRY_CONVERT
            (
                INT,
                NULLIF(LTRIM(RTRIM(CustomerID)), N'')
            ) AS ClienteIDOrigen,

            COALESCE
            (
                NULLIF(LTRIM(RTRIM(FirstName)), N''),
                N'Nombre no especificado'
            ) AS Nombre,

            COALESCE
            (
                NULLIF(LTRIM(RTRIM(LastName)), N''),
                N'Apellido no especificado'
            ) AS Apellido,

            NULLIF
            (
                LTRIM(RTRIM(Email)),
                N''
            ) AS Email,

            NULLIF
            (
                LTRIM(RTRIM(Phone)),
                N''
            ) AS Telefono,

            COALESCE
            (
                NULLIF(LTRIM(RTRIM(City)), N''),
                N'Ciudad no especificada'
            ) AS Ciudad,

            COALESCE
            (
                NULLIF(LTRIM(RTRIM(Country)), N''),
                N'Pais no especificado'
            ) AS Pais,

            ROW_NUMBER() OVER
            (
                PARTITION BY TRY_CONVERT
                (
                    INT,
                    NULLIF(LTRIM(RTRIM(CustomerID)), N'')
                )
                ORDER BY
                    CustomerID,
                    FirstName,
                    LastName
            ) AS NumeroFila
        FROM stg.Clientes
        WHERE TRY_CONVERT
              (
                  INT,
                  NULLIF(LTRIM(RTRIM(CustomerID)), N'')
              ) IS NOT NULL
    )
    INSERT INTO #ClientesTransformados
    (
        ClienteIDOrigen,
        Nombre,
        Apellido,
        NombreCompleto,
        Email,
        Telefono,
        Ciudad,
        Region,
        Pais,
        SegmentoCliente,
        FuenteDatosKey
    )
    SELECT
        ClienteIDOrigen,
        Nombre,
        Apellido,

        LTRIM
        (
            RTRIM
            (
                CONCAT
                (
                    Nombre,
                    N' ',
                    Apellido
                )
            )
        ) AS NombreCompleto,

        Email,
        Telefono,
        Ciudad,
        N'Region no especificada',
        Pais,
        N'Segmento no especificado',
        @FuenteDatosKey
    FROM ClientesPreparados
    WHERE NumeroFila = 1;

    SET @FilasValidas = @@ROWCOUNT;


    /* ========================================================
       7. Actualizar e insertar la dimensión
       ======================================================== */

    BEGIN TRY
        BEGIN TRANSACTION;

        /* Actualizar solamente los clientes que cambiaron. */

        UPDATE destino
        SET
            destino.Nombre = origen.Nombre,
            destino.Apellido = origen.Apellido,
            destino.NombreCompleto = origen.NombreCompleto,
            destino.Email = origen.Email,
            destino.Telefono = origen.Telefono,
            destino.Ciudad = origen.Ciudad,
            destino.Region = origen.Region,
            destino.Pais = origen.Pais,
            destino.SegmentoCliente = origen.SegmentoCliente,
            destino.FechaFinVigencia = CONVERT(DATE, '99991231'),
            destino.EsActual = 1,
            destino.FechaCarga = SYSDATETIME()
        FROM dw.DimCliente AS destino
        INNER JOIN #ClientesTransformados AS origen
            ON destino.ClienteIDOrigen =
               origen.ClienteIDOrigen
           AND destino.FuenteDatosKey =
               origen.FuenteDatosKey
        WHERE
               destino.Nombre <> origen.Nombre

            OR destino.Apellido <> origen.Apellido

            OR destino.NombreCompleto <>
               origen.NombreCompleto

            OR ISNULL(destino.Email, N'') <>
               ISNULL(origen.Email, N'')

            OR ISNULL(destino.Telefono, N'') <>
               ISNULL(origen.Telefono, N'')

            OR destino.Ciudad <> origen.Ciudad

            OR destino.Region <> origen.Region

            OR destino.Pais <> origen.Pais

            OR destino.SegmentoCliente <>
               origen.SegmentoCliente

            OR destino.EsActual <> 1;

        SET @FilasActualizadas = @@ROWCOUNT;


        /* Insertar únicamente clientes que todavía no existen. */

        INSERT INTO dw.DimCliente
        (
            ClienteIDOrigen,
            Nombre,
            Apellido,
            NombreCompleto,
            Email,
            Telefono,
            Ciudad,
            Region,
            Pais,
            SegmentoCliente,
            FechaInicioVigencia,
            FechaFinVigencia,
            EsActual,
            FechaCarga,
            FuenteDatosKey
        )
        SELECT
            origen.ClienteIDOrigen,
            origen.Nombre,
            origen.Apellido,
            origen.NombreCompleto,
            origen.Email,
            origen.Telefono,
            origen.Ciudad,
            origen.Region,
            origen.Pais,
            origen.SegmentoCliente,
            CONVERT(DATE, SYSDATETIME()),
            CONVERT(DATE, '99991231'),
            1,
            SYSDATETIME(),
            origen.FuenteDatosKey
        FROM #ClientesTransformados AS origen
        WHERE NOT EXISTS
        (
            SELECT 1
            FROM dw.DimCliente AS destino
            WHERE destino.ClienteIDOrigen =
                  origen.ClienteIDOrigen

              AND destino.FuenteDatosKey =
                  origen.FuenteDatosKey
        );

        SET @FilasInsertadas = @@ROWCOUNT;

        COMMIT TRANSACTION;


        /* ====================================================
           8. Resultado del procedimiento
           ==================================================== */

        SELECT
            N'DimCliente' AS Dimension,
            @FilasLeidas AS FilasLeidas,
            @FilasValidas AS FilasValidas,
            @FilasInvalidas AS FilasInvalidas,
            @FilasDuplicadas AS FilasDuplicadas,
            @FilasInsertadas AS FilasInsertadas,
            @FilasActualizadas AS FilasActualizadas,
            N'Completada' AS EstadoCarga;
    END TRY

    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;
GO

/* ============================================================
   PRUEBA: carga de la dimensión Cliente
   ============================================================ */

EXEC etl.usp_CargarDimCliente;
GO
SELECT TOP (10)
    ClienteKey,
    ClienteIDOrigen,
    Nombre,
    Apellido,
    NombreCompleto,
    Email,
    Telefono,
    Ciudad,
    Region,
    Pais,
    SegmentoCliente,
    EsActual,
    FuenteDatosKey
FROM dw.DimCliente
WHERE ClienteKey <> 0
ORDER BY ClienteKey;
GO

SELECT
    COUNT(*) AS TotalRegistrosDimCliente
FROM dw.DimCliente;
GO

/* ============================================================
   PROCEDIMIENTO: etl.usp_CargarDimProducto

   Descripción:
   Integra los productos del archivo CSV y de la API REST,
   valida sus campos y mantiene actualizada la dimensión
   dw.DimProducto.

   Fuentes:
   - stg.Productos
   - stg.ProductosAPI

   Estrategia:
   - Carga multifuente.
   - Trazabilidad mediante FuenteDatosKey.
   - Actualización tipo SCD 1.
   - Eliminación de duplicados por producto y fuente.
   - Conversión segura mediante TRY_CONVERT.
   - Procesamiento por conjuntos.
   ============================================================ */

CREATE OR ALTER PROCEDURE etl.usp_CargarDimProducto
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @FuenteCsvKey SMALLINT;
    DECLARE @FuenteApiKey SMALLINT;

    DECLARE @FilasLeidasCsv INT = 0;
    DECLARE @FilasLeidasApi INT = 0;
    DECLARE @FilasValidas INT = 0;
    DECLARE @FilasInvalidas INT = 0;
    DECLARE @FilasDuplicadas INT = 0;
    DECLARE @FilasInsertadas INT = 0;
    DECLARE @FilasActualizadas INT = 0;


    /* ========================================================
       1. Obtener las claves de las fuentes
       ======================================================== */

    SELECT
        @FuenteCsvKey = FuenteDatosKey
    FROM dw.DimFuenteDatos
    WHERE NombreFuente = N'Archivos CSV del proyecto';

    SELECT
        @FuenteApiKey = FuenteDatosKey
    FROM dw.DimFuenteDatos
    WHERE NombreFuente = N'API REST externa';


    IF @FuenteCsvKey IS NULL
    BEGIN
        THROW 50002,
              'No se encontró la fuente Archivos CSV del proyecto.',
              1;
    END;


    IF @FuenteApiKey IS NULL
    BEGIN
        THROW 50003,
              'No se encontró la fuente API REST externa.',
              1;
    END;


    /* ========================================================
       2. Contabilizar los registros recibidos
       ======================================================== */

    SELECT
        @FilasLeidasCsv = COUNT(*)
    FROM stg.Productos;

    SELECT
        @FilasLeidasApi = COUNT(*)
    FROM stg.ProductosAPI;


    /* ========================================================
       3. Unificar temporalmente las dos fuentes

       Se conserva FuenteDatosKey para evitar mezclar productos
       que poseen el mismo identificador en diferentes sistemas.
       ======================================================== */

    CREATE TABLE #ProductosOrigen
    (
        ProductoIDTexto NVARCHAR(50)  NULL,
        NombreProducto  NVARCHAR(200) NULL,
        Categoria       NVARCHAR(100) NULL,
        PrecioTexto     NVARCHAR(50)  NULL,
        StockTexto      NVARCHAR(50)  NULL,
        FuenteDatosKey  SMALLINT      NOT NULL
    );


    INSERT INTO #ProductosOrigen
    (
        ProductoIDTexto,
        NombreProducto,
        Categoria,
        PrecioTexto,
        StockTexto,
        FuenteDatosKey
    )
    SELECT
        ProductID,
        ProductName,
        Category,
        Price,
        Stock,
        @FuenteCsvKey
    FROM stg.Productos;


    INSERT INTO #ProductosOrigen
    (
        ProductoIDTexto,
        NombreProducto,
        Categoria,
        PrecioTexto,
        StockTexto,
        FuenteDatosKey
    )
    SELECT
        ProductID,
        ProductName,
        Category,
        Price,
        Stock,
        @FuenteApiKey
    FROM stg.ProductosAPI;


    /* ========================================================
       4. Contar identificadores inválidos
       ======================================================== */

    SELECT
        @FilasInvalidas = COUNT(*)
    FROM #ProductosOrigen
    WHERE TRY_CONVERT
          (
              INT,
              NULLIF
              (
                  LTRIM(RTRIM(ProductoIDTexto)),
                  N''
              )
          ) IS NULL;


    /* ========================================================
       5. Contar duplicados dentro de una misma fuente
       ======================================================== */

    SELECT
        @FilasDuplicadas =
            SUM(Cantidad - 1)
    FROM
    (
        SELECT
            FuenteDatosKey,

            TRY_CONVERT
            (
                INT,
                NULLIF
                (
                    LTRIM(RTRIM(ProductoIDTexto)),
                    N''
                )
            ) AS ProductoIDOrigen,

            COUNT(*) AS Cantidad
        FROM #ProductosOrigen
        WHERE TRY_CONVERT
              (
                  INT,
                  NULLIF
                  (
                      LTRIM(RTRIM(ProductoIDTexto)),
                      N''
                  )
              ) IS NOT NULL
        GROUP BY
            FuenteDatosKey,

            TRY_CONVERT
            (
                INT,
                NULLIF
                (
                    LTRIM(RTRIM(ProductoIDTexto)),
                    N''
                )
            )
        HAVING COUNT(*) > 1
    ) AS ProductosRepetidos;

    SET @FilasDuplicadas =
        ISNULL(@FilasDuplicadas, 0);


    /* ========================================================
       6. Crear la estructura de productos transformados
       ======================================================== */

    CREATE TABLE #ProductosTransformados
    (
        ProductoIDOrigen INT            NOT NULL,
        NombreProducto   NVARCHAR(200)  NOT NULL,
        Categoria        NVARCHAR(100)  NOT NULL,
        PrecioLista      DECIMAL(18, 2) NULL,
        StockActual      INT            NULL,
        FuenteDatosKey   SMALLINT       NOT NULL,

        CONSTRAINT PK_Temporal_Productos
            PRIMARY KEY
            (
                ProductoIDOrigen,
                FuenteDatosKey
            )
    );


    /* ========================================================
       7. Limpiar, convertir y eliminar duplicados
       ======================================================== */

    ;WITH ProductosPreparados AS
    (
        SELECT
            TRY_CONVERT
            (
                INT,
                NULLIF
                (
                    LTRIM(RTRIM(ProductoIDTexto)),
                    N''
                )
            ) AS ProductoIDOrigen,

            COALESCE
            (
                NULLIF
                (
                    LTRIM(RTRIM(NombreProducto)),
                    N''
                ),
                N'Producto no especificado'
            ) AS NombreProducto,

            COALESCE
            (
                NULLIF
                (
                    LTRIM(RTRIM(Categoria)),
                    N''
                ),
                N'Categoria no especificada'
            ) AS Categoria,

            TRY_CONVERT
            (
                DECIMAL(18, 2),
                NULLIF
                (
                    LTRIM(RTRIM(PrecioTexto)),
                    N''
                )
            ) AS PrecioLista,

            TRY_CONVERT
            (
                INT,
                NULLIF
                (
                    LTRIM(RTRIM(StockTexto)),
                    N''
                )
            ) AS StockActual,

            FuenteDatosKey,

            ROW_NUMBER() OVER
            (
                PARTITION BY
                    FuenteDatosKey,

                    TRY_CONVERT
                    (
                        INT,
                        NULLIF
                        (
                            LTRIM(RTRIM(ProductoIDTexto)),
                            N''
                        )
                    )

                ORDER BY
                    ProductoIDTexto,
                    NombreProducto
            ) AS NumeroFila
        FROM #ProductosOrigen
        WHERE TRY_CONVERT
              (
                  INT,
                  NULLIF
                  (
                      LTRIM(RTRIM(ProductoIDTexto)),
                      N''
                  )
              ) IS NOT NULL
    )
    INSERT INTO #ProductosTransformados
    (
        ProductoIDOrigen,
        NombreProducto,
        Categoria,
        PrecioLista,
        StockActual,
        FuenteDatosKey
    )
    SELECT
        ProductoIDOrigen,
        NombreProducto,
        Categoria,
        PrecioLista,
        StockActual,
        FuenteDatosKey
    FROM ProductosPreparados
    WHERE NumeroFila = 1;

    SET @FilasValidas = @@ROWCOUNT;


    /* ========================================================
       8. Actualizar e insertar la dimensión
       ======================================================== */

    BEGIN TRY
        BEGIN TRANSACTION;


        /* Actualizar únicamente los productos modificados. */

        UPDATE destino
        SET
            destino.NombreProducto =
                origen.NombreProducto,

            destino.Categoria =
                origen.Categoria,

            destino.PrecioLista =
                origen.PrecioLista,

            destino.StockActual =
                origen.StockActual,

            destino.FechaFinVigencia =
                CONVERT(DATE, '99991231'),

            destino.EsActual = 1,

            destino.FechaCarga =
                SYSDATETIME()
        FROM dw.DimProducto AS destino
        INNER JOIN #ProductosTransformados AS origen
            ON destino.ProductoIDOrigen =
               origen.ProductoIDOrigen

           AND destino.FuenteDatosKey =
               origen.FuenteDatosKey
        WHERE
               destino.NombreProducto <>
               origen.NombreProducto

            OR destino.Categoria <>
               origen.Categoria

            OR ISNULL(destino.PrecioLista, -1) <>
               ISNULL(origen.PrecioLista, -1)

            OR ISNULL(destino.StockActual, -1) <>
               ISNULL(origen.StockActual, -1)

            OR destino.EsActual <> 1;

        SET @FilasActualizadas = @@ROWCOUNT;


        /* Insertar productos que todavía no existen. */

        INSERT INTO dw.DimProducto
        (
            ProductoIDOrigen,
            NombreProducto,
            Categoria,
            PrecioLista,
            StockActual,
            FechaInicioVigencia,
            FechaFinVigencia,
            EsActual,
            FechaCarga,
            FuenteDatosKey
        )
        SELECT
            origen.ProductoIDOrigen,
            origen.NombreProducto,
            origen.Categoria,
            origen.PrecioLista,
            origen.StockActual,
            CONVERT(DATE, SYSDATETIME()),
            CONVERT(DATE, '99991231'),
            1,
            SYSDATETIME(),
            origen.FuenteDatosKey
        FROM #ProductosTransformados AS origen
        WHERE NOT EXISTS
        (
            SELECT 1
            FROM dw.DimProducto AS destino
            WHERE destino.ProductoIDOrigen =
                  origen.ProductoIDOrigen

              AND destino.FuenteDatosKey =
                  origen.FuenteDatosKey
        );

        SET @FilasInsertadas = @@ROWCOUNT;


        COMMIT TRANSACTION;


        /* ====================================================
           9. Resultado del procedimiento
           ==================================================== */

        SELECT
            N'DimProducto' AS Dimension,
            @FilasLeidasCsv AS FilasLeidasCSV,
            @FilasLeidasApi AS FilasLeidasAPI,
            @FilasLeidasCsv + @FilasLeidasApi
                AS TotalFilasLeidas,
            @FilasValidas AS FilasValidas,
            @FilasInvalidas AS FilasInvalidas,
            @FilasDuplicadas AS FilasDuplicadas,
            @FilasInsertadas AS FilasInsertadas,
            @FilasActualizadas AS FilasActualizadas,
            N'Completada' AS EstadoCarga;
    END TRY

    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;
GO

/* ============================================================
   PRUEBA: carga de la dimensión Producto
   ============================================================ */

EXEC etl.usp_CargarDimProducto;
GO

SELECT
    f.NombreFuente,
    COUNT(*) AS CantidadProductos
FROM dw.DimProducto AS p
INNER JOIN dw.DimFuenteDatos AS f
    ON p.FuenteDatosKey = f.FuenteDatosKey
WHERE p.ProductoKey <> 0
GROUP BY
    f.NombreFuente
ORDER BY
    f.NombreFuente;
GO


SELECT
    COUNT(*) AS TotalRegistrosDimProducto
FROM dw.DimProducto;
GO

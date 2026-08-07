USE DW_SistemaVentas;
GO

/* ============================================================
   PROCEDIMIENTO: etl.usp_CargarDimensiones

   Descripción:
   Orquesta la ejecución de todas las dimensiones del
   Data Warehouse respetando su orden lógico.

   Orden:
   1. DimFuenteDatos
   2. DimEstadoPedido
   3. DimFecha
   4. DimCliente
   5. DimProducto

   Diseño:
   Cada dimensión administra su propia transacción, de modo
   que la lógica permanezca modular, mantenible y reutilizable.
   ============================================================ */

CREATE OR ALTER PROCEDURE etl.usp_CargarDimensiones
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @FechaInicio DATETIME2(0) = SYSDATETIME();
    DECLARE @FechaFin DATETIME2(0);

    DECLARE @ControlCargaKey INT;

    DECLARE @FilasLeidas INT = 0;
    DECLARE @FilasInsertadas INT = 0;
    DECLARE @FilasActualizadas INT = 0;
    DECLARE @FilasRechazadas INT = 0;

    /* ========================================================
       Tablas temporales para capturar el resultado devuelto
       por cada procedimiento individual.
       ======================================================== */

    CREATE TABLE #ResultadoFuente
    (
        Dimension NVARCHAR(100),
        FilasInsertadas INT,
        FilasActualizadas INT,
        EstadoCarga NVARCHAR(50)
    );

    CREATE TABLE #ResultadoEstado
    (
        Dimension NVARCHAR(100),
        EstadosReconocidos INT,
        EstadosNoReconocidos INT,
        FilasInsertadas INT,
        FilasActualizadas INT,
        EstadoCarga NVARCHAR(50)
    );

    CREATE TABLE #ResultadoFecha
    (
        Dimension NVARCHAR(100),
        FilasLeidas INT,
        FechasDetectadas INT,
        FechasInvalidas INT,
        FilasInsertadas INT,
        FilasActualizadas INT,
        EstadoCarga NVARCHAR(50)
    );

    CREATE TABLE #ResultadoCliente
    (
        Dimension NVARCHAR(100),
        FilasLeidas INT,
        FilasValidas INT,
        FilasInvalidas INT,
        FilasDuplicadas INT,
        FilasInsertadas INT,
        FilasActualizadas INT,
        EstadoCarga NVARCHAR(50)
    );

    CREATE TABLE #ResultadoProducto
    (
        Dimension NVARCHAR(100),
        FilasLeidasCSV INT,
        FilasLeidasAPI INT,
        TotalFilasLeidas INT,
        FilasValidas INT,
        FilasInvalidas INT,
        FilasDuplicadas INT,
        FilasInsertadas INT,
        FilasActualizadas INT,
        EstadoCarga NVARCHAR(50)
    );

    BEGIN TRY

        /* ====================================================
           1. Registrar el inicio del proceso
           FuenteDatosKey 0 representa una ejecución multifuente.
           ==================================================== */

        INSERT INTO etl.ControlCarga
        (
            FuenteDatosKey,
            NombreProceso,
            ArchivoOrigen,
            FechaInicio,
            FechaFin,
            EstadoCarga,
            FilasLeidas,
            FilasInsertadas,
            FilasActualizadas,
            FilasRechazadas,
            MensajeError
        )
        VALUES
        (
            0,
            N'Carga incremental de dimensiones',
            N'stg.Clientes, stg.Productos, stg.ProductosAPI, stg.Ordenes y stg.PedidosBD',
            @FechaInicio,
            NULL,
            N'Iniciada',
            0,
            0,
            0,
            0,
            NULL
        );

        SET @ControlCargaKey =
            CONVERT(INT, SCOPE_IDENTITY());


        /* ====================================================
           2. Ejecutar las dimensiones en orden
           ==================================================== */

        INSERT INTO #ResultadoFuente
        EXEC etl.usp_CargarDimFuenteDatos;

        INSERT INTO #ResultadoEstado
        EXEC etl.usp_CargarDimEstadoPedido;

        INSERT INTO #ResultadoFecha
        EXEC etl.usp_CargarDimFecha;

        INSERT INTO #ResultadoCliente
        EXEC etl.usp_CargarDimCliente;

        INSERT INTO #ResultadoProducto
        EXEC etl.usp_CargarDimProducto;


        /* ====================================================
           3. Calcular métricas generales

           Las filas leídas corresponden a las tablas staging
           utilizadas específicamente por las dimensiones.
           ==================================================== */

        SELECT
            @FilasLeidas =
                  (SELECT COUNT(*) FROM stg.Clientes)
                + (SELECT COUNT(*) FROM stg.Productos)
                + (SELECT COUNT(*) FROM stg.ProductosAPI)
                + (SELECT COUNT(*) FROM stg.Ordenes)
                + (SELECT COUNT(*) FROM stg.PedidosBD);


        SELECT
            @FilasInsertadas =
                  ISNULL(
                      (SELECT FilasInsertadas
                       FROM #ResultadoFuente),
                      0
                  )
                + ISNULL(
                      (SELECT FilasInsertadas
                       FROM #ResultadoEstado),
                      0
                  )
                + ISNULL(
                      (SELECT FilasInsertadas
                       FROM #ResultadoFecha),
                      0
                  )
                + ISNULL(
                      (SELECT FilasInsertadas
                       FROM #ResultadoCliente),
                      0
                  )
                + ISNULL(
                      (SELECT FilasInsertadas
                       FROM #ResultadoProducto),
                      0
                  );


        SELECT
            @FilasActualizadas =
                  ISNULL(
                      (SELECT FilasActualizadas
                       FROM #ResultadoFuente),
                      0
                  )
                + ISNULL(
                      (SELECT FilasActualizadas
                       FROM #ResultadoEstado),
                      0
                  )
                + ISNULL(
                      (SELECT FilasActualizadas
                       FROM #ResultadoFecha),
                      0
                  )
                + ISNULL(
                      (SELECT FilasActualizadas
                       FROM #ResultadoCliente),
                      0
                  )
                + ISNULL(
                      (SELECT FilasActualizadas
                       FROM #ResultadoProducto),
                      0
                  );


        SELECT
            @FilasRechazadas =
                  ISNULL(
                      (SELECT EstadosNoReconocidos
                       FROM #ResultadoEstado),
                      0
                  )
                + ISNULL(
                      (SELECT FechasInvalidas
                       FROM #ResultadoFecha),
                      0
                  )
                + ISNULL(
                      (
                          SELECT
                              FilasInvalidas
                              + FilasDuplicadas
                          FROM #ResultadoCliente
                      ),
                      0
                  )
                + ISNULL(
                      (
                          SELECT
                              FilasInvalidas
                              + FilasDuplicadas
                          FROM #ResultadoProducto
                      ),
                      0
                  );


        SET @FechaFin = SYSDATETIME();


        /* ====================================================
           4. Finalizar el registro de auditoría
           ==================================================== */

        UPDATE etl.ControlCarga
        SET
            FechaFin = @FechaFin,
            EstadoCarga = N'Completada',
            FilasLeidas = @FilasLeidas,
            FilasInsertadas = @FilasInsertadas,
            FilasActualizadas = @FilasActualizadas,
            FilasRechazadas = @FilasRechazadas,
            MensajeError = NULL
        WHERE ControlCargaKey = @ControlCargaKey;


        /* ====================================================
           5. Mostrar los resultados de cada dimensión
           ==================================================== */

        SELECT * FROM #ResultadoFuente;
        SELECT * FROM #ResultadoEstado;
        SELECT * FROM #ResultadoFecha;
        SELECT * FROM #ResultadoCliente;
        SELECT * FROM #ResultadoProducto;


        /* ====================================================
           6. Resumen general
           ==================================================== */

        SELECT
            @ControlCargaKey AS ControlCargaKey,
            N'Carga general de dimensiones' AS Proceso,
            N'Completada' AS EstadoCarga,
            @FechaInicio AS FechaInicio,
            @FechaFin AS FechaFin,

            DATEDIFF
            (
                MILLISECOND,
                @FechaInicio,
                @FechaFin
            ) AS DuracionMilisegundos,

            @FilasLeidas AS FilasLeidas,
            @FilasInsertadas AS FilasInsertadas,
            @FilasActualizadas AS FilasActualizadas,
            @FilasRechazadas AS FilasRechazadas,

            (
                SELECT COUNT(*)
                FROM dw.DimFuenteDatos
            ) AS TotalDimFuenteDatos,

            (
                SELECT COUNT(*)
                FROM dw.DimEstadoPedido
            ) AS TotalDimEstadoPedido,

            (
                SELECT COUNT(*)
                FROM dw.DimFecha
            ) AS TotalDimFecha,

            (
                SELECT COUNT(*)
                FROM dw.DimCliente
            ) AS TotalDimCliente,

            (
                SELECT COUNT(*)
                FROM dw.DimProducto
            ) AS TotalDimProducto;
    END TRY

    BEGIN CATCH

        SET @FechaFin = SYSDATETIME();

        IF @ControlCargaKey IS NOT NULL
        BEGIN
            UPDATE etl.ControlCarga
            SET
                FechaFin = @FechaFin,
                EstadoCarga = N'Fallida',
                FilasLeidas = @FilasLeidas,
                FilasInsertadas = @FilasInsertadas,
                FilasActualizadas = @FilasActualizadas,
                FilasRechazadas = @FilasRechazadas,
                MensajeError = ERROR_MESSAGE()
            WHERE ControlCargaKey = @ControlCargaKey;
        END;

        SELECT
            N'Carga general de dimensiones' AS Proceso,
            N'Fallida' AS EstadoCarga,
            @FechaInicio AS FechaInicio,
            @FechaFin AS FechaFin,
            ERROR_NUMBER() AS NumeroError,
            ERROR_PROCEDURE() AS ProcedimientoError,
            ERROR_LINE() AS LineaError,
            ERROR_MESSAGE() AS MensajeError;

        THROW;
    END CATCH;
END;
GO

EXEC etl.usp_CargarDimensiones;
GO

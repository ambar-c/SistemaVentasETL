USE DW_SistemaVentas;
GO

CREATE OR ALTER PROCEDURE etl.usp_CargarFacts
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @FechaInicio DATETIME2(3) = SYSDATETIME();
    DECLARE @FechaFin DATETIME2(3);

    DECLARE @ControlCargaKey BIGINT;

    DECLARE @FilasLeidas INT = 0;
    DECLARE @FilasInsertadas INT = 0;
    DECLARE @FilasActualizadas INT = 0;
    DECLARE @FilasRechazadas INT = 0;

    BEGIN TRY

        /* =====================================================
           1. Registrar inicio del proceso ETL
           ===================================================== */

        SELECT @FilasLeidas = COUNT(*)
        FROM stg.DetallesOrden;

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
            1,
            N'Carga completa de FactVenta',
            N'stg.Ordenes, stg.DetallesOrden',
            @FechaInicio,
            NULL,
            N'Iniciada',
            @FilasLeidas,
            0,
            0,
            0,
            NULL
        );

        SET @ControlCargaKey = SCOPE_IDENTITY();


        /* =====================================================
           2. Iniciar transacción general
           ===================================================== */

        BEGIN TRANSACTION;


        /* =====================================================
           3. Limpiar FactVenta
           REQUISITO: limpiar antes de cargar
           ===================================================== */

        EXEC etl.usp_LimpiarFactVenta;


        /* =====================================================
           4. Cargar nuevamente FactVenta
           ===================================================== */

        EXEC etl.usp_CargarFactVenta;


        /* =====================================================
           5. Obtener cantidad final
           ===================================================== */

        SELECT @FilasInsertadas = COUNT(*)
        FROM dw.FactVenta;

        SET @FilasRechazadas =
            @FilasLeidas - @FilasInsertadas;


        /* =====================================================
           6. Confirmar la carga
           ===================================================== */

        COMMIT TRANSACTION;

        SET @FechaFin = SYSDATETIME();


        /* =====================================================
           7. Actualizar control ETL como completado
           ===================================================== */

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


        /* =====================================================
           8. Resultado final
           ===================================================== */

        SELECT
            @ControlCargaKey AS ControlCargaKey,
            N'dw.FactVenta' AS Tabla,
            @FilasLeidas AS FilasLeidas,
            @FilasInsertadas AS FilasInsertadas,
            @FilasRechazadas AS FilasRechazadas,
            N'Completada' AS EstadoCarga,
            @FechaInicio AS FechaInicio,
            @FechaFin AS FechaFin;

    END TRY

    BEGIN CATCH

        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        SET @FechaFin = SYSDATETIME();

        IF @ControlCargaKey IS NOT NULL
        BEGIN
            UPDATE etl.ControlCarga
            SET
                FechaFin = @FechaFin,
                EstadoCarga = N'Fallida',
                FilasLeidas = @FilasLeidas,
                FilasInsertadas = 0,
                FilasActualizadas = 0,
                FilasRechazadas = @FilasLeidas,
                MensajeError = ERROR_MESSAGE()
            WHERE ControlCargaKey = @ControlCargaKey;
        END;

        THROW;

    END CATCH;
END;
GO
USE DW_SistemaVentas;
GO

CREATE OR ALTER PROCEDURE etl.usp_LimpiarFactVenta
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @RegistrosAntes BIGINT;

    BEGIN TRY

        SELECT @RegistrosAntes = COUNT_BIG(*)
        FROM dw.FactVenta;

        BEGIN TRANSACTION;

        TRUNCATE TABLE dw.FactVenta;

        COMMIT TRANSACTION;

        SELECT
            'dw.FactVenta' AS Tabla,
            @RegistrosAntes AS RegistrosAntes,
            COUNT_BIG(*) AS RegistrosDespues,
            SYSDATETIME() AS FechaLimpieza
        FROM dw.FactVenta;

    END TRY
    BEGIN CATCH

        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        THROW;

    END CATCH;
END;
GO
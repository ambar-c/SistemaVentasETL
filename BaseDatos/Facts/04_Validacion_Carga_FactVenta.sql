USE DW_SistemaVentas;
GO

/* ============================================================
   VALIDACIÓN FINAL DE LA CARGA DE FactVenta
   ============================================================ */


/* 1. Cantidad total de registros */
SELECT COUNT(*) AS TotalFactVenta
FROM dw.FactVenta;
GO


/* 2. Última ejecución del proceso de Facts */
SELECT TOP (1)
    ControlCargaKey,
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
FROM etl.ControlCarga
WHERE NombreProceso = N'Carga completa de FactVenta'
ORDER BY ControlCargaKey DESC;
GO


/* 3. Validación de claves dimensionales desconocidas */
SELECT
    SUM(CASE WHEN FechaKey = 0 THEN 1 ELSE 0 END)
        AS FechasDesconocidas,

    SUM(CASE WHEN ClienteKey = 0 THEN 1 ELSE 0 END)
        AS ClientesDesconocidos,

    SUM(CASE WHEN ProductoKey = 0 THEN 1 ELSE 0 END)
        AS ProductosDesconocidos,

    SUM(CASE WHEN EstadoPedidoKey = 0 THEN 1 ELSE 0 END)
        AS EstadosDesconocidos,

    SUM(CASE WHEN FuenteDatosKey = 0 THEN 1 ELSE 0 END)
        AS FuentesDesconocidas
FROM dw.FactVenta;
GO


/* 4. Muestra de registros cargados */
SELECT TOP (10)
    VentaKey,
    NumeroOrdenOrigen,
    FechaKey,
    ClienteKey,
    ProductoKey,
    EstadoPedidoKey,
    FuenteDatosKey,
    Cantidad,
    PrecioUnitarioVenta,
    ImporteTotal,
    FechaCarga
FROM dw.FactVenta
ORDER BY VentaKey;
GO
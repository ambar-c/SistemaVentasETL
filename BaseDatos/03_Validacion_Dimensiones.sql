USE DW_SistemaVentas;
GO

/* ============================================================
   1. CONTEO GENERAL DE LAS DIMENSIONES
   ============================================================ */

SELECT
    'DimFuenteDatos' AS Dimension,
    COUNT(*) AS TotalRegistros
FROM dw.DimFuenteDatos

UNION ALL

SELECT
    'DimEstadoPedido',
    COUNT(*)
FROM dw.DimEstadoPedido

UNION ALL

SELECT
    'DimFecha',
    COUNT(*)
FROM dw.DimFecha

UNION ALL

SELECT
    'DimCliente',
    COUNT(*)
FROM dw.DimCliente

UNION ALL

SELECT
    'DimProducto',
    COUNT(*)
FROM dw.DimProducto;
GO


/* ============================================================
   2. DIMENSIÓN FUENTE DE DATOS POBLADA
   ============================================================ */

SELECT
    FuenteDatosKey,
    NombreFuente,
    TipoFuente,
    SistemaOrigen,
    Descripcion,
    FechaRegistro
FROM dw.DimFuenteDatos
ORDER BY FuenteDatosKey;
GO


/* ============================================================
   3. DIMENSIÓN ESTADO DE PEDIDO POBLADA
   ============================================================ */

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
   4. MUESTRA DE LA DIMENSIÓN FECHA
   ============================================================ */

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


/* ============================================================
   5. MUESTRA DE LA DIMENSIÓN CLIENTE
   ============================================================ */

SELECT TOP (10)
    ClienteKey,
    ClienteIDOrigen,
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


/* ============================================================
   6. MUESTRA DE LA DIMENSIÓN PRODUCTO CON SU FUENTE
   ============================================================ */

SELECT TOP (15)
    p.ProductoKey,
    p.ProductoIDOrigen,
    p.NombreProducto,
    p.Categoria,
    p.PrecioLista,
    p.StockActual,
    p.EsActual,
    f.NombreFuente
FROM dw.DimProducto AS p
INNER JOIN dw.DimFuenteDatos AS f
    ON p.FuenteDatosKey = f.FuenteDatosKey
WHERE p.ProductoKey <> 0
ORDER BY
    f.FuenteDatosKey,
    p.ProductoIDOrigen;
GO


/* ============================================================
   7. PRODUCTOS AGRUPADOS POR FUENTE
   ============================================================ */

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

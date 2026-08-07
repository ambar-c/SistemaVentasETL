namespace SistemaVentasETL.Interfaces;

public interface IDimensionLoader
{
    Task LoadDimensionsAsync(
        CancellationToken cancellationToken = default);
}
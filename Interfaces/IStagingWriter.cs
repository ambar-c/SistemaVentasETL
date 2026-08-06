namespace SistemaVentasETL.Interfaces;

public interface IStagingWriter
{
    Task WriteAsync<T>(
        IReadOnlyCollection<T> records,
        CancellationToken cancellationToken = default);
}
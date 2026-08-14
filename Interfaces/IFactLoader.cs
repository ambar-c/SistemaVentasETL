namespace SistemaVentasETL.Interfaces
{
    public interface IFactLoader
    {
        Task LoadFactsAsync(CancellationToken cancellationToken);
    }
}
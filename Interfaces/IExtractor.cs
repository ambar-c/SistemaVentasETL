using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;

namespace SistemaVentasETL.Interfaces;

public interface IExtractor<T>
{
    Task<IReadOnlyList<T>> ExtractAsync(
        CancellationToken cancellationToken = default);
}
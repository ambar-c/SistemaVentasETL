namespace SistemaVentasETL.Models;

public class HistoricalOrderDetail
{
    public long OrderDetailID { get; set; }

    public int OrderID { get; set; }

    public int ProductID { get; set; }

    public int Quantity { get; set; }

    public decimal UnitPrice { get; set; }

    public decimal TotalPrice { get; set; }

    public DateTime CreatedAt { get; set; }
}
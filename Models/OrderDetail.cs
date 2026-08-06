namespace SistemaVentasETL.Models;

public class OrderDetail
{
    public int OrderID { get; set; }

    public int ProductID { get; set; }

    public int Quantity { get; set; }

    public decimal TotalPrice { get; set; }
}
namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>
/// App Mobile HU-27: lee con IA el total de la boleta o factura fotografiada al rendir un gasto. Devuelve null si no se pudo leer, si la IA no está
/// configurada o si falla: el gasto se registra igual y el Jefe de Operaciones lo revisa como siempre.
/// </summary>
public interface ILectorComprobanteIa
{
    Task<decimal?> LeerTotalAsync(byte[] imagenJpeg, CancellationToken ct);
}

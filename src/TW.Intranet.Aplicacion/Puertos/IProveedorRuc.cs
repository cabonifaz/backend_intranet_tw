using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>
/// Proveedor externo de datos de RUC (OpenRUC u otro). Se pueden registrar varios:
/// el caso de uso los prueba en orden de registro hasta que uno encuentre el RUC.
/// Nunca lanza excepciones: todo error se devuelve en el resultado.
/// </summary>
public interface IProveedorRuc
{
    /// <summary>Código corto del proveedor (se guarda en caché y log), ej. "openruc".</summary>
    string Nombre { get; }

    /// <summary>true si el proveedor puede consultar este RUC (ej. OpenRUC solo cubre RUC 20).</summary>
    bool Cubre(string ruc);

    Task<ResultadoProveedorRucDto> ConsultarAsync(string ruc, CancellationToken ct);
}

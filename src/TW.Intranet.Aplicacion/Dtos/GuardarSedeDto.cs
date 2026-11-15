using System.ComponentModel.DataAnnotations;

namespace TW.Intranet.Aplicacion.Dtos;

public record GuardarSedeDto(
    long    IdSede,
    long    IdCliente,
    [Required][StringLength(200)] string  Nombre,
    [StringLength(100)]           string? TipoInstalacion,
    [Required][StringLength(100)] string? Region,
    [Required][StringLength(100)] string? Provincia,
    [Required][StringLength(100)] string? Distrito,
    // Pistas de llegada ("frente al grifo Primax, portón negro"); antes Urbanizacion.
    [StringLength(200)]           string? Referencia,
    [Required][StringLength(500)] string  DireccionExacta,
    // Ubicación exacta de la planta (pin del mapa). Las dos o ninguna; al editar, null = se conserva la actual.
    // El rango de Perú lo valida SP_GuardarSede (responde 400 con el mensaje de negocio).
    decimal? Latitud  = null,
    decimal? Longitud = null,
    // true = borra la ubicación guardada (al editar).
    bool QuitarUbicacion = false,
    // TRANSICIÓN: nombre viejo de Referencia, mientras el front no se actualice. Se usa solo si Referencia no llega. Quitar cuando el front envíe "referencia".
    [StringLength(200)] string? Urbanizacion = null
)
{
    /// <summary>Referencia que se guarda: la nueva si llega; si no, la del campo viejo "urbanizacion".</summary>
    public string? ReferenciaFinal => Referencia ?? Urbanizacion;
}

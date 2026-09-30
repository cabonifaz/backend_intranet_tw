using System.ComponentModel.DataAnnotations;

namespace TW.Intranet.Aplicacion.Dtos;

public record GuardarRequerimientoComandoDto(
    long      IdRequerimiento,
    [Range(1, long.MaxValue, ErrorMessage = "Debe seleccionar un cliente.")]
    long      IdCliente,
    long?     IdSede,
    long?     IdContacto,
    [Range(1, int.MaxValue, ErrorMessage = "Debe seleccionar un origen.")]
    int       IdOrigen,
    [Range(1, int.MaxValue, ErrorMessage = "Debe seleccionar un área.")]
    int       IdArea,
    [Range(1, int.MaxValue, ErrorMessage = "Debe seleccionar una prioridad.")]
    int       IdPrioridad,
    DateTime? FechaNecesidad,
    [Required][StringLength(2000, MinimumLength = 10)]
    string    Descripcion,
    bool      NotificarCorreo,
    bool      RequiereVisita,
    bool      ClienteDeuda
);

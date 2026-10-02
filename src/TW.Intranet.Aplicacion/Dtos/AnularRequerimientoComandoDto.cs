using System.ComponentModel.DataAnnotations;

namespace TW.Intranet.Aplicacion.Dtos;

public record AnularRequerimientoComandoDto(
    [Range(1, int.MaxValue, ErrorMessage = "Debe seleccionar un motivo.")]
    int    IdMotivo,
    [Required][StringLength(1000, MinimumLength = 10)]
    string Justificacion
);

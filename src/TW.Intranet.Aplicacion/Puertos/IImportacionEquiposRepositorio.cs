using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>Importación de equipos de una propuesta desde Excel.</summary>
public interface IImportacionEquiposRepositorio
{
    /// <summary>
    /// Equipos, sedes y clasificaciones del cliente, catálogo de suministros (equipo / instrumento / pesa) y los
    /// equipos de OTROS clientes cuya serie normalizada (solo letras y dígitos, en mayúsculas) está en la lista.
    /// </summary>
    Task<RespuestaDto<CandidatosImportacionEquiposDto>> ObtenerCandidatosAsync(
        long idCliente, IReadOnlyList<string> seriesNormalizadas, long idUsuario, CancellationToken ct);

    /// <summary>Valida todas las filas y, si no hay errores, crea los equipos nuevos (todo o nada).</summary>
    Task<RespuestaDto<ResultadoImportacionEquiposDto>> ImportarAsync(
        ConfirmarImportacionEquiposSolicitudDto solicitud, long idUsuario, CancellationToken ct);
}

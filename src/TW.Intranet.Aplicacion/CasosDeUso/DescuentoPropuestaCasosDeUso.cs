using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ─────────────────────────────────────────────────────────────────────────────
// HU-11 — Aplicación de Descuento Comercial. Validaciones de forma aquí. Las de
// negocio (borrador, permiso, motivo válido, tope del subtotal) están en
// SP_AplicarDescuentoPropuesta, que usa la misma fórmula que SP_GuardarPropuesta.
// ─────────────────────────────────────────────────────────────────────────────

/// <summary>Calcula los nuevos montos sin guardar (previsualización en tiempo real).</summary>
public class PrevisualizarDescuentoPropuestaCasoDeUso(IPropuestasRepositorio repositorio)
{
    public async Task<RespuestaDto<DescuentoPropuestaResultadoDto>> EjecutarAsync(
        long idPropuesta, AplicarDescuentoPropuestaDto dto, long idUsuario, CancellationToken ct = default)
    {
        var error = DescuentoValidacion.Validar(idPropuesta, dto, exigirMotivo: false);
        if (error is not null)
            return new RespuestaDto<DescuentoPropuestaResultadoDto>(1, error);

        return await repositorio.AplicarDescuentoAsync(
            idPropuesta, DescuentoValidacion.Tipo(dto), dto.Valor, dto.IdMotivoDescuento,
            soloPrevisualizar: true, idUsuario, ct);
    }
}

/// <summary>Aplica y guarda el descuento global.</summary>
public class AplicarDescuentoPropuestaCasoDeUso(IPropuestasRepositorio repositorio)
{
    public async Task<RespuestaDto<DescuentoPropuestaResultadoDto>> EjecutarAsync(
        long idPropuesta, AplicarDescuentoPropuestaDto dto, long idUsuario, CancellationToken ct = default)
    {
        var error = DescuentoValidacion.Validar(idPropuesta, dto, exigirMotivo: true);
        if (error is not null)
            return new RespuestaDto<DescuentoPropuestaResultadoDto>(1, error);

        return await repositorio.AplicarDescuentoAsync(
            idPropuesta, DescuentoValidacion.Tipo(dto), dto.Valor, dto.IdMotivoDescuento,
            soloPrevisualizar: false, idUsuario, ct);
    }
}

/// <summary>Quita el descuento global de la propuesta.</summary>
public class QuitarDescuentoPropuestaCasoDeUso(IPropuestasRepositorio repositorio)
{
    public async Task<RespuestaDto<DescuentoPropuestaResultadoDto>> EjecutarAsync(
        long idPropuesta, long idUsuario, CancellationToken ct = default)
    {
        if (idPropuesta <= 0)
            return new RespuestaDto<DescuentoPropuestaResultadoDto>(1, "Indique la propuesta.");

        return await repositorio.AplicarDescuentoAsync(
            idPropuesta, "ninguno", 0, null, soloPrevisualizar: false, idUsuario, ct);
    }
}

internal static class DescuentoValidacion
{
    public static string Tipo(AplicarDescuentoPropuestaDto dto) => (dto.Tipo ?? "").Trim().ToLowerInvariant();

    public static string? Validar(long idPropuesta, AplicarDescuentoPropuestaDto? dto, bool exigirMotivo)
    {
        if (idPropuesta <= 0)
            return "Indique la propuesta.";
        if (dto is null)
            return "Indique el descuento a aplicar.";

        var tipo = Tipo(dto);
        // En previsualización se admite 'ninguno' para leer el estado actual sin simular descuento.
        var tiposValidos = exigirMotivo ? new[] { "porcentaje", "monto" } : new[] { "porcentaje", "monto", "ninguno" };
        if (!tiposValidos.Contains(tipo))
            return "Seleccione el tipo de descuento (porcentaje o monto fijo).";
        if (tipo != "ninguno")
        {
            if (dto.Valor <= 0)
                return tipo == "porcentaje" ? "Ingrese un porcentaje mayor a 0." : "Ingrese un monto mayor a 0.";
            if (tipo == "porcentaje" && dto.Valor > 100)
                return "El porcentaje no puede ser mayor a 100.";
            if (decimal.Round(dto.Valor, 2) != dto.Valor)
                return "El descuento admite como máximo 2 decimales.";
        }
        if (exigirMotivo && (dto.IdMotivoDescuento is null || dto.IdMotivoDescuento <= 0))
            return "Seleccione el motivo del descuento.";

        return null;
    }
}

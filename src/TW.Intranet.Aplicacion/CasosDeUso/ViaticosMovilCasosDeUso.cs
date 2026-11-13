using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ── App Mobile HU-25 / HU-26 — Viáticos y gastos ────────────────────────────────

/// <summary>
/// Viáticos que el Jefe de Operaciones asignó al técnico al programar y los gastos que rindió.
/// El técnico sale del token: nadie puede pedir los de otro. Las reglas (depositado, rendido, por rendir, saldo) viven en el SP.
/// </summary>
/// <summary>HU-27: conceptos del gasto (catálogo de la intranet) para solicitar un reembolso.</summary>
public class ObtenerConceptosGastoMovilCasoDeUso(IViaticosMovilRepositorio repositorio)
{
    public Task<RespuestaDto<List<ConceptoGastoMovilDto>>> EjecutarAsync(long idUsuario, CancellationToken ct = default)
        => idUsuario <= 0
            ? Task.FromResult(new RespuestaDto<List<ConceptoGastoMovilDto>>(1, "No se pudo identificar al usuario."))
            : repositorio.ObtenerConceptosAsync(idUsuario, ct);
}

public class ObtenerViaticosMovilCasoDeUso(IViaticosMovilRepositorio repositorio)
{
    public Task<RespuestaDto<ViaticosMovilDto>> EjecutarAsync(long idUsuario, CancellationToken ct = default)
    {
        if (idUsuario <= 0)
            return Task.FromResult(new RespuestaDto<ViaticosMovilDto>(1, "No se pudo identificar al usuario."));

        return repositorio.ObtenerAsync(idUsuario, ct);
    }
}

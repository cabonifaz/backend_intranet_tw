using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ═══════════════════════════════════════════════════════════════════════════
// Módulo Órdenes de Servicio / Metrología (OS / OM), Sprint 4.
// ═══════════════════════════════════════════════════════════════════════════

/// <summary>HU-41 Bandeja consolidada de OS y OM: tarjetas por estado, filtros, filas y paginación.</summary>
public class ObtenerBandejaOrdenesServicioCasoDeUso(IOrdenServicioRepositorio repositorio)
{
    internal static readonly string[] Estados =
        ["", "todas", "todos", "borrador", "emitida", "programada", "en_ejecucion", "finalizada", "anulada"];

    public Task<RespuestaDto<BandejaOrdenesServicioDto>> EjecutarAsync(FiltrosBandejaOrdenesServicioDto f, long idUsuario, CancellationToken ct = default)
    {
        var (filtros, error) = Normalizar(f);
        return error is not null
            ? Task.FromResult(new RespuestaDto<BandejaOrdenesServicioDto>(1, error))
            : repositorio.ObtenerBandejaAsync(filtros!, false, idUsuario, ct);
    }

    internal static (FiltrosBandejaOrdenesServicioDto? Filtros, string? Error) Normalizar(FiltrosBandejaOrdenesServicioDto f)
    {
        var estado = f.Estado?.Trim().ToLowerInvariant() ?? "";
        if (!Estados.Contains(estado))
            return (null, "Estado no válido. Use todas, borrador, emitida, programada, en_ejecucion, finalizada o anulada.");

        var tipo = f.Tipo?.Trim().ToUpperInvariant() ?? "";
        if (tipo is not ("" or "TODOS" or "OS" or "OM"))
            return (null, "Tipo no válido. Use OS, OM o todos.");

        if (f.FechaDesde is { } desde && f.FechaHasta is { } hasta && desde.Date > hasta.Date)
            return (null, "La fecha desde no puede ser posterior a la fecha hasta.");

        var busqueda = f.Busqueda?.Trim();
        return (new FiltrosBandejaOrdenesServicioDto
        {
            Estado        = estado,
            Tipo          = tipo is "" or "TODOS" ? null : tipo,
            IdCliente     = f.IdCliente     is > 0 ? f.IdCliente     : null,
            IdResponsable = f.IdResponsable is > 0 ? f.IdResponsable : null,
            FechaDesde    = f.FechaDesde?.Date,
            FechaHasta    = f.FechaHasta?.Date,
            Busqueda      = string.IsNullOrEmpty(busqueda) ? null : busqueda[..Math.Min(busqueda.Length, 200)],
            Pagina        = Math.Max(1, f.Pagina),
            PorPagina     = f.PorPagina is < 1 or > 100 ? 10 : f.PorPagina,
        }, null);
    }
}

/// <summary>HU-41 Exportar XLSX: todas las filas con los filtros aplicados.</summary>
public class ExportarBandejaOrdenesServicioCasoDeUso(IOrdenServicioRepositorio repositorio, IGeneradorExcel excel)
{
    private const string TipoXlsx = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";

    public async Task<RespuestaDto<ArchivoGeneradoDto>> EjecutarAsync(FiltrosBandejaOrdenesServicioDto f, long idUsuario, CancellationToken ct = default)
    {
        var (filtros, error) = ObtenerBandejaOrdenesServicioCasoDeUso.Normalizar(f);
        if (error is not null) return new(1, error);

        var r = await repositorio.ObtenerBandejaAsync(filtros!, true, idUsuario, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null) return new(r.IdTipoMensaje, r.Mensaje);

        var hoja = new HojaExcel("Órdenes de servicio",
            ["N° OS/OM", "Tipo", "Fecha de emisión", "Cliente", "RUC", "Propuesta origen", "Responsable de la orden",
             "N° equipos", "N° conceptos", "Estado", "Solicitud de edición pendiente"],
            r.Datos.Items.Select(x => (IReadOnlyList<object?>)
            [
                x.Numero, x.Tipo, x.FechaEmision, x.RazonSocial, x.Ruc,
                x.NumeroPropuesta is null ? null : x.VersionPropuesta is > 1 ? $"{x.NumeroPropuesta} (v{x.VersionPropuesta})" : x.NumeroPropuesta,
                x.Responsable, x.NumeroEquipos, x.NumeroConceptos, x.EstadoLabel, x.SolicitudPendiente ? "Sí" : "No",
            ]).ToList());

        return new(2, "Bandeja exportada.",
            new ArchivoGeneradoDto(excel.Generar([hoja]), $"Ordenes-Servicio-{DateTime.Now:yyyyMMdd-HHmm}.xlsx", TipoXlsx));
    }
}

using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ── HU-35 Bandeja de Programación Operativa (Sprint 5) ──────────────────────
// La bandeja solo lee: cada fila indica qué acciones puede hacer el usuario (Programar HU-36, Reprogramar HU-38,
// Cancelar = anulación de la OS/OM ya existente, Ver detalle = detalle de la OS/OM ya existente).

/// <summary>
/// Validación y normalización de la entrada de la bandeja. Desarrollo seguro: los valores de texto que llegan al SP
/// salen de listas cerradas, los identificadores deben ser positivos y los tamaños y rangos tienen tope.
/// </summary>
internal static class EntradaProgramacion
{
    internal static readonly string[] SubEstados =
        ["", "todos", "pendiente_programar", "pendiente_conf_cliente", "pendiente_reprogramacion", "pendiente_ssoma"];

    internal static readonly string[] Rangos =
        ["", "todos", "hoy", "esta_semana", "proxima_semana", "personalizado"];

    internal const int MaxBusqueda  = 200;
    internal const int MaxZona      = 100;
    internal const int MaxPagina    = 10_000;
    internal const int MaxDiasRango = 366;

    /// <param name="programados">true para el tab Programados (rango de fechas, por defecto "todos"); false para Pendientes.</param>
    internal static (FiltrosProgramacionDto? Filtros, string? Error) Normalizar(FiltrosProgramacionDto f, bool programados)
    {
        var subEstado = f.SubEstado?.Trim().ToLowerInvariant() ?? "";
        if (!SubEstados.Contains(subEstado))
            return (null, "Sub-estado no válido. Use todos, pendiente_programar, pendiente_conf_cliente, pendiente_reprogramacion o pendiente_ssoma.");

        var rango = f.Rango?.Trim().ToLowerInvariant() ?? "";
        if (!Rangos.Contains(rango))
            return (null, "Rango no válido. Use todos, hoy, esta_semana, proxima_semana o personalizado.");

        var tipo = f.Tipo?.Trim().ToUpperInvariant() ?? "";
        if (tipo is not ("" or "TODOS" or "OS" or "OM"))
            return (null, "Tipo no válido. Use OS, OM o todos.");

        DateTime? desde = null, hasta = null;
        if (programados)
        {
            if (rango == "") rango = "todos";   // sin rango = todas las fechas (el front no envía el parámetro para "Todos")
            if (rango == "personalizado")
            {
                desde = f.FechaDesde?.Date;
                hasta = f.FechaHasta?.Date;
                if (desde is null && hasta is null)
                    return (null, "Indique la fecha desde o la fecha hasta para el rango personalizado.");
                if (desde is { } d && hasta is { } h)
                {
                    if (d > h) return (null, "La fecha desde no puede ser posterior a la fecha hasta.");
                    if ((h - d).TotalDays > MaxDiasRango) return (null, $"El rango no puede superar {MaxDiasRango} días.");
                }
            }
        }

        var busqueda = f.Busqueda?.Trim();
        var zona     = f.Zona?.Trim();
        if (zona is { Length: > MaxZona })
            return (null, "La zona no es válida.");
        return (new FiltrosProgramacionDto
        {
            SubEstado  = subEstado is "" or "todos" ? null : subEstado,
            Rango      = programados ? (rango == "todos" ? null : rango) : null,
            FechaDesde = desde,
            FechaHasta = hasta,
            Tipo       = tipo is "" or "TODOS" ? null : tipo,
            IdCliente  = f.IdCliente is > 0 ? f.IdCliente : null,
            IdArea     = f.IdArea    is > 0 ? f.IdArea    : null,
            IdTecnico  = f.IdTecnico is > 0 ? f.IdTecnico : null,
            IdSede     = f.IdSede    is > 0 ? f.IdSede    : null,
            Zona       = string.IsNullOrEmpty(zona) || zona.Equals("todas", StringComparison.OrdinalIgnoreCase) ? null : zona,
            Busqueda   = string.IsNullOrEmpty(busqueda) ? null : busqueda[..Math.Min(busqueda.Length, MaxBusqueda)],
            Pagina     = Math.Clamp(f.Pagina, 1, MaxPagina),
            PorPagina  = f.PorPagina is < 1 or > 100 ? 10 : f.PorPagina,
        }, null);
    }

    /// <summary>Semana a mostrar: una fecha razonable (2020 hasta dos años adelante).</summary>
    internal static string? ValidarFechaSemana(DateTime? fecha)
        => fecha is { } f && (f.Year < 2020 || f.Date > DateTime.Today.AddYears(2))
            ? "La fecha de la semana no es válida."
            : null;
}

/// <summary>HU-35 Tab Vista Principal: tarjetas, calendario semanal, matriz de carga y alertas.</summary>
public class ObtenerResumenProgramacionCasoDeUso(IProgramacionOperativaRepositorio repositorio)
{
    /// <param name="busqueda">Opcional: acota el calendario (N° OS/OM, cliente, RUC o técnico). Tope de 200 caracteres.</param>
    public Task<RespuestaDto<ResumenProgramacionDto>> EjecutarAsync(DateTime? fechaSemana, string? busqueda, long idUsuario, CancellationToken ct = default)
    {
        var error = EntradaProgramacion.ValidarFechaSemana(fechaSemana);
        if (error is not null)
            return Task.FromResult(new RespuestaDto<ResumenProgramacionDto>(1, error));

        var texto = busqueda?.Trim();
        return repositorio.ObtenerResumenAsync(
            fechaSemana?.Date,
            string.IsNullOrEmpty(texto) ? null : texto[..Math.Min(texto.Length, EntradaProgramacion.MaxBusqueda)],
            idUsuario, ct);
    }
}

/// <summary>HU-35 Tab Pendientes.</summary>
public class ObtenerPendientesProgramacionCasoDeUso(IProgramacionOperativaRepositorio repositorio)
{
    public Task<RespuestaDto<ListaProgramacionDto>> EjecutarAsync(FiltrosProgramacionDto f, long idUsuario, CancellationToken ct = default)
    {
        var (filtros, error) = EntradaProgramacion.Normalizar(f, programados: false);
        return error is not null
            ? Task.FromResult(new RespuestaDto<ListaProgramacionDto>(1, error))
            : repositorio.ObtenerPendientesAsync(filtros!, false, idUsuario, ct);
    }
}

/// <summary>HU-35 Tab Programados.</summary>
public class ObtenerProgramadosProgramacionCasoDeUso(IProgramacionOperativaRepositorio repositorio)
{
    public Task<RespuestaDto<ListaProgramacionDto>> EjecutarAsync(FiltrosProgramacionDto f, long idUsuario, CancellationToken ct = default)
    {
        var (filtros, error) = EntradaProgramacion.Normalizar(f, programados: true);
        return error is not null
            ? Task.FromResult(new RespuestaDto<ListaProgramacionDto>(1, error))
            : repositorio.ObtenerProgramadosAsync(filtros!, false, idUsuario, ct);
    }
}

/// <summary>HU-35 Exportar XLSX de Pendientes: todas las filas (hasta 5000) con los filtros aplicados.</summary>
public class ExportarPendientesProgramacionCasoDeUso(IProgramacionOperativaRepositorio repositorio, IGeneradorExcel excel)
{
    private const string TipoXlsx = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";

    public async Task<RespuestaDto<ArchivoGeneradoDto>> EjecutarAsync(FiltrosProgramacionDto f, long idUsuario, CancellationToken ct = default)
    {
        var (filtros, error) = EntradaProgramacion.Normalizar(f, programados: false);
        if (error is not null) return new(1, error);

        var r = await repositorio.ObtenerPendientesAsync(filtros!, true, idUsuario, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null) return new(r.IdTipoMensaje, r.Mensaje);

        var hoja = new HojaExcel("Pendientes",
            ["N° OS/OM", "Tipo", "Tipo de servicio", "Cliente", "RUC", "Propuesta", "Sub-estado", "Motivo SSOMA", "Fecha propuesta",
             "Técnico", "Técnicos de apoyo", "Sede", "Zona", "Área", "Días en espera"],
            r.Datos.Items.Select(x => (IReadOnlyList<object?>)
            [
                x.Numero, x.Tipo, x.TipoServicio, x.RazonSocial, x.Ruc, Propuesta(x), x.SubEstadoLabel, x.SsomaMotivo,
                FechaPropuesta(x), x.Tecnico, x.TecnicosApoyo, x.Sede, x.Zona, x.Area, x.DiasEnEspera,
            ]).ToList());

        return new(2, "Pendientes exportados.",
            new ArchivoGeneradoDto(excel.Generar([hoja]), $"Programacion-Pendientes-{DateTime.Now:yyyyMMdd-HHmm}.xlsx", TipoXlsx));
    }

    /// <summary>Fecha y horario programados; si todavía no se programa, el rango tentativo que fijó Comercial.</summary>
    internal static string? FechaPropuesta(ItemProgramacionDto x)
        => x.FechaEjecucion is not null
            ? (x.HoraInicio is null ? x.FechaEjecucion : $"{x.FechaEjecucion} {x.HoraInicio}-{x.HoraFin}")
            : x.FechaProgramadaDesde is null ? null
            : x.FechaProgramadaHasta is null || x.FechaProgramadaHasta == x.FechaProgramadaDesde
                ? $"Tentativa {x.FechaProgramadaDesde}"
                : $"Tentativa {x.FechaProgramadaDesde} a {x.FechaProgramadaHasta}";

    internal static string EstadoViatico(string estado) => estado switch
    {
        "depositado"         => "Depositado",
        "pendiente_deposito" => "Pendiente de depósito",
        _                    => "Sin asignar",
    };

    internal static string? Propuesta(ItemProgramacionDto x)
        => x.NumeroPropuesta is null ? null
         : x.VersionPropuesta is > 1 ? $"{x.NumeroPropuesta} (v{x.VersionPropuesta})" : x.NumeroPropuesta;
}

/// <summary>HU-35 Exportar XLSX de Programados: todas las filas (hasta 5000) con los filtros aplicados.</summary>
public class ExportarProgramadosProgramacionCasoDeUso(IProgramacionOperativaRepositorio repositorio, IGeneradorExcel excel)
{
    private const string TipoXlsx = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";

    public async Task<RespuestaDto<ArchivoGeneradoDto>> EjecutarAsync(FiltrosProgramacionDto f, long idUsuario, CancellationToken ct = default)
    {
        var (filtros, error) = EntradaProgramacion.Normalizar(f, programados: true);
        if (error is not null) return new(1, error);

        var r = await repositorio.ObtenerProgramadosAsync(filtros!, true, idUsuario, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null) return new(r.IdTipoMensaje, r.Mensaje);

        var hoja = new HojaExcel("Programados",
            ["N° OS/OM", "Tipo", "Tipo de servicio", "Cliente", "RUC", "Propuesta", "Fecha de ejecución", "Hora inicio", "Hora fin",
             "Técnico", "Técnicos de apoyo", "Sede", "Zona", "Moneda", "Viáticos", "Estado de viáticos"],
            r.Datos.Items.Select(x => (IReadOnlyList<object?>)
            [
                x.Numero, x.Tipo, x.TipoServicio, x.RazonSocial, x.Ruc, ExportarPendientesProgramacionCasoDeUso.Propuesta(x),
                x.FechaEjecucion, x.HoraInicio, x.HoraFin, x.Tecnico, x.TecnicosApoyo, x.Sede, x.Zona,
                x.ViaticoMoneda, x.ViaticoMonto, ExportarPendientesProgramacionCasoDeUso.EstadoViatico(x.ViaticoEstado),
            ]).ToList());

        return new(2, "Programados exportados.",
            new ArchivoGeneradoDto(excel.Generar([hoja]), $"Programacion-Programados-{DateTime.Now:yyyyMMdd-HHmm}.xlsx", TipoXlsx));
    }
}

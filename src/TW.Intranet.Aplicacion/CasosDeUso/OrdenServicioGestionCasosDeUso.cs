using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Aplicacion.Servicios;

namespace TW.Intranet.Aplicacion.CasosDeUso;

// ═══════════════════════════════════════════════════════════════════════════
// Módulo Órdenes de Servicio / Metrología (OS / OM), Sprint 4: HU-40, HU-42, HU-43 y HU-44.
// (HU-41 Bandeja en OrdenServicioCasosDeUso.cs)
// ═══════════════════════════════════════════════════════════════════════════

// ── HU-40 Crear / editar ─────────────────────────────────────────────────────

/// <summary>Modal "Elegir Propuesta Aceptada": propuestas aceptadas sin OS/OM activa.</summary>
public class ObtenerPropuestasDisponiblesOsCasoDeUso(IOrdenServicioRepositorio repositorio)
{
    public Task<RespuestaDto<PropuestasDisponiblesOsDto>> EjecutarAsync(FiltrosPropuestasDisponiblesOsDto f, long idUsuario, CancellationToken ct = default)
    {
        f.Busqueda  = GuardarOrdenServicioCasoDeUso.Recortar(f.Busqueda, 200);
        f.Tipo      = GuardarOrdenServicioCasoDeUso.Recortar(f.Tipo, 5)?.ToUpperInvariant();
        f.Pagina    = Math.Max(1, f.Pagina);
        f.PorPagina = f.PorPagina is < 1 or > 100 ? 10 : f.PorPagina;
        return repositorio.ObtenerPropuestasDisponiblesAsync(f, idUsuario, ct);
    }
}

/// <summary>Catálogos MOTIVO_EDICION_OS (tipo = edicion) y MOTIVO_ANULACION_OS (tipo = anulacion).</summary>
public class ObtenerMotivosOrdenServicioCasoDeUso(IOrdenServicioRepositorio repositorio)
{
    public Task<RespuestaDto<List<OpcionFiltroDto>>> EjecutarAsync(string tipo, long idUsuario, CancellationToken ct = default) =>
        tipo is "edicion" or "anulacion"
            ? repositorio.ObtenerMotivosAsync(tipo, idUsuario, ct)
            : Task.FromResult(new RespuestaDto<List<OpcionFiltroDto>>(1, "Tipo de motivo no válido."));
}

/// <summary>Ficha Nueva OS/OM desde una propuesta aceptada (idPropuesta) o Editar (idOs).</summary>
public class PrepararOrdenServicioCasoDeUso(IOrdenServicioRepositorio repositorio)
{
    public Task<RespuestaDto<FichaOrdenServicioDto>> EjecutarAsync(long? idPropuesta, long? idOs, long idUsuario, CancellationToken ct = default)
    {
        if (idOs is not > 0 && idPropuesta is not > 0)
            return Task.FromResult(new RespuestaDto<FichaOrdenServicioDto>(1, "Indique la propuesta aceptada o la orden a editar."));
        return repositorio.PrepararAsync(idOs is > 0 ? null : idPropuesta, idOs is > 0 ? idOs : null, idUsuario, ct);
    }
}

/// <summary>Guardar borrador, Emitir, o Guardar cambios y re-emitir (con edición aprobada). idOs = 0: nueva.</summary>
public class GuardarOrdenServicioCasoDeUso(IOrdenServicioRepositorio repositorio)
{
    public Task<RespuestaDto<OrdenServicioGuardadaDto>> EjecutarAsync(long idOs, GuardarOrdenServicioDto? d, long idUsuario, CancellationToken ct = default)
    {
        static Task<RespuestaDto<OrdenServicioGuardadaDto>> Error(string m) => Task.FromResult(new RespuestaDto<OrdenServicioGuardadaDto>(1, m));

        if (d is null) return Error("Envíe los datos de la orden.");
        if (!d.Emitir) return Error("Las órdenes de servicio deben emitirse al guardar.");
        if (idOs <= 0 && d.IdPropuesta is not > 0) return Error("Indique la propuesta aceptada que origina la orden.");
        if (d.FechaProgramadaDesde is { } desde && d.FechaProgramadaHasta is { } hasta && desde.Date > hasta.Date)
            return Error("La fecha programada \"Desde\" no puede ser posterior a \"Hasta\".");
        if ((d.Observaciones?.Trim().Length ?? 0) > 2000) return Error("Las observaciones admiten hasta 2000 caracteres.");

        // Conceptos: el mismo suministro puede repetirse con otro alcance (cada ítem de la propuesta es un concepto)
        var conceptos = d.ConceptosDetalle ?? d.Conceptos.Select(c => new ConceptoGuardarOsDto { IdSuministro = c }).ToList();
        if (conceptos.Count > 200) return Error("Una orden admite hasta 200 conceptos.");
        if (d.Equipos.Count > 1000) return Error("Una orden admite hasta 1000 equipos.");
        if (conceptos.Any(c => c is null || c.IdSuministro <= 0) || d.Equipos.Any(e => e.IdEquipo <= 0))
            return Error("Hay conceptos o equipos no válidos.");
        if (conceptos.Any(c => (c.Alcance?.Trim().Length ?? 0) > 100)) return Error("El alcance de un concepto admite hasta 100 caracteres.");
        var guardados = conceptos.Where(c => c.IdOsConcepto is > 0).Select(c => c.IdOsConcepto!.Value).ToList();
        if (guardados.Distinct().Count() != guardados.Count) return Error("Hay conceptos repetidos (mismo idOsConcepto).");
        if (d.Equipos.Select(e => e.IdEquipo).Distinct().Count() != d.Equipos.Count) return Error("Hay equipos repetidos.");
        if (d.Equipos.Any(e => e.ConceptosIdx is { } idx ? idx.Any(i => i < 0 || i >= conceptos.Count)
                                                         : e.Conceptos.Any(c => conceptos.All(x => x.IdSuministro != c))))
            return Error("Un equipo tiene asignado un concepto que no está en la sección Conceptos del Servicio.");
        foreach (var c in conceptos) c.Alcance = Recortar(c.Alcance, 100);
        d.ConceptosDetalle = conceptos;

        d.Observaciones   = Recortar(d.Observaciones, 2000);
        d.CertRazonSocial = Recortar(d.CertRazonSocial, 300);
        d.CertRuc         = Recortar(d.CertRuc, 20);
        d.CertDireccion   = Recortar(d.CertDireccion, 500);
        d.CertContacto    = Recortar(d.CertContacto, 200);
        if (d.Importacion is { } imp)
        {
            imp.NombreArchivo = Recortar(Path.GetFileName(imp.NombreArchivo ?? ""), 200);
            imp.Modo = imp.Modo?.Trim().ToLowerInvariant() == "reemplazar" ? "reemplazar" : "fusionar";
        }
        return repositorio.GuardarAsync(Math.Max(0, idOs), d, idUsuario, ct);
    }

    internal static string? Recortar(string? s, int max)
    {
        if (string.IsNullOrWhiteSpace(s)) return null;
        s = s.Trim();
        return s.Length > max ? s[..max] : s;
    }
}

/// <summary>Modal "Solicitar Edición al Jefe Comercial": motivos y a quién se dirige.</summary>
public class PrepararSolicitudEdicionOsCasoDeUso(IOrdenServicioRepositorio repositorio)
{
    public Task<RespuestaDto<PreparacionSolicitudEdicionOsDto>> EjecutarAsync(long idOs, long idUsuario, CancellationToken ct = default) =>
        idOs <= 0 ? Task.FromResult(new RespuestaDto<PreparacionSolicitudEdicionOsDto>(1, "Orden no válida."))
                  : repositorio.PrepararSolicitudEdicionAsync(idOs, idUsuario, ct);
}

/// <summary>El comercial responsable solicita la edición: notificación (campanita) y correo al Jefe Comercial.</summary>
public class SolicitarEdicionOsCasoDeUso(IOrdenServicioRepositorio repositorio, NotificadorCorreo notificador, OpcionesCorreo opciones)
{
    public async Task<RespuestaDto<SolicitudEdicionOsDto>> EjecutarAsync(long idOs, SolicitarEdicionOsDto? d, long idUsuario, CancellationToken ct = default)
    {
        if (idOs <= 0) return new(1, "Orden no válida.");
        if (d is null || d.IdMotivo <= 0) return new(1, "Seleccione el motivo de la edición.");
        var comentario = d.Comentario?.Trim() ?? "";
        if (comentario.Length < 20) return new(1, "El comentario es obligatorio (mínimo 20 caracteres).");
        if (comentario.Length > 500) return new(1, "El comentario admite hasta 500 caracteres.");

        var r = await repositorio.SolicitarEdicionAsync(idOs, d.IdMotivo, comentario, idUsuario, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null || string.IsNullOrWhiteSpace(r.Datos.CorreoDestinatario)) return r;

        var envio = await notificador.EnviarAsync("os_solicitud_edicion", PlantillasCorreo.SolicitudEdicionOs(r.Datos, opciones),
                                                  "orden_servicio", idOs, idUsuario, ct);
        return new(2, envio.Enviado ? r.Mensaje : $"{r.Mensaje} No se pudo enviar el correo; se notificó en la intranet.",
                   r.Datos with { CorreoEnviado = envio.Enviado, ErrorCorreo = envio.Error });
    }
}

/// <summary>El Jefe Comercial aprueba o rechaza la edición: notificación y correo al comercial.</summary>
public class ResolverSolicitudEdicionOsCasoDeUso(IOrdenServicioRepositorio repositorio, NotificadorCorreo notificador, OpcionesCorreo opciones)
{
    public async Task<RespuestaDto<SolicitudEdicionOsDto>> EjecutarAsync(long idSolicitud, ResolverSolicitudEdicionOsDto? d, long idUsuario,
                                                                        CancellationToken ct = default)
    {
        if (idSolicitud <= 0) return new(1, "Solicitud no válida.");
        if (d is null) return new(1, "Indique si aprueba o rechaza la edición.");
        var comentario = d.Comentario?.Trim();
        if (!d.Aprobar && (comentario?.Length ?? 0) < 10) return new(1, "Indique el motivo del rechazo (mínimo 10 caracteres).");
        if ((comentario?.Length ?? 0) > 500) return new(1, "El comentario admite hasta 500 caracteres.");

        var r = await repositorio.ResolverSolicitudEdicionAsync(idSolicitud, d.Aprobar, string.IsNullOrEmpty(comentario) ? null : comentario, idUsuario, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null || string.IsNullOrWhiteSpace(r.Datos.CorreoDestinatario)) return r;

        var envio = await notificador.EnviarAsync(d.Aprobar ? "os_edicion_aprobada" : "os_edicion_rechazada",
                                                  PlantillasCorreo.ResolucionEdicionOs(r.Datos, opciones), "orden_servicio", r.Datos.IdOs, idUsuario, ct);
        return new(2, envio.Enviado ? r.Mensaje : $"{r.Mensaje} No se pudo enviar el correo; se notificó en la intranet.",
                   r.Datos with { CorreoEnviado = envio.Enviado, ErrorCorreo = envio.Error });
    }
}

/// <summary>Modal Anular: impacto en la programación y motivos.</summary>
public class PrepararAnulacionOsCasoDeUso(IOrdenServicioRepositorio repositorio)
{
    public Task<RespuestaDto<PreparacionAnulacionOsDto>> EjecutarAsync(long idOs, long idUsuario, CancellationToken ct = default) =>
        idOs <= 0 ? Task.FromResult(new RespuestaDto<PreparacionAnulacionOsDto>(1, "Orden no válida."))
                  : repositorio.PrepararAnulacionAsync(idOs, idUsuario, ct);
}

/// <summary>Anular: motivo tipificado + justificación (20 a 500 caracteres).</summary>
public class AnularOrdenServicioCasoDeUso(IOrdenServicioRepositorio repositorio)
{
    public Task<RespuestaDto<AnulacionOrdenServicioDto>> EjecutarAsync(long idOs, AnularOrdenServicioDto? d, long idUsuario, CancellationToken ct = default)
    {
        static Task<RespuestaDto<AnulacionOrdenServicioDto>> Error(string m) => Task.FromResult(new RespuestaDto<AnulacionOrdenServicioDto>(1, m));
        if (idOs <= 0) return Error("Orden no válida.");
        if (d is null || d.IdMotivo <= 0) return Error("Seleccione el motivo de anulación.");
        var comentario = d.Comentario?.Trim() ?? "";
        if (comentario.Length < 20) return Error("La justificación es obligatoria (mínimo 20 caracteres).");
        if (comentario.Length > 500) return Error("La justificación admite hasta 500 caracteres.");
        return repositorio.AnularAsync(idOs, d.IdMotivo, comentario, idUsuario, ct);
    }
}

// ── HU-42 Detalle ────────────────────────────────────────────────────────────

/// <summary>Cabecera, tab Resumen y Avance por Equipos (con el progreso general).</summary>
public class ObtenerDetalleOrdenServicioCasoDeUso(IOrdenServicioRepositorio repositorio)
{
    public async Task<RespuestaDto<DetalleOrdenServicioDto>> EjecutarAsync(long idOs, long idUsuario, CancellationToken ct = default)
    {
        if (idOs <= 0) return new(1, "Orden no válida.");
        var r = await repositorio.ObtenerDetalleAsync(idOs, idUsuario, ct);
        if (r.IdTipoMensaje != 2 || r.Datos is null) return r;

        var d = r.Datos;
        var equipos = d.Avance.Equipos;
        int Contar(string estado) => equipos.Count(e => e.EstadoEjecucion == estado);
        var ejecutados = Contar("ejecutado");
        var avance = new AvanceOrdenServicioDto(equipos.Count, Contar("pendiente"), Contar("en_proceso"), ejecutados, Contar("observado"),
                                                equipos.Count == 0 ? 0 : Math.Round(100m * ejecutados / equipos.Count, 0), equipos);
        return new(2, r.Mensaje, d with
        {
            Avance = avance,
            DiasHabilesEstimados = d.Tipo == "OS" ? DiasHabiles(d.FechaProgramadaDesde, d.FechaProgramadaHasta) : null,
            FechaProgramadaDesde = d.Tipo == "OS" ? d.FechaProgramadaDesde : null,
            FechaProgramadaHasta = d.Tipo == "OS" ? d.FechaProgramadaHasta : null,
        });
    }

    /// <summary>Días de lunes a viernes entre las dos fechas (incluidas).</summary>
    internal static int? DiasHabiles(DateTime? desde, DateTime? hasta)
    {
        if (desde is null || hasta is null || hasta.Value.Date < desde.Value.Date) return null;
        int n = 0;
        for (var f = desde.Value.Date; f <= hasta.Value.Date; f = f.AddDays(1))
            if (f.DayOfWeek is not (DayOfWeek.Saturday or DayOfWeek.Sunday)) n++;
        return n;
    }
}

/// <summary>Tabs del detalle (carga perezosa).</summary>
public class ObtenerTabsOrdenServicioCasoDeUso(IOrdenServicioRepositorio repositorio)
{
    private static Task<RespuestaDto<T>> Invalida<T>() => Task.FromResult(new RespuestaDto<T>(1, "Orden no válida."));

    public Task<RespuestaDto<PropuestaOrigenOsDto>> PropuestaAsync(long idOs, long idUsuario, CancellationToken ct = default) =>
        idOs <= 0 ? Invalida<PropuestaOrigenOsDto>() : repositorio.ObtenerPropuestaOrigenAsync(idOs, idUsuario, ct);
    public Task<RespuestaDto<List<EquipoOrdenServicioDto>>> EquiposAsync(long idOs, long idUsuario, CancellationToken ct = default) =>
        idOs <= 0 ? Invalida<List<EquipoOrdenServicioDto>>() : repositorio.ObtenerEquiposAsync(idOs, idUsuario, ct);
    public Task<RespuestaDto<List<ConceptoOrdenServicioDto>>> ConceptosAsync(long idOs, long idUsuario, CancellationToken ct = default) =>
        idOs <= 0 ? Invalida<List<ConceptoOrdenServicioDto>>() : repositorio.ObtenerConceptosAsync(idOs, idUsuario, ct);
    public Task<RespuestaDto<string?>> ObservacionesAsync(long idOs, long idUsuario, CancellationToken ct = default) =>
        idOs <= 0 ? Invalida<string?>() : repositorio.ObtenerObservacionesAsync(idOs, idUsuario, ct);
    public Task<RespuestaDto<ProgramacionOrdenServicioDto>> ProgramacionAsync(long idOs, long idUsuario, CancellationToken ct = default) =>
        idOs <= 0 ? Invalida<ProgramacionOrdenServicioDto>() : repositorio.ObtenerProgramacionAsync(idOs, idUsuario, ct);
    public Task<RespuestaDto<CertificadoOsDto>> CertificadoAsync(long idOs, long idUsuario, CancellationToken ct = default) =>
        idOs <= 0 ? Invalida<CertificadoOsDto>() : repositorio.ObtenerCertificadoAsync(idOs, idUsuario, ct);
}

// ── HU-43 Buscadores ─────────────────────────────────────────────────────────

public class BuscarEquiposOrdenServicioCasoDeUso(IOrdenServicioRepositorio repositorio)
{
    public Task<RespuestaDto<BusquedaEquiposOsDto>> EjecutarAsync(FiltrosBuscarEquiposOsDto f, long idUsuario, CancellationToken ct = default)
    {
        if (f.IdCliente <= 0) return Task.FromResult(new RespuestaDto<BusquedaEquiposOsDto>(1, "Indique el cliente."));
        f.Busqueda      = GuardarOrdenServicioCasoDeUso.Recortar(f.Busqueda, 200);
        f.Clasificacion = GuardarOrdenServicioCasoDeUso.Recortar(f.Clasificacion, 60)?.ToLowerInvariant();
        f.Ubicacion     = GuardarOrdenServicioCasoDeUso.Recortar(f.Ubicacion, 200);
        f.Pagina        = Math.Max(1, f.Pagina);
        f.PorPagina     = f.PorPagina < 1 ? 20 : Math.Min(f.PorPagina, 1000);
        return repositorio.BuscarEquiposAsync(f, idUsuario, ct);
    }
}

public class BuscarConceptosOrdenServicioCasoDeUso(IOrdenServicioRepositorio repositorio)
{
    public Task<RespuestaDto<BusquedaConceptosOsDto>> EjecutarAsync(FiltrosBuscarConceptosOsDto f, long idUsuario, CancellationToken ct = default)
    {
        f.Busqueda  = GuardarOrdenServicioCasoDeUso.Recortar(f.Busqueda, 200);
        f.Tipo      = GuardarOrdenServicioCasoDeUso.Recortar(f.Tipo, 60);
        f.Pagina    = Math.Max(1, f.Pagina);
        f.PorPagina = f.PorPagina < 1 ? 20 : Math.Min(f.PorPagina, 1000);
        return repositorio.BuscarConceptosAsync(f, idUsuario, ct);
    }
}

// ── HU-44 Importación por Excel (plantilla oficial) ──────────────────────────

internal static class PlantillaImportacionOs
{
    public const long   TamanoMaximo = 5 * 1024 * 1024;
    public const int    MaxConceptos = 500;
    public const int    MaxEquipos   = 1000;
    public const string HojaConceptos = "Conceptos";
    public const string HojaEquipos   = "Equipos";
    public const string TipoXlsx = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
}

/// <summary>Plantilla oficial: hoja Conceptos [Concepto] y hoja Equipos [Código TW, Conceptos Aplicados]. Sin precios.</summary>
public class DescargarPlantillaImportacionOsCasoDeUso(IGeneradorExcel excel)
{
    public ArchivoGeneradoDto Ejecutar() => new(
        excel.Generar(
        [
            new HojaExcel(PlantillaImportacionOs.HojaConceptos, ["Concepto"], []),
            new HojaExcel(PlantillaImportacionOs.HojaEquipos, ["Código TW", "Conceptos Aplicados"], []),
        ]),
        "Plantilla_Importacion_OS_OM.xlsx", PlantillaImportacionOs.TipoXlsx);
}

/// <summary>
/// Analiza el Excel de la plantilla oficial (no guarda nada): conceptos contra el catálogo de Suministros de clase
/// Servicio, códigos TW contra el catálogo de equipos del cliente y la relación concepto ↔ equipo de la columna
/// "Conceptos Aplicados" (nombres separados por punto y coma). El front aplica el resultado al formulario (Fusionar o
/// Reemplazar) y al guardar envía el resumen en "importacion" para la auditoría.
/// </summary>
public class AnalizarImportacionOsCasoDeUso(ILectorHojaCalculo lector, IOrdenServicioRepositorio repositorio)
{
    public async Task<RespuestaDto<AnalisisImportacionOsDto>> EjecutarAsync(
        Stream contenido, string nombreArchivo, long tamano, long idCliente, long? idOs, long idUsuario, CancellationToken ct = default)
    {
        if (idCliente <= 0) return new(1, "Indique el cliente de la orden.");
        if (tamano <= 0) return new(1, "Adjunte el archivo Excel.");
        if (tamano > PlantillaImportacionOs.TamanoMaximo) return new(1, "El archivo supera el máximo de 5 MB.");
        var extension = Path.GetExtension(nombreArchivo ?? "").ToLowerInvariant();
        if (extension is not (".xlsx" or ".xls")) return new(1, "Adjunte un archivo .xlsx (use la plantilla oficial).");

        var libro = lector.LeerLibro(contenido, nombreArchivo ?? "", PlantillaImportacionOs.MaxEquipos + 5);
        if (libro.HojaExcedida is not null || libro.Hojas is null)
            return new(1, libro.HojaExcedida is not null
                ? "El archivo excede el límite permitido. Divide la carga en varios archivos."
                : libro.Error ?? "No se pudo leer el archivo.");

        var hojaConceptos = libro.Hojas.FirstOrDefault(h => Similitud.Normalizar(h.Nombre).StartsWith("concepto"));
        var hojaEquipos   = libro.Hojas.FirstOrDefault(h => Similitud.Normalizar(h.Nombre).StartsWith("equipo"));
        if (hojaConceptos is null && hojaEquipos is null)
            return new(1, "El archivo no tiene las hojas \"Conceptos\" y \"Equipos\". Descargue la plantilla oficial.");

        // ── Lectura de las hojas ──
        var conceptosLeidos = LeerColumnas(hojaConceptos, ["concepto"], out var errorConceptos);
        var equiposLeidos   = LeerColumnas(hojaEquipos, ["codigo tw", "conceptos aplicados"], out var errorEquipos);
        if (errorConceptos is not null) return new(1, errorConceptos);
        if (errorEquipos is not null) return new(1, errorEquipos);
        if (conceptosLeidos.Count > PlantillaImportacionOs.MaxConceptos || equiposLeidos.Count > PlantillaImportacionOs.MaxEquipos)
            return new(1, "El archivo excede el límite permitido. Divide la carga en varios archivos.");
        if (conceptosLeidos.Count == 0 && equiposLeidos.Count == 0) return new(1, "El archivo no tiene conceptos ni equipos.");

        var codigos = equiposLeidos.Select(e => e.Valores[0].Trim().ToUpperInvariant()).Where(c => c.Length > 0).Distinct().ToList();
        var bd = await repositorio.ObtenerCandidatosImportacionAsync(idCliente, idOs is > 0 ? idOs : null, codigos, idUsuario, ct);
        if (bd.IdTipoMensaje != 2 || bd.Datos is null) return new(bd.IdTipoMensaje, bd.Mensaje);

        var catalogo = bd.Datos.Conceptos;
        (ConceptoCatalogoOsDto? Concepto, bool Aproximado) Buscar(string texto)
        {
            var norm = Similitud.Normalizar(texto);
            var exacto = catalogo.FirstOrDefault(c => c.Codigo.Equals(texto.Trim(), StringComparison.OrdinalIgnoreCase))
                      ?? catalogo.FirstOrDefault(c => Similitud.Normalizar(c.Descripcion) == norm);
            if (exacto is not null) return (exacto, false);
            var parecidos = catalogo.Select(c => (c, p: Similitud.Puntaje(texto, c.Descripcion)))
                                    .Where(x => x.p >= 90).OrderByDescending(x => x.p).ToList();
            return parecidos.Count == 1 || (parecidos.Count > 1 && parecidos[0].p > parecidos[1].p)
                ? (parecidos[0].c, true) : (null, false);
        }

        // ── Conceptos ──
        var conceptos = new List<ConceptoImportacionOsDto>();
        var vistos = new HashSet<long>();
        foreach (var (fila, valores) in conceptosLeidos)
        {
            var texto = valores[0].Trim();
            var (c, aprox) = Buscar(texto);
            if (c is null)
                conceptos.Add(new() { Fila = fila, Texto = texto, Estado = "error", Mensaje = "Concepto no encontrado en el catálogo maestro (Suministros de tipo Servicio)." });
            else if (!vistos.Add(c.IdSuministro))
                conceptos.Add(new() { Fila = fila, Texto = texto, Estado = "advertencia", Mensaje = "Concepto repetido en el archivo: se importa una sola vez.",
                                      IdSuministro = c.IdSuministro, Codigo = c.Codigo, Descripcion = c.Descripcion, Clasificacion = c.TipoLabel });
            else
                conceptos.Add(new() { Fila = fila, Texto = texto, Estado = aprox ? "advertencia" : "ok",
                                      Mensaje = aprox ? $"Se reconoció como \"{c.Descripcion}\"." : null,
                                      IdSuministro = c.IdSuministro, Codigo = c.Codigo, Descripcion = c.Descripcion, Clasificacion = c.TipoLabel });
        }

        // ── Equipos y relación ──
        var porCodigo = bd.Datos.Equipos.GroupBy(e => e.CodigoTw.ToUpperInvariant()).ToDictionary(g => g.Key, g => g.First());
        var noDisponibles = bd.Datos.NoDisponibles.GroupBy(x => x.CodigoTw.ToUpperInvariant()).ToDictionary(g => g.Key, g => g.First().Motivo);
        var equipos = new List<EquipoImportacionOsDto>();
        var equiposVistos = new HashSet<long>();
        var relaciones = new Dictionary<long, List<string>>();   // idSuministro → códigos TW
        foreach (var (fila, valores) in equiposLeidos)
        {
            var codigo = valores[0].Trim().ToUpperInvariant();
            var textos = (valores.Count > 1 ? valores[1] : "")
                .Split([';', '|', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).ToList();
            if (codigo.Length == 0)
            {
                equipos.Add(new() { Fila = fila, CodigoTw = "", Estado = "error", Mensaje = "Falta el código TW del equipo.", ConceptosTexto = textos });
                continue;
            }
            if (!porCodigo.TryGetValue(codigo, out var eq))
            {
                equipos.Add(new() { Fila = fila, CodigoTw = codigo, Estado = "error", ConceptosTexto = textos,
                                    Mensaje = noDisponibles.TryGetValue(codigo, out var motivo)
                                        ? $"El equipo {motivo}." : "El equipo no existe en el catálogo del cliente." });
                continue;
            }
            if (!equiposVistos.Add(eq.IdEquipo))
            {
                equipos.Add(new() { Fila = fila, CodigoTw = codigo, Estado = "advertencia", Equipo = eq, ConceptosTexto = textos,
                                    Mensaje = "Equipo repetido en el archivo: se importa una sola vez." });
                continue;
            }

            var ids = new List<long>();
            var noEncontrados = new List<string>();
            foreach (var t in textos)
            {
                var (c, _) = Buscar(t);
                if (c is null) { noEncontrados.Add(t); continue; }
                if (!ids.Contains(c.IdSuministro)) ids.Add(c.IdSuministro);
                // Concepto aplicado que no estaba en la hoja Conceptos: se agrega a la orden
                if (vistos.Add(c.IdSuministro))
                    conceptos.Add(new() { Fila = 0, Texto = t, Estado = "advertencia", IdSuministro = c.IdSuministro, Codigo = c.Codigo,
                                          Descripcion = c.Descripcion, Clasificacion = c.TipoLabel,
                                          Mensaje = $"No estaba en la hoja Conceptos; se agrega porque lo usa el equipo {codigo}." });
                if (!relaciones.TryGetValue(c.IdSuministro, out var lista)) relaciones[c.IdSuministro] = lista = [];
                lista.Add(eq.CodigoTw);
            }

            string estado = "ok"; string? mensaje = null;
            if (noEncontrados.Count > 0)
            {
                estado = "error";
                mensaje = $"Concepto no encontrado en el catálogo maestro: {string.Join("; ", noEncontrados)}.";
            }
            else if (eq.OtraOsNumero is not null)
            {
                estado = "advertencia";
                mensaje = $"Este equipo ya forma parte de la orden {eq.OtraOsNumero} ({Estado(eq.OtraOsEstado)}). Se asociará también a esta orden.";
            }
            equipos.Add(new() { Fila = fila, CodigoTw = eq.CodigoTw, Estado = estado, Mensaje = mensaje, Equipo = eq,
                                ConceptosTexto = textos, Conceptos = ids });
        }

        conceptos = conceptos.Select(c => c.IdSuministro is long id && relaciones.TryGetValue(id, out var cods) && c.Estado != "error"
                                              && conceptos.First(x => x.IdSuministro == id) == c
                                              ? c with { EquiposAplicados = cods } : c).ToList();

        var resumen = new ResumenImportacionOsDto(
            conceptos.Count(c => c.Estado == "ok"), conceptos.Count(c => c.Estado == "advertencia"), conceptos.Count(c => c.Estado == "error"),
            equipos.Count(e => e.Estado == "ok"), equipos.Count(e => e.Estado == "advertencia"), equipos.Count(e => e.Estado == "error"),
            equipos.Where(e => e.Estado != "error").Sum(e => e.Conceptos.Count));
        var puede = resumen.ConceptosError == 0 && resumen.EquiposError == 0;

        return new(2, puede ? "Archivo procesado: puede confirmar la importación." : "El archivo tiene errores: corríjalo y vuelva a subirlo.",
            new AnalisisImportacionOsDto
            {
                NombreArchivo = Path.GetFileName(nombreArchivo ?? ""), Resumen = resumen, PuedeConfirmar = puede,
                Conceptos = conceptos, Equipos = equipos,
            });
    }

    private static string Estado(string? e) => e switch
    {
        "emitida" => "Emitida", "programada" => "Programada", "reprogramada" => "Reprogramada", "en_ruta" => "En ruta",
        "en_ejecucion" => "En ejecución", "pausada" => "Pausada", "bloqueada" => "Bloqueada", _ => e ?? "",
    };

    /// <summary>Filas con datos debajo de los encabezados de la hoja (las columnas se buscan por su título).</summary>
    private static List<(int Fila, List<string> Valores)> LeerColumnas(HojaLeida? hoja, string[] titulos, out string? error)
    {
        error = null;
        var r = new List<(int, List<string>)>();
        if (hoja is null) return r;

        FilaLeida? encabezado = null; int[] columnas = [];
        foreach (var f in hoja.Filas.Take(10))
        {
            var normal = f.Celdas.Select(Similitud.Normalizar).ToList();
            var idx = titulos.Select(t => normal.FindIndex(c => c == t || c.StartsWith(t))).ToArray();
            if (idx[0] >= 0) { encabezado = f; columnas = idx; break; }
        }
        if (encabezado is null)
        {
            error = $"La hoja \"{hoja.Nombre}\" no tiene la columna \"{(titulos[0] == "concepto" ? "Concepto" : "Código TW")}\". Use la plantilla oficial.";
            return r;
        }

        foreach (var f in hoja.Filas.Where(f => f.Numero > encabezado.Numero))
        {
            var valores = columnas.Select(c => c >= 0 && c < f.Celdas.Count ? f.Celdas[c] : "").ToList();
            if (valores.All(string.IsNullOrWhiteSpace)) continue;
            r.Add((f.Numero, valores));
        }
        return r;
    }
}

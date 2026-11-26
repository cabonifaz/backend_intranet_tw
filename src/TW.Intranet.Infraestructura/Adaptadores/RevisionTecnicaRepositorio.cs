using System.Text.Json;
using System.Text.Json.Serialization;
using MySqlConnector;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>
/// Revisión Técnica (HU-56 a HU-59) y Precotizaciones Técnicas (HU-60). Las filas de los SPs se leen a los DTOs por nombre
/// de columna (snake_case → PascalCase), así que un SP puede sumar columnas sin romper el mapeo.
/// </summary>
public class RevisionTecnicaRepositorio(CadenaConexionBd conexion) : RepositorioSpBase(conexion), IRevisionTecnicaRepositorio
{
    // ── Servicio Técnico › Revisión de Informes ───────────────────────────────────────────────

    public Task<RespuestaDto<BandejaInformesDto>> ObtenerBandejaAsync(FiltrosBandejaInformesDto f, bool exportar, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerBandejaInformesTecnicos",
            p =>
            {
                p.AddWithValue("p_id_usuario",        idUsuario);
                p.AddWithValue("p_grupo",             Valor(f.Grupo));
                p.AddWithValue("p_busqueda",          Valor(f.Busqueda));
                p.AddWithValue("p_id_tecnico",        Valor(f.IdTecnico));
                p.AddWithValue("p_id_cliente",        Valor(f.IdCliente));
                p.AddWithValue("p_con_observaciones", f.ConObservaciones is null ? DBNull.Value : Bit(f.ConObservaciones.Value));
                p.AddWithValue("p_sla_vencido",       Bit(f.SlaVencido));
                p.AddWithValue("p_fecha_desde",       f.FechaDesde is null ? DBNull.Value : f.FechaDesde.Value.Date);
                p.AddWithValue("p_fecha_hasta",       f.FechaHasta is null ? DBNull.Value : f.FechaHasta.Value.Date);
                p.AddWithValue("p_pagina",            f.Pagina);
                p.AddWithValue("p_por_pagina",        f.PorPagina);
                p.AddWithValue("p_exportar",          Bit(exportar));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var tarjetas = await LeerUnaAsync<TarjetasInformesDto>(r, ct) ?? new TarjetasInformesDto();
                await r.NextResultAsync(ct);
                var items = await LeerFilasAsync<ItemBandejaInformeDto>(r, ct);
                var total = await LeerTotalAsync(r, ct);
                await r.NextResultAsync(ct);
                var tecnicos = await LeerFilasAsync<OpcionInformeDto>(r, ct);
                await r.NextResultAsync(ct);
                var clientes = await LeerFilasAsync<OpcionInformeDto>(r, ct);
                return new RespuestaDto<BandejaInformesDto>(2, mensaje,
                    new BandejaInformesDto(tarjetas, items, total, f.Pagina, f.PorPagina, tecnicos, clientes));
            }, ct);

    public Task<RespuestaDto<DetalleInformeTecnicoDto>> ObtenerDetalleAsync(long idInforme, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerDetalleInformeTecnico",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_informe", idInforme);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var c = await LeerUnaAsync<CabeceraInformeCruda>(r, ct);
                if (c is null) return new RespuestaDto<DetalleInformeTecnicoDto>(1, "El informe no existe o no está en tu alcance.");
                await r.NextResultAsync(ct); var pasos   = await LeerFilasAsync<PasoInformeDto>(r, ct);
                await r.NextResultAsync(ct); var ensayos = await LeerFilasAsync<EnsayoInformeDto>(r, ct);
                await r.NextResultAsync(ct); var obs     = await LeerFilasAsync<ObservacionInformeDto>(r, ct);
                await r.NextResultAsync(ct); var recs    = await LeerFilasAsync<RecomendacionInformeDto>(r, ct);
                await r.NextResultAsync(ct); var fotos   = await LeerFilasAsync<FotoInformeDto>(r, ct);
                await r.NextResultAsync(ct); var precot  = await LeerFilasAsync<ItemPrecotizacionDto>(r, ct);
                await r.NextResultAsync(ct); var hist    = await LeerFilasAsync<EventoRecienteDto>(r, ct);
                var det = InformeEquipoMovilRepositorio.LeerDetalle(c.DetalleServicio);
                return new RespuestaDto<DetalleInformeTecnicoDto>(2, mensaje,
                    new DetalleInformeTecnicoDto(c, pasos, ensayos, obs, recs, fotos, precot, hist,
                        ResponsableCliente: new ResponsableClienteDto(c.ResponsableNombre, c.ResponsableCargo, c.ResponsableTelefono),
                        DiagnosticoFinal:   new DiagnosticoFinalDto(c.SeveridadGeneral, c.EstadoEquipoFinal, c.RevJefatura, c.RequierePrecotizacion,
                                                                    c.SegundaVisita, c.AplicaGarantia),
                        ComentarioPruebas:  c.ComentarioPruebas,
                        DetalleServicio:    new DetalleServicioInformeDto(det.Tipo, det.Celdas, det.Suma, det.Comp, det.Anillos)));
            }, ct);

    /// <summary>Cabecera del informe con los campos crudos de la cabecera de la app (se devuelven en bloques; no salen en el JSON de la cabecera).</summary>
    private sealed class CabeceraInformeCruda : CabeceraInformeDto
    {
        public string? ResponsableNombre     { get; init; }
        public string? ResponsableCargo      { get; init; }
        public string? ResponsableTelefono   { get; init; }
        public string? DetalleServicio       { get; init; }
        public string? ComentarioPruebas     { get; init; }
        public string? SeveridadGeneral      { get; init; }
        public string? EstadoEquipoFinal     { get; init; }
        public bool    RevJefatura           { get; init; }
        public bool    RequierePrecotizacion { get; init; }
        public bool    SegundaVisita         { get; init; }
        public bool    AplicaGarantia        { get; init; }
    }

    public Task<RespuestaDto<InformeGuardadoDto>> GuardarInformeAsync(long idInforme, GuardarInformeTecnicoDto d, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_GuardarInformeTecnico",
            p =>
            {
                p.AddWithValue("p_id_usuario",          idUsuario);
                p.AddWithValue("p_id_informe",          idInforme);
                p.AddWithValue("p_cambiar_descripcion", Bit(d.DescripcionComplementaria is not null));
                p.AddWithValue("p_descripcion",         (object?)d.DescripcionComplementaria ?? DBNull.Value);
                p.AddWithValue("p_resultado",           Json(d.Resultado));
                p.AddWithValue("p_procedimientos",      Json(d.Procedimiento));
                p.AddWithValue("p_ensayos",             Json(d.Ensayos));
                p.AddWithValue("p_observaciones",       Json(d.Observaciones));
                p.AddWithValue("p_recomendaciones",     Json(d.Recomendaciones));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var fila = await LeerUnaAsync<InformeGuardadoDto>(r, ct);
                return new RespuestaDto<InformeGuardadoDto>(2, mensaje, fila);
            }, ct);

    public Task<RespuestaDto<PrecotizacionGuardadaDto>> GuardarPrecotizacionAsync(long idInforme, GuardarPrecotizacionInformeDto d, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_GuardarPrecotizacionInforme",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_informe", idInforme);
                p.AddWithValue("p_nota",       Valor(d.Nota));
                p.AddWithValue("p_items",      Json(d.Items));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var fila = await LeerUnaAsync<PrecotizacionGuardadaDto>(r, ct);
                return new RespuestaDto<PrecotizacionGuardadaDto>(2, mensaje, fila);
            }, ct);

    public Task<RespuestaDto<PreparacionRevisionInformeDto>> PrepararRevisionAsync(long idInforme, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_PrepararRevisionInforme",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_informe", idInforme);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var cabecera = await LeerUnaAsync<CabeceraRevisionInformeDto>(r, ct) ?? new CabeceraRevisionInformeDto();
                await r.NextResultAsync(ct);
                var checklist = await LeerFilasAsync<ItemChecklistRevisionDto>(r, ct);
                return new RespuestaDto<PreparacionRevisionInformeDto>(2, mensaje, new PreparacionRevisionInformeDto(cabecera, checklist));
            }, ct);

    public Task<RespuestaDto<InformeRevisadoDto>> RegistrarRevisionAsync(long idInforme, string? nota, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_RegistrarRevisionInforme",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_informe", idInforme);
                p.AddWithValue("p_nota",       Valor(nota));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                return new RespuestaDto<InformeRevisadoDto>(2, mensaje, await LeerUnaAsync<InformeRevisadoDto>(r, ct));
            }, ct);

    public Task<RespuestaDto<IReadOnlyList<ObservacionSeguimientoInformeDto>>> ObtenerObservacionesSeguimientoAsync(long idInforme, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerObservacionesSeguimientoInforme",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_informe", idInforme);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var filas = await LeerFilasAsync<ObservacionSeguimientoInformeDto>(r, ct);
                return new RespuestaDto<IReadOnlyList<ObservacionSeguimientoInformeDto>>(2, mensaje, filas);
            }, ct);

    public Task<RespuestaDto<HistorialInformeDto>> ObtenerHistorialAsync(long idInforme, string? categoria, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerHistorialInforme",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_informe", idInforme);
                p.AddWithValue("p_categoria",  Valor(categoria));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var contadores = await LeerUnaAsync<ContadoresHistorialInformeDto>(r, ct) ?? new ContadoresHistorialInformeDto();
                await r.NextResultAsync(ct);
                var eventos = await LeerFilasAsync<EventoHistorialInformeDto>(r, ct);
                return new RespuestaDto<HistorialInformeDto>(2, mensaje, new HistorialInformeDto(contadores, eventos));
            }, ct);

    public Task<RespuestaDto<ArchivoEvidenciaMovilDto>> ObtenerArchivoFotoAsync(long idInforme, long idEvidencia, long idUsuario, CancellationToken ct)
        => EjecutarAsync<ArchivoEvidenciaMovilDto>("SP_ObtenerArchivoFotoInforme",
            p =>
            {
                p.AddWithValue("p_id_usuario",   idUsuario);
                p.AddWithValue("p_id_informe",   idInforme);
                p.AddWithValue("p_id_evidencia", idEvidencia);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<ArchivoEvidenciaMovilDto>(1, "Foto no encontrada.");
                return new RespuestaDto<ArchivoEvidenciaMovilDto>(2, mensaje, new ArchivoEvidenciaMovilDto(
                    Texto(r, "ruta") ?? string.Empty, Texto(r, "ruta_cuadro"), Booleano(r, "es_video")));
            }, ct);

    // ── Servicio Técnico › Informe Complementario (23/11/2026) ─────────────────────────────────

    public Task<RespuestaDto<InformeComplementarioCreadoDto>> CrearComplementarioAsync(long idInforme, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_CrearInformeComplementario",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_informe", idInforme);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                return new RespuestaDto<InformeComplementarioCreadoDto>(2, mensaje, await LeerUnaAsync<InformeComplementarioCreadoDto>(r, ct));
            }, ct);

    public Task<RespuestaDto<DetalleInformeComplementarioDto>> ObtenerComplementarioAsync(long idComplementario, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerInformeComplementario",
            p =>
            {
                p.AddWithValue("p_id_usuario",        idUsuario);
                p.AddWithValue("p_id_complementario", idComplementario);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var c = await LeerUnaAsync<CabeceraComplementarioCruda>(r, ct);
                if (c is null) return new RespuestaDto<DetalleInformeComplementarioDto>(1, "El informe complementario no existe o no está en tu alcance.");
                await r.NextResultAsync(ct); var pasos    = await LeerFilasAsync<PasoInformeDto>(r, ct);
                await r.NextResultAsync(ct); var ensayos  = await LeerFilasAsync<EnsayoInformeDto>(r, ct);
                await r.NextResultAsync(ct); var obs      = await LeerFilasAsync<ObservacionComplementarioDto>(r, ct);
                await r.NextResultAsync(ct); var recs     = await LeerFilasAsync<RecomendacionInformeDto>(r, ct);
                await r.NextResultAsync(ct); var fotos    = await LeerFilasAsync<FotoInformeComplementarioDto>(r, ct);
                await r.NextResultAsync(ct); var precot   = await LeerFilasAsync<ItemPrecotizacionDto>(r, ct);
                await r.NextResultAsync(ct); var opciones = await LeerFilasAsync<OpcionListaCruda>(r, ct);

                var det = InformeEquipoMovilRepositorio.LeerDetalle(c.DetalleServicio);
                List<OpcionFichaComplementarioDto> Lista(string lista) =>
                    opciones.Where(o => o.Lista == lista && o.Codigo is not null).Select(o => new OpcionFichaComplementarioDto(o.Codigo!, o.Nombre ?? o.Codigo!, o.Padre)).ToList();
                return new RespuestaDto<DetalleInformeComplementarioDto>(2, mensaje,
                    new DetalleInformeComplementarioDto(c, pasos, ensayos, obs, recs, fotos, precot,
                        ResponsableCliente: new ResponsableClienteDto(c.ResponsableNombre, c.ResponsableCargo, c.ResponsableTelefono),
                        DiagnosticoFinal:   new DiagnosticoFinalDto(c.SeveridadGeneral, c.EstadoEquipoFinal, c.RevJefatura, c.RequierePrecotizacion,
                                                                    c.SegundaVisita, c.AplicaGarantia),
                        ComentarioPruebas:  c.ComentarioPruebas,
                        DetalleServicio:    new DetalleServicioInformeDto(det.Tipo, det.Celdas, det.Suma, det.Comp, det.Anillos),
                        ResultadoOriginal:  new ResultadoOriginalDto(c.ResultadoGlobal, c.ErrorMaximo, c.DecisionTecnica, c.ErrorCritico),
                        PrecotizacionDetalle: new PrecotizacionComplementarioDetalleDto(c.IdPrecotizacion, c.NumeroPrecot, c.EstadoPrecot, c.NotaPrecotizacion, precot),
                        Opciones: new OpcionesInformeComplementarioDto(
                            Lista("tipo_equipo"), Lista("clasificacion"), Lista("componente"),
                            [new("critico", "Crítico"), new("alto", "Alto"), new("medio", "Medio"), new("bajo", "Bajo")],
                            [new("alta", "Alta"), new("media", "Media"), new("baja", "Baja")],
                            [new("alta", "Alta"), new("media", "Media"), new("opcional", "Opcional")])));
            }, ct);

    /// <summary>Cabecera del complementario con los campos crudos de la app (se arman en bloques: responsable, diagnóstico, detalle del servicio).
    /// Se devuelve como CabeceraInformeComplementarioDto: los campos crudos no salen en el JSON de la cabecera.</summary>
    private sealed class CabeceraComplementarioCruda : CabeceraInformeComplementarioDto
    {
        public string? ResponsableNombre     { get; init; }
        public string? ResponsableCargo      { get; init; }
        public string? ResponsableTelefono   { get; init; }
        public string? DetalleServicio       { get; init; }
        public string? ComentarioPruebas     { get; init; }
        public string? SeveridadGeneral      { get; init; }
        public string? EstadoEquipoFinal     { get; init; }
        public bool    RevJefatura           { get; init; }
        public bool    RequierePrecotizacion { get; init; }
        public bool    SegundaVisita         { get; init; }
        public bool    AplicaGarantia        { get; init; }
        public string? ErrorCritico          { get; init; }
    }

    private sealed class OpcionListaCruda
    {
        public string? Lista  { get; init; }
        public string? Codigo { get; init; }
        public string? Nombre { get; init; }
        public string? Padre  { get; init; }
    }

    public Task<RespuestaDto<InformeComplementarioGuardadoDto>> GuardarComplementarioAsync(long idComplementario, GuardarInformeComplementarioDto d, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_GuardarInformeComplementario",
            p =>
            {
                p.AddWithValue("p_id_usuario",          idUsuario);
                p.AddWithValue("p_id_complementario",   idComplementario);
                p.AddWithValue("p_cambiar_descripcion", Bit(d.ObservacionesGenerales is not null));
                p.AddWithValue("p_descripcion",         (object?)d.ObservacionesGenerales ?? DBNull.Value);
                p.AddWithValue("p_observaciones",       Json(d.Observaciones));
                p.AddWithValue("p_recomendaciones",     Json(d.Recomendaciones));
                p.AddWithValue("p_precotizacion",       Json(d.Precotizacion));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                return new RespuestaDto<InformeComplementarioGuardadoDto>(2, mensaje, await LeerUnaAsync<InformeComplementarioGuardadoDto>(r, ct));
            }, ct);

    public Task<RespuestaDto<FotoComplementarioSubidaDto>> RegistrarFotoComplementarioAsync(long idComplementario, string ruta, bool esVideo, string? momento,
                                                                                           string? descripcion, long? idObservacion, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_RegistrarFotoInformeComplementario",
            p =>
            {
                p.AddWithValue("p_id_usuario",        idUsuario);
                p.AddWithValue("p_id_complementario", idComplementario);
                p.AddWithValue("p_ruta",              ruta);
                p.AddWithValue("p_es_video",          Bit(esVideo));
                p.AddWithValue("p_momento",           Valor(momento));
                p.AddWithValue("p_descripcion",       Valor(descripcion));
                p.AddWithValue("p_id_observacion",    Valor(idObservacion));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                return new RespuestaDto<FotoComplementarioSubidaDto>(2, mensaje, await LeerUnaAsync<FotoComplementarioSubidaDto>(r, ct));
            }, ct);

    public Task<RespuestaDto<ArchivoBorrableDto?>> QuitarFotoComplementarioAsync(long idComplementario, long idEvidencia, long idUsuario, CancellationToken ct)
        => EjecutarAsync<ArchivoBorrableDto?>("SP_QuitarFotoInformeComplementario",
            p =>
            {
                p.AddWithValue("p_id_usuario",        idUsuario);
                p.AddWithValue("p_id_complementario", idComplementario);
                p.AddWithValue("p_id_evidencia",      idEvidencia);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                ArchivoBorrableDto? archivo = null;
                if (await r.ReadAsync(ct) && Texto(r, "ruta_borrable") is { Length: > 0 } ruta)
                    archivo = new ArchivoBorrableDto(ruta, Texto(r, "ruta_cuadro_borrable"));
                return new RespuestaDto<ArchivoBorrableDto?>(2, mensaje, archivo);
            }, ct);

    public Task<RespuestaDto<DescripcionFotoComplementarioDto>> ActualizarDescripcionFotoComplementarioAsync(long idComplementario, long idEvidencia, string? descripcion,
                                                                                                             long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ActualizarDescripcionFotoInformeComplementario",
            p =>
            {
                p.AddWithValue("p_id_usuario",        idUsuario);
                p.AddWithValue("p_id_complementario", idComplementario);
                p.AddWithValue("p_id_evidencia",      idEvidencia);
                p.AddWithValue("p_descripcion",       Valor(descripcion));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                return new RespuestaDto<DescripcionFotoComplementarioDto>(2, mensaje, await LeerUnaAsync<DescripcionFotoComplementarioDto>(r, ct));
            }, ct);

    public Task<RespuestaDto<ArchivoEvidenciaMovilDto>> ObtenerArchivoFotoComplementarioAsync(long idComplementario, long idEvidencia, long idUsuario, CancellationToken ct)
        => EjecutarAsync<ArchivoEvidenciaMovilDto>("SP_ObtenerArchivoFotoInformeComplementario",
            p =>
            {
                p.AddWithValue("p_id_usuario",        idUsuario);
                p.AddWithValue("p_id_complementario", idComplementario);
                p.AddWithValue("p_id_evidencia",      idEvidencia);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct)) return new RespuestaDto<ArchivoEvidenciaMovilDto>(1, "Foto no encontrada.");
                return new RespuestaDto<ArchivoEvidenciaMovilDto>(2, mensaje, new ArchivoEvidenciaMovilDto(
                    Texto(r, "ruta") ?? string.Empty, Texto(r, "ruta_cuadro"), Booleano(r, "es_video")));
            }, ct);

    public Task<RespuestaDto<List<ArchivoBorrableDto>>> DescartarComplementarioAsync(long idComplementario, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_DescartarInformeComplementario",
            p =>
            {
                p.AddWithValue("p_id_usuario",        idUsuario);
                p.AddWithValue("p_id_complementario", idComplementario);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var archivos = new List<ArchivoBorrableDto>();
                while (await r.ReadAsync(ct))
                    if (Texto(r, "ruta") is { Length: > 0 } ruta) archivos.Add(new ArchivoBorrableDto(ruta, Texto(r, "ruta_cuadro")));
                return new RespuestaDto<List<ArchivoBorrableDto>>(2, mensaje, archivos);
            }, ct);

    // ── CRM › Precotizaciones Técnicas ────────────────────────────────────────────────────────

    public Task<RespuestaDto<BandejaPrecotizacionesDto>> ObtenerBandejaPrecotizacionesAsync(FiltrosPrecotizacionesDto f, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerBandejaPrecotizaciones",
            p =>
            {
                p.AddWithValue("p_id_usuario",    idUsuario);
                p.AddWithValue("p_estado",        Valor(f.Estado));
                p.AddWithValue("p_busqueda",      Valor(f.Busqueda));
                p.AddWithValue("p_id_supervisor", Valor(f.IdSupervisor));
                p.AddWithValue("p_fecha_desde",   f.FechaDesde is null ? DBNull.Value : f.FechaDesde.Value.Date);
                p.AddWithValue("p_fecha_hasta",   f.FechaHasta is null ? DBNull.Value : f.FechaHasta.Value.Date);
                p.AddWithValue("p_pagina",        f.Pagina);
                p.AddWithValue("p_por_pagina",    f.PorPagina);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var tarjetas = await LeerUnaAsync<TarjetasPrecotizacionesDto>(r, ct) ?? new TarjetasPrecotizacionesDto();
                await r.NextResultAsync(ct);
                var items = await LeerFilasAsync<ItemBandejaPrecotizacionDto>(r, ct);
                var total = await LeerTotalAsync(r, ct);
                await r.NextResultAsync(ct);
                var supervisores = await LeerFilasAsync<OpcionInformeDto>(r, ct);
                return new RespuestaDto<BandejaPrecotizacionesDto>(2, mensaje,
                    new BandejaPrecotizacionesDto(tarjetas, items, total, f.Pagina, f.PorPagina, supervisores));
            }, ct);

    public Task<RespuestaDto<DetallePrecotizacionDto>> ObtenerDetallePrecotizacionAsync(long idPrecotizacion, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerDetallePrecotizacion",
            p =>
            {
                p.AddWithValue("p_id_usuario",       idUsuario);
                p.AddWithValue("p_id_precotizacion", idPrecotizacion);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var cabecera = await LeerUnaAsync<CabeceraPrecotizacionDto>(r, ct);
                if (cabecera is null) return new RespuestaDto<DetallePrecotizacionDto>(1, "La precotización no existe o no está en tu alcance.");
                await r.NextResultAsync(ct); var obs   = await LeerFilasAsync<ObservacionPrecotizacionDto>(r, ct);
                await r.NextResultAsync(ct); var items = await LeerFilasAsync<ItemPrecotizacionDto>(r, ct);
                await r.NextResultAsync(ct); var traza = await LeerFilasAsync<PasoTrazabilidadPrecotizacionDto>(r, ct);
                return new RespuestaDto<DetallePrecotizacionDto>(2, mensaje, new DetallePrecotizacionDto(cabecera, obs, items, traza));
            }, ct);

    public Task<RespuestaDto<PrecargaPrecotizacionDto>> ObtenerPrecargaPrecotizacionAsync(long idPrecotizacion, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerPrecargaPrecotizacion",
            p =>
            {
                p.AddWithValue("p_id_usuario",       idUsuario);
                p.AddWithValue("p_id_precotizacion", idPrecotizacion);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var cabecera = await LeerUnaAsync<CabeceraPrecargaPrecotizacionDto>(r, ct) ?? new CabeceraPrecargaPrecotizacionDto();
                await r.NextResultAsync(ct);
                var items = await LeerFilasAsync<ItemPrecargaPrecotizacionDto>(r, ct);
                return new RespuestaDto<PrecargaPrecotizacionDto>(2, mensaje, new PrecargaPrecotizacionDto(cabecera, items));
            }, ct);

    public Task<RespuestaDto<PrecotizacionConvertidaDto>> ConvertirPrecotizacionAsync(long idPrecotizacion, long idPropuesta, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ConvertirPrecotizacion",
            p =>
            {
                p.AddWithValue("p_id_usuario",       idUsuario);
                p.AddWithValue("p_id_precotizacion", idPrecotizacion);
                p.AddWithValue("p_id_propuesta",     idPropuesta);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                return new RespuestaDto<PrecotizacionConvertidaDto>(2, mensaje, await LeerUnaAsync<PrecotizacionConvertidaDto>(r, ct));
            }, ct);

    // ── Lectura genérica de filas ─────────────────────────────────────────────────────────────

    private static readonly JsonSerializerOptions OpcionesLectura = new()
    {
        PropertyNamingPolicy        = JsonNamingPolicy.SnakeCaseLower,
        PropertyNameCaseInsensitive = true,
        NumberHandling              = JsonNumberHandling.AllowReadingFromString,
        Converters                  = { new BooleanoFlexible() },
    };

    private static readonly JsonSerializerOptions OpcionesEscritura = new(JsonSerializerDefaults.Web);

    private static object Json<TV>(TV? valor) where TV : class
        => valor is null ? DBNull.Value : JsonSerializer.Serialize(valor, OpcionesEscritura);

    private static T LeerFila<T>(MySqlDataReader r)
    {
        var fila = new Dictionary<string, object?>(r.FieldCount, StringComparer.OrdinalIgnoreCase);
        for (var i = 0; i < r.FieldCount; i++)
        {
            fila[r.GetName(i)] = r.IsDBNull(i) ? null : r.GetValue(i) switch
            {
                TimeSpan t => t.ToString(@"hh\:mm"),
                DateOnly d => d.ToDateTime(TimeOnly.MinValue),
                byte[] b   => Convert.ToBase64String(b),
                var v      => v,
            };
        }
        return JsonSerializer.Deserialize<T>(JsonSerializer.SerializeToUtf8Bytes(fila), OpcionesLectura)!;
    }

    private static async Task<List<T>> LeerFilasAsync<T>(MySqlDataReader r, CancellationToken ct)
    {
        var lista = new List<T>();
        while (await r.ReadAsync(ct)) lista.Add(LeerFila<T>(r));
        return lista;
    }

    private static async Task<T?> LeerUnaAsync<T>(MySqlDataReader r, CancellationToken ct) where T : class
        => await r.ReadAsync(ct) ? LeerFila<T>(r) : null;

    /// <summary>MySQL devuelve los indicadores como 0/1 (BIGINT o TINYINT): se aceptan número, texto o booleano.</summary>
    private sealed class BooleanoFlexible : JsonConverter<bool>
    {
        public override bool Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options) => reader.TokenType switch
        {
            JsonTokenType.True   => true,
            JsonTokenType.False  => false,
            JsonTokenType.Number => reader.TryGetDecimal(out var n) && n != 0,
            JsonTokenType.String => reader.GetString() is { } s && (s == "1" || s.Equals("true", StringComparison.OrdinalIgnoreCase)),
            _                    => false,
        };

        public override void Write(Utf8JsonWriter writer, bool value, JsonSerializerOptions options) => writer.WriteBooleanValue(value);
    }
}

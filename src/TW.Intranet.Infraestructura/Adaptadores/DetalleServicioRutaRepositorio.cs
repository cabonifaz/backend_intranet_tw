using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>HU-52 Detalle del Servicio en Ruta (Sprint 5). Solo lectura: todo pasa por SPs parametrizados.</summary>
public class DetalleServicioRutaRepositorio(CadenaConexionBd conexion) : RepositorioSpBase(conexion), IDetalleServicioRutaRepositorio
{
    public Task<RespuestaDto<DetalleServicioRutaDto>> ObtenerDetalleAsync(long idUsuario, long idOs, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerDetalleServicioRuta",
            p => { p.AddWithValue("p_id_usuario", idUsuario); p.AddWithValue("p_id_os", idOs); },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<DetalleServicioRutaDto>(3, "El procedimiento no devolvió la cabecera.");
                var cab = new CabeceraServicioRutaDto(EnteroLargo(r, "IdOs"), Texto(r, "Numero") ?? "", Texto(r, "Tipo") ?? "OS", Texto(r, "Propuesta"),
                    Texto(r, "CodigoProgramacion"), Texto(r, "Expediente"), EnteroLargo(r, "IdCliente"), Texto(r, "Cliente") ?? "", Texto(r, "Ruc"),
                    Texto(r, "Sede"), Texto(r, "DireccionSede"), Texto(r, "TipoServicio"), EnteroNulo(r, "MinutosEstimados"), Entero(r, "EquiposProgramados"),
                    Texto(r, "Norma"), Texto(r, "NotaProcedimiento"), EnteroLargoNulo(r, "IdTecnicoLider"), Texto(r, "TecnicoLider"), Texto(r, "CargoTecnico"),
                    Texto(r, "EstadoSsoma"), Texto(r, "HoraInicio"), Texto(r, "HoraFin"), Texto(r, "SalidaReal"), Texto(r, "PuntualidadSalida"),
                    Texto(r, "Estado") ?? "", Texto(r, "FechaEjecucion") ?? "", Texto(r, "UltimaActualizacion") ?? "", Entero(r, "RefrescoSegundos"),
                    Booleano(r, "MostrarCierre"), Texto(r, "TelefonoTecnico"));
                var met = new MetricasServicioRutaDto(Entero(r, "AvancePct"), Entero(r, "EquiposCompletados"), Entero(r, "EquiposTotal"), Entero(r, "DemorasIncidencias"),
                    Entero(r, "MinutosDemora"), Texto(r, "MotivoDemora"), Entero(r, "AlertasActivas"), Entero(r, "MinutosServicio"), EnteroNulo(r, "MinutosEstimados"));

                await r.NextResultAsync(ct);
                var equipos = new List<EquipoResumenRutaDto>();
                while (await r.ReadAsync(ct))
                    equipos.Add(new EquipoResumenRutaDto(EnteroLargo(r, "IdEquipo"), Texto(r, "Codigo") ?? "", Texto(r, "Modelo"), Texto(r, "Serie"),
                        Texto(r, "EstadoEjecucion") ?? "pendiente", Texto(r, "EtapaActual"), Texto(r, "HoraCompletado"), Booleano(r, "Observado")));

                await r.NextResultAsync(ct);
                var resp = new List<ResponsableServicioRutaDto>();
                while (await r.ReadAsync(ct))
                    resp.Add(new ResponsableServicioRutaDto(EnteroLargo(r, "IdUsuario"), Texto(r, "Nombre") ?? "", Texto(r, "Rol") ?? "", Texto(r, "Cargo"), Texto(r, "Nota")));

                await r.NextResultAsync(ct);
                ContactoPlantaDto? contacto = null;
                if (await r.ReadAsync(ct))
                    contacto = new ContactoPlantaDto(Texto(r, "Nombre") ?? "", Texto(r, "Cargo"), Texto(r, "Telefono"), Texto(r, "Correo"), Texto(r, "ConfirmadoA"), EnteroNulo(r, "HaceMinutos"));

                return new RespuestaDto<DetalleServicioRutaDto>(2, mensaje, new DetalleServicioRutaDto(cab, met, equipos, resp, contacto));
            },
            ct);

    public Task<RespuestaDto<AvanceServicioRutaDto>> ObtenerAvanceAsync(long idUsuario, long idOs, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerAvanceServicioRuta",
            p => { p.AddWithValue("p_id_usuario", idUsuario); p.AddWithValue("p_id_os", idOs); },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var filas = new List<(long Id, string Codigo, string? Modelo, string? Serie, string Estado, int Fotos, int Ensayos, int Cert, int Obs, int Med, string? Ini, string? Fin, int? Min)>();
                while (await r.ReadAsync(ct))
                    filas.Add((EnteroLargo(r, "IdEquipo"), Texto(r, "Codigo") ?? "", Texto(r, "Modelo"), Texto(r, "Serie"), Texto(r, "Estado") ?? "pendiente",
                        Entero(r, "Fotos"), Entero(r, "Ensayos"), Entero(r, "CertificadoPreliminar"), Entero(r, "Observaciones"), Entero(r, "Mediciones"),
                        Texto(r, "Iniciado"), Texto(r, "Finalizado"), EnteroNulo(r, "Minutos")));

                await r.NextResultAsync(ct);
                var etapas = new Dictionary<long, List<EtapaEquipoRutaDto>>();
                while (await r.ReadAsync(ct))
                {
                    long id = EnteroLargo(r, "IdEquipo");
                    if (!etapas.TryGetValue(id, out var lista))
                        etapas[id] = lista = [];
                    lista.Add(new EtapaEquipoRutaDto(Texto(r, "Etapa") ?? "", Entero(r, "Orden"), Texto(r, "Estado") ?? "pendiente", Texto(r, "Hora")));
                }

                var equipos = filas.Select(f => new EquipoAvanceRutaDto(f.Id, f.Codigo, f.Modelo, f.Serie, f.Estado, f.Fotos, f.Ensayos, f.Cert, f.Obs, f.Med, f.Ini, f.Fin, f.Min,
                    etapas.TryGetValue(f.Id, out var e) ? e : [])).ToList();
                return new RespuestaDto<AvanceServicioRutaDto>(2, mensaje,
                    new AvanceServicioRutaDto(equipos.Count(x => x.Estado == "ejecutado"), equipos.Count, equipos));
            },
            ct);

    public Task<RespuestaDto<SeccionEquipoRutaDto>> ObtenerSeccionEquipoAsync(long idUsuario, long idOs, long idEquipo, string seccion, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerEquipoServicioRuta",
            p => { p.AddWithValue("p_id_usuario", idUsuario); p.AddWithValue("p_id_os", idOs); p.AddWithValue("p_id_equipo", idEquipo); p.AddWithValue("p_seccion", seccion); },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var filas = new List<ElementoEquipoRutaDto>();
                while (await r.ReadAsync(ct))
                    filas.Add(new ElementoEquipoRutaDto(EnteroLargo(r, "Id"), Texto(r, "Titulo") ?? "", Texto(r, "Detalle"), Texto(r, "Fecha"), Texto(r, "Url"),
                        Texto(r, "Resultado"), EnteroNulo(r, "UltimaHaceMin")));
                return new RespuestaDto<SeccionEquipoRutaDto>(2, mensaje, new SeccionEquipoRutaDto(seccion, filas));
            },
            ct);

    public Task<RespuestaDto<MapaServicioRutaDto>> ObtenerMapaAsync(long idUsuario, long idOs, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerMapaServicioRuta",
            p => { p.AddWithValue("p_id_usuario", idUsuario); p.AddWithValue("p_id_os", idOs); },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<MapaServicioRutaDto>(3, "El procedimiento no devolvió el panel GPS.");
                var panel = new PanelGpsRutaDto(EnteroLargo(r, "IdOs"), Texto(r, "Estado") ?? "", Texto(r, "Tecnico"), Texto(r, "Cliente"), Texto(r, "Sede"),
                    Texto(r, "DireccionSede"), DecimalNulo(r, "LatSede"), DecimalNulo(r, "LonSede"), Entero(r, "RadioProximidadM"), Booleano(r, "MostrarRadio"),
                    DecimalNulo(r, "Latitud"), DecimalNulo(r, "Longitud"), Texto(r, "UltimaUbicacion"), EnteroNulo(r, "DistanciaM"), Texto(r, "UltimaActualizacion"),
                    EnteroNulo(r, "SegundosDesdeUltima"), Texto(r, "Conexion") ?? "sin_senal", Entero(r, "MinutosEnPunto"), EnteroNulo(r, "PrecisionM"),
                    DecimalNulo(r, "VelocidadKmh"), DecimalNulo(r, "AltitudM"), EnteroNulo(r, "Satelites"), EnteroNulo(r, "LatenciaMs"));

                await r.NextResultAsync(ct);
                var ruta = new List<PuntoRutaDto>();
                while (await r.ReadAsync(ct))
                    ruta.Add(new PuntoRutaDto(DecimalNulo(r, "Latitud") ?? 0m, DecimalNulo(r, "Longitud") ?? 0m, Texto(r, "Hora") ?? ""));
                ruta.Reverse(); // el SP devuelve del más reciente al más antiguo; el mapa necesita el orden cronológico

                await r.NextResultAsync(ct);
                var crono = new List<HitoGpsDto>();
                while (await r.ReadAsync(ct))
                    crono.Add(new HitoGpsDto(Texto(r, "Hito") ?? "", Texto(r, "Hora")));
                return new RespuestaDto<MapaServicioRutaDto>(2, mensaje, new MapaServicioRutaDto(panel, ruta, crono));
            },
            ct);

    public Task<RespuestaDto<TimelineServicioRutaDto>> ObtenerTimelineAsync(long idUsuario, long idOs, ConsultaTimelineNormalizada q, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerTimelineServicioRuta",
            p => { p.AddWithValue("p_id_usuario", idUsuario); p.AddWithValue("p_id_os", idOs); p.AddWithValue("p_categoria", q.Categoria); p.AddWithValue("p_orden", q.Orden); },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var conteos = new ConteoTimelineDto(0, 0, 0, 0, 0);
                if (await r.ReadAsync(ct))
                    conteos = new ConteoTimelineDto(Entero(r, "Hitos"), Entero(r, "Alertas"), Entero(r, "Incidencias"), Entero(r, "Asistente"), Entero(r, "Total"));
                await r.NextResultAsync(ct);
                var eventos = new List<EventoTimelineRutaDto>();
                while (await r.ReadAsync(ct))
                    eventos.Add(new EventoTimelineRutaDto(Texto(r, "Hora") ?? "", Texto(r, "Categoria") ?? "", Texto(r, "Origen") ?? "", Texto(r, "Titulo") ?? "",
                        Texto(r, "Detalle"), Texto(r, "Clave") ?? "", Texto(r, "Badge"), Texto(r, "Registrador"), Texto(r, "Vinculo")));
                return new RespuestaDto<TimelineServicioRutaDto>(2, mensaje, new TimelineServicioRutaDto(conteos, eventos));
            },
            ct);

    public Task<RespuestaDto<IncidenciasServicioRutaDto>> ObtenerIncidenciasAsync(long idUsuario, long idOs, string? clave, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerIncidenciasServicioRuta",
            p => { p.AddWithValue("p_id_usuario", idUsuario); p.AddWithValue("p_id_os", idOs); p.AddWithValue("p_clave", Valor(clave)); },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var kpis = new KpisIncidenciasRutaDto(0, 0, 0, 0, 0);
                if (await r.ReadAsync(ct))
                    kpis = new KpisIncidenciasRutaDto(Entero(r, "Total"), Entero(r, "Retrasan"), Entero(r, "Detienen"), Entero(r, "PorTecnico"), Entero(r, "PorAsistente"));
                await r.NextResultAsync(ct);
                var filas = new List<IncidenciaServicioRutaDto>();
                while (await r.ReadAsync(ct))
                    filas.Add(new IncidenciaServicioRutaDto(Texto(r, "Clave") ?? "", Texto(r, "Hora") ?? "", Texto(r, "TipoCodigo") ?? "", Texto(r, "Tipo") ?? "",
                        Texto(r, "Descripcion"), EnteroNulo(r, "DuracionMin"), Texto(r, "Impacto") ?? "retrasa", Texto(r, "Origen") ?? "tecnico", Texto(r, "Registrador"),
                        Texto(r, "Evidencia"), Booleano(r, "TieneEvidencia")));
                return new RespuestaDto<IncidenciasServicioRutaDto>(2, mensaje, new IncidenciasServicioRutaDto(kpis, filas));
            },
            ct);

    public Task<RespuestaDto<CierreServicioRutaDto>> ObtenerCierreAsync(long idUsuario, long idOs, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerCierreServicioRuta",
            p => { p.AddWithValue("p_id_usuario", idUsuario); p.AddWithValue("p_id_os", idOs); },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<CierreServicioRutaDto>(3, "El procedimiento no devolvió el resumen del cierre.");
                var resumen = new ResumenCierreRutaDto(Texto(r, "Inicio"), Texto(r, "Fin"), EnteroNulo(r, "DuracionMin"), Entero(r, "EquiposTotal"), Entero(r, "EquiposEjecutados"),
                    Entero(r, "DemorasIncidencias"), Entero(r, "Fotos"), Entero(r, "Mediciones"), Texto(r, "Observaciones"));
                await r.NextResultAsync(ct);
                var ordenes = new List<OrdenCierreRutaDto>();
                while (await r.ReadAsync(ct))
                    ordenes.Add(new OrdenCierreRutaDto(Texto(r, "Numero") ?? "", Texto(r, "Estado") ?? "", Texto(r, "Certificado"), Texto(r, "FechaEmision")));
                return new RespuestaDto<CierreServicioRutaDto>(2, mensaje, new CierreServicioRutaDto(resumen, ordenes));
            },
            ct);
}

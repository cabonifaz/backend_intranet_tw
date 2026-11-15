using MySqlConnector;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>HU-35 Bandeja de Programación Operativa (Sprint 5, solo lectura).</summary>
public class ProgramacionOperativaRepositorio(CadenaConexionBd conexion) : RepositorioSpBase(conexion), IProgramacionOperativaRepositorio
{
    // ══════════════════════ Tab Vista Principal ══════════════════════

    public Task<RespuestaDto<ResumenProgramacionDto>> ObtenerResumenAsync(
        DateTime? fechaSemana, string? busqueda, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerResumenProgramacion",
            p =>
            {
                p.AddWithValue("p_id_usuario",   idUsuario);
                p.AddWithValue("p_fecha_semana", Valor(fechaSemana?.Date));
                p.AddWithValue("p_busqueda",     Valor(busqueda));
            },
            async (r, mensaje) =>
            {
                // 2. Tarjetas (más la semana y la capacidad)
                await r.NextResultAsync(ct);
                string inicio = "", fin = "";
                decimal capacidad = 0, capacidadDia = 0;
                var tarjetas = new TarjetasProgramacionDto(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
                if (await r.ReadAsync(ct))
                {
                    inicio    = Fecha(r, "inicio_semana") ?? "";
                    fin       = Fecha(r, "fin_semana") ?? "";
                    capacidad = DecimalNulo(r, "capacidad_semanal_horas") ?? 0;
                    capacidadDia = DecimalNulo(r, "capacidad_diaria_horas") ?? 0;
                    tarjetas  = new TarjetasProgramacionDto(
                        Entero(r, "servicios_hoy"), Entero(r, "en_ejecucion_hoy"),
                        Entero(r, "pendientes_programar"), Entero(r, "pendientes_conf_cliente"),
                        Entero(r, "pendientes_reprogramacion"), Entero(r, "pendientes_ssoma"),
                        Entero(r, "total_pendientes"), Entero(r, "programados"), Entero(r, "programados_semana"),
                        Entero(r, "con_conflicto"), Entero(r, "tecnicos_disponibles"), Entero(r, "plantilla_tecnicos"),
                        Entero(r, "finalizados_hoy"));
                }

                // 3. Calendario
                await r.NextResultAsync(ct);
                var calendario = new List<ServicioCalendarioDto>();
                while (await r.ReadAsync(ct))
                    calendario.Add(new ServicioCalendarioDto(
                        EnteroLargo(r, "id_os"), Texto(r, "tipo") ?? "OS", Texto(r, "numero") ?? "",
                        Texto(r, "estado") ?? "", Texto(r, "sub_estado") ?? "",
                        EnteroLargo(r, "id_tecnico"), Texto(r, "tecnico"),
                        Texto(r, "rol") ?? "principal", Texto(r, "tecnico_principal"),
                        Fecha(r, "fecha_ejecucion"), Texto(r, "hora_inicio"), Texto(r, "hora_fin"),
                        DecimalNulo(r, "horas"), Texto(r, "cliente"), Texto(r, "sede"), Texto(r, "tipo_servicio"),
                        Booleano(r, "en_conflicto"), Booleano(r, "confirmacion_cliente"),
                        EnteroLargoNulo(r, "id_programacion")));

                // 4. Carga por técnico y día (se conserva el orden del SP)
                await r.NextResultAsync(ct);
                var orden = new List<long>();
                var datos = new Dictionary<long, (string Nombre, string? Cargo, string Tipo, string? Sede, List<CargaDiaDto> Dias)>();
                while (await r.ReadAsync(ct))
                {
                    var id = EnteroLargo(r, "id_usuario");
                    if (!datos.TryGetValue(id, out var t))
                    {
                        t = (Texto(r, "nombre") ?? "", Texto(r, "cargo"), Texto(r, "tipo_recurso") ?? "tecnico",
                             Texto(r, "sede_operativa_nombre"), []);
                        datos[id] = t;
                        orden.Add(id);
                    }
                    t.Dias.Add(new CargaDiaDto(Fecha(r, "fecha") ?? "", DecimalNulo(r, "horas") ?? 0,
                                               Texto(r, "nivel") ?? "libre", Booleano(r, "conflicto"), Entero(r, "servicios")));
                }

                // 5. Carga por técnico en la semana
                await r.NextResultAsync(ct);
                var totales = new Dictionary<long, (decimal Horas, int Pct, string Nivel)>();
                while (await r.ReadAsync(ct))
                    totales[EnteroLargo(r, "id_usuario")] =
                        (DecimalNulo(r, "total_horas") ?? 0, Entero(r, "utilizacion_pct"), Texto(r, "nivel") ?? "libre");

                var carga = orden.Select(id =>
                {
                    var t = datos[id];
                    var s = totales.TryGetValue(id, out var x) ? x : (Horas: 0m, Pct: 0, Nivel: "libre");
                    return new CargaTecnicoDto(id, t.Nombre, t.Cargo, t.Tipo, t.Sede, t.Dias, s.Horas, s.Pct, s.Nivel);
                }).ToList();

                // 6. Alertas
                await r.NextResultAsync(ct);
                var alertas = new List<AlertaProgramacionDto>();
                while (await r.ReadAsync(ct))
                    alertas.Add(new AlertaProgramacionDto(
                        Texto(r, "tipo") ?? "", Texto(r, "severidad") ?? "advertencia",
                        Texto(r, "titulo") ?? "", Texto(r, "detalle") ?? "",
                        EnteroLargoNulo(r, "id_usuario"), EnteroLargoNulo(r, "id_os"), EnteroLargoNulo(r, "id_os_2"),
                        Fecha(r, "fecha"), Entero(r, "cantidad")));

                return new RespuestaDto<ResumenProgramacionDto>(2, mensaje,
                    new ResumenProgramacionDto(inicio, fin, capacidad, tarjetas, calendario, carga, alertas, capacidadDia));
            },
            ct);

    // ══════════════════════ Tabs Pendientes y Programados ══════════════════════

    public Task<RespuestaDto<ListaProgramacionDto>> ObtenerPendientesAsync(
        FiltrosProgramacionDto f, bool exportar, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerPendientesProgramacion",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_sub_estado", Valor(f.SubEstado));
                p.AddWithValue("p_tipo",       Valor(f.Tipo));
                p.AddWithValue("p_id_cliente", Valor(f.IdCliente));
                p.AddWithValue("p_id_area",    Valor(f.IdArea));
                p.AddWithValue("p_id_tecnico", Valor(f.IdTecnico));
                p.AddWithValue("p_id_sede",    Valor(f.IdSede));
                p.AddWithValue("p_zona",       Valor(f.Zona));
                p.AddWithValue("p_busqueda",   Valor(f.Busqueda));
                p.AddWithValue("p_pagina",     f.Pagina);
                p.AddWithValue("p_por_pagina", f.PorPagina);
                p.AddWithValue("p_exportar",   Bit(exportar));
            },
            (r, mensaje) => LeerListaAsync(r, mensaje, f, exportar, conConteo: true, ct),
            ct);

    public Task<RespuestaDto<ListaProgramacionDto>> ObtenerProgramadosAsync(
        FiltrosProgramacionDto f, bool exportar, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerProgramadosProgramacion",
            p =>
            {
                p.AddWithValue("p_id_usuario",  idUsuario);
                p.AddWithValue("p_rango",       Valor(f.Rango));
                p.AddWithValue("p_fecha_desde", Valor(f.FechaDesde?.Date));
                p.AddWithValue("p_fecha_hasta", Valor(f.FechaHasta?.Date));
                p.AddWithValue("p_tipo",        Valor(f.Tipo));
                p.AddWithValue("p_id_cliente",  Valor(f.IdCliente));
                p.AddWithValue("p_id_area",     Valor(f.IdArea));
                p.AddWithValue("p_id_tecnico",  Valor(f.IdTecnico));
                p.AddWithValue("p_id_sede",     Valor(f.IdSede));
                p.AddWithValue("p_zona",        Valor(f.Zona));
                p.AddWithValue("p_busqueda",    Valor(f.Busqueda));
                p.AddWithValue("p_pagina",      f.Pagina);
                p.AddWithValue("p_por_pagina",  f.PorPagina);
                p.AddWithValue("p_exportar",    Bit(exportar));
            },
            (r, mensaje) => LeerListaAsync(r, mensaje, f, exportar, conConteo: false, ct),
            ct);

    // ══════════════════════ Lectores comunes ══════════════════════

    /// <summary>
    /// Resultados 2 a 8 de los SPs de lista: filas, total y las cinco opciones de filtro (clientes, áreas, técnicos, sedes
    /// y zonas); Pendientes agrega el 9: cantidad por sub-estado.
    /// </summary>
    private static async Task<RespuestaDto<ListaProgramacionDto>> LeerListaAsync(
        MySqlDataReader r, string mensaje, FiltrosProgramacionDto f, bool exportar, bool conConteo, CancellationToken ct)
    {
        await r.NextResultAsync(ct);
        var items = new List<ItemProgramacionDto>();
        while (await r.ReadAsync(ct))
            items.Add(LeerItem(r));

        var total = await LeerTotalAsync(r, ct);
        var clientes = await LeerOpcionesAsync(r, ct);
        var areas    = await LeerOpcionesAsync(r, ct);
        var tecnicos = await LeerOpcionesAsync(r, ct);
        var sedes    = await LeerOpcionesAsync(r, ct);
        var zonas    = await LeerOpcionesAsync(r, ct);

        ConteoSubEstadosDto? conteo = null;
        if (conConteo && await r.NextResultAsync(ct) && await r.ReadAsync(ct))
            conteo = new ConteoSubEstadosDto(Entero(r, "pendiente_programar"), Entero(r, "pendiente_conf_cliente"),
                                             Entero(r, "pendiente_reprogramacion"), Entero(r, "pendiente_ssoma"));

        return new RespuestaDto<ListaProgramacionDto>(2, mensaje,
            new ListaProgramacionDto(items, total, exportar ? 1 : f.Pagina, exportar ? total : f.PorPagina,
                                     clientes, areas, tecnicos, sedes, zonas, conteo));
    }

    private static ItemProgramacionDto LeerItem(MySqlDataReader r) => new()
    {
        IdOs                         = EnteroLargo(r, "id_os"),
        Tipo                         = Texto(r, "tipo") ?? "OS",
        Numero                       = Texto(r, "numero") ?? "",
        Estado                       = Texto(r, "estado") ?? "",
        EstadoLabel                  = Texto(r, "estado_label") ?? "",
        SubEstado                    = Texto(r, "sub_estado") ?? "",
        SubEstadoLabel               = Texto(r, "sub_estado_label") ?? "",
        IdExpediente                 = EnteroLargoNulo(r, "id_expediente"),
        IdCliente                    = EnteroLargoNulo(r, "id_cliente"),
        RazonSocial                  = Texto(r, "razon_social"),
        Ruc                          = Texto(r, "ruc"),
        IdSede                       = EnteroLargoNulo(r, "id_sede"),
        Sede                         = Texto(r, "sede"),
        Zona                         = Texto(r, "zona"),
        IdPropuesta                  = EnteroLargoNulo(r, "id_propuesta"),
        NumeroPropuesta              = Texto(r, "numero_propuesta"),
        VersionPropuesta             = EnteroNulo(r, "version_propuesta"),
        NumeroRequerimiento          = Texto(r, "numero_requerimiento"),
        IdArea                       = EnteroNulo(r, "id_area"),
        Area                         = Texto(r, "area"),
        IdTecnico                    = EnteroLargoNulo(r, "id_tecnico"),
        Tecnico                      = Texto(r, "tecnico"),
        TecnicosApoyo                = Texto(r, "tecnicos_apoyo"),
        NumeroTecnicos               = Entero(r, "n_tecnicos"),
        IdTipoServicio               = EnteroNulo(r, "id_tipo_servicio"),
        TipoServicio                 = Texto(r, "tipo_servicio"),
        SsomaMotivo                  = Texto(r, "ssoma_motivo"),
        IdProgramacion               = EnteroLargoNulo(r, "id_programacion"),
        CodigoProgramacion           = Texto(r, "codigo_programacion"),
        FechaEjecucion               = Fecha(r, "fecha_ejecucion"),
        HoraInicio                   = Texto(r, "hora_inicio"),
        HoraFin                      = Texto(r, "hora_fin"),
        Horas                        = DecimalNulo(r, "horas"),
        FechaProgramadaDesde         = Fecha(r, "fecha_programada_desde"),
        FechaProgramadaHasta         = Fecha(r, "fecha_programada_hasta"),
        ConfirmacionCliente          = Booleano(r, "confirmacion_cliente"),
        FechaConfirmacionCliente     = FechaHora(r, "fecha_confirmacion_cliente"),
        EnConflicto                  = Booleano(r, "en_conflicto"),
        IdReprogramacionPendiente    = EnteroLargoNulo(r, "id_reprogramacion_pendiente"),
        DiasEnEspera                 = Entero(r, "dias_en_espera"),
        ViaticoMonto                 = DecimalNulo(r, "viatico_monto") ?? 0,
        ViaticoPendiente             = DecimalNulo(r, "viatico_pendiente") ?? 0,
        ViaticoMoneda                = Texto(r, "viatico_moneda") ?? "S/",
        ViaticoEstado                = Texto(r, "viatico_estado") ?? "sin_asignar",
        PuedeProgramar               = Booleano(r, "puede_programar"),
        PuedeReprogramar             = Booleano(r, "puede_reprogramar"),
        PuedeSolicitarReprogramacion = Booleano(r, "puede_solicitar_reprogramacion"),
        PuedeResolverReprogramacion  = Booleano(r, "puede_resolver_reprogramacion"),
        PuedeCancelar                = Booleano(r, "puede_cancelar"),
        PuedeVerDetalle              = Booleano(r, "puede_ver_detalle"),
    };

    private static async Task<List<OpcionFiltroDto>> LeerOpcionesAsync(MySqlDataReader r, CancellationToken ct)
    {
        await r.NextResultAsync(ct);
        var opciones = new List<OpcionFiltroDto>();
        while (await r.ReadAsync(ct))
            opciones.Add(new OpcionFiltroDto(EnteroLargoNulo(r, "id") ?? 0, Texto(r, "nombre") ?? "", Texto(r, "codigo")));
        return opciones;
    }
}

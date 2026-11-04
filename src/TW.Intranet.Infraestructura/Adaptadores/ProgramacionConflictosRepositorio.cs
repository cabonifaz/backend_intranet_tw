using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>HU-39 Carga de Recursos y Alertas de Conflicto Sobrevenido (Sprint 5). Todo pasa por SPs parametrizados.</summary>
public class ProgramacionConflictosRepositorio(CadenaConexionBd conexion) : RepositorioSpBase(conexion), IProgramacionConflictosRepositorio
{
    public Task<RespuestaDto<ConflictosProgramacionDto>> ObtenerConflictosAsync(long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerConflictosProgramacion",
            p => p.AddWithValue("p_id_usuario", idUsuario),
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                ConflictosResumenDto resumen;
                if (await r.ReadAsync(ct))
                    resumen = new ConflictosResumenDto(Entero(r, "total"), Entero(r, "criticas"), Entero(r, "baja"), Entero(r, "ssoma_vencido"),
                        Entero(r, "solapamiento"), Entero(r, "extension_duracion"), Texto(r, "modo") ?? "solo_lectura", Booleano(r, "puede_resolver"));
                else
                    resumen = new ConflictosResumenDto(0, 0, 0, 0, 0, 0, "solo_lectura", false);

                await r.NextResultAsync(ct);
                var conflictos = new List<ConflictoDto>();
                while (await r.ReadAsync(ct))
                    conflictos.Add(new ConflictoDto(Texto(r, "clave") ?? "", Texto(r, "tipo") ?? "", Texto(r, "tipo_label") ?? "",
                        Texto(r, "severidad") ?? "", Texto(r, "titulo") ?? "", Texto(r, "detalle") ?? "", EnteroLargo(r, "id_tecnico"),
                        Texto(r, "tecnico") ?? "", Fecha(r, "fecha"), Entero(r, "n_servicios"), EnteroLargoNulo(r, "id_os_a"),
                        EnteroLargoNulo(r, "id_os_b"), Texto(r, "solape_inicio"), Texto(r, "solape_fin"), EnteroNulo(r, "id_motivo_sugerido"),
                        Texto(r, "motivo_sugerido"), Texto(r, "modo") ?? "solo_lectura", Booleano(r, "puede_resolver")));

                await r.NextResultAsync(ct);
                var servicios = new List<ServicioAfectadoDto>();
                while (await r.ReadAsync(ct))
                    servicios.Add(new ServicioAfectadoDto(Texto(r, "clave") ?? "", EnteroLargo(r, "id_os"), Texto(r, "numero_os") ?? "",
                        Texto(r, "tipo") ?? "OS", Texto(r, "razon_social"), Texto(r, "tipo_servicio"), EnteroLargoNulo(r, "id_programacion"),
                        Texto(r, "estado_programacion"), Fecha(r, "fecha"), Texto(r, "hora_inicio"), Texto(r, "hora_fin"), Booleano(r, "resoluble")));

                return new RespuestaDto<ConflictosProgramacionDto>(2, mensaje, new ConflictosProgramacionDto(resumen, conflictos, servicios));
            },
            ct);

    public Task<RespuestaDto<ConflictoModalDto>> ObtenerConflictoAsync(string tipo, long idTecnico, long idOsA, long? idOsB, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerConflictoProgramacion",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_tipo",       tipo);
                p.AddWithValue("p_id_tecnico", idTecnico);
                p.AddWithValue("p_id_os_a",    idOsA);
                p.AddWithValue("p_id_os_b",    Valor(idOsB));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<ConflictoModalDto>(1, "El conflicto ya no existe o cambió: actualiza la lista de alertas.");
                var c = new ConflictoDetalleDto(Texto(r, "clave") ?? "", Texto(r, "tipo") ?? "", Texto(r, "severidad") ?? "", Texto(r, "titulo") ?? "",
                    Texto(r, "detalle") ?? "", EnteroLargo(r, "id_tecnico"), Texto(r, "tecnico") ?? "", Texto(r, "cargo"), Texto(r, "sede_operativa"),
                    Fecha(r, "fecha"), Texto(r, "solape_inicio"), Texto(r, "solape_fin"), Entero(r, "solape_minutos"), Texto(r, "impacto_operativo"),
                    EnteroNulo(r, "id_motivo_sugerido"), Texto(r, "motivo_sugerido"), Texto(r, "modo") ?? "solo_lectura", Booleano(r, "puede_resolver"));

                await r.NextResultAsync(ct);
                var servicios = new List<ServicioConflictoDto>();
                while (await r.ReadAsync(ct))
                    servicios.Add(new ServicioConflictoDto(Entero(r, "orden"), Texto(r, "etiqueta") ?? "", EnteroLargo(r, "id_os"),
                        EnteroLargoNulo(r, "id_programacion"), Texto(r, "numero_os") ?? "", Texto(r, "tipo") ?? "OS", Texto(r, "razon_social"),
                        Texto(r, "tipo_servicio"), Texto(r, "estado_programacion"), Texto(r, "estado_label"), Fecha(r, "fecha"),
                        Texto(r, "hora_inicio"), Texto(r, "hora_fin"), DecimalNulo(r, "horas"), Booleano(r, "resoluble")));

                await r.NextResultAsync(ct);
                var opciones = new List<OpcionResolucionDto>();
                while (await r.ReadAsync(ct))
                    opciones.Add(new OpcionResolucionDto(Texto(r, "codigo") ?? "", Texto(r, "titulo") ?? "", Texto(r, "descripcion") ?? "",
                        EnteroLargoNulo(r, "afecta_id_os"), EnteroLargoNulo(r, "afecta_id_programacion"), Booleano(r, "mantiene_confirmado"),
                        Booleano(r, "vuelve_pendiente_cliente"), Booleano(r, "disponible"), Texto(r, "motivo_no_disponible")));

                await r.NextResultAsync(ct);
                var recursos = new List<RecursoSugeridoDto>();
                while (await r.ReadAsync(ct))
                    recursos.Add(new RecursoSugeridoDto(EnteroLargo(r, "para_id_os"), Texto(r, "para_numero") ?? "", EnteroLargo(r, "id_tecnico"),
                        Texto(r, "nombre") ?? "", Texto(r, "cargo"), Texto(r, "tipo_recurso"), Texto(r, "sede_operativa"), Texto(r, "ssoma_estado"),
                        DecimalNulo(r, "horas_semana") ?? 0m, Entero(r, "utilizacion_pct"), Entero(r, "score")));

                return new RespuestaDto<ConflictoModalDto>(2, mensaje, new ConflictoModalDto(c, servicios, opciones, recursos));
            },
            ct);

    public Task<RespuestaDto<ReprogramacionResultadoDto>> ResolverConflictoAsync(ResolucionConflictoNormalizada n, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ResolverConflictoProgramacion",
            p =>
            {
                p.AddWithValue("p_id_usuario",       idUsuario);
                p.AddWithValue("p_tipo",             n.Tipo);
                p.AddWithValue("p_id_tecnico",       n.IdTecnico);
                p.AddWithValue("p_id_os_a",          n.IdOsA);
                p.AddWithValue("p_id_os_b",          Valor(n.IdOsB));
                p.AddWithValue("p_opcion",           n.Opcion);
                p.AddWithValue("p_id_os_objetivo",   Valor(n.IdOsObjetivo));
                p.AddWithValue("p_id_nuevo_tecnico", Valor(n.IdNuevoTecnico));
                p.AddWithValue("p_fecha",            n.Fecha is null ? DBNull.Value : n.Fecha.Value.Date);
                p.AddWithValue("p_hora_inicio",      Valor(n.HoraInicio));
                p.AddWithValue("p_hora_fin",         Valor(n.HoraFin));
                p.AddWithValue("p_comentario",       Valor(n.Comentario));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<ReprogramacionResultadoDto>(3, "El cambio se guardó pero el procedimiento no devolvió su detalle.");
                return new RespuestaDto<ReprogramacionResultadoDto>(2, mensaje,
                    new ReprogramacionResultadoDto(
                        Texto(r, "modo") ?? "solicitud", EnteroLargoNulo(r, "id_solicitud"), EnteroLargo(r, "id_programacion"),
                        Texto(r, "codigo") ?? "", Texto(r, "estado") ?? "", Texto(r, "estado_label") ?? "",
                        Booleano(r, "requiere_reconfirmar_cliente"), Booleano(r, "cambia_fecha_hora"),
                        Booleano(r, "cambia_tecnicos"), Booleano(r, "cambia_equipos"),
                        Fecha(r, "fecha_ejecucion"), Texto(r, "hora_inicio"), Texto(r, "hora_fin")));
            },
            ct);

    public Task<RespuestaDto<TecnicoDiaDto>> ObtenerProgramacionesTecnicoDiaAsync(long idTecnico, DateTime fecha, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerProgramacionesTecnicoDia",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_tecnico", idTecnico);
                p.AddWithValue("p_fecha",      fecha.Date);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<TecnicoDiaDto>(1, "El técnico no existe.");
                var carga = new CargaDiaTecnicoDto(EnteroLargo(r, "id_tecnico"), Texto(r, "tecnico") ?? "", Texto(r, "cargo"), Texto(r, "sede_operativa"),
                    Texto(r, "estado_usuario") ?? "", Fecha(r, "fecha") ?? "", DecimalNulo(r, "horas") ?? 0m, Entero(r, "servicios"),
                    Booleano(r, "conflicto"), Texto(r, "nivel") ?? "libre", Booleano(r, "puede_gestionar"));

                await r.NextResultAsync(ct);
                var lista = new List<ProgramacionDiaDto>();
                while (await r.ReadAsync(ct))
                    lista.Add(new ProgramacionDiaDto(EnteroLargo(r, "id_os"), Texto(r, "tipo") ?? "OS", Texto(r, "numero_os") ?? "",
                        Texto(r, "estado_os") ?? "", Texto(r, "sub_estado"), Texto(r, "rol") ?? "principal", EnteroLargoNulo(r, "id_programacion"),
                        Texto(r, "codigo"), Texto(r, "estado_programacion"), Texto(r, "estado_programacion_label"), Texto(r, "razon_social"),
                        Texto(r, "sede"), Texto(r, "tipo_servicio"), Texto(r, "hora_inicio"), Texto(r, "hora_fin"), DecimalNulo(r, "horas"),
                        Booleano(r, "en_conflicto"), Booleano(r, "solicitud_pendiente")));

                return new RespuestaDto<TecnicoDiaDto>(2, mensaje, new TecnicoDiaDto(carga, lista));
            },
            ct);
}

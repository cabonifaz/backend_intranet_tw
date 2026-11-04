using MySqlConnector;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>HU-37 Detalle de la Programación y registro de la confirmación con el cliente (Sprint 5).</summary>
public class ProgramacionDetalleRepositorio(CadenaConexionBd conexion) : RepositorioSpBase(conexion), IProgramacionDetalleRepositorio
{
    // ══════════════════════ Detalle de la programación ══════════════════════

    public Task<RespuestaDto<DetalleProgramacionDto>> ObtenerDetalleAsync(long idProgramacion, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerDetalleProgramacion",
            p =>
            {
                p.AddWithValue("p_id_usuario",      idUsuario);
                p.AddWithValue("p_id_programacion", idProgramacion);
            },
            async (r, mensaje) =>
            {
                // 2. Programación
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<DetalleProgramacionDto>(1, "La programación no existe.");

                var cabecera = new CabeceraProgramacionDto
                {
                    IdProgramacion     = EnteroLargo(r, "id_programacion"),
                    Codigo             = Texto(r, "codigo") ?? "",
                    Estado             = Texto(r, "estado") ?? "",
                    EstadoLabel        = Texto(r, "estado_label") ?? "",
                    IdOs               = EnteroLargo(r, "id_os"),
                    NumeroOs           = Texto(r, "numero_os") ?? "",
                    Tipo               = Texto(r, "tipo") ?? "OS",
                    EstadoOs           = Texto(r, "estado_os"),
                    IdExpediente       = EnteroLargoNulo(r, "id_expediente"),
                    NumeroExpediente   = Texto(r, "numero_expediente"),
                    IdCliente          = EnteroLargoNulo(r, "id_cliente"),
                    RazonSocial        = Texto(r, "razon_social"),
                    Ruc                = Texto(r, "ruc"),
                    IdSede             = EnteroLargoNulo(r, "id_sede"),
                    Sede               = Texto(r, "sede"),
                    Ubicacion          = Texto(r, "ubicacion"),
                    IdPropuesta        = EnteroLargoNulo(r, "id_propuesta"),
                    NumeroPropuesta    = Texto(r, "numero_propuesta"),
                    VersionPropuesta   = EnteroNulo(r, "version_propuesta"),
                    IdTipoServicio     = EnteroNulo(r, "id_tipo_servicio"),
                    TipoServicio       = Texto(r, "tipo_servicio"),
                    FechaEjecucion     = Fecha(r, "fecha_ejecucion"),
                    HoraInicio         = Texto(r, "hora_inicio"),
                    HoraFin            = Texto(r, "hora_fin"),
                    DuracionHoras      = DecimalNulo(r, "duracion_horas"),
                    Observaciones      = Texto(r, "observaciones"),
                    TecnicoPrincipal   = Texto(r, "tecnico_principal"),
                    NumeroTecnicos     = Entero(r, "n_tecnicos"),
                    NumeroEquipos      = Entero(r, "n_equipos"),
                    NumeroConceptos    = Entero(r, "n_conceptos"),
                    ProximoPaso        = Texto(r, "proximo_paso") ?? "",
                    CreadoEn           = FechaHora(r, "creado_en"),
                    CreadoPor          = Texto(r, "creado_por_nombre"),
                    BloqueoSsomaActivo = Booleano(r, "bloqueo_ssoma_activo"),
                    Acciones           = new AccionesDetalleProgramacionDto(
                        Booleano(r, "puede_registrar_respuesta"), Booleano(r, "puede_reasignar"), Booleano(r, "puede_reprogramar"),
                        Booleano(r, "reprogramacion_directa"), Booleano(r, "reprogramacion_requiere_solicitud"),
                        Booleano(r, "puede_cancelar"), Booleano(r, "puede_gestionar_viaticos"), Booleano(r, "puede_ver_expediente")),
                };

                // 3. Técnicos
                await r.NextResultAsync(ct);
                var tecnicos = new List<TecnicoDetalleProgramacionDto>();
                while (await r.ReadAsync(ct))
                    tecnicos.Add(new TecnicoDetalleProgramacionDto(
                        EnteroLargo(r, "id_usuario"), Texto(r, "nombre") ?? "", Texto(r, "cargo"), Texto(r, "rol") ?? "apoyo",
                        Texto(r, "ssoma_al_programar"), Texto(r, "ssoma_actual"), Texto(r, "ssoma_motivo")));

                // 4. Equipos reservados
                await r.NextResultAsync(ct);
                var equipos = new List<EquipoDetalleProgramacionDto>();
                while (await r.ReadAsync(ct))
                    equipos.Add(new EquipoDetalleProgramacionDto(
                        EnteroLargo(r, "id_equipo"), Texto(r, "codigo_tw"), Texto(r, "marca"), Texto(r, "modelo"), Texto(r, "num_serie")));

                // 5. Conceptos
                await r.NextResultAsync(ct);
                var conceptos = new List<ConceptoProgramacionDto>();
                while (await r.ReadAsync(ct))
                    conceptos.Add(new ConceptoProgramacionDto(
                        EnteroLargo(r, "id_os_concepto"), Texto(r, "codigo"), Texto(r, "descripcion") ?? "",
                        Texto(r, "alcance"), Entero(r, "orden")));

                // 6. Checklist
                await r.NextResultAsync(ct);
                var checklist = new List<ItemChecklistProgramacionDto>();
                while (await r.ReadAsync(ct))
                    checklist.Add(new ItemChecklistProgramacionDto(
                        Texto(r, "item") ?? "", Texto(r, "titulo") ?? "", Booleano(r, "cumple"), Booleano(r, "requiere_accion"),
                        Texto(r, "detalle")));

                // 7. Alertas SSOMA sobrevenidas
                await r.NextResultAsync(ct);
                var alertas = new List<AlertaSsomaProgramacionDto>();
                while (await r.ReadAsync(ct))
                    alertas.Add(new AlertaSsomaProgramacionDto(
                        Texto(r, "severidad") ?? "critica", EnteroLargo(r, "id_usuario"), Texto(r, "tecnico") ?? "",
                        Texto(r, "requisito"), Texto(r, "situacion"), Texto(r, "estado_doc"), Fecha(r, "fecha_vencimiento"),
                        EnteroNulo(r, "dias_vencido"), Booleano(r, "ya_vencio"), Texto(r, "mensaje")));

                // 8. Historial
                await r.NextResultAsync(ct);
                var historial = new List<EventoProgramacionDto>();
                while (await r.ReadAsync(ct))
                    historial.Add(new EventoProgramacionDto(
                        FechaHora(r, "fecha"), Texto(r, "tipo") ?? "estado", Texto(r, "titulo") ?? "", Texto(r, "descripcion"),
                        Texto(r, "usuario"), Texto(r, "estado_anterior"), Texto(r, "estado_nuevo"), Texto(r, "motivo")));

                // 9. Respuestas del cliente
                await r.NextResultAsync(ct);
                var respuestas = new List<RespuestaClienteProgramacionDto>();
                while (await r.ReadAsync(ct))
                    respuestas.Add(new RespuestaClienteProgramacionDto(
                        EnteroLargo(r, "id"), Texto(r, "canal") ?? "", Texto(r, "canal_label") ?? "", Texto(r, "resultado") ?? "",
                        Texto(r, "resultado_label") ?? "", Texto(r, "comentario"), FechaHora(r, "fecha_registro"),
                        Texto(r, "registrado_por")));

                return new RespuestaDto<DetalleProgramacionDto>(2, mensaje,
                    new DetalleProgramacionDto(cabecera, tecnicos, equipos, conceptos, checklist, alertas, historial, respuestas));
            },
            ct);

    // ══════════════════════ Registrar la respuesta del cliente ══════════════════════

    public Task<RespuestaDto<RespuestaClienteRegistradaDto>> RegistrarRespuestaClienteAsync(
        NuevaRespuestaCliente n, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_RegistrarRespuestaClienteProgramacion",
            p =>
            {
                p.AddWithValue("p_id_usuario",      idUsuario);
                p.AddWithValue("p_id_programacion", n.IdProgramacion);
                p.AddWithValue("p_canal",           n.Canal);
                p.AddWithValue("p_resultado",       n.Resultado);
                p.AddWithValue("p_comentario",      Valor(n.Comentario));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<RespuestaClienteRegistradaDto>(3, "La respuesta se guardó pero el procedimiento no devolvió su detalle.");

                var idConfirmacion = EnteroLargo(r, "id_confirmacion");
                var idProgramacion = EnteroLargo(r, "id_programacion");
                var codigo         = Texto(r, "codigo") ?? "";
                var estado         = Texto(r, "estado") ?? "";
                var estadoLabel    = Texto(r, "estado_label") ?? "";
                var canal          = Texto(r, "canal") ?? "";
                var resultado      = Texto(r, "resultado") ?? "";
                var comentario     = Texto(r, "comentario");
                var idOs           = EnteroLargo(r, "id_os");
                var numeroOs       = Texto(r, "numero_os") ?? "";
                var siguiente      = Texto(r, "siguiente_accion") ?? "";
                var viaticos       = Booleano(r, "puede_gestionar_viaticos");
                var solicitud      = Booleano(r, "requiere_solicitud");
                var motivo         = Booleano(r, "requiere_motivo_cancelacion");

                await r.NextResultAsync(ct);
                var advertencias = new List<string>();
                while (await r.ReadAsync(ct))
                    advertencias.Add(Texto(r, "advertencia") ?? "");

                return new RespuestaDto<RespuestaClienteRegistradaDto>(2, mensaje,
                    new RespuestaClienteRegistradaDto(idConfirmacion, idProgramacion, codigo, estado, estadoLabel, canal, resultado,
                        comentario, idOs, numeroOs, siguiente, viaticos, solicitud, motivo, advertencias));
            },
            ct);
}

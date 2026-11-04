using System.Text.Json;
using MySqlConnector;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>HU-36 Programación de OS y asignación de recursos (Sprint 5).</summary>
public class ProgramacionRepositorio(CadenaConexionBd conexion) : RepositorioSpBase(conexion), IProgramacionRepositorio
{
    // ══════════════════════ Ficha "Programar Servicio" ══════════════════════

    public Task<RespuestaDto<FichaProgramacionDto>> ObtenerFichaAsync(long idOs, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_PrepararProgramacion",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_os",      idOs);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<FichaProgramacionDto>(1, "La orden de servicio no existe.");

                var orden = new OrdenParaProgramarDto
                {
                    IdOs                     = EnteroLargo(r, "id_os"),
                    Tipo                     = Texto(r, "tipo") ?? "OS",
                    Numero                   = Texto(r, "numero") ?? "",
                    Estado                   = Texto(r, "estado") ?? "",
                    IdExpediente             = EnteroLargoNulo(r, "id_expediente"),
                    NumeroExpediente         = Texto(r, "numero_expediente"),
                    IdCliente                = EnteroLargoNulo(r, "id_cliente"),
                    RazonSocial              = Texto(r, "razon_social"),
                    Ruc                      = Texto(r, "ruc"),
                    IdSede                   = EnteroLargoNulo(r, "id_sede"),
                    Sede                     = Texto(r, "sede"),
                    Ubicacion                = Texto(r, "ubicacion"),
                    IdPropuesta              = EnteroLargoNulo(r, "id_propuesta"),
                    NumeroPropuesta          = Texto(r, "numero_propuesta"),
                    VersionPropuesta         = EnteroNulo(r, "version_propuesta"),
                    IdTipoServicio           = EnteroNulo(r, "id_tipo_servicio"),
                    TipoServicio             = Texto(r, "tipo_servicio"),
                    NumeroRequerimiento      = Texto(r, "numero_requerimiento"),
                    IdArea                   = EnteroNulo(r, "id_area"),
                    Area                     = Texto(r, "area"),
                    FechaProgramadaDesde     = Fecha(r, "fecha_programada_desde"),
                    FechaProgramadaHasta     = Fecha(r, "fecha_programada_hasta"),
                    NumeroEquipos            = Entero(r, "n_equipos"),
                    NumeroConceptos          = Entero(r, "n_conceptos"),
                    IdProgramacionActiva     = EnteroLargoNulo(r, "id_programacion_activa"),
                    CodigoProgramacionActiva = Texto(r, "codigo_programacion_activa"),
                    PuedeProgramar           = Booleano(r, "puede_programar"),
                    MotivoNoProgramable      = Texto(r, "motivo_no_programable"),
                };

                await r.NextResultAsync(ct);
                var equipos = new List<EquipoProgramacionDto>();
                while (await r.ReadAsync(ct))
                    equipos.Add(new EquipoProgramacionDto(
                        EnteroLargo(r, "id_os_equipo"), EnteroLargo(r, "id_equipo"), Texto(r, "codigo_tw"), Texto(r, "marca"),
                        Texto(r, "modelo"), Texto(r, "num_serie"), Texto(r, "ubicacion_especifica"), Texto(r, "alcance_maximo"),
                        Entero(r, "orden")));

                await r.NextResultAsync(ct);
                var requisitos = new List<RequisitoSsomaProgramacionDto>();
                while (await r.ReadAsync(ct))
                    requisitos.Add(new RequisitoSsomaProgramacionDto(
                        EnteroLargo(r, "id"), Entero(r, "id_requisito"), Texto(r, "requisito") ?? "", Booleano(r, "es_obligatorio"),
                        Booleano(r, "bloquea_servicio"), Texto(r, "sede"), Texto(r, "aplica_a") ?? "ambos",
                        Texto(r, "documento_equivalente")));

                await r.NextResultAsync(ct);
                var conceptos = new List<ConceptoProgramacionDto>();
                while (await r.ReadAsync(ct))
                    conceptos.Add(new ConceptoProgramacionDto(
                        EnteroLargo(r, "id_os_concepto"), Texto(r, "codigo"), Texto(r, "descripcion") ?? "",
                        Texto(r, "alcance"), Entero(r, "orden")));

                return new RespuestaDto<FichaProgramacionDto>(2, mensaje,
                    new FichaProgramacionDto(orden, equipos, requisitos, conceptos));
            },
            ct);

    // ══════════════════════ Buscador de técnicos ══════════════════════

    public Task<RespuestaDto<BusquedaTecnicosDto>> BuscarTecnicosAsync(
        long idOs, FiltroTecnicosProgramacion f, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_BuscarTecnicosProgramacion",
            p =>
            {
                p.AddWithValue("p_id_usuario",          idUsuario);
                p.AddWithValue("p_id_os",               idOs);
                p.AddWithValue("p_fecha",               Valor(f.Fecha));
                p.AddWithValue("p_hora_inicio",         Valor(f.HoraInicio));
                p.AddWithValue("p_hora_fin",            Valor(f.HoraFin));
                p.AddWithValue("p_solo_disponibles",    Bit(f.SoloDisponibles));
                p.AddWithValue("p_solo_ssoma_conforme", Bit(f.SoloSsomaConforme));
                p.AddWithValue("p_busqueda",            Valor(f.Busqueda));
                p.AddWithValue("p_sede_operativa",      Valor(f.SedeOperativa));
                p.AddWithValue("p_tipo_recurso",        Valor(f.TipoRecurso));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var filas = new List<TecnicoProgramacionDto>();
                while (await r.ReadAsync(ct))
                    filas.Add(new TecnicoProgramacionDto(
                        EnteroLargo(r, "id_usuario"), Texto(r, "nombre") ?? "", Texto(r, "cargo"), Texto(r, "area"),
                        Texto(r, "tipo_recurso") ?? "tecnico", Texto(r, "sede_operativa"), Texto(r, "sede_operativa_nombre"),
                        Texto(r, "disponibilidad") ?? "sin_horario",
                        Texto(r, "conflicto_os"), Texto(r, "conflicto_desde"), Texto(r, "conflicto_hasta"),
                        Entero(r, "servicios_dia"), DecimalNulo(r, "horas_dia") ?? 0,
                        Entero(r, "servicios_max_dia"), Entero(r, "cupo_libre"), DecimalNulo(r, "horas_libres") ?? 0,
                        Texto(r, "ssoma_estado") ?? "conforme", Texto(r, "ssoma_motivo"), Texto(r, "ssoma_faltantes"),
                        Entero(r, "ssoma_requeridos"), Entero(r, "ssoma_cumplidos"),
                        Entero(r, "servicios_cliente"), Texto(r, "experiencia_cliente") ?? "sin_experiencia",
                        DecimalNulo(r, "scorecard_pct"), Texto(r, "scorecard_nivel"), EnteroNulo(r, "scorecard_servicios"),
                        []));

                await r.NextResultAsync(ct);
                var documentos = new Dictionary<long, List<DocumentoSsomaTecnicoDto>>();
                while (await r.ReadAsync(ct))
                {
                    var id = EnteroLargo(r, "id_usuario");
                    if (!documentos.TryGetValue(id, out var lista))
                        documentos[id] = lista = [];
                    lista.Add(new DocumentoSsomaTecnicoDto(
                        Texto(r, "requisito") ?? "", Texto(r, "estado"), Fecha(r, "fecha_vencimiento"),
                        Texto(r, "situacion") ?? "conforme", Booleano(r, "requerido"), Booleano(r, "bloquea")));
                }

                await r.NextResultAsync(ct);
                var contadores = await r.ReadAsync(ct)
                    ? new ContadoresRecursoDto(Entero(r, "tecnicos"), Entero(r, "metrologos"), Entero(r, "externos"))
                    : new ContadoresRecursoDto(0, 0, 0);

                var tecnicos = filas
                    .Select(t => t with { DocumentosSsoma = documentos.TryGetValue(t.IdUsuario, out var d) ? d : [] })
                    .ToList();

                return new RespuestaDto<BusquedaTecnicosDto>(2, mensaje, new BusquedaTecnicosDto(tecnicos, tecnicos.Count, contadores));
            },
            ct);

    // ══════════════════════ Crear la programación ══════════════════════

    public Task<RespuestaDto<ProgramacionCreadaDto>> CrearAsync(NuevaProgramacion n, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_CrearProgramacion",
            p =>
            {
                p.AddWithValue("p_id_usuario",           idUsuario);
                p.AddWithValue("p_id_os",                n.IdOs);
                p.AddWithValue("p_fecha",                n.Fecha.Date);
                p.AddWithValue("p_hora_inicio",          n.HoraInicio);
                p.AddWithValue("p_hora_fin",             n.HoraFin);
                p.AddWithValue("p_id_tecnico_principal", n.IdTecnicoPrincipal);
                p.AddWithValue("p_ids_apoyo",            JsonSerializer.Serialize(n.IdsApoyo));
                p.AddWithValue("p_ids_equipos",          JsonSerializer.Serialize(n.IdsEquipos));
                p.AddWithValue("p_observaciones",        Valor(n.Observaciones));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<ProgramacionCreadaDto>(3, "La programación se guardó pero el procedimiento no devolvió su código.");

                var idProgramacion = EnteroLargo(r, "id_programacion");
                var codigo         = Texto(r, "codigo") ?? "";
                var idOs           = EnteroLargo(r, "id_os");
                var numeroOs       = Texto(r, "numero_os") ?? "";
                var estado         = Texto(r, "estado") ?? "pendiente_confirmacion";
                var fecha          = Fecha(r, "fecha_ejecucion");
                var horaInicio     = Texto(r, "hora_inicio");
                var horaFin        = Texto(r, "hora_fin");

                await r.NextResultAsync(ct);
                var advertencias = new List<string>();
                while (await r.ReadAsync(ct))
                    advertencias.Add(Texto(r, "advertencia") ?? "");

                return new RespuestaDto<ProgramacionCreadaDto>(2, mensaje,
                    new ProgramacionCreadaDto(idProgramacion, codigo, idOs, numeroOs, estado, fecha, horaInicio, horaFin, advertencias));
            },
            ct);

    // ══════════════════════ Derivar al área SSOMA ══════════════════════

    public Task<RespuestaDto<DerivacionSsomaDto>> DerivarSsomaAsync(NuevaDerivacionSsoma n, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_DerivarSsomaProgramacion",
            p =>
            {
                p.AddWithValue("p_id_usuario",   idUsuario);
                p.AddWithValue("p_id_os",        n.IdOs);
                p.AddWithValue("p_fecha",        Valor(n.Fecha?.Date));
                p.AddWithValue("p_ids_tecnicos", JsonSerializer.Serialize(n.IdsTecnicos));
                p.AddWithValue("p_comentario",   Valor(n.Comentario));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                int notificados = 0, conPendientes = 0;
                if (await r.ReadAsync(ct))
                {
                    notificados   = Entero(r, "notificados");
                    conPendientes = Entero(r, "tecnicos_con_pendientes");
                }

                await r.NextResultAsync(ct);
                var pendientes = new List<PendienteSsomaDerivadoDto>();
                while (await r.ReadAsync(ct))
                    pendientes.Add(new PendienteSsomaDerivadoDto(
                        EnteroLargo(r, "id_usuario"), Texto(r, "tecnico") ?? "", Texto(r, "requisito") ?? "",
                        Texto(r, "situacion") ?? "", Fecha(r, "fecha_vencimiento")));

                return new RespuestaDto<DerivacionSsomaDto>(2, mensaje, new DerivacionSsomaDto(notificados, conPendientes, pendientes));
            },
            ct);
}

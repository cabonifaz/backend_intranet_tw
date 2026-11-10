using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>Asistente IA y Procedimientos de la app móvil (App Mobile HU-19). Todo pasa por SP; el usuario siempre sale del token.</summary>
public class AsistenteMovilRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), IAsistenteMovilRepositorio
{
    public Task<RespuestaDto<InicioAsistenteMovilDto>> ObtenerInicioAsync(long idUsuario, long? idOs, long? idOsEquipo, CancellationToken ct) =>
        EjecutarAsync<InicioAsistenteMovilDto>("SP_InicioAsistenteMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario",   idUsuario);
                p.AddWithValue("p_id_os",        Valor(idOs));
                p.AddWithValue("p_id_os_equipo", Valor(idOsEquipo));
            },
            async (r, mensaje) =>
            {
                ContextoAsistenteMovilDto? contexto = null;
                await r.NextResultAsync(ct);
                if (await r.ReadAsync(ct))
                    contexto = new ContextoAsistenteMovilDto(
                        EnteroLargo(r, "id_os"), Texto(r, "numero_os") ?? string.Empty, EnteroLargo(r, "id_os_equipo"), Texto(r, "nombre") ?? "Equipo", Entero(r, "numero"),
                        Texto(r, "marca"), Texto(r, "modelo"), Texto(r, "codigo_cliente"), Texto(r, "numero_serie"), Texto(r, "servicio_sigla"), Texto(r, "estado") ?? "por_iniciar");

                var fuentes = new List<FuenteDisponibleAsistenteMovilDto>();
                await r.NextResultAsync(ct);
                while (await r.ReadAsync(ct))
                    fuentes.Add(new FuenteDisponibleAsistenteMovilDto(
                        Texto(r, "id_documento") ?? string.Empty, Texto(r, "tipo") ?? "manual", Texto(r, "titulo") ?? string.Empty, Texto(r, "version"), Texto(r, "entidad"),
                        Fecha(r, "actualizado"), Booleano(r, "disponible")));

                var sugerencias = new List<string>();
                await r.NextResultAsync(ct);
                while (await r.ReadAsync(ct))
                    if (Texto(r, "texto") is { Length: > 0 } t) sugerencias.Add(t);

                var recientes = new List<ConsultaRecienteAsistenteMovilDto>();
                await r.NextResultAsync(ct);
                while (await r.ReadAsync(ct))
                    recientes.Add(new ConsultaRecienteAsistenteMovilDto(EnteroLargo(r, "id_consulta"), Texto(r, "pregunta") ?? string.Empty, Texto(r, "fuente"), FechaHora(r, "creado_en")));

                return new RespuestaDto<InicioAsistenteMovilDto>(2, mensaje, new InicioAsistenteMovilDto(contexto, fuentes, sugerencias, recientes));
            }, ct);

    public Task<RespuestaDto<List<EquipoAsistenteMovilDto>>> ObtenerEquiposAsync(long idUsuario, CancellationToken ct) =>
        EjecutarAsync<List<EquipoAsistenteMovilDto>>("SP_EquiposAsistenteMovil",
            p => p.AddWithValue("p_id_usuario", idUsuario),
            async (r, mensaje) =>
            {
                var lista = new List<EquipoAsistenteMovilDto>();
                await r.NextResultAsync(ct);
                while (await r.ReadAsync(ct))
                    lista.Add(new EquipoAsistenteMovilDto(
                        EnteroLargo(r, "id_os"), Texto(r, "numero_os") ?? string.Empty, EnteroLargo(r, "id_os_equipo"), Texto(r, "nombre") ?? "Equipo", Entero(r, "numero"),
                        Texto(r, "marca"), Texto(r, "modelo"), Texto(r, "codigo_cliente"), Texto(r, "estado") ?? "por_iniciar", Booleano(r, "en_trabajo"),
                        Entero(r, "fuentes_disponibles")));
                return new RespuestaDto<List<EquipoAsistenteMovilDto>>(2, mensaje, lista);
            }, ct);

    public Task<RespuestaDto<DocumentosAsistenteMovilDto>> ObtenerDocumentosAsync(long idUsuario, long idOs, long idOsEquipo, CancellationToken ct) =>
        EjecutarAsync<DocumentosAsistenteMovilDto>("SP_DocumentosAsistenteMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario",   idUsuario);
                p.AddWithValue("p_id_os",        idOs);
                p.AddWithValue("p_id_os_equipo", idOsEquipo);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<DocumentosAsistenteMovilDto>(1, "Servicio o equipo no encontrado.");
                var contexto = new ContextoIaAsistente(
                    EnteroLargo(r, "id_os"), Texto(r, "numero_os") ?? string.Empty, EnteroLargo(r, "id_os_equipo"), Texto(r, "nombre") ?? "Equipo", Entero(r, "numero"),
                    Texto(r, "marca"), Texto(r, "modelo"), Texto(r, "codigo_cliente"), Texto(r, "numero_serie"), Texto(r, "servicio_sigla"), Texto(r, "estado") ?? "por_iniciar",
                    Texto(r, "tipo_equipo"));

                var documentos = new List<DocumentoAsistenteMovil>();
                await r.NextResultAsync(ct);
                while (await r.ReadAsync(ct))
                    documentos.Add(new DocumentoAsistenteMovil(
                        Texto(r, "id_documento") ?? string.Empty, Texto(r, "tipo") ?? "manual", Texto(r, "titulo") ?? string.Empty, Texto(r, "version"), Texto(r, "entidad"),
                        Fecha(r, "actualizado"), Texto(r, "ubicacion") ?? string.Empty, Booleano(r, "disponible")));

                return new RespuestaDto<DocumentosAsistenteMovilDto>(2, mensaje, new DocumentosAsistenteMovilDto(contexto, documentos));
            }, ct);

    private static async Task<RespuestaDto<ConsultaRegistradaAsistente>> LeerConsultaRegistradaAsync(MySqlConnector.MySqlDataReader r, string mensaje, CancellationToken ct)
    {
        await r.NextResultAsync(ct);
        if (!await r.ReadAsync(ct))
            return new RespuestaDto<ConsultaRegistradaAsistente>(1, "No se pudo registrar la consulta.");
        return new RespuestaDto<ConsultaRegistradaAsistente>(2, mensaje, new ConsultaRegistradaAsistente(EnteroLargo(r, "id_consulta"), FechaHora(r, "creado_en")));
    }

    public Task<RespuestaDto<ConsultaRegistradaAsistente>> IniciarConsultaAsync(long idUsuario, long idOs, long idOsEquipo, string pregunta, string origen, CancellationToken ct) =>
        EjecutarAsync<ConsultaRegistradaAsistente>("SP_RegistrarConsultaAsistenteMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario",      idUsuario);
                p.AddWithValue("p_id_consulta",     DBNull.Value);
                p.AddWithValue("p_id_os",           idOs);
                p.AddWithValue("p_id_os_equipo",    idOsEquipo);
                p.AddWithValue("p_pregunta",        pregunta);
                p.AddWithValue("p_origen",          origen);
                p.AddWithValue("p_estado",          DBNull.Value);
                p.AddWithValue("p_documentos_json", DBNull.Value);
                p.AddWithValue("p_respuesta_json",  DBNull.Value);
                p.AddWithValue("p_motor",           DBNull.Value);
                p.AddWithValue("p_duracion_ms",     DBNull.Value);
            },
            (r, mensaje) => LeerConsultaRegistradaAsync(r, mensaje, ct), ct);

    public Task<RespuestaDto<ConsultaRegistradaAsistente>> CompletarConsultaAsync(
        long idUsuario, long idConsulta, string estado, string? documentosJson, string? respuestaJson, string? motor, int duracionMs, CancellationToken ct) =>
        EjecutarAsync<ConsultaRegistradaAsistente>("SP_RegistrarConsultaAsistenteMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario",      idUsuario);
                p.AddWithValue("p_id_consulta",     idConsulta);
                p.AddWithValue("p_id_os",           DBNull.Value);
                p.AddWithValue("p_id_os_equipo",    DBNull.Value);
                p.AddWithValue("p_pregunta",        DBNull.Value);
                p.AddWithValue("p_origen",          DBNull.Value);
                p.AddWithValue("p_estado",          estado);
                p.AddWithValue("p_documentos_json", Valor(documentosJson));
                p.AddWithValue("p_respuesta_json",  Valor(respuestaJson));
                p.AddWithValue("p_motor",           Valor(motor));
                p.AddWithValue("p_duracion_ms",     duracionMs);
            },
            (r, mensaje) => LeerConsultaRegistradaAsync(r, mensaje, ct), ct);

    public Task<RespuestaDto<ConsultaGuardadaAsistente>> ObtenerConsultaAsync(long idUsuario, long idConsulta, CancellationToken ct) =>
        EjecutarAsync<ConsultaGuardadaAsistente>("SP_ObtenerConsultaAsistenteMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario",  idUsuario);
                p.AddWithValue("p_id_consulta", idConsulta);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<ConsultaGuardadaAsistente>(1, "Consulta no encontrada.");
                return new RespuestaDto<ConsultaGuardadaAsistente>(2, mensaje, new ConsultaGuardadaAsistente(
                    EnteroLargo(r, "id_consulta"), EnteroLargo(r, "id_os"), EnteroLargo(r, "id_os_equipo"), Texto(r, "pregunta") ?? string.Empty, Texto(r, "origen") ?? "texto",
                    Texto(r, "estado") ?? "respondida", FechaHora(r, "creado_en"), Texto(r, "respuesta_json"), EsNulo(r, "util") ? null : Booleano(r, "util")));
            }, ct);

    public Task<RespuestaDto<object>> ValorarConsultaAsync(long idUsuario, long idConsulta, bool util, CancellationToken ct) =>
        EjecutarAsync<object>("SP_ValorarConsultaAsistenteMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario",  idUsuario);
                p.AddWithValue("p_id_consulta", idConsulta);
                p.AddWithValue("p_util",        Bit(util));
            },
            (_, mensaje) => Task.FromResult(new RespuestaDto<object>(2, mensaje)), ct);

    public Task<RespuestaDto<List<GuardadoAsistenteMovilDto>>> ListarGuardadosAsync(long idUsuario, string? busqueda, CancellationToken ct) =>
        EjecutarAsync<List<GuardadoAsistenteMovilDto>>("SP_ListarGuardadosAsistenteMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_busqueda",   Valor(busqueda));
            },
            async (r, mensaje) =>
            {
                var lista = new List<GuardadoAsistenteMovilDto>();
                await r.NextResultAsync(ct);
                while (await r.ReadAsync(ct))
                    lista.Add(new GuardadoAsistenteMovilDto(
                        EnteroLargo(r, "id_guardado"), Texto(r, "tipo") ?? "respuesta", Texto(r, "titulo") ?? string.Empty, Texto(r, "subtitulo"), FechaHora(r, "creado_en"),
                        Entero(r, "tamano_bytes")));
                return new RespuestaDto<List<GuardadoAsistenteMovilDto>>(2, mensaje, lista);
            }, ct);

    private static async Task<RespuestaDto<GuardadoCrudoAsistente>> LeerGuardadoAsync(MySqlConnector.MySqlDataReader r, string mensaje, CancellationToken ct)
    {
        await r.NextResultAsync(ct);
        if (!await r.ReadAsync(ct))
            return new RespuestaDto<GuardadoCrudoAsistente>(1, "Guardado no encontrado.");
        return new RespuestaDto<GuardadoCrudoAsistente>(2, mensaje, new GuardadoCrudoAsistente(
            EnteroLargo(r, "id_guardado"), Texto(r, "tipo") ?? "respuesta", Texto(r, "titulo") ?? string.Empty, Texto(r, "subtitulo"), FechaHora(r, "creado_en"),
            Entero(r, "tamano_bytes"), Texto(r, "contenido_json")));
    }

    public Task<RespuestaDto<GuardadoCrudoAsistente>> GuardarAsync(
        long idUsuario, long idConsulta, string tipo, int n, string titulo, string? subtitulo, string contenidoJson, CancellationToken ct) =>
        EjecutarAsync<GuardadoCrudoAsistente>("SP_GuardarAsistenteMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario",     idUsuario);
                p.AddWithValue("p_id_consulta",    idConsulta);
                p.AddWithValue("p_tipo",           tipo);
                p.AddWithValue("p_n",              n);
                p.AddWithValue("p_titulo",         titulo);
                p.AddWithValue("p_subtitulo",      Valor(subtitulo));
                p.AddWithValue("p_contenido_json", contenidoJson);
            },
            (r, mensaje) => LeerGuardadoAsync(r, mensaje, ct), ct);

    public Task<RespuestaDto<GuardadoCrudoAsistente>> ObtenerGuardadoAsync(long idUsuario, long idGuardado, CancellationToken ct) =>
        EjecutarAsync<GuardadoCrudoAsistente>("SP_ObtenerGuardadoAsistenteMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario",  idUsuario);
                p.AddWithValue("p_id_guardado", idGuardado);
            },
            (r, mensaje) => LeerGuardadoAsync(r, mensaje, ct), ct);

    public Task<RespuestaDto<object>> EliminarGuardadoAsync(long idUsuario, long idGuardado, CancellationToken ct) =>
        EjecutarAsync<object>("SP_EliminarGuardadoAsistenteMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario",  idUsuario);
                p.AddWithValue("p_id_guardado", idGuardado);
            },
            (_, mensaje) => Task.FromResult(new RespuestaDto<object>(2, mensaje)), ct);
}

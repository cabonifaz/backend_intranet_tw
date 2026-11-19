using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>Revisión de informes técnicos del Jefe de Área en la app móvil (App Mobile HU-33). Todo sale de procedimientos almacenados.</summary>
public class InformesRevisionMovilRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), IInformesRevisionMovilRepositorio
{
    public Task<RespuestaDto<InformesRevisionDto>> ObtenerAsync(long idUsuario, string grupo, string? busqueda, CancellationToken ct) =>
        EjecutarAsync<InformesRevisionDto>("SP_ObtenerInformesRevisionMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_grupo",      grupo);
                p.AddWithValue("p_busqueda",   Valor(busqueda));
            },
            async (r, mensaje) =>
            {
                // 2 KPIs
                await r.NextResultAsync(ct);
                var kpis = await r.ReadAsync(ct)
                    ? new InformesRevisionKpisDto(Entero(r, "pendientes"), Entero(r, "observados"), Entero(r, "sin_evidencias"), Entero(r, "sla_vencido"),
                                                  Texto(r, "actualizado"), Math.Max(Entero(r, "refresco_segundos"), 10))
                    : new InformesRevisionKpisDto(0, 0, 0, 0, null, 30);

                // 3 Informes
                await r.NextResultAsync(ct);
                var informes = new List<InformeRevisionItemDto>();
                while (await r.ReadAsync(ct))
                    informes.Add(new InformeRevisionItemDto(EnteroLargo(r, "id_informe"), Texto(r, "numero_informe") ?? string.Empty, Texto(r, "numero_os"), Texto(r, "cliente"),
                                                            Texto(r, "equipo"), Texto(r, "codigo_tw"), Texto(r, "tecnico"), Texto(r, "estado") ?? "por_revisar",
                                                            Entero(r, "evidencias"), Entero(r, "forzadas"), Booleano(r, "firmado_cliente"), Entero(r, "horas_espera"),
                                                            Booleano(r, "sla_vencido"), Texto(r, "plazo_en")));

                return new RespuestaDto<InformesRevisionDto>(2, mensaje, new InformesRevisionDto(kpis, informes));
            }, ct);

    public Task<RespuestaDto<InformeRevisionDetalleDto>> ObtenerDetalleAsync(long idUsuario, long idInforme, CancellationToken ct) =>
        EjecutarAsync<InformeRevisionDetalleDto>("SP_ObtenerInformeRevisionMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_informe", idInforme);
            },
            async (r, mensaje) =>
            {
                // 2 Cabecera
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<InformeRevisionDetalleDto>(1, "El informe no existe o no está en tu alcance.");
                var cabecera = new InformeRevisionCabeceraDto(
                    EnteroLargo(r, "id_informe"), Texto(r, "numero_informe") ?? string.Empty, Texto(r, "tipo_servicio"), Texto(r, "numero_os"), Texto(r, "cliente"), Texto(r, "sede"),
                    Texto(r, "equipo"), Texto(r, "codigo_tw"), Texto(r, "numero_serie"), Texto(r, "tecnico"), Texto(r, "fecha_ejecucion"), Texto(r, "diagnostico"),
                    Texto(r, "estado") ?? "por_revisar", Booleano(r, "sla_vencido"), Entero(r, "horas_espera"), Booleano(r, "puede_aprobar"), Booleano(r, "puede_observar"),
                    Texto(r, "motivo_bloqueo"), Texto(r, "revisor"), Texto(r, "fecha_revision"), Texto(r, "nota"));

                // 3 Validaciones
                await r.NextResultAsync(ct);
                var validaciones = new List<ValidacionInformeDto>();
                while (await r.ReadAsync(ct))
                    validaciones.Add(new ValidacionInformeDto(Texto(r, "codigo") ?? string.Empty, Texto(r, "titulo") ?? string.Empty, Texto(r, "detalle"), Texto(r, "estado") ?? "ok",
                                                              Booleano(r, "obligatoria")));

                // 4 Evidencias
                await r.NextResultAsync(ct);
                var evidencias = new List<EvidenciaInformeDto>();
                while (await r.ReadAsync(ct))
                    evidencias.Add(new EvidenciaInformeDto(EnteroLargo(r, "id_evidencia"), Texto(r, "etiqueta") ?? "Evidencia", Booleano(r, "forzada"), Texto(r, "motivo_forzada"),
                                                           Booleano(r, "es_video"), Texto(r, "validacion_ia")));

                // 5 Corrección pendiente (0 o 1 fila)
                await r.NextResultAsync(ct);
                CorreccionInformeDto? correccion = null;
                if (await r.ReadAsync(ct))
                    correccion = new CorreccionInformeDto(EnteroLargo(r, "id_correccion"), Texto(r, "motivo") ?? string.Empty, Texto(r, "motivo_nombre") ?? string.Empty,
                                                          (Texto(r, "secciones") ?? string.Empty).Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).ToList(),
                                                          Texto(r, "instruccion") ?? string.Empty, Texto(r, "plazo_en"), Texto(r, "estado") ?? "pendiente", Texto(r, "por"),
                                                          Texto(r, "creada_en"));

                // 6 Motivos · 7 Secciones · 8 Plazos
                await r.NextResultAsync(ct);
                var motivos = new List<OpcionRevisionInformeDto>();
                while (await r.ReadAsync(ct)) motivos.Add(new OpcionRevisionInformeDto(Texto(r, "codigo") ?? string.Empty, Texto(r, "nombre") ?? string.Empty));

                await r.NextResultAsync(ct);
                var secciones = new List<OpcionRevisionInformeDto>();
                while (await r.ReadAsync(ct)) secciones.Add(new OpcionRevisionInformeDto(Texto(r, "codigo") ?? string.Empty, Texto(r, "nombre") ?? string.Empty));

                await r.NextResultAsync(ct);
                var plazos = new List<PlazoInformeDto>();
                while (await r.ReadAsync(ct)) plazos.Add(new PlazoInformeDto(Entero(r, "horas"), Texto(r, "texto") ?? string.Empty));

                return new RespuestaDto<InformeRevisionDetalleDto>(2, mensaje,
                    new InformeRevisionDetalleDto(cabecera, validaciones, evidencias, correccion, motivos, secciones, plazos));
            }, ct);

    public Task<RespuestaDto<ArchivoAprobacionMovilDto>> ObtenerArchivoAsync(long idUsuario, long idInforme, long idEvidencia, CancellationToken ct) =>
        EjecutarAsync<ArchivoAprobacionMovilDto>("SP_ObtenerArchivoEvidenciaInformeMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario",   idUsuario);
                p.AddWithValue("p_id_informe",   idInforme);
                p.AddWithValue("p_id_evidencia", idEvidencia);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                return await r.ReadAsync(ct) && Texto(r, "ruta") is { } ruta
                    ? new RespuestaDto<ArchivoAprobacionMovilDto>(2, mensaje, new ArchivoAprobacionMovilDto(ruta, Texto(r, "ruta_cuadro"), Booleano(r, "es_video")))
                    : new RespuestaDto<ArchivoAprobacionMovilDto>(1, "Archivo no encontrado.");
            }, ct);

    public Task<RespuestaDto<ObservacionInformeResultadoDto>> ObservarAsync(long idUsuario, long idInforme, string motivo, string secciones, string instruccion, int plazoHoras, CancellationToken ct) =>
        EjecutarAsync<ObservacionInformeResultadoDto>("SP_ObservarInformeMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario",  idUsuario);
                p.AddWithValue("p_id_informe",  idInforme);
                p.AddWithValue("p_motivo",      motivo);
                p.AddWithValue("p_secciones",   secciones);
                p.AddWithValue("p_instruccion", instruccion);
                p.AddWithValue("p_plazo_horas", plazoHoras);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                return await r.ReadAsync(ct)
                    ? new RespuestaDto<ObservacionInformeResultadoDto>(2, mensaje, new ObservacionInformeResultadoDto(EnteroLargo(r, "id_correccion"), Texto(r, "plazo_en"), Entero(r, "notificados")))
                    : new RespuestaDto<ObservacionInformeResultadoDto>(2, mensaje, new ObservacionInformeResultadoDto(0, null, 0));
            }, ct);

    public Task<RespuestaDto<AprobacionInformeResultadoDto>> AprobarAsync(long idUsuario, long idInforme, string? nota, CancellationToken ct) =>
        EjecutarAsync<AprobacionInformeResultadoDto>("SP_AprobarInformeMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_informe", idInforme);
                p.AddWithValue("p_nota",       Valor(nota));
            },
            async (r, mensaje) =>
            {
                // Resultado de SP_RegistrarRevisionInforme: id_informe, estado (revisado), fecha_revision, id_precotizacion, numero_precotizacion
                await r.NextResultAsync(ct);
                return await r.ReadAsync(ct)
                    ? new RespuestaDto<AprobacionInformeResultadoDto>(2, mensaje, new AprobacionInformeResultadoDto(EnteroLargo(r, "id_informe"), Texto(r, "estado") ?? "revisado"))
                    : new RespuestaDto<AprobacionInformeResultadoDto>(2, mensaje, new AprobacionInformeResultadoDto(idInforme, "revisado"));
            }, ct);
}

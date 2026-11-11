using MySqlConnector;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

public class NotificacionesRepositorio(CadenaConexionBd conexion) : RepositorioSpBase(conexion), INotificacionesRepositorio
{
    private readonly CadenaConexionBd _conexion = conexion;

    public async Task<RespuestaDto<List<NotificacionDto>>> ObtenerPorUsuarioAsync(
        long idUsuario, CancellationToken ct)
    {
        try
        {
            await using var conn = new MySqlConnection(_conexion.Valor);
            await conn.OpenAsync(ct);

            await using var cmd = new MySqlCommand("SP_ObtenerNotificaciones", conn)
            {
                CommandType = System.Data.CommandType.StoredProcedure
            };
            cmd.Parameters.AddWithValue("p_id_usuario", idUsuario);

            await using var reader = await cmd.ExecuteReaderAsync(ct);

            if (!await reader.ReadAsync(ct))
                return new RespuestaDto<List<NotificacionDto>>(3, "El procedimiento no devolvió resultado.");

            int    idTipo  = reader.GetInt32("IdTipoMensaje");
            string mensaje = reader.GetString("Mensaje");

            if (idTipo != 2)
                return new RespuestaDto<List<NotificacionDto>>(idTipo, mensaje);

            await reader.NextResultAsync(ct);

            var notificaciones = new List<NotificacionDto>();
            while (await reader.ReadAsync(ct))
            {
                notificaciones.Add(new NotificacionDto(
                    IdNotificacion: reader.GetInt32("id_notificacion"),
                    Tipo:           reader.GetString("tipo"),
                    Titulo:         reader.GetString("titulo"),
                    Cuerpo:         reader.GetString("cuerpo"),
                    TipoDot:        reader.GetString("tipo_dot"),
                    Tiempo:         reader.GetString("tiempo"),
                    Leida:          reader.GetInt32("leida") == 1,
                    CreadoEn:       reader.GetDateTime("creado_en")
                ));
            }

            return new RespuestaDto<List<NotificacionDto>>(2, mensaje, notificaciones);
        }
        catch (Exception ex)
        {
            return new RespuestaDto<List<NotificacionDto>>(3, ex.Message);
        }
    }

    // ── HU-90 Centro de Notificaciones ────────────────────────────────────────

    public Task<RespuestaDto<ResumenNotificacionesDto>> ObtenerResumenAsync(long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerResumenNotificaciones",
            p => p.AddWithValue("p_id_usuario", idUsuario),
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var noLeidas = await r.ReadAsync(ct) ? Entero(r, "no_leidas") : 0;

                await r.NextResultAsync(ct);
                var ultimas = new List<FilaNotificacionDto>();
                while (await r.ReadAsync(ct)) ultimas.Add(LeerFila(r));

                return new RespuestaDto<ResumenNotificacionesDto>(2, mensaje, new ResumenNotificacionesDto(noLeidas, ultimas));
            }, ct);

    public Task<RespuestaDto<BandejaNotificacionesDto>> ObtenerBandejaAsync(FiltrosBandejaNotificacionesDto f, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerBandejaNotificaciones",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_estado",     Valor(f.Estado));
                p.AddWithValue("p_modulos",    Valor(f.Modulos));
                p.AddWithValue("p_tipos",      Valor(f.Tipos));
                p.AddWithValue("p_rango",      Valor(f.Rango));
                p.AddWithValue("p_desde",      f.FechaDesde.HasValue ? f.FechaDesde.Value.Date : DBNull.Value);
                p.AddWithValue("p_hasta",      f.FechaHasta.HasValue ? f.FechaHasta.Value.Date : DBNull.Value);
                p.AddWithValue("p_remitente",  Valor(f.Remitente));
                p.AddWithValue("p_busqueda",   Valor(f.Busqueda));
                p.AddWithValue("p_pagina",     f.Pagina);
                p.AddWithValue("p_por_pagina", f.PorPagina);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var items = new List<FilaNotificacionDto>();
                while (await r.ReadAsync(ct)) items.Add(LeerFila(r));

                var total = await LeerTotalAsync(r, ct);

                await r.NextResultAsync(ct);
                var noLeidas = await r.ReadAsync(ct) ? Entero(r, "no_leidas") : 0;

                return new RespuestaDto<BandejaNotificacionesDto>(2, mensaje,
                    new BandejaNotificacionesDto(total, noLeidas, f.Pagina, f.PorPagina, items));
            }, ct);

    public Task<RespuestaDto<DetalleNotificacionDto>> ObtenerDetalleAsync(long idNotificacion, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerDetalleNotificacion",
            p =>
            {
                p.AddWithValue("p_id_usuario",      idUsuario);
                p.AddWithValue("p_id_notificacion", idNotificacion);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<DetalleNotificacionDto>(1, "Notificación no encontrada.");

                var fila = LeerFila(r);
                return new RespuestaDto<DetalleNotificacionDto>(2, mensaje, new DetalleNotificacionDto(
                    Notificacion:   fila,
                    Mensaje:        Texto(r, "mensaje") ?? "",
                    FechaLectura:   FechaHora(r, "fecha_lectura"),
                    FechaArchivado: FechaHora(r, "fecha_archivado"),
                    PuedeArchivar:  fila.Leida && !fila.Archivada,
                    NoLeidas:       Entero(r, "no_leidas")));
            }, ct);

    public Task<RespuestaDto<ResultadoMarcadoNotificacionesDto>> MarcarLeidasAsync(
        IReadOnlyCollection<long> ids, bool todas, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_MarcarNotificacionesLeidas",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_ids",        todas || ids.Count == 0 ? DBNull.Value : string.Join(',', ids));
                p.AddWithValue("p_todas",      Bit(todas));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                return await r.ReadAsync(ct)
                    ? new RespuestaDto<ResultadoMarcadoNotificacionesDto>(2, mensaje,
                          new ResultadoMarcadoNotificacionesDto(Entero(r, "marcadas"), Entero(r, "no_leidas")))
                    : new RespuestaDto<ResultadoMarcadoNotificacionesDto>(3, "El procedimiento no devolvió el resultado.");
            }, ct);

    public Task<RespuestaDto<ResultadoArchivadoNotificacionDto>> ArchivarAsync(long idNotificacion, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ArchivarNotificacion",
            p =>
            {
                p.AddWithValue("p_id_usuario",      idUsuario);
                p.AddWithValue("p_id_notificacion", idNotificacion);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                return await r.ReadAsync(ct)
                    ? new RespuestaDto<ResultadoArchivadoNotificacionDto>(2, mensaje,
                          new ResultadoArchivadoNotificacionDto(EnteroLargo(r, "id_notificacion"), Entero(r, "no_leidas")))
                    : new RespuestaDto<ResultadoArchivadoNotificacionDto>(3, "El procedimiento no devolvió el resultado.");
            }, ct);

    public Task<RespuestaDto<ConteosFiltrosNotificacionesDto>> ObtenerConteosFiltrosAsync(long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerFiltrosNotificaciones",
            p => p.AddWithValue("p_id_usuario", idUsuario),
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var modulos = new List<ConteoFiltroNotificacionDto>();
                while (await r.ReadAsync(ct))
                    modulos.Add(new(Texto(r, "valor") ?? "", Entero(r, "total"), Entero(r, "no_leidas")));

                await r.NextResultAsync(ct);
                var tipos = new List<ConteoFiltroNotificacionDto>();
                while (await r.ReadAsync(ct))
                    tipos.Add(new(Texto(r, "valor") ?? "", Entero(r, "total"), Entero(r, "no_leidas")));

                await r.NextResultAsync(ct);
                var remitentes = new List<RemitenteFiltroNotificacionDto>();
                while (await r.ReadAsync(ct))
                    remitentes.Add(new(EnteroLargo(r, "id_remitente"), Texto(r, "remitente") ?? "", Entero(r, "total")));

                return new RespuestaDto<ConteosFiltrosNotificacionesDto>(2, mensaje,
                    new ConteosFiltrosNotificacionesDto(modulos, tipos, remitentes));
            }, ct);

    public Task<RespuestaDto<ResultadoAlertasOperativasDto>> GenerarAlertasOperativasAsync(CancellationToken ct)
        => EjecutarAsync("SP_GenerarAlertasOperativas",
            _ => { },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                return await r.ReadAsync(ct)
                    ? new RespuestaDto<ResultadoAlertasOperativasDto>(2, mensaje,
                          new ResultadoAlertasOperativasDto(Entero(r, "generadas"), Entero(r, "alertas")))
                    : new RespuestaDto<ResultadoAlertasOperativasDto>(2, mensaje, new ResultadoAlertasOperativasDto(0, 0));
            }, ct);

    public Task<RespuestaDto<NotificacionesNuevasDto>> ObtenerNuevasAsync(long desdeId, int limite, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerNotificacionesNuevas",
            p =>
            {
                p.AddWithValue("p_desde_id", desdeId);
                p.AddWithValue("p_limite",   limite);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var ultimoId = await r.ReadAsync(ct) ? EnteroLargo(r, "ultimo_id") : 0;

                await r.NextResultAsync(ct);
                var nuevas = new List<NotificacionNuevaDto>();
                while (await r.ReadAsync(ct))
                    nuevas.Add(new NotificacionNuevaDto(EnteroLargo(r, "id_usuario_destino"), LeerFila(r), Entero(r, "no_leidas")));

                return new RespuestaDto<NotificacionesNuevasDto>(2, mensaje, new NotificacionesNuevasDto(ultimoId, nuevas));
            }, ct);

    /// <summary>Fila común (campana, bandeja y detalle).</summary>
    private static FilaNotificacionDto LeerFila(MySqlDataReader r)
    {
        var modulo     = Texto(r, "modulo") ?? "sistema";
        var tipo       = Texto(r, "tipo") ?? "informativo";
        var accion     = Texto(r, "destino_accion");
        var entidad    = Texto(r, "entidad_tipo");
        var idEntidad  = EnteroLargoNulo(r, "id_entidad");

        return new FilaNotificacionDto(
            IdNotificacion:    EnteroLargo(r, "id_notificacion"),
            Titulo:            Texto(r, "titulo") ?? "",
            Resumen:           Texto(r, "resumen") ?? "",
            Modulo:            modulo,
            ModuloLabel:       CatalogoNotificaciones.EtiquetaModulo(modulo),
            Tipo:              tipo,
            TipoLabel:         CatalogoNotificaciones.EtiquetaTipo(tipo),
            Prioridad:         Texto(r, "prioridad") ?? "normal",
            EsAlertaOperativa: tipo == "alerta_operativa",
            Leida:             Booleano(r, "leida"),
            Archivada:         Booleano(r, "archivada"),
            Remitente:         new RemitenteNotificacionDto(EnteroLargoNulo(r, "id_remitente"),
                                                            Texto(r, "remitente") ?? "Sistema TotalWeight",
                                                            Texto(r, "iniciales") ?? "S"),
            FechaCreacion:     FechaHora(r, "fecha_creacion") ?? DateTime.MinValue,
            Grupo:             Texto(r, "grupo") ?? "antiguas",
            Destino:           accion is not null && entidad is not null && idEntidad is not null
                                   ? new DestinoNotificacionDto(accion, entidad, idEntidad.Value, Texto(r, "destino_tab"))
                                   : null);
    }
}

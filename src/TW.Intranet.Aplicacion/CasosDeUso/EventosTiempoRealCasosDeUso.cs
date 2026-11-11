using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

/// <summary>
/// HU-90 parte 2 — Eventos de dominio en tiempo real, emitidos por los casos de uso DESPUÉS de que el SP respondió éxito (2).
/// Se envían con CancellationToken.None: si el usuario cerró la pestaña después del commit, el evento igual sale para los demás.
/// No cambian el envelope: el adaptador nunca lanza excepciones.
/// </summary>
public static class EventosTiempoRealCasosDeUso
{
    public static Task OcRegistradaAsync(this INotificadorTiempoReal n, long idOc, string numeroOc, string estado,
                                         IEnumerable<long> idsPropuesta, bool autogenerada)
    {
        var ids = idsPropuesta.Where(i => i > 0).Distinct().ToList();
        return n.EnviarAGruposAsync(GruposOc(idOc, ids), EventosTiempoReal.OcRegistrada,
                                    new OcEventoDto(idOc, numeroOc, estado, ids, autogenerada), CancellationToken.None);
    }

    public static Task OcAnuladaAsync(this INotificadorTiempoReal n, AnulacionOrdenCompraDto d)
    {
        var ids = d.Propuestas.Select(p => p.IdPropuesta).Where(i => i > 0).Distinct().ToList();
        return n.EnviarAGruposAsync(GruposOc(d.IdOc, ids), EventosTiempoReal.OcAnulada,
                                    new OcEventoDto(d.IdOc, d.NumeroOc, d.Estado, ids, false), CancellationToken.None);
    }

    public static Task VbAsignadoAsync(this INotificadorTiempoReal n, VistoBuenoPropuestaDto d)
        => n.EnviarAGruposAsync(GruposVb(d.IdPropuesta), EventosTiempoReal.VbAsignado,
                                new VbEventoDto(d.IdPropuesta, d.Numero, d.Estado, "pendiente", null), CancellationToken.None);

    public static Task VbResueltoAsync(this INotificadorTiempoReal n, ResultadoResolverVistoBuenoDto d, string accion)
        => n.EnviarAGruposAsync(GruposVb(d.IdPropuesta), EventosTiempoReal.VbResuelto,
                                new VbEventoDto(d.IdPropuesta, null, d.Estado, d.EstadoVb, accion), CancellationToken.None);

    public static Task OsEmitidaAsync(this INotificadorTiempoReal n, OrdenServicioGuardadaDto d, bool reemitida)
        => n.EnviarAGruposAsync(GruposOs(d.IdOs), EventosTiempoReal.OsEmitida,
                                new OsEventoDto(d.IdOs, d.Numero, d.Tipo, d.Estado, reemitida), CancellationToken.None);

    public static Task OsEstadoCambiadoAsync(this INotificadorTiempoReal n, long idOs, string numero, string? tipo, string estado)
        => n.EnviarAGruposAsync(GruposOs(idOs), EventosTiempoReal.OsEstadoCambiado,
                                new OsEventoDto(idOs, numero, tipo, estado, false), CancellationToken.None);

    public static Task PrecotizacionRecibidaAsync(this INotificadorTiempoReal n, PrecotizacionGuardadaDto d, long idInforme)
        => n.EnviarAGruposAsync([GruposTiempoReal.Permiso("precot_ver")], EventosTiempoReal.PrecotizacionRecibida,
                                new PrecotizacionEventoDto(d.IdPrecotizacion, d.Numero, d.Estado, idInforme), CancellationToken.None);

    /// <summary>notificacion.actualizada al usuario (sincroniza sus otras pestañas: badge y lista).</summary>
    public static Task NotificacionActualizadaAsync(this INotificadorTiempoReal n, long idUsuario, IEnumerable<long> ids, bool todas,
                                                    string estado, int noLeidas)
        => n.EnviarAUsuariosAsync([idUsuario], EventosTiempoReal.NotificacionActualizada,
                                  new NotificacionActualizadaEventoDto(ids.ToList(), todas, estado, noLeidas), CancellationToken.None);

    private static List<string> GruposOc(long idOc, List<long> idsPropuesta)
    {
        var grupos = new List<string> { GruposTiempoReal.Permiso("oc_bandeja"), GruposTiempoReal.Entidad("oc", idOc) };
        grupos.AddRange(idsPropuesta.Select(id => GruposTiempoReal.Entidad("propuesta", id)));
        return grupos;
    }

    private static List<string> GruposVb(long idPropuesta)
        => [GruposTiempoReal.Permiso("propuesta_vb_bandeja"), GruposTiempoReal.Entidad("propuesta", idPropuesta)];

    private static List<string> GruposOs(long idOs)
        => [GruposTiempoReal.Permiso("os_bandeja"), GruposTiempoReal.Permiso("os_bandeja_operaciones"), GruposTiempoReal.Entidad("os", idOs)];
}

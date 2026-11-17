using MySqlConnector;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>Alertas y apoyo en campo de la app móvil del jefe (App Mobile HU-32).</summary>
public class AlertasCampoMovilRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), IAlertasCampoMovilRepositorio
{
    private static LecturaAlertaMovilDto LeerLectura(MySqlDataReader r, bool conGrupo) => new(
        conGrupo ? EnteroNulo(r, "grupo") : null,
        Entero(r, conGrupo ? "posicion" : "orden"),
        DecimalNulo(r, "carga"), DecimalNulo(r, "indicacion"), DecimalNulo(r, "error"), DecimalNulo(r, "emp"),
        Texto(r, "resultado"), Booleano(r, "critico"));

    public Task<RespuestaDto<AlertaCampoMovilDto>> ObtenerAlertaAsync(long idUsuario, long idNotificacion, CancellationToken ct) =>
        EjecutarAsync<AlertaCampoMovilDto>("SP_ObtenerAlertaCampoMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_notificacion", idNotificacion);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<AlertaCampoMovilDto>(1, "La alerta no existe o no es tuya.");
                var cabecera = (
                    IdNotificacion: EnteroLargo(r, "id_notificacion"), Titulo: Texto(r, "titulo") ?? string.Empty, Cuerpo: Texto(r, "cuerpo") ?? string.Empty,
                    CreadaEn: FechaHora(r, "creada_en")?.ToString("yyyy-MM-ddTHH:mm:ss"), HaceMin: Entero(r, "hace_min"),
                    IdOs: EnteroLargo(r, "id_os"), NumeroOs: Texto(r, "numero_os") ?? string.Empty, Cliente: Texto(r, "cliente"), Sede: Texto(r, "sede"),
                    IdTecnico: EnteroLargoNulo(r, "id_tecnico"), Tecnico: Texto(r, "tecnico"), Telefono: Texto(r, "telefono"),
                    IdOsEquipo: EnteroLargoNulo(r, "id_os_equipo"), EquipoCodigo: Texto(r, "equipo_codigo"), EquipoDescripcion: Texto(r, "equipo_descripcion"),
                    EquipoUbicacion: Texto(r, "equipo_ubicacion"));

                var pesaje = new List<LecturaAlertaMovilDto>();
                if (await r.NextResultAsync(ct))
                    while (await r.ReadAsync(ct)) pesaje.Add(LeerLectura(r, false));
                var excentricidad = new List<LecturaAlertaMovilDto>();
                if (await r.NextResultAsync(ct))
                    while (await r.ReadAsync(ct)) excentricidad.Add(LeerLectura(r, true));

                return new RespuestaDto<AlertaCampoMovilDto>(2, mensaje, new AlertaCampoMovilDto(
                    cabecera.IdNotificacion, cabecera.Titulo, cabecera.Cuerpo, cabecera.CreadaEn, cabecera.HaceMin,
                    cabecera.IdOs, cabecera.NumeroOs, cabecera.Cliente, cabecera.Sede,
                    cabecera.IdTecnico, cabecera.Tecnico, cabecera.Telefono,
                    cabecera.IdOsEquipo, cabecera.EquipoCodigo, cabecera.EquipoDescripcion, cabecera.EquipoUbicacion,
                    pesaje, excentricidad));
            }, ct);

    public Task<RespuestaDto<ContactoAlertaMovilDto>> AccionAsync(long idUsuario, long idNotificacion, string accion, string? mensaje, CancellationToken ct) =>
        EjecutarAsync<ContactoAlertaMovilDto>("SP_AccionAlertaCampoMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_notificacion", idNotificacion);
                p.AddWithValue("p_accion", accion);
                p.AddWithValue("p_mensaje", Valor(mensaje));
            },
            async (r, msg) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<ContactoAlertaMovilDto>(1, "No se pudo registrar la acción.");
                return new RespuestaDto<ContactoAlertaMovilDto>(2, msg, new ContactoAlertaMovilDto(Texto(r, "nombre") ?? string.Empty, Texto(r, "telefono")));
            }, ct);

    public Task<RespuestaDto<ReasignacionOsMovilDto>> ObtenerTecnicosAsync(long idUsuario, long idOs, CancellationToken ct) =>
        EjecutarAsync<ReasignacionOsMovilDto>("SP_ObtenerTecnicosReasignacionMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_os", idOs);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<ReasignacionOsMovilDto>(1, "El servicio no existe o no pertenece a tu área.");
                var os = (IdOs: EnteroLargo(r, "id_os"), Numero: Texto(r, "numero_os") ?? string.Empty, Cliente: Texto(r, "cliente"),
                          IdTec: EnteroLargoNulo(r, "id_tecnico_actual"), Tec: Texto(r, "tecnico_actual"),
                          Lat: DecimalNulo(r, "planta_latitud"), Lon: DecimalNulo(r, "planta_longitud"));

                var lista = new List<TecnicoReasignacionMovilDto>();
                if (await r.NextResultAsync(ct))
                    while (await r.ReadAsync(ct))
                        lista.Add(new TecnicoReasignacionMovilDto(
                            EnteroLargo(r, "id_usuario"), Texto(r, "nombre") ?? string.Empty, Texto(r, "iniciales") ?? "?",
                            DecimalNulo(r, "distancia_km"), EnteroNulo(r, "llega_min"),
                            Entero(r, "servicios_hoy"), Entero(r, "carga_pct"), Texto(r, "ssoma") ?? "conforme",
                            Booleano(r, "disponible"), Texto(r, "motivo_no")));

                return new RespuestaDto<ReasignacionOsMovilDto>(2, mensaje,
                    new ReasignacionOsMovilDto(os.IdOs, os.Numero, os.Cliente, os.IdTec, os.Tec, os.Lat, os.Lon, lista));
            }, ct);

    public Task<RespuestaDto<ReasignadoMovilDto>> ReasignarAsync(long idUsuario, long idOs, long idTecnico, CancellationToken ct) =>
        EjecutarAsync<ReasignadoMovilDto>("SP_ReasignarTecnicoMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_os", idOs);
                p.AddWithValue("p_id_tecnico", idTecnico);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<ReasignadoMovilDto>(1, "No se pudo reasignar el servicio.");
                return new RespuestaDto<ReasignadoMovilDto>(2, mensaje,
                    new ReasignadoMovilDto(EnteroLargo(r, "id_os"), EnteroLargo(r, "id_tecnico"), Texto(r, "tecnico") ?? string.Empty, Entero(r, "notificados")));
            }, ct);

    public Task<RespuestaDto<IncidenciaRegistradaMovilDto>> RegistrarIncidenciaAsync(
        long idUsuario, long idOs, int idTipo, int idNivel, string impacto, string descripcion, string? rutaFoto, bool escalar, CancellationToken ct) =>
        EjecutarAsync<IncidenciaRegistradaMovilDto>("SP_RegistrarIncidenciaCampoMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_os", idOs);
                p.AddWithValue("p_id_tipo", idTipo);
                p.AddWithValue("p_id_nivel", idNivel);
                p.AddWithValue("p_impacto", impacto);
                p.AddWithValue("p_descripcion", descripcion);
                p.AddWithValue("p_evidencia", Valor(rutaFoto));
                p.AddWithValue("p_escalar", escalar ? 1 : 0);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<IncidenciaRegistradaMovilDto>(1, "No se pudo registrar la incidencia.");
                return new RespuestaDto<IncidenciaRegistradaMovilDto>(2, mensaje,
                    new IncidenciaRegistradaMovilDto(EnteroLargo(r, "id_incidencia"), Texto(r, "estado") ?? string.Empty, Entero(r, "notificados")));
            }, ct);
}

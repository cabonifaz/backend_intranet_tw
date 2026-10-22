using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>Agenda de servicios de la app móvil (App Mobile HU-03).</summary>
public class ServiciosMovilRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), IServiciosMovilRepositorio
{
    public Task<RespuestaDto<List<ServicioProgramadoMovilDto>>> ObtenerProgramadosAsync(
        long idUsuario, string filtro, string? busqueda, CancellationToken ct) =>
        EjecutarAsync<List<ServicioProgramadoMovilDto>>("SP_ObtenerServiciosProgramadosMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_filtro",     filtro);
                p.AddWithValue("p_busqueda",   Valor(busqueda));
            },
            async (r, mensaje) =>
            {
                var lista = new List<ServicioProgramadoMovilDto>();
                await r.NextResultAsync(ct);
                while (await r.ReadAsync(ct))
                {
                    lista.Add(new ServicioProgramadoMovilDto(
                        EnteroLargo(r, "id_os"),
                        Texto(r, "numero_os") ?? string.Empty,
                        Texto(r, "numero_rq"),
                        Texto(r, "numero_om"),
                        Texto(r, "cliente"),
                        Fecha(r, "fecha_ejecucion"),
                        Texto(r, "hora_inicio"),
                        Texto(r, "estado_os") ?? string.Empty,
                        Texto(r, "sede"),
                        Texto(r, "responsable"),
                        Entero(r, "objetivos_total"),
                        Entero(r, "objetivos_completados"),
                        Booleano(r, "cliente_confirmado"),
                        Texto(r, "estado_ssoma") ?? "pendiente",
                        Entero(r, "alertas_predictivas"),
                        Texto(r, "estado_general") ?? "PENDIENTE",
                        Texto(r, "motivo_bloqueo")));
                }
                return new RespuestaDto<List<ServicioProgramadoMovilDto>>(2, mensaje, lista);
            }, ct);
}

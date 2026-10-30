using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>Menú principal de la app móvil (App Mobile HU-02).</summary>
public class MenuMovilRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), IMenuMovilRepositorio
{
    public Task<RespuestaDto<ResumenMenuMovilDto>> ObtenerResumenAsync(long idUsuario, CancellationToken ct) =>
        EjecutarAsync<ResumenMenuMovilDto>("SP_ObtenerResumenMenuMovil",
            p => p.AddWithValue("p_id_usuario", idUsuario),
            async (r, mensaje) =>
            {
                // 2do resultado: indicadores
                await r.NextResultAsync(ct);
                int asignados = 0, hoy = 0;
                if (await r.ReadAsync(ct))
                {
                    asignados = Entero(r, "servicios_asignados");
                    hoy       = Entero(r, "servicios_hoy");
                }

                // 3er resultado: próximo servicio (puede no haber)
                ProximoServicioMovilDto? proximo = null;
                if (await r.NextResultAsync(ct) && await r.ReadAsync(ct))
                {
                    proximo = new ProximoServicioMovilDto(
                        EnteroLargo(r, "id_os"),
                        Texto(r, "numero") ?? string.Empty,
                        Texto(r, "cliente"),
                        Texto(r, "sede"),
                        Texto(r, "distrito"),
                        Texto(r, "tipo_servicio"),
                        Fecha(r, "fecha_ejecucion"),
                        Texto(r, "hora_inicio"),
                        Texto(r, "estado") ?? string.Empty);
                }

                return new RespuestaDto<ResumenMenuMovilDto>(2, mensaje, new ResumenMenuMovilDto(asignados, hoy, proximo));
            }, ct);
}

using System.Text.Json;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>Ingreso de equipos de la OS desde la app móvil (App Mobile HU-22).</summary>
public class IngresoEquiposMovilRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), IIngresoEquiposMovilRepositorio
{
    public Task<RespuestaDto<IngresosOsMovilDto>> ObtenerAsync(long idUsuario, long idOs, CancellationToken ct) =>
        EjecutarAsync<IngresosOsMovilDto>("SP_ObtenerIngresosEquiposMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_os", idOs);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var lista = new List<IngresoEquipoMovilDto>();
                while (await r.ReadAsync(ct))
                    lista.Add(new IngresoEquipoMovilDto(
                        EnteroLargo(r, "id_os_equipo"),
                        Texto(r, "estado_ingreso") ?? string.Empty,
                        Texto(r, "observacion"),
                        FechaHora(r, "ingresado_en")?.ToString("yyyy-MM-ddTHH:mm:ss"),
                        Entero(r, "fotos")));
                return new RespuestaDto<IngresosOsMovilDto>(2, mensaje, new IngresosOsMovilDto(lista));
            }, ct);

    public Task<RespuestaDto<EquipoAgregadoMovilDto>> AgregarExistenteAsync(long idUsuario, long idOs, string codigo, CancellationToken ct) =>
        EjecutarAsync<EquipoAgregadoMovilDto>("SP_AgregarEquipoExistenteOsMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_os", idOs);
                p.AddWithValue("p_codigo", codigo);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<EquipoAgregadoMovilDto>(1, "No se pudo agregar el equipo a la OS.");
                return new RespuestaDto<EquipoAgregadoMovilDto>(2, mensaje,
                    new EquipoAgregadoMovilDto(EnteroLargo(r, "id_os_equipo"), EnteroLargo(r, "id_equipo"), Texto(r, "codigo_tw") ?? string.Empty));
            }, ct);

    public Task<RespuestaDto<ResultadoIngresoEquipoMovilDto>> RegistrarAsync(
        long idUsuario, long idOs, long idOsEquipo, string estado, string? observacion, IReadOnlyList<string> rutasFotos, CancellationToken ct) =>
        EjecutarAsync<ResultadoIngresoEquipoMovilDto>("SP_RegistrarIngresoEquipoMovil",
            p =>
            {
                p.AddWithValue("p_id_usuario", idUsuario);
                p.AddWithValue("p_id_os", idOs);
                p.AddWithValue("p_id_os_equipo", idOsEquipo);
                p.AddWithValue("p_estado", estado);
                p.AddWithValue("p_observacion", Valor(observacion));
                p.AddWithValue("p_fotos", JsonSerializer.Serialize(rutasFotos));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<ResultadoIngresoEquipoMovilDto>(1, "No se pudo registrar el ingreso del equipo.");
                return new RespuestaDto<ResultadoIngresoEquipoMovilDto>(2, mensaje, new ResultadoIngresoEquipoMovilDto(
                    EnteroLargo(r, "id_ingreso"),
                    EnteroLargo(r, "id_os_equipo"),
                    Texto(r, "estado_ingreso") ?? string.Empty,
                    FechaHora(r, "ingresado_en")?.ToString("yyyy-MM-ddTHH:mm:ss"),
                    Entero(r, "fotos")));
            }, ct);
}

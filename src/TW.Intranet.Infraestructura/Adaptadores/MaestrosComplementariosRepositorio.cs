using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

public class MaestrosComplementariosRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), IMaestrosComplementariosRepositorio
{
    // ── Ubigeo ────────────────────────────────────────────────────────────────
    public Task<RespuestaDto<List<UbigeoItemDto>>> ObtenerUbigeoAsync(
        string nivel, string? departamento, string? provincia, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerUbigeo",
            p =>
            {
                p.AddWithValue("p_nivel",        nivel);
                p.AddWithValue("p_departamento", Valor(departamento));
                p.AddWithValue("p_provincia",    Valor(provincia));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var items = new List<UbigeoItemDto>();
                while (await r.ReadAsync(ct))
                    items.Add(new UbigeoItemDto(Texto(r, "codigo") ?? "", Texto(r, "nombre") ?? ""));
                return new RespuestaDto<List<UbigeoItemDto>>(2, mensaje, items);
            }, ct);

    // ── Áreas del cliente ─────────────────────────────────────────────────────
    public Task<RespuestaDto<List<AreaClienteDto>>> ObtenerAreasClienteAsync(long idCliente, bool soloActivas, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerAreasCliente",
            p =>
            {
                p.AddWithValue("p_id_cliente",   idCliente);
                p.AddWithValue("p_solo_activas", Bit(soloActivas));
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var items = new List<AreaClienteDto>();
                while (await r.ReadAsync(ct))
                    items.Add(new AreaClienteDto(
                        EnteroLargo(r, "id_area"), EnteroLargo(r, "id_cliente"),
                        Texto(r, "nombre") ?? "", Texto(r, "estado") ?? "", (int)EnteroLargo(r, "equipos")));
                return new RespuestaDto<List<AreaClienteDto>>(2, mensaje, items);
            }, ct);

    public Task<RespuestaDto<AreaClienteDto>> GuardarAreaClienteAsync(
        long idCliente, GuardarAreaClienteDto dto, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_GuardarAreaCliente",
            p =>
            {
                p.AddWithValue("p_id_area",    dto.IdArea);
                p.AddWithValue("p_id_cliente", idCliente);
                p.AddWithValue("p_nombre",     dto.Nombre ?? "");
                p.AddWithValue("p_id_usuario", idUsuario);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<AreaClienteDto>(2, mensaje);
                return new RespuestaDto<AreaClienteDto>(2, mensaje,
                    new AreaClienteDto(EnteroLargo(r, "id_area"), idCliente, Texto(r, "nombre") ?? "", "Activo", 0));
            }, ct);

    public Task<RespuestaDto<bool>> CambiarEstadoAreaClienteAsync(long idArea, string estado, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_CambiarEstadoAreaCliente",
            p =>
            {
                p.AddWithValue("p_id_area",    idArea);
                p.AddWithValue("p_estado",     estado);
                p.AddWithValue("p_id_usuario", idUsuario);
            },
            (_, mensaje) => Task.FromResult(new RespuestaDto<bool>(2, mensaje, true)), ct);

    // ── Códigos de formato por ventana ────────────────────────────────────────
    public Task<RespuestaDto<List<FormatoVentanaDto>>> ObtenerFormatosVentanaAsync(string? clave, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerFormatosVentana",
            p => p.AddWithValue("p_clave", Valor(clave)),
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var items = new List<FormatoVentanaDto>();
                while (await r.ReadAsync(ct))
                    items.Add(new FormatoVentanaDto(
                        Texto(r, "clave") ?? "", Texto(r, "nombre_ventana") ?? "",
                        Texto(r, "codigo_formato"), EnteroNulo(r, "version"),
                        Texto(r, "etiqueta"), FechaHora(r, "fecha_modificacion")));
                return new RespuestaDto<List<FormatoVentanaDto>>(2, mensaje, items);
            }, ct);

    public Task<RespuestaDto<bool>> GuardarFormatoVentanaAsync(string clave, GuardarFormatoVentanaDto dto, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_GuardarFormatoVentana",
            p =>
            {
                p.AddWithValue("p_clave",          clave);
                p.AddWithValue("p_nombre_ventana", Valor(dto.NombreVentana));
                p.AddWithValue("p_codigo_formato", Valor(dto.CodigoFormato));
                p.AddWithValue("p_version",        Valor(dto.Version));
                p.AddWithValue("p_id_usuario",     idUsuario);
            },
            (_, mensaje) => Task.FromResult(new RespuestaDto<bool>(2, mensaje, true)), ct);
}

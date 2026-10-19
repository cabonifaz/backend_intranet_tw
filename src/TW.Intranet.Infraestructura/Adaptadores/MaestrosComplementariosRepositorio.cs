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

    // ── Áreas por cliente (nombres libres) ────────────────────────────────────
    public Task<RespuestaDto<List<AreaClienteDto>>> ObtenerAreasClienteAsync(
        long idCliente, bool soloActivas, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerAreasCliente",
            p =>
            {
                p.AddWithValue("p_id_cliente",   idCliente);
                p.AddWithValue("p_solo_activas", soloActivas ? 1 : 0);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var items = new List<AreaClienteDto>();
                while (await r.ReadAsync(ct))
                    items.Add(new AreaClienteDto(
                        EnteroLargo(r, "id_area"),
                        EnteroLargo(r, "id_cliente"),
                        Texto(r, "nombre") ?? "",
                        Texto(r, "estado") ?? "Activo",
                        Entero(r, "equipos")));
                return new RespuestaDto<List<AreaClienteDto>>(2, mensaje, items);
            }, ct);

    public Task<RespuestaDto<AreaClienteDto?>> GuardarAreaClienteAsync(
        long idCliente, GuardarAreaClienteDto dto, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_GuardarAreaCliente",
            p =>
            {
                p.AddWithValue("p_id_area",    dto.IdArea);
                p.AddWithValue("p_id_cliente", idCliente);
                p.AddWithValue("p_nombre",     Valor(dto.Nombre));
                p.AddWithValue("p_id_usuario", idUsuario);
            },
            async (r, mensaje) =>
            {
                // Segundo resultset: { id_area, nombre }
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<AreaClienteDto?>(3, "El procedimiento no devolvió el área guardada.");
                var idArea = EnteroLargo(r, "id_area");
                var nombre = Texto(r, "nombre") ?? "";
                return new RespuestaDto<AreaClienteDto?>(2, mensaje,
                    new AreaClienteDto(idArea, idCliente, nombre, "Activo", 0));
            }, ct);

    public Task<RespuestaDto<bool>> CambiarEstadoAreaClienteAsync(
        long idArea, CambiarEstadoAreaClienteDto dto, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_CambiarEstadoAreaCliente",
            p =>
            {
                p.AddWithValue("p_id_area",    idArea);
                p.AddWithValue("p_estado",     Valor(dto.Estado));
                p.AddWithValue("p_id_usuario", idUsuario);
            },
            (_, mensaje) => Task.FromResult(new RespuestaDto<bool>(2, mensaje, true)), ct);

    // ── Requisitos SSOMA asignados al cliente ─────────────────────────────────
    public Task<RespuestaDto<List<RequisitoSsomaClienteDto>>> ObtenerRequisitosDelClienteAsync(long idCliente, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerRequisitosDelCliente",
            p => p.AddWithValue("p_id_cliente", idCliente),
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var items = new List<RequisitoSsomaClienteDto>();
                while (await r.ReadAsync(ct))
                    items.Add(new RequisitoSsomaClienteDto(
                        Texto(r, "codigo") ?? "",
                        Texto(r, "nombre") ?? ""));
                return new RespuestaDto<List<RequisitoSsomaClienteDto>>(2, mensaje, items);
            }, ct);

    public Task<RespuestaDto<bool>> SincronizarRequisitosClienteAsync(
        long idCliente, SincronizarRequisitosSsomaDto dto, long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_SincronizarRequisitosCliente",
            p =>
            {
                p.AddWithValue("p_id_cliente", idCliente);
                // Si Codigos es null → NULL en SQL (no cambia); si [] → JSON '[]' (borra todos).
                p.AddWithValue("p_requisitos", dto.Codigos is null
                    ? (object)DBNull.Value
                    : System.Text.Json.JsonSerializer.Serialize(dto.Codigos));
                p.AddWithValue("p_id_usuario", idUsuario);
            },
            (_, mensaje) => Task.FromResult(new RespuestaDto<bool>(2, mensaje, true)), ct);

    // ── Próximo código de ficha (referencial) ─────────────────────────────────
    public Task<RespuestaDto<SiguienteCodigoDto>> ObtenerSiguienteCodigoAsync(string entidad, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerSiguienteCodigo",
            p => p.AddWithValue("p_entidad", entidad),
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<SiguienteCodigoDto>(3, "El procedimiento no devolvió el código.");
                return new RespuestaDto<SiguienteCodigoDto>(2, mensaje,
                    new SiguienteCodigoDto(Texto(r, "entidad") ?? entidad, Texto(r, "codigo") ?? ""));
            }, ct);

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

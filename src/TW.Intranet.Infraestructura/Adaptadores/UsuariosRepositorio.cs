using System.Data;
using MySqlConnector;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>Usuarios y suplencias (HU-82, HU-83, HU-84).</summary>
public class UsuariosRepositorio(CadenaConexionBd conexion) : IUsuariosRepositorio
{
    // ══════════════════════════════════════════════════════════════════════════
    //  USUARIOS
    // ══════════════════════════════════════════════════════════════════════════

    public Task<RespuestaDto<UsuariosPaginadoDto>> ObtenerUsuariosAsync(
        string? busqueda, string? rol, string? estado, int pagina, int porPagina, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerUsuarios",
            p =>
            {
                p.AddWithValue("p_busqueda",   Valor(busqueda));
                p.AddWithValue("p_rol",        Valor(rol));
                p.AddWithValue("p_estado",     Valor(estado));
                p.AddWithValue("p_pagina",     pagina);
                p.AddWithValue("p_por_pagina", porPagina);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var items = new List<UsuarioListaItemDto>();
                while (await r.ReadAsync(ct))
                    items.Add(LeerUsuarioLista(r));

                await r.NextResultAsync(ct);
                int total = await r.ReadAsync(ct) ? Entero(r, "total") : 0;

                return new RespuestaDto<UsuariosPaginadoDto>(2, mensaje,
                    new UsuariosPaginadoDto(items, total, pagina, porPagina));
            }, ct);

    public Task<RespuestaDto<UsuarioDetalleDto>> ObtenerUsuarioPorIdAsync(long idUsuario, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerUsuarioPorId",
            p => p.AddWithValue("p_id_usuario", idUsuario),
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<UsuarioDetalleDto>(1, "Usuario no encontrado.");

                var lista = LeerUsuarioLista(r);
                var tipoDocumento    = Texto(r, "tipo_documento") ?? "DNI";
                var numeroDocumento  = Texto(r, "numero_documento") ?? "";
                var cargo            = Texto(r, "cargo");
                var sedeOperativa    = Texto(r, "sede_operativa");
                var idSupervisor     = EnteroLargoNulo(r, "id_supervisor");
                var habilitadoInacal = Booleano(r, "habilitado_firma_inacal");
                var registroInacal   = Texto(r, "numero_registro_inacal");
                var fechaExpiracion  = Fecha(r, "fecha_expiracion_certificacion");
                var induccionSctr    = Booleano(r, "requiere_induccion_sctr");
                var forzarCambio     = Booleano(r, "forzar_cambio_contrasena");
                var enviarCorreo     = Booleano(r, "enviar_credenciales_correo");
                var dosFactores      = Booleano(r, "autenticacion_2fa");

                var detalle = new UsuarioDetalleDto(
                    lista.IdUsuario, lista.Nombre, lista.Apellido, lista.Correo,
                    lista.RolSistema, lista.RolSistemaLabel, lista.Area, lista.Telefono,
                    lista.Estado, lista.UltimoAcceso, lista.FechaCreacion,
                    tipoDocumento, numeroDocumento, cargo,
                    sedeOperativa, idSupervisor,
                    habilitadoInacal, registroInacal, fechaExpiracion, induccionSctr,
                    forzarCambio, enviarCorreo, dosFactores);

                return new RespuestaDto<UsuarioDetalleDto>(2, mensaje, detalle);
            }, ct);

    public Task<RespuestaDto<List<UsuarioListaItemDto>>> ObtenerJefesDisponiblesAsync(CancellationToken ct)
        => EjecutarAsync("SP_ObtenerJefesDisponibles",
            _ => { },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var items = new List<UsuarioListaItemDto>();
                while (await r.ReadAsync(ct))
                    items.Add(LeerUsuarioLista(r));
                return new RespuestaDto<List<UsuarioListaItemDto>>(2, mensaje, items);
            }, ct);

    public Task<RespuestaDto<List<SedeOperativaDto>>> ObtenerSedesOperativasAsync(CancellationToken ct)
        => EjecutarAsync("SP_ObtenerSedesOperativas",
            _ => { },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var items = new List<SedeOperativaDto>();
                while (await r.ReadAsync(ct))
                {
                    items.Add(new SedeOperativaDto(
                        IdSede:    Entero(r, "id_sede"),
                        Nombre:    Texto(r, "nombre") ?? "",
                        Ubicacion: Texto(r, "ubicacion"),
                        Tipo:      Texto(r, "tipo")));
                }
                return new RespuestaDto<List<SedeOperativaDto>>(2, mensaje, items);
            }, ct);

    public Task<RespuestaDto<long>> GuardarUsuarioAsync(
        GuardarUsuarioDto dto, string? passwordHash, DateTime? fechaExpiracion,
        long idEjecutor, CancellationToken ct)
        => EjecutarAsync("SP_GuardarUsuario",
            p =>
            {
                p.AddWithValue("p_id_usuario",                     dto.IdUsuario);
                p.AddWithValue("p_nombre",                         dto.Nombre!.Trim());
                p.AddWithValue("p_apellido",                       dto.Apellido!.Trim());
                p.AddWithValue("p_tipo_documento",                 string.IsNullOrWhiteSpace(dto.TipoDocumento) ? "DNI" : dto.TipoDocumento.Trim());
                p.AddWithValue("p_numero_documento",               dto.NumeroDocumento!.Trim());
                p.AddWithValue("p_correo",                         dto.Correo!);
                p.AddWithValue("p_telefono",                       Valor(dto.Telefono));
                p.AddWithValue("p_cargo",                          Valor(dto.Cargo));
                p.AddWithValue("p_area",                           Valor(dto.Area));
                p.AddWithValue("p_rol_sistema",                    dto.RolSistema!);
                p.AddWithValue("p_sede_operativa",                 Valor(dto.SedeOperativa));
                p.AddWithValue("p_id_supervisor",                  (object?)dto.IdSupervisorDirecto ?? DBNull.Value);
                p.AddWithValue("p_habilitado_firma_inacal",        dto.HabilitadoFirmaInacal ? 1 : 0);
                p.AddWithValue("p_numero_registro_inacal",         Valor(dto.NumeroRegistroInacal));
                p.AddWithValue("p_fecha_expiracion_certificacion", (object?)fechaExpiracion ?? DBNull.Value);
                p.AddWithValue("p_requiere_induccion_sctr",        dto.RequiereInduccionSctr ? 1 : 0);
                p.AddWithValue("p_password_hash",                  Valor(passwordHash));
                p.AddWithValue("p_forzar_cambio_contrasena",       dto.ForzarCambioContrasena ? 1 : 0);
                p.AddWithValue("p_enviar_credenciales_correo",     dto.EnviarCredencialesCorreo ? 1 : 0);
                p.AddWithValue("p_autenticacion_2fa",              dto.Autenticacion2fa ? 1 : 0);
                p.AddWithValue("p_guardar_como_borrador",          dto.GuardarComoBorrador ? 1 : 0);
                p.AddWithValue("p_id_usuario_ejecutor",            idEjecutor);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                long id = await r.ReadAsync(ct) ? EnteroLargo(r, "id_usuario") : 0;
                return new RespuestaDto<long>(2, mensaje, id);
            }, ct);

    public Task<RespuestaDto<object>> CambiarEstadoUsuarioAsync(
        long idUsuario, string estado, long idEjecutor, CancellationToken ct)
        => EjecutarAsync("SP_CambiarEstadoUsuario",
            p =>
            {
                p.AddWithValue("p_id_usuario",          idUsuario);
                p.AddWithValue("p_estado",              estado);
                p.AddWithValue("p_id_usuario_ejecutor", idEjecutor);
            },
            (_, mensaje) => Task.FromResult(new RespuestaDto<object>(2, mensaje)), ct);

    // ══════════════════════════════════════════════════════════════════════════
    //  SUPLENTES
    // ══════════════════════════════════════════════════════════════════════════

    public Task<RespuestaDto<SuplentesPaginadoDto>> ObtenerSuplentesAsync(
        string? busqueda, string? estado, int pagina, int porPagina, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerSuplentes",
            p =>
            {
                p.AddWithValue("p_busqueda",   Valor(busqueda));
                p.AddWithValue("p_estado",     Valor(estado));
                p.AddWithValue("p_pagina",     pagina);
                p.AddWithValue("p_por_pagina", porPagina);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var items = new List<SuplenteListaItemDto>();
                while (await r.ReadAsync(ct))
                    items.Add(LeerSuplente(r));

                await r.NextResultAsync(ct);
                int total = await r.ReadAsync(ct) ? Entero(r, "total") : 0;

                return new RespuestaDto<SuplentesPaginadoDto>(2, mensaje,
                    new SuplentesPaginadoDto(items, total, pagina, porPagina));
            }, ct);

    public Task<RespuestaDto<SuplenteListaItemDto>> ObtenerSuplentePorIdAsync(long idAsignacion, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerSuplentePorId",
            p => p.AddWithValue("p_id_asignacion", idAsignacion),
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                if (!await r.ReadAsync(ct))
                    return new RespuestaDto<SuplenteListaItemDto>(1, "Asignación no encontrada.");
                return new RespuestaDto<SuplenteListaItemDto>(2, mensaje, LeerSuplente(r));
            }, ct);

    public Task<RespuestaDto<List<SuplenteListaItemDto>>> ObtenerSuplenciasPorUsuarioAsync(
        long idUsuario, string perspectiva, CancellationToken ct)
        => EjecutarAsync("SP_ObtenerSuplenciasPorUsuario",
            p =>
            {
                p.AddWithValue("p_id_usuario",  idUsuario);
                p.AddWithValue("p_perspectiva", perspectiva);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                var items = new List<SuplenteListaItemDto>();
                while (await r.ReadAsync(ct))
                    items.Add(LeerSuplente(r));
                return new RespuestaDto<List<SuplenteListaItemDto>>(2, mensaje, items);
            }, ct);

    public Task<RespuestaDto<long>> GuardarSuplenteAsync(
        GuardarSuplenteDto dto, DateTime fechaInicio, DateTime? fechaFin, string usuario, CancellationToken ct)
        => EjecutarAsync("SP_GuardarSuplente",
            p =>
            {
                p.AddWithValue("p_id_asignacion", dto.IdAsignacion);
                p.AddWithValue("p_id_titular",    dto.IdTitular);
                p.AddWithValue("p_id_suplente",   dto.IdSuplente);
                p.AddWithValue("p_fecha_inicio",  fechaInicio);
                p.AddWithValue("p_fecha_fin",     (object?)fechaFin ?? DBNull.Value);
                p.AddWithValue("p_activo",        dto.Activo ? 1 : 0);
                p.AddWithValue("p_usuario",       usuario);
            },
            async (r, mensaje) =>
            {
                await r.NextResultAsync(ct);
                long id = await r.ReadAsync(ct) ? EnteroLargo(r, "id_asignacion") : 0;
                return new RespuestaDto<long>(2, mensaje, id);
            }, ct);

    public Task<RespuestaDto<object>> CambiarEstadoSuplenteAsync(
        long idAsignacion, string estado, string usuario, CancellationToken ct)
        => EjecutarAsync("SP_CambiarEstadoSuplente",
            p =>
            {
                p.AddWithValue("p_id_asignacion", idAsignacion);
                p.AddWithValue("p_estado",        estado);
                p.AddWithValue("p_usuario",       usuario);
            },
            (_, mensaje) => Task.FromResult(new RespuestaDto<object>(2, mensaje)), ct);

    // ══════════════════════════════════════════════════════════════════════════
    //  Infraestructura común
    // ══════════════════════════════════════════════════════════════════════════

    /// <summary>
    /// Abre conexión, ejecuta el SP y lee el header (IdTipoMensaje, Mensaje).
    /// Si IdTipoMensaje != 2 devuelve el mensaje del SP; si es 2, delega en <paramref name="leerDatos"/>.
    /// </summary>
    private async Task<RespuestaDto<T>> EjecutarAsync<T>(
        string sp,
        Action<MySqlParameterCollection> parametros,
        Func<MySqlDataReader, string, Task<RespuestaDto<T>>> leerDatos,
        CancellationToken ct)
    {
        try
        {
            await using var conn = new MySqlConnection(conexion.Valor);
            await conn.OpenAsync(ct);

            await using var cmd = new MySqlCommand(sp, conn)
            {
                CommandType = CommandType.StoredProcedure
            };
            parametros(cmd.Parameters);

            await using var reader = await cmd.ExecuteReaderAsync(ct);

            if (!await reader.ReadAsync(ct))
                return new RespuestaDto<T>(3, "El procedimiento no devolvió resultado.");

            int    idTipo  = Convert.ToInt32(reader["IdTipoMensaje"]);
            string mensaje = Convert.ToString(reader["Mensaje"]) ?? "";

            if (idTipo != 2)
                return new RespuestaDto<T>(idTipo, mensaje);

            return await leerDatos(reader, mensaje);
        }
        catch (Exception ex)
        {
            return new RespuestaDto<T>(3, ex.Message);
        }
    }

    private static UsuarioListaItemDto LeerUsuarioLista(MySqlDataReader r) => new(
        IdUsuario:       EnteroLargo(r, "id_usuario"),
        Nombre:          Texto(r, "nombre") ?? "",
        Apellido:        Texto(r, "apellido") ?? "",
        Correo:          Texto(r, "correo") ?? "",
        RolSistema:      Texto(r, "rol_sistema") ?? "",
        RolSistemaLabel: Texto(r, "rol_sistema_label") ?? Texto(r, "rol_sistema") ?? "",
        Area:            Texto(r, "area"),
        Telefono:        Texto(r, "telefono"),
        Estado:          Texto(r, "estado") ?? "",
        UltimoAcceso:    FechaHora(r, "ultimo_acceso"),
        FechaCreacion:   FechaHora(r, "fecha_creacion"));

    private static SuplenteListaItemDto LeerSuplente(MySqlDataReader r) => new(
        IdAsignacion:     EnteroLargo(r, "id_asignacion"),
        IdTitular:        EnteroLargo(r, "id_titular"),
        TitularNombre:    Texto(r, "titular_nombre") ?? "",
        TitularApellido:  Texto(r, "titular_apellido") ?? "",
        TitularCargo:     Texto(r, "titular_cargo"),
        IdSuplente:       EnteroLargo(r, "id_suplente"),
        SuplenteNombre:   Texto(r, "suplente_nombre") ?? "",
        SuplenteApellido: Texto(r, "suplente_apellido") ?? "",
        SuplenteCargo:    Texto(r, "suplente_cargo"),
        FechaInicio:      Fecha(r, "fecha_inicio") ?? "",
        FechaFin:         Fecha(r, "fecha_fin"),
        Estado:           Texto(r, "estado") ?? "",
        FechaCreacion:    FechaHora(r, "fecha_creacion"));

    // ── Lectura segura de columnas ────────────────────────────────────────────
    private static object Valor(string? v) =>
        string.IsNullOrWhiteSpace(v) ? DBNull.Value : v.Trim();

    private static bool EsNulo(MySqlDataReader r, string col) => r.IsDBNull(r.GetOrdinal(col));

    private static string? Texto(MySqlDataReader r, string col) =>
        EsNulo(r, col) ? null : Convert.ToString(r[col]);

    private static int Entero(MySqlDataReader r, string col) =>
        EsNulo(r, col) ? 0 : Convert.ToInt32(r[col]);

    private static long EnteroLargo(MySqlDataReader r, string col) =>
        EsNulo(r, col) ? 0 : Convert.ToInt64(r[col]);

    private static long? EnteroLargoNulo(MySqlDataReader r, string col) =>
        EsNulo(r, col) ? null : Convert.ToInt64(r[col]);

    private static bool Booleano(MySqlDataReader r, string col) =>
        !EsNulo(r, col) && Convert.ToBoolean(r[col]);

    private static DateTime? FechaHora(MySqlDataReader r, string col) =>
        EsNulo(r, col) ? null : Convert.ToDateTime(r[col]);

    /// <summary>Columnas DATE → "yyyy-MM-dd" (formato que usa el front).</summary>
    private static string? Fecha(MySqlDataReader r, string col)
    {
        if (EsNulo(r, col)) return null;
        return r[col] switch
        {
            DateTime d => d.ToString("yyyy-MM-dd"),
            DateOnly d => d.ToString("yyyy-MM-dd"),
            var otro   => Convert.ToString(otro)
        };
    }
}

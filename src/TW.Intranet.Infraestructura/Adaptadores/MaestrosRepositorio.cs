using MySqlConnector;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

public class MaestrosRepositorio(CadenaConexionBd conexion) : IMaestrosRepositorio
{
    // ── Clientes ──────────────────────────────────────────────────────────────

    public async Task<RespuestaDto<List<ClienteListaItemDto>>> ObtenerClientesAsync(
        string? busqueda, string? estado, CancellationToken ct)
    {
        try
        {
            await using var conn = new MySqlConnection(conexion.Valor);
            await conn.OpenAsync(ct);

            await using var cmd = new MySqlCommand("SP_ObtenerClientes", conn)
            {
                CommandType = System.Data.CommandType.StoredProcedure
            };
            cmd.Parameters.AddWithValue("p_busqueda", busqueda ?? (object)DBNull.Value);
            cmd.Parameters.AddWithValue("p_estado",   estado   ?? (object)DBNull.Value);

            await using var reader = await cmd.ExecuteReaderAsync(ct);

            if (!await reader.ReadAsync(ct))
                return new RespuestaDto<List<ClienteListaItemDto>>(3, "El procedimiento no devolvió resultado.");

            int    idTipo  = reader.GetInt32("IdTipoMensaje");
            string mensaje = reader.GetString("Mensaje");

            if (idTipo != 2)
                return new RespuestaDto<List<ClienteListaItemDto>>(idTipo, mensaje);

            await reader.NextResultAsync(ct);

            var lista = new List<ClienteListaItemDto>();
            while (await reader.ReadAsync(ct))
            {
                lista.Add(new ClienteListaItemDto(
                    IdCliente:              reader.GetInt64("id_cliente"),
                    Ruc:                    reader.GetString("ruc"),
                    RazonSocial:            reader.GetString("razon_social"),
                    NombreComercial:        reader.IsDBNull(reader.GetOrdinal("nombre_comercial")) ? null : reader.GetString("nombre_comercial"),
                    TipoCliente:            reader.GetString("tipo_cliente"),
                    CondicionFiscal:        reader.GetString("condicion_fiscal"),
                    CondicionContribuyente: reader.GetString("condicion_contribuyente"),
                    EsVip:                  reader.GetBoolean("es_vip"),
                    Estado:                 reader.GetString("estado")
                ));
            }

            return new RespuestaDto<List<ClienteListaItemDto>>(2, mensaje, lista);
        }
        catch (Exception ex)
        {
            return new RespuestaDto<List<ClienteListaItemDto>>(3, ex.Message);
        }
    }

    public async Task<RespuestaDto<ClienteDetalleDto>> ObtenerClientePorIdAsync(
        long idCliente, CancellationToken ct)
    {
        try
        {
            await using var conn = new MySqlConnection(conexion.Valor);
            await conn.OpenAsync(ct);

            await using var cmd = new MySqlCommand("SP_ObtenerClientePorId", conn)
            {
                CommandType = System.Data.CommandType.StoredProcedure
            };
            cmd.Parameters.AddWithValue("p_id_cliente", idCliente);

            await using var reader = await cmd.ExecuteReaderAsync(ct);

            if (!await reader.ReadAsync(ct))
                return new RespuestaDto<ClienteDetalleDto>(3, "El procedimiento no devolvió resultado.");

            int    idTipo  = reader.GetInt32("IdTipoMensaje");
            string mensaje = reader.GetString("Mensaje");

            if (idTipo != 2)
                return new RespuestaDto<ClienteDetalleDto>(idTipo, mensaje);

            await reader.NextResultAsync(ct);

            if (!await reader.ReadAsync(ct))
                return new RespuestaDto<ClienteDetalleDto>(3, "El procedimiento no devolvió datos del cliente.");

            var ord = (string col) => reader.GetOrdinal(col);
            var nullable = (string col) => reader.IsDBNull(ord(col));

            var detalle = new ClienteDetalleDto(
                IdCliente:              reader.GetInt64("id_cliente"),
                TipoDocumento:          reader.GetString("tipo_documento"),
                Ruc:                    reader.GetString("ruc"),
                TipoCliente:            reader.GetString("tipo_cliente"),
                RazonSocial:            reader.GetString("razon_social"),
                NombreComercial:        nullable("nombre_comercial")   ? null : reader.GetString("nombre_comercial"),
                CondicionFiscal:        reader.GetString("condicion_fiscal"),
                CondicionContribuyente: reader.GetString("condicion_contribuyente"),
                CondicionPago:          nullable("condicion_pago")     ? null : reader.GetString("condicion_pago"),
                LineaCreditoUsd:        nullable("linea_credito_usd")  ? null : reader.GetDecimal("linea_credito_usd"),
                TelefonoCentral:        nullable("telefono_central")   ? null : reader.GetString("telefono_central"),
                DomicilioFiscal:        nullable("domicilio_fiscal")   ? null : reader.GetString("domicilio_fiscal"),
                EsVip:                  reader.GetBoolean("es_vip"),
                ReglaVip:               nullable("regla_vip")          ? null : reader.GetString("regla_vip"),
                DescuentoVipPct:        nullable("descuento_vip_pct")  ? null : reader.GetDecimal("descuento_vip_pct"),
                PatronMasasAsignado:    nullable("patron_masas_asignado") ? null : reader.GetString("patron_masas_asignado"),
                SsomaPolizaSctr:        reader.GetBoolean("ssoma_poliza_sctr"),
                SsomaCamioneta4x4:      reader.GetBoolean("ssoma_camioneta_4x4"),
                SsomaInduccionSsoma:    reader.GetBoolean("ssoma_induccion_ssoma"),
                SsomaExamenMedico:      reader.GetBoolean("ssoma_examen_medico"),
                SsomaNotas:             nullable("ssoma_notas")        ? null : reader.GetString("ssoma_notas"),
                Categoria:              nullable("categoria")          ? null : reader.GetString("categoria"),
                Estado:                 reader.GetString("estado")
            );

            return new RespuestaDto<ClienteDetalleDto>(2, mensaje, detalle);
        }
        catch (Exception ex)
        {
            return new RespuestaDto<ClienteDetalleDto>(3, ex.Message);
        }
    }

    public async Task<RespuestaDto<long>> GuardarClienteAsync(
        GuardarClienteDto dto, string usuCre, CancellationToken ct)
    {
        try
        {
            await using var conn = new MySqlConnection(conexion.Valor);
            await conn.OpenAsync(ct);

            await using var cmd = new MySqlCommand("SP_GuardarCliente", conn)
            {
                CommandType = System.Data.CommandType.StoredProcedure
            };
            cmd.Parameters.AddWithValue("p_id_cliente",              dto.IdCliente);
            cmd.Parameters.AddWithValue("p_tipo_documento",          dto.TipoDocumento);
            cmd.Parameters.AddWithValue("p_ruc",                     dto.Ruc);
            cmd.Parameters.AddWithValue("p_tipo_cliente",            dto.TipoCliente);
            cmd.Parameters.AddWithValue("p_razon_social",            dto.RazonSocial);
            cmd.Parameters.AddWithValue("p_nombre_comercial",        dto.NombreComercial ?? (object)DBNull.Value);
            cmd.Parameters.AddWithValue("p_condicion_fiscal",        dto.CondicionFiscal);
            cmd.Parameters.AddWithValue("p_condicion_contribuyente", dto.CondicionContribuyente);
            cmd.Parameters.AddWithValue("p_condicion_pago",          dto.CondicionPago    ?? (object)DBNull.Value);
            cmd.Parameters.AddWithValue("p_linea_credito_usd",       dto.LineaCreditoUsd  ?? (object)DBNull.Value);
            cmd.Parameters.AddWithValue("p_telefono_central",        dto.TelefonoCentral  ?? (object)DBNull.Value);
            cmd.Parameters.AddWithValue("p_domicilio_fiscal",        dto.DomicilioFiscal  ?? (object)DBNull.Value);
            cmd.Parameters.AddWithValue("p_es_vip",                  dto.EsVip ? 1 : 0);
            cmd.Parameters.AddWithValue("p_regla_vip",               dto.ReglaVip         ?? (object)DBNull.Value);
            cmd.Parameters.AddWithValue("p_descuento_vip_pct",       dto.DescuentoVipPct  ?? (object)DBNull.Value);
            cmd.Parameters.AddWithValue("p_patron_masas_asignado",   dto.PatronMasasAsignado ?? (object)DBNull.Value);
            cmd.Parameters.AddWithValue("p_ssoma_poliza_sctr",       dto.SsomaPolizaSctr     ? 1 : 0);
            cmd.Parameters.AddWithValue("p_ssoma_camioneta_4x4",     dto.SsomaCamioneta4x4   ? 1 : 0);
            cmd.Parameters.AddWithValue("p_ssoma_induccion_ssoma",   dto.SsomaInduccionSsoma ? 1 : 0);
            cmd.Parameters.AddWithValue("p_ssoma_examen_medico",     dto.SsomaExamenMedico   ? 1 : 0);
            cmd.Parameters.AddWithValue("p_ssoma_notas",             dto.SsomaNotas       ?? (object)DBNull.Value);
            cmd.Parameters.AddWithValue("p_categoria",               dto.Categoria        ?? (object)DBNull.Value);
            cmd.Parameters.AddWithValue("p_usu_cre",                 usuCre);

            await using var reader = await cmd.ExecuteReaderAsync(ct);

            if (!await reader.ReadAsync(ct))
                return new RespuestaDto<long>(3, "El procedimiento no devolvió resultado.");

            int    idTipo  = reader.GetInt32("IdTipoMensaje");
            string mensaje = reader.GetString("Mensaje");

            if (idTipo != 2)
                return new RespuestaDto<long>(idTipo, mensaje);

            await reader.NextResultAsync(ct);

            if (!await reader.ReadAsync(ct))
                return new RespuestaDto<long>(3, "El procedimiento no devolvió el identificador.");

            long idCliente = reader.GetInt64("id_cliente");
            return new RespuestaDto<long>(2, mensaje, idCliente);
        }
        catch (Exception ex)
        {
            return new RespuestaDto<long>(3, ex.Message);
        }
    }

    public async Task<RespuestaDto<List<CatalogoItemDto>>> ObtenerCatalogoAsync(
        string descripcion, CancellationToken ct)
    {
        try
        {
            await using var conn = new MySqlConnection(conexion.Valor);
            await conn.OpenAsync(ct);

            await using var cmd = new MySqlCommand("SP_ObtenerCatalogo", conn)
            {
                CommandType = System.Data.CommandType.StoredProcedure
            };
            cmd.Parameters.AddWithValue("p_descripcion", descripcion);

            await using var reader = await cmd.ExecuteReaderAsync(ct);

            if (!await reader.ReadAsync(ct))
                return new RespuestaDto<List<CatalogoItemDto>>(3, "El procedimiento no devolvió resultado.");

            int    idTipo  = reader.GetInt32("IdTipoMensaje");
            string mensaje = reader.GetString("Mensaje");

            if (idTipo != 2)
                return new RespuestaDto<List<CatalogoItemDto>>(idTipo, mensaje);

            await reader.NextResultAsync(ct);

            var lista = new List<CatalogoItemDto>();
            while (await reader.ReadAsync(ct))
            {
                lista.Add(new CatalogoItemDto(
                    Id:     reader.GetInt32("id"),
                    Nombre: reader.GetString("nombre"),
                    Codigo: reader.IsDBNull(reader.GetOrdinal("codigo")) ? null : reader.GetString("codigo")
                ));
            }

            return new RespuestaDto<List<CatalogoItemDto>>(2, mensaje, lista);
        }
        catch (Exception ex)
        {
            return new RespuestaDto<List<CatalogoItemDto>>(3, ex.Message);
        }
    }

    // ── Sedes ─────────────────────────────────────────────────────────────────

    public async Task<RespuestaDto<List<SedeClienteDto>>> ObtenerSedesPorClienteAsync(
        long idCliente, CancellationToken ct)
    {
        try
        {
            await using var conn = new MySqlConnection(conexion.Valor);
            await conn.OpenAsync(ct);

            await using var cmd = new MySqlCommand("SP_ObtenerSedesPorCliente", conn)
            {
                CommandType = System.Data.CommandType.StoredProcedure
            };
            cmd.Parameters.AddWithValue("p_id_cliente", idCliente);

            await using var reader = await cmd.ExecuteReaderAsync(ct);

            if (!await reader.ReadAsync(ct))
                return new RespuestaDto<List<SedeClienteDto>>(3, "El procedimiento no devolvió resultado.");

            int    idTipo  = reader.GetInt32("IdTipoMensaje");
            string mensaje = reader.GetString("Mensaje");

            if (idTipo != 2)
                return new RespuestaDto<List<SedeClienteDto>>(idTipo, mensaje);

            await reader.NextResultAsync(ct);

            var lista = new List<SedeClienteDto>();
            while (await reader.ReadAsync(ct))
            {
                var nullable = (string col) => reader.IsDBNull(reader.GetOrdinal(col));
                lista.Add(new SedeClienteDto(
                    IdSede:          reader.GetInt64("id_sede"),
                    IdCliente:       reader.GetInt64("id_cliente"),
                    Nombre:          reader.GetString("nombre"),
                    TipoInstalacion: nullable("tipo_instalacion") ? null : reader.GetString("tipo_instalacion"),
                    Region:          nullable("region")           ? null : reader.GetString("region"),
                    Provincia:       nullable("provincia")        ? null : reader.GetString("provincia"),
                    Distrito:        nullable("distrito")         ? null : reader.GetString("distrito"),
                    Urbanizacion:    nullable("urbanizacion")     ? null : reader.GetString("urbanizacion"),
                    DireccionExacta: nullable("direccion_exacta") ? null : reader.GetString("direccion_exacta"),
                    Estado:          reader.GetString("estado")
                ));
            }

            return new RespuestaDto<List<SedeClienteDto>>(2, mensaje, lista);
        }
        catch (Exception ex)
        {
            return new RespuestaDto<List<SedeClienteDto>>(3, ex.Message);
        }
    }

    public async Task<RespuestaDto<long>> GuardarSedeAsync(
        GuardarSedeDto dto, string usuCre, CancellationToken ct)
    {
        try
        {
            await using var conn = new MySqlConnection(conexion.Valor);
            await conn.OpenAsync(ct);

            await using var cmd = new MySqlCommand("SP_GuardarSede", conn)
            {
                CommandType = System.Data.CommandType.StoredProcedure
            };
            cmd.Parameters.AddWithValue("p_id_sede",          dto.IdSede);
            cmd.Parameters.AddWithValue("p_id_cliente",       dto.IdCliente);
            cmd.Parameters.AddWithValue("p_nombre",           dto.Nombre);
            cmd.Parameters.AddWithValue("p_tipo_instalacion", dto.TipoInstalacion ?? (object)DBNull.Value);
            cmd.Parameters.AddWithValue("p_region",           dto.Region          ?? (object)DBNull.Value);
            cmd.Parameters.AddWithValue("p_provincia",        dto.Provincia       ?? (object)DBNull.Value);
            cmd.Parameters.AddWithValue("p_distrito",         dto.Distrito        ?? (object)DBNull.Value);
            cmd.Parameters.AddWithValue("p_urbanizacion",     dto.Urbanizacion    ?? (object)DBNull.Value);
            cmd.Parameters.AddWithValue("p_direccion_exacta", dto.DireccionExacta ?? (object)DBNull.Value);
            cmd.Parameters.AddWithValue("p_usu_cre",          usuCre);

            await using var reader = await cmd.ExecuteReaderAsync(ct);

            if (!await reader.ReadAsync(ct))
                return new RespuestaDto<long>(3, "El procedimiento no devolvió resultado.");

            int    idTipo  = reader.GetInt32("IdTipoMensaje");
            string mensaje = reader.GetString("Mensaje");

            if (idTipo != 2)
                return new RespuestaDto<long>(idTipo, mensaje);

            await reader.NextResultAsync(ct);

            if (!await reader.ReadAsync(ct))
                return new RespuestaDto<long>(3, "El procedimiento no devolvió el identificador.");

            long idSede = reader.GetInt64("id_sede");
            return new RespuestaDto<long>(2, mensaje, idSede);
        }
        catch (Exception ex)
        {
            return new RespuestaDto<long>(3, ex.Message);
        }
    }

    public async Task<RespuestaDto<object>> CambiarEstadoSedeAsync(
        CambiarEstadoSedeDto dto, string usuMod, CancellationToken ct)
    {
        try
        {
            await using var conn = new MySqlConnection(conexion.Valor);
            await conn.OpenAsync(ct);

            await using var cmd = new MySqlCommand("SP_CambiarEstadoSede", conn)
            {
                CommandType = System.Data.CommandType.StoredProcedure
            };
            cmd.Parameters.AddWithValue("p_id_sede",  dto.IdSede);
            cmd.Parameters.AddWithValue("p_estado",   dto.Estado);
            cmd.Parameters.AddWithValue("p_usu_mod",  usuMod);

            await using var reader = await cmd.ExecuteReaderAsync(ct);

            if (!await reader.ReadAsync(ct))
                return new RespuestaDto<object>(3, "El procedimiento no devolvió resultado.");

            int    idTipo  = reader.GetInt32("IdTipoMensaje");
            string mensaje = reader.GetString("Mensaje");

            return new RespuestaDto<object>(idTipo, mensaje);
        }
        catch (Exception ex)
        {
            return new RespuestaDto<object>(3, ex.Message);
        }
    }

    // ── Contactos ─────────────────────────────────────────────────────────────

    public async Task<RespuestaDto<List<ContactoClienteDto>>> ObtenerContactosPorClienteAsync(
        long idCliente, CancellationToken ct)
    {
        try
        {
            await using var conn = new MySqlConnection(conexion.Valor);
            await conn.OpenAsync(ct);

            await using var cmd = new MySqlCommand("SP_ObtenerContactosPorCliente", conn)
            {
                CommandType = System.Data.CommandType.StoredProcedure
            };
            cmd.Parameters.AddWithValue("p_id_cliente", idCliente);

            await using var reader = await cmd.ExecuteReaderAsync(ct);

            if (!await reader.ReadAsync(ct))
                return new RespuestaDto<List<ContactoClienteDto>>(3, "El procedimiento no devolvió resultado.");

            int    idTipo  = reader.GetInt32("IdTipoMensaje");
            string mensaje = reader.GetString("Mensaje");

            if (idTipo != 2)
                return new RespuestaDto<List<ContactoClienteDto>>(idTipo, mensaje);

            await reader.NextResultAsync(ct);

            var lista = new List<ContactoClienteDto>();
            while (await reader.ReadAsync(ct))
            {
                var n = (string col) => reader.IsDBNull(reader.GetOrdinal(col));
                lista.Add(new ContactoClienteDto(
                    IdContacto:                     reader.GetInt64("id_contacto"),
                    IdCliente:                      reader.GetInt64("id_cliente"),
                    IdSede:                         n("id_sede") ? null : reader.GetInt64("id_sede"),
                    Nombres:                        reader.GetString("nombres"),
                    DocumentoIdentidad:             n("documento_identidad")             ? null : reader.GetString("documento_identidad"),
                    Cargo:                          n("cargo")                           ? null : reader.GetString("cargo"),
                    Area:                           n("area")                            ? null : reader.GetString("area"),
                    Correo:                         n("correo")                          ? null : reader.GetString("correo"),
                    TelefonoMovil:                  n("telefono_movil")                  ? null : reader.GetString("telefono_movil"),
                    TelefonoAnexo:                  n("telefono_anexo")                  ? null : reader.GetString("telefono_anexo"),
                    EsContactoPrincipal:            reader.GetBoolean("es_contacto_principal"),
                    AutorizadoAprobarCotizaciones:  reader.GetBoolean("autorizado_aprobar_cotizaciones"),
                    RecibeAlertasCalibracion:       reader.GetBoolean("recibe_alertas_calibracion"),
                    AutorizadoRecepcionTecnica:     reader.GetBoolean("autorizado_recepcion_tecnica"),
                    Estado:                         reader.GetString("estado")
                ));
            }

            return new RespuestaDto<List<ContactoClienteDto>>(2, mensaje, lista);
        }
        catch (Exception ex)
        {
            return new RespuestaDto<List<ContactoClienteDto>>(3, ex.Message);
        }
    }

    public async Task<RespuestaDto<long>> GuardarContactoAsync(
        GuardarContactoDto dto, string usuCre, CancellationToken ct)
    {
        try
        {
            await using var conn = new MySqlConnection(conexion.Valor);
            await conn.OpenAsync(ct);

            await using var cmd = new MySqlCommand("SP_GuardarContacto", conn)
            {
                CommandType = System.Data.CommandType.StoredProcedure
            };
            cmd.Parameters.AddWithValue("p_id_contacto",                     dto.IdContacto);
            cmd.Parameters.AddWithValue("p_id_cliente",                      dto.IdCliente);
            cmd.Parameters.AddWithValue("p_id_sede",                         dto.IdSede    ?? (object)DBNull.Value);
            cmd.Parameters.AddWithValue("p_nombres",                         dto.Nombres);
            cmd.Parameters.AddWithValue("p_documento_identidad",             dto.DocumentoIdentidad            ?? (object)DBNull.Value);
            cmd.Parameters.AddWithValue("p_cargo",                           dto.Cargo                         ?? (object)DBNull.Value);
            cmd.Parameters.AddWithValue("p_area",                            dto.Area                          ?? (object)DBNull.Value);
            cmd.Parameters.AddWithValue("p_correo",                          dto.Correo                        ?? (object)DBNull.Value);
            cmd.Parameters.AddWithValue("p_telefono_movil",                  dto.TelefonoMovil                 ?? (object)DBNull.Value);
            cmd.Parameters.AddWithValue("p_telefono_anexo",                  dto.TelefonoAnexo                 ?? (object)DBNull.Value);
            cmd.Parameters.AddWithValue("p_es_contacto_principal",           dto.EsContactoPrincipal           ? 1 : 0);
            cmd.Parameters.AddWithValue("p_autorizado_aprobar_cotizaciones", dto.AutorizadoAprobarCotizaciones ? 1 : 0);
            cmd.Parameters.AddWithValue("p_recibe_alertas_calibracion",      dto.RecibeAlertasCalibracion      ? 1 : 0);
            cmd.Parameters.AddWithValue("p_autorizado_recepcion_tecnica",    dto.AutorizadoRecepcionTecnica    ? 1 : 0);
            cmd.Parameters.AddWithValue("p_usu_cre",                         usuCre);

            await using var reader = await cmd.ExecuteReaderAsync(ct);

            if (!await reader.ReadAsync(ct))
                return new RespuestaDto<long>(3, "El procedimiento no devolvió resultado.");

            int    idTipo  = reader.GetInt32("IdTipoMensaje");
            string mensaje = reader.GetString("Mensaje");

            if (idTipo != 2)
                return new RespuestaDto<long>(idTipo, mensaje);

            await reader.NextResultAsync(ct);

            if (!await reader.ReadAsync(ct))
                return new RespuestaDto<long>(3, "El procedimiento no devolvió el identificador.");

            long idContacto = reader.GetInt64("id_contacto");
            return new RespuestaDto<long>(2, mensaje, idContacto);
        }
        catch (Exception ex)
        {
            return new RespuestaDto<long>(3, ex.Message);
        }
    }

    public async Task<RespuestaDto<object>> CambiarEstadoContactoAsync(
        CambiarEstadoContactoDto dto, string usuMod, CancellationToken ct)
    {
        try
        {
            await using var conn = new MySqlConnection(conexion.Valor);
            await conn.OpenAsync(ct);

            await using var cmd = new MySqlCommand("SP_CambiarEstadoContacto", conn)
            {
                CommandType = System.Data.CommandType.StoredProcedure
            };
            cmd.Parameters.AddWithValue("p_id_contacto", dto.IdContacto);
            cmd.Parameters.AddWithValue("p_estado",      dto.Estado);
            cmd.Parameters.AddWithValue("p_usu_mod",     usuMod);

            await using var reader = await cmd.ExecuteReaderAsync(ct);

            if (!await reader.ReadAsync(ct))
                return new RespuestaDto<object>(3, "El procedimiento no devolvió resultado.");

            int    idTipo  = reader.GetInt32("IdTipoMensaje");
            string mensaje = reader.GetString("Mensaje");

            return new RespuestaDto<object>(idTipo, mensaje);
        }
        catch (Exception ex)
        {
            return new RespuestaDto<object>(3, ex.Message);
        }
    }

    public async Task<RespuestaDto<object>> CambiarEstadoClienteAsync(
        CambiarEstadoClienteDto dto, string usuMod, CancellationToken ct)
    {
        try
        {
            await using var conn = new MySqlConnection(conexion.Valor);
            await conn.OpenAsync(ct);

            await using var cmd = new MySqlCommand("SP_CambiarEstadoCliente", conn)
            {
                CommandType = System.Data.CommandType.StoredProcedure
            };
            cmd.Parameters.AddWithValue("p_id_cliente", dto.IdCliente);
            cmd.Parameters.AddWithValue("p_estado",     dto.Estado);
            cmd.Parameters.AddWithValue("p_usu_mod",    usuMod);

            await using var reader = await cmd.ExecuteReaderAsync(ct);

            if (!await reader.ReadAsync(ct))
                return new RespuestaDto<object>(3, "El procedimiento no devolvió resultado.");

            int    idTipo  = reader.GetInt32("IdTipoMensaje");
            string mensaje = reader.GetString("Mensaje");

            return new RespuestaDto<object>(idTipo, mensaje);
        }
        catch (Exception ex)
        {
            return new RespuestaDto<object>(3, ex.Message);
        }
    }
}

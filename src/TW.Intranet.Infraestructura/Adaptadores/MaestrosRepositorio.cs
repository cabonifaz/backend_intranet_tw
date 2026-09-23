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

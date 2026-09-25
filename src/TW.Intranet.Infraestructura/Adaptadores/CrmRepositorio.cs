using MySqlConnector;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

public class CrmRepositorio(CadenaConexionBd conexion) : ICrmRepositorio
{
    // ── ObtenerRequerimientos ─────────────────────────────────────────────────
    public async Task<RespuestaDto<RequerimientosPaginadoDto>> ObtenerRequerimientosAsync(
        string? estado, string? busqueda, int pagina, int porPagina, CancellationToken ct)
    {
        try
        {
            await using var conn = new MySqlConnection(conexion.Valor);
            await conn.OpenAsync(ct);

            await using var cmd = new MySqlCommand("SP_ObtenerRequerimientos", conn)
            {
                CommandType = System.Data.CommandType.StoredProcedure
            };
            cmd.Parameters.AddWithValue("p_estado",     estado   ?? (object)DBNull.Value);
            cmd.Parameters.AddWithValue("p_busqueda",   busqueda ?? (object)DBNull.Value);
            cmd.Parameters.AddWithValue("p_pagina",     pagina);
            cmd.Parameters.AddWithValue("p_por_pagina", porPagina);

            await using var reader = await cmd.ExecuteReaderAsync(ct);

            if (!await reader.ReadAsync(ct))
                return new RespuestaDto<RequerimientosPaginadoDto>(3, "El procedimiento no devolvió resultado.");

            int    idTipo  = reader.GetInt32("IdTipoMensaje");
            string mensaje = reader.GetString("Mensaje");

            if (idTipo != 2)
                return new RespuestaDto<RequerimientosPaginadoDto>(idTipo, mensaje);

            await reader.NextResultAsync(ct);
            var kpis = new KpisRequerimientosDto(0, 0, 0, 0);
            if (await reader.ReadAsync(ct))
            {
                kpis = new KpisRequerimientosDto(
                    RqActivos:    reader.GetInt32("rq_activos"),
                    SinPropuesta: reader.GetInt32("sin_propuesta"),
                    SlaUrgentes:  reader.GetInt32("sla_urgentes"),
                    Bloqueados:   reader.GetInt32("bloqueados")
                );
            }

            await reader.NextResultAsync(ct);
            var items = new List<RequerimientoListaItemDto>();
            while (await reader.ReadAsync(ct))
            {
                string? nullable(string col) =>
                    reader.IsDBNull(reader.GetOrdinal(col)) ? null : reader.GetString(col);

                items.Add(new RequerimientoListaItemDto(
                    IdRequerimiento: reader.GetInt64("id_requerimiento"),
                    Numero:          reader.GetString("numero"),
                    RazonSocial:     nullable("razon_social") ?? "",
                    Ruc:             nullable("ruc") ?? "",
                    NombreSede:      nullable("nombre_sede"),
                    NombreContacto:  nullable("nombre_contacto"),
                    TipoLabel:       nullable("tipo_label"),
                    OrigenLabel:     nullable("origen_label"),
                    PrioridadLabel:  nullable("prioridad_label"),
                    IdPrioridad:     reader.GetInt32("id_prioridad"),
                    Responsable:     nullable("responsable"),
                    FechaCreacion:   reader.GetDateTime("fecha_creacion"),
                    Estado:          reader.GetString("estado"),
                    EstadoLabel:     nullable("estado_label")
                ));
            }

            await reader.NextResultAsync(ct);
            int total = 0;
            if (await reader.ReadAsync(ct))
                total = reader.GetInt32("total");

            return new RespuestaDto<RequerimientosPaginadoDto>(2, mensaje,
                new RequerimientosPaginadoDto(kpis, items, total, pagina, porPagina));
        }
        catch (Exception ex)
        {
            return new RespuestaDto<RequerimientosPaginadoDto>(3, ex.Message);
        }
    }

    // ── ObtenerCatalogos ──────────────────────────────────────────────────────
    public async Task<RespuestaDto<CatalogosRequerimientoDto>> ObtenerCatalogosAsync(CancellationToken ct)
    {
        try
        {
            await using var conn = new MySqlConnection(conexion.Valor);
            await conn.OpenAsync(ct);

            await using var cmd = new MySqlCommand("SP_ObtenerCatalogosRequerimiento", conn)
            {
                CommandType = System.Data.CommandType.StoredProcedure
            };

            await using var reader = await cmd.ExecuteReaderAsync(ct);

            if (!await reader.ReadAsync(ct))
                return new RespuestaDto<CatalogosRequerimientoDto>(3, "El procedimiento no devolvió resultado.");

            int    idTipo  = reader.GetInt32("IdTipoMensaje");
            string mensaje = reader.GetString("Mensaje");

            if (idTipo != 2)
                return new RespuestaDto<CatalogosRequerimientoDto>(idTipo, mensaje);

            static List<CatalogoItemDto> leerItems(MySqlDataReader r)
            {
                var lista = new List<CatalogoItemDto>();
                while (r.Read())
                    lista.Add(new CatalogoItemDto(r.GetInt32("id"), r.GetString("nombre"), null));
                return lista;
            }

            await reader.NextResultAsync(ct);
            var origenes = leerItems(reader);

            await reader.NextResultAsync(ct);
            var areas = leerItems(reader);

            await reader.NextResultAsync(ct);
            var prioridades = leerItems(reader);

            return new RespuestaDto<CatalogosRequerimientoDto>(2, mensaje,
                new CatalogosRequerimientoDto(origenes, areas, prioridades));
        }
        catch (Exception ex)
        {
            return new RespuestaDto<CatalogosRequerimientoDto>(3, ex.Message);
        }
    }

    // ── ObtenerRequerimientoPorId ─────────────────────────────────────────────
    public async Task<RespuestaDto<RequerimientoFichaDto>> ObtenerRequerimientoPorIdAsync(
        long idRequerimiento, CancellationToken ct)
    {
        try
        {
            await using var conn = new MySqlConnection(conexion.Valor);
            await conn.OpenAsync(ct);

            await using var cmd = new MySqlCommand("SP_ObtenerRequerimientoPorId", conn)
            {
                CommandType = System.Data.CommandType.StoredProcedure
            };
            cmd.Parameters.AddWithValue("p_id_requerimiento", idRequerimiento);

            await using var reader = await cmd.ExecuteReaderAsync(ct);

            if (!await reader.ReadAsync(ct))
                return new RespuestaDto<RequerimientoFichaDto>(3, "El procedimiento no devolvió resultado.");

            int    idTipo  = reader.GetInt32("IdTipoMensaje");
            string mensaje = reader.GetString("Mensaje");

            if (idTipo != 2)
                return new RespuestaDto<RequerimientoFichaDto>(idTipo, mensaje);

            await reader.NextResultAsync(ct);
            if (!await reader.ReadAsync(ct))
                return new RespuestaDto<RequerimientoFichaDto>(3, "Requerimiento no encontrado.");

            string? nullable(string col) =>
                reader.IsDBNull(reader.GetOrdinal(col)) ? null : reader.GetString(col);

            DateTime? nullableDate(string col) =>
                reader.IsDBNull(reader.GetOrdinal(col)) ? null : reader.GetDateTime(col);

            long? nullableLong(string col) =>
                reader.IsDBNull(reader.GetOrdinal(col)) ? null : reader.GetInt64(col);

            var ficha = new RequerimientoFichaDto(
                IdRequerimiento: reader.GetInt64("id_requerimiento"),
                Numero:          reader.GetString("numero"),
                IdCliente:       reader.GetInt64("id_cliente"),
                RazonSocial:     reader.GetString("razon_social"),
                Ruc:             reader.GetString("ruc"),
                IdContacto:      nullableLong("id_contacto"),
                IdSede:          nullableLong("id_sede"),
                NombreContacto:  nullable("nombre_contacto"),
                NombreSede:      nullable("nombre_sede"),
                IdOrigen:        reader.GetInt32("id_origen"),
                OrigenLabel:     nullable("origen_label"),
                IdArea:          reader.GetInt32("id_area"),
                AreaLabel:       nullable("area_label"),
                IdPrioridad:     reader.GetInt32("id_prioridad"),
                PrioridadLabel:  nullable("prioridad_label"),
                FechaNecesidad:  nullableDate("fecha_necesidad"),
                Descripcion:     reader.GetString("descripcion"),
                NotificarCorreo: reader.GetBoolean("notificar_correo"),
                RequiereVisita:  reader.GetBoolean("requiere_visita"),
                ClienteDeuda:    reader.GetBoolean("cliente_deuda"),
                Estado:          reader.GetString("estado"),
                EstadoLabel:     nullable("estado_label")
            );

            return new RespuestaDto<RequerimientoFichaDto>(2, mensaje, ficha);
        }
        catch (Exception ex)
        {
            return new RespuestaDto<RequerimientoFichaDto>(3, ex.Message);
        }
    }

    // ── GuardarRequerimiento ──────────────────────────────────────────────────
    public async Task<RespuestaDto<long>> GuardarRequerimientoAsync(
        GuardarRequerimientoComandoDto comando, long idUsuario, CancellationToken ct)
    {
        try
        {
            await using var conn = new MySqlConnection(conexion.Valor);
            await conn.OpenAsync(ct);

            await using var cmd = new MySqlCommand("SP_GuardarRequerimiento", conn)
            {
                CommandType = System.Data.CommandType.StoredProcedure
            };
            cmd.Parameters.AddWithValue("p_id_requerimiento", comando.IdRequerimiento);
            cmd.Parameters.AddWithValue("p_id_cliente",       comando.IdCliente);
            cmd.Parameters.AddWithValue("p_id_sede",          comando.IdSede    ?? (object)DBNull.Value);
            cmd.Parameters.AddWithValue("p_id_contacto",      comando.IdContacto ?? (object)DBNull.Value);
            cmd.Parameters.AddWithValue("p_id_origen",        comando.IdOrigen);
            cmd.Parameters.AddWithValue("p_id_area",          comando.IdArea);
            cmd.Parameters.AddWithValue("p_id_prioridad",     comando.IdPrioridad);
            cmd.Parameters.AddWithValue("p_fecha_necesidad",  comando.FechaNecesidad ?? (object)DBNull.Value);
            cmd.Parameters.AddWithValue("p_descripcion",      comando.Descripcion);
            cmd.Parameters.AddWithValue("p_notificar_correo", comando.NotificarCorreo ? 1 : 0);
            cmd.Parameters.AddWithValue("p_requiere_visita",  comando.RequiereVisita  ? 1 : 0);
            cmd.Parameters.AddWithValue("p_cliente_deuda",    comando.ClienteDeuda    ? 1 : 0);
            cmd.Parameters.AddWithValue("p_id_usuario",       idUsuario);

            await using var reader = await cmd.ExecuteReaderAsync(ct);

            if (!await reader.ReadAsync(ct))
                return new RespuestaDto<long>(3, "El procedimiento no devolvió resultado.");

            int    idTipo  = reader.GetInt32("IdTipoMensaje");
            string mensaje = reader.GetString("Mensaje");

            if (idTipo != 2)
                return new RespuestaDto<long>(idTipo, mensaje);

            await reader.NextResultAsync(ct);
            long idRq = 0;
            if (await reader.ReadAsync(ct))
                idRq = reader.GetInt64("id_requerimiento");

            return new RespuestaDto<long>(2, mensaje, idRq);
        }
        catch (Exception ex)
        {
            return new RespuestaDto<long>(3, ex.Message);
        }
    }
}

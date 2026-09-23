using MySqlConnector;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

public class DashboardRepositorio(CadenaConexionBd conexion) : IDashboardRepositorio
{
    public async Task<RespuestaDto<KpisDashboardDto>> ObtenerResumenAsync(CancellationToken ct)
    {
        try
        {
            await using var conn = new MySqlConnection(conexion.Valor);
            await conn.OpenAsync(ct);

            await using var cmd = new MySqlCommand("SP_ObtenerResumenDashboard", conn)
            {
                CommandType = System.Data.CommandType.StoredProcedure
            };

            await using var reader = await cmd.ExecuteReaderAsync(ct);

            if (!await reader.ReadAsync(ct))
                return new RespuestaDto<KpisDashboardDto>(3, "El procedimiento no devolvió resultado.");

            int    idTipo  = reader.GetInt32("IdTipoMensaje");
            string mensaje = reader.GetString("Mensaje");

            if (idTipo != 2)
                return new RespuestaDto<KpisDashboardDto>(idTipo, mensaje);

            await reader.NextResultAsync(ct);

            if (!await reader.ReadAsync(ct))
                return new RespuestaDto<KpisDashboardDto>(3, "El procedimiento no devolvió los KPIs.");

            var kpis = new KpisDashboardDto(
                ServiciosProgramados:  reader.GetInt32("servicios_programados"),
                ServiciosEnEjecucion:  reader.GetInt32("servicios_en_ejecucion"),
                ExpedientesBloqueados: reader.GetInt32("expedientes_bloqueados"),
                PendientesSsoma:       reader.GetInt32("pendientes_ssoma"),
                PendientesConformidad: reader.GetInt32("pendientes_conformidad"),
                ListosFacturar:        reader.GetInt32("listos_facturar"),
                SlaVencidos:           reader.GetInt32("sla_vencidos"),
                TecnicosEnRuta:        reader.GetInt32("tecnicos_en_ruta"),
                CumplimientoSla:       reader.GetDecimal("cumplimiento_sla"),
                VariacionSla:          reader.GetDecimal("variacion_sla")
            );

            return new RespuestaDto<KpisDashboardDto>(2, mensaje, kpis);
        }
        catch (Exception ex)
        {
            return new RespuestaDto<KpisDashboardDto>(3, ex.Message);
        }
    }

    public async Task<RespuestaDto<List<AlertaOperativaDto>>> ObtenerAlertasAsync(CancellationToken ct)
    {
        try
        {
            await using var conn = new MySqlConnection(conexion.Valor);
            await conn.OpenAsync(ct);

            await using var cmd = new MySqlCommand("SP_ObtenerAlertasOperativas", conn)
            {
                CommandType = System.Data.CommandType.StoredProcedure
            };

            await using var reader = await cmd.ExecuteReaderAsync(ct);

            if (!await reader.ReadAsync(ct))
                return new RespuestaDto<List<AlertaOperativaDto>>(3, "El procedimiento no devolvió resultado.");

            int    idTipo  = reader.GetInt32("IdTipoMensaje");
            string mensaje = reader.GetString("Mensaje");

            if (idTipo != 2)
                return new RespuestaDto<List<AlertaOperativaDto>>(idTipo, mensaje);

            await reader.NextResultAsync(ct);

            var alertas = new List<AlertaOperativaDto>();
            while (await reader.ReadAsync(ct))
            {
                alertas.Add(new AlertaOperativaDto(
                    IdAlerta:         reader.GetInt32("id_alerta"),
                    Nivel:            reader.GetString("nivel"),
                    NumeroExpediente: reader.GetString("numero_expediente"),
                    Cliente:          reader.GetString("cliente"),
                    TipoServicio:     reader.GetString("tipo_servicio"),
                    AreaResponsable:  reader.GetString("area_responsable"),
                    MotivoAlerta:     reader.GetString("motivo_alerta"),
                    TiempoDetenido:   reader.GetString("tiempo_detenido"),
                    Estado:           reader.GetString("estado"),
                    CreadoEn:         reader.GetDateTime("creado_en")
                ));
            }

            return new RespuestaDto<List<AlertaOperativaDto>>(2, mensaje, alertas);
        }
        catch (Exception ex)
        {
            return new RespuestaDto<List<AlertaOperativaDto>>(3, ex.Message);
        }
    }
}

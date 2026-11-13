using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>Viáticos asignados al programar y gastos rendidos del técnico (App Mobile HU-25 / HU-26).</summary>
public class ViaticosMovilRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), IViaticosMovilRepositorio
{
    public Task<RespuestaDto<List<ConceptoGastoMovilDto>>> ObtenerConceptosAsync(long idUsuario, CancellationToken ct) =>
        EjecutarAsync<List<ConceptoGastoMovilDto>>("SP_ObtenerConceptosGastoMovil",
            p => p.AddWithValue("p_id_usuario", idUsuario),
            async (r, mensaje) =>
            {
                var lista = new List<ConceptoGastoMovilDto>();
                await r.NextResultAsync(ct);
                while (await r.ReadAsync(ct))
                    lista.Add(new ConceptoGastoMovilDto(Entero(r, "id_concepto"), Texto(r, "concepto") ?? string.Empty, Booleano(r, "es_otro")));
                return new RespuestaDto<List<ConceptoGastoMovilDto>>(2, mensaje, lista);
            }, ct);

    public Task<RespuestaDto<ViaticosMovilDto>> ObtenerAsync(long idUsuario, CancellationToken ct) =>
        EjecutarAsync<ViaticosMovilDto>("SP_ObtenerViaticosMovil",
            p => p.AddWithValue("p_id_usuario", idUsuario),
            async (r, mensaje) =>
            {
                // 2. Resumen
                await r.NextResultAsync(ct);
                var resumen = new ResumenViaticosMovilDto(0, 0, 0, 0, 0, 0);
                if (await r.ReadAsync(ct))
                    resumen = new ResumenViaticosMovilDto(
                        DecimalNulo(r, "saldo_por_rendir") ?? 0m,
                        Entero(r, "viaticos_activos"),
                        Entero(r, "viaticos_finalizados"),
                        DecimalNulo(r, "gastos_en_revision") ?? 0m,
                        Entero(r, "gastos_en_revision_n"),
                        Entero(r, "gastos_observados_n"));

                // 3. Viáticos (uno por programación)
                var viaticos = new List<ViaticoMovilDto>();
                await r.NextResultAsync(ct);
                while (await r.ReadAsync(ct))
                    viaticos.Add(new ViaticoMovilDto(
                        EnteroLargo(r, "id_programacion"),
                        Texto(r, "codigo") ?? string.Empty,
                        Texto(r, "estado_prog") ?? string.Empty,
                        Texto(r, "estado_prog_label") ?? string.Empty,
                        Booleano(r, "cerrada"),
                        EnteroLargo(r, "id_os"),
                        Texto(r, "numero_os") ?? string.Empty,
                        Texto(r, "cliente"),
                        Texto(r, "sede"),
                        Fecha(r, "fecha_ejecucion"),
                        Texto(r, "hora_inicio"),
                        Texto(r, "hora_fin"),
                        DecimalNulo(r, "asignado") ?? 0m,
                        DecimalNulo(r, "depositado") ?? 0m,
                        DecimalNulo(r, "pendiente_deposito") ?? 0m,
                        DecimalNulo(r, "rendido") ?? 0m,
                        DecimalNulo(r, "por_rendir") ?? 0m,
                        Entero(r, "porcentaje_rendido"),
                        FechaHora(r, "cerrado_en"),
                        DecimalNulo(r, "saldo_final"),
                        Texto(r, "tipo_saldo")));

                // 4. Adelanto por concepto
                var lineas = new List<LineaViaticoMovilDto>();
                await r.NextResultAsync(ct);
                while (await r.ReadAsync(ct))
                    lineas.Add(new LineaViaticoMovilDto(
                        EnteroLargo(r, "id_programacion"),
                        Entero(r, "id_concepto"),
                        Texto(r, "concepto") ?? string.Empty,
                        DecimalNulo(r, "asignado") ?? 0m,
                        DecimalNulo(r, "depositado") ?? 0m,
                        Fecha(r, "fecha_deposito"),
                        DecimalNulo(r, "rendido") ?? 0m,
                        DecimalNulo(r, "por_rendir") ?? 0m,
                        Texto(r, "estado_deposito") ?? "pendiente",
                        EnteroLargo(r, "id_viatico_linea")));

                // 5. Gastos rendidos
                var gastos = new List<GastoMovilDto>();
                await r.NextResultAsync(ct);
                while (await r.ReadAsync(ct))
                    gastos.Add(new GastoMovilDto(
                        EnteroLargo(r, "id_gasto"),
                        Texto(r, "codigo") ?? string.Empty,
                        Fecha(r, "fecha"),
                        Entero(r, "id_concepto"),
                        Texto(r, "concepto") ?? string.Empty,
                        DecimalNulo(r, "monto") ?? 0m,
                        Texto(r, "moneda") ?? "S/",
                        Texto(r, "descripcion"),
                        Texto(r, "estado") ?? string.Empty,
                        Texto(r, "comentario_revision"),
                        Texto(r, "revisado_por"),
                        FechaHora(r, "revisado_en"),
                        FechaHora(r, "creado_en"),
                        Booleano(r, "tiene_comprobante"),
                        EnteroLargo(r, "id_os"),
                        Texto(r, "numero_os") ?? string.Empty,
                        EnteroLargoNulo(r, "id_programacion"),
                        Texto(r, "codigo_programacion"),
                        Texto(r, "origen"),
                        Texto(r, "concepto_texto"),
                        Texto(r, "motivo_sin_foto"),
                        DecimalNulo(r, "monto_ia"),
                        DecimalNulo(r, "coincide_ia") is { } c ? c != 0 : null,
                        Entero(r, "n_fotos")));

                // 6. Reparto de sus gastos
                var repartos = new List<RepartoGastoMovilDto>();
                await r.NextResultAsync(ct);
                while (await r.ReadAsync(ct))
                    repartos.Add(new RepartoGastoMovilDto(EnteroLargo(r, "id_gasto"), EnteroLargo(r, "id_viatico_linea"),
                        Texto(r, "concepto") ?? string.Empty, DecimalNulo(r, "monto") ?? 0m));

                // 7. Fotos de sus gastos
                var fotos = new List<FotoGastoMovilDto>();
                await r.NextResultAsync(ct);
                while (await r.ReadAsync(ct))
                    fotos.Add(new FotoGastoMovilDto(EnteroLargo(r, "id_gasto"), Entero(r, "orden")));

                return new RespuestaDto<ViaticosMovilDto>(2, mensaje, new ViaticosMovilDto(resumen, viaticos, lineas, gastos, repartos, fotos));
            }, ct);
}

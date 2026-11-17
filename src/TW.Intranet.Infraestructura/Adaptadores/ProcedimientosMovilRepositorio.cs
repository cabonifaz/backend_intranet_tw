using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>Biblioteca de procedimientos de la app móvil (App Mobile HU-24).</summary>
public class ProcedimientosMovilRepositorio(CadenaConexionBd conexion)
    : RepositorioSpBase(conexion), IProcedimientosMovilRepositorio
{
    public Task<RespuestaDto<BibliotecaProcedimientosMovilDto>> ObtenerBibliotecaAsync(long idUsuario, CancellationToken ct) =>
        EjecutarAsync<BibliotecaProcedimientosMovilDto>("SP_ObtenerProcedimientosMovil",
            p => p.AddWithValue("p_id_usuario", idUsuario),
            async (r, mensaje) =>
            {
                // 2do resultado: procedimientos
                await r.NextResultAsync(ct);
                var filas = new List<ProcedimientoMovilDto>();
                while (await r.ReadAsync(ct))
                {
                    filas.Add(new ProcedimientoMovilDto(
                        EnteroLargo(r, "id_procedimiento"),
                        Texto(r, "codigo") ?? string.Empty,
                        Entero(r, "anio"),
                        Entero(r, "version"),
                        Texto(r, "norma_base"),
                        Texto(r, "autor_norma"),
                        Texto(r, "tipo_procedimiento"),
                        Texto(r, "descripcion") ?? string.Empty,
                        Texto(r, "alcance"),
                        Texto(r, "aprobado_por"),
                        Fecha(r, "actualizado"),
                        Texto(r, "pdf_nombre"),
                        EnteroLargoNulo(r, "pdf_tamano"),
                        Texto(r, "pdf_hash"),
                        Booleano(r, "formato_digital_iso"),
                        Texto(r, "para_servicio_hoy"),
                        []));
                }

                // 3er resultado: versiones anteriores
                var historial = new Dictionary<long, List<VersionProcedimientoMovilDto>>();
                if (await r.NextResultAsync(ct))
                {
                    while (await r.ReadAsync(ct))
                    {
                        var id = EnteroLargo(r, "id_procedimiento");
                        if (!historial.TryGetValue(id, out var lista)) historial[id] = lista = [];
                        lista.Add(new VersionProcedimientoMovilDto(Entero(r, "version"), Fecha(r, "reemplazada_el")));
                    }
                }

                var procedimientos = filas
                    .Select(f => f with { Historial = historial.TryGetValue(f.IdProcedimiento, out var h) ? h : [] })
                    .ToList();
                return new RespuestaDto<BibliotecaProcedimientosMovilDto>(2, mensaje, new BibliotecaProcedimientosMovilDto(procedimientos));
            }, ct);
}

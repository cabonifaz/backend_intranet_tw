using System.Text.Json;
using MySqlConnector;
using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Infraestructura.Configuracion;

namespace TW.Intranet.Infraestructura.Adaptadores;

/// <summary>Propuestas — importación de equipos desde Excel (SP_ObtenerCandidatosImportacionEquipos, SP_ImportarEquiposPropuesta).</summary>
public class ImportacionEquiposRepositorio(CadenaConexionBd conexion) : RepositorioSpBase(conexion), IImportacionEquiposRepositorio
{
    public Task<RespuestaDto<CandidatosImportacionEquiposDto>> ObtenerCandidatosAsync(
        long idCliente, IReadOnlyList<string> seriesNormalizadas, long idUsuario, CancellationToken ct) =>
        EjecutarAsync<CandidatosImportacionEquiposDto>("SP_ObtenerCandidatosImportacionEquipos", p =>
        {
            p.AddWithValue("p_id_cliente",  idCliente);
            p.AddWithValue("p_series_json", JsonSerializer.Serialize(seriesNormalizadas));
            p.AddWithValue("p_id_usuario",  idUsuario);
        },
        async (r, mensaje) =>
        {
            string? razonSocial = null;
            await r.NextResultAsync(ct);
            if (await r.ReadAsync(ct)) razonSocial = Texto(r, "razon_social");

            var equipos = new List<EquipoConciliadoDto>();
            await r.NextResultAsync(ct);
            while (await r.ReadAsync(ct)) equipos.Add(LeerEquipo(r));

            var sedes = new List<OpcionImportacionDto>();
            await r.NextResultAsync(ct);
            while (await r.ReadAsync(ct)) sedes.Add(new OpcionImportacionDto(EnteroLargo(r, "id_sede"), null, Texto(r, "nombre") ?? ""));

            var suministros = new List<SuministroConciliadoDto>();
            await r.NextResultAsync(ct);
            while (await r.ReadAsync(ct))
                suministros.Add(new SuministroConciliadoDto
                {
                    IdSuministro = EnteroLargo(r, "id_suministro"),
                    Codigo       = Texto(r, "codigo") ?? "",
                    Descripcion  = Texto(r, "descripcion") ?? "",
                    Clase        = Texto(r, "clase"),
                    Tipo         = Texto(r, "tipo"),
                    Subtipo      = Texto(r, "subtipo"),
                    Marca        = Texto(r, "marca"),
                    Modelo       = Texto(r, "modelo"),
                });

            var otros = new List<EquipoOtroClienteDto>();
            await r.NextResultAsync(ct);
            while (await r.ReadAsync(ct))
                otros.Add(new EquipoOtroClienteDto(EnteroLargo(r, "id_equipo"), Texto(r, "codigo_tw") ?? "", Texto(r, "num_serie") ?? "",
                                                   Texto(r, "marca") ?? "", Texto(r, "modelo") ?? "", Texto(r, "razon_social")));

            var clasificaciones = new List<OpcionImportacionDto>();
            await r.NextResultAsync(ct);
            while (await r.ReadAsync(ct)) clasificaciones.Add(new OpcionImportacionDto(null, Texto(r, "codigo"), Texto(r, "nombre") ?? ""));

            return new RespuestaDto<CandidatosImportacionEquiposDto>(2, mensaje, new CandidatosImportacionEquiposDto
            {
                RazonSocialCliente = razonSocial,
                Equipos            = equipos,
                Sedes              = sedes,
                Suministros        = suministros,
                EnOtrosClientes    = otros,
                Clasificaciones    = clasificaciones,
            });
        }, ct);

    public Task<RespuestaDto<ResultadoImportacionEquiposDto>> ImportarAsync(
        ConfirmarImportacionEquiposSolicitudDto s, long idUsuario, CancellationToken ct)
    {
        var filas = s.Filas.Select(f => new
        {
            fila          = f.Fila,
            accion        = f.Accion,
            idEquipo      = f.Accion == "vincular" ? f.IdEquipo : null,
            numSerie      = f.NumSerie,
            marca         = f.Marca,
            modelo        = f.Modelo,
            clasificacion = f.Clasificacion,
            idSuministro  = f.IdSuministro,
            idSede        = f.IdSede,
            codigoCliente = f.CodigoCliente,
            ubicacion     = f.Ubicacion,
            alcanceMaximo = f.AlcanceMaximo,
        });

        return EjecutarAsync<ResultadoImportacionEquiposDto>("SP_ImportarEquiposPropuesta", p =>
        {
            p.AddWithValue("p_id_cliente", s.IdCliente);
            p.AddWithValue("p_filas_json", JsonSerializer.Serialize(filas));
            p.AddWithValue("p_id_usuario", idUsuario);
        },
        async (r, mensaje) =>
        {
            int vinculados = 0, creados = 0, reutilizados = 0;
            await r.NextResultAsync(ct);
            if (await r.ReadAsync(ct))
            {
                vinculados   = Entero(r, "vinculados");
                creados      = Entero(r, "creados");
                reutilizados = Entero(r, "reutilizados");
            }

            var equipos = new List<EquipoImportadoDto>();
            await r.NextResultAsync(ct);
            while (await r.ReadAsync(ct))
                equipos.Add(new EquipoImportadoDto
                {
                    Fila               = Entero(r, "fila"),
                    IdEquipo           = EnteroLargo(r, "id_equipo"),
                    CodigoTw           = Texto(r, "codigo_tw") ?? "",
                    NumSerie           = Texto(r, "num_serie") ?? "",
                    Marca              = Texto(r, "marca") ?? "",
                    Modelo             = Texto(r, "modelo") ?? "",
                    Clasificacion      = Texto(r, "clasificacion") ?? "",
                    ClasificacionLabel = Texto(r, "clasificacion_label") ?? "",
                    Tipo               = Texto(r, "suministro_tipo") ?? Texto(r, "clasificacion_label"),
                    Subtipo            = Texto(r, "suministro_subtipo"),
                    IdSede             = EnteroLargo(r, "id_sede"),
                    SedeNombre         = Texto(r, "sede_nombre"),
                    CodigoCliente      = Texto(r, "codigo_cliente"),
                    Ubicacion          = Texto(r, "ubicacion_especifica"),
                    Resultado          = Texto(r, "resultado") ?? "vinculado",
                });

            return new RespuestaDto<ResultadoImportacionEquiposDto>(2, mensaje, new ResultadoImportacionEquiposDto
            {
                Vinculados = vinculados, Creados = creados, Reutilizados = reutilizados, Equipos = equipos,
            });
        }, ct);
    }

    private static EquipoConciliadoDto LeerEquipo(MySqlDataReader r) => new()
    {
        IdEquipo           = EnteroLargo(r, "id_equipo"),
        CodigoTw           = Texto(r, "codigo_tw") ?? "",
        NumSerie           = Texto(r, "num_serie") ?? "",
        CodigoCliente      = Texto(r, "codigo_cliente"),
        Clasificacion      = Texto(r, "clasificacion") ?? "",
        ClasificacionLabel = Texto(r, "clasificacion_label") ?? "",
        Marca              = Texto(r, "marca") ?? "",
        Modelo             = Texto(r, "modelo") ?? "",
        IdSede             = EnteroLargo(r, "id_sede"),
        SedeNombre         = Texto(r, "sede_nombre"),
        Ubicacion          = Texto(r, "ubicacion_especifica"),
        AlcanceMaximo      = Texto(r, "alcance_maximo"),
        Estado             = Texto(r, "estado") ?? "activo",
        Tipo               = Texto(r, "suministro_tipo") ?? Texto(r, "clasificacion_label"),
        Subtipo            = Texto(r, "suministro_subtipo"),
    };
}

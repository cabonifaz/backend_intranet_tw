using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;

namespace TW.Intranet.Aplicacion.CasosDeUso;

/// <summary>
/// HU-09 — Detalle de Propuesta: une la propuesta completa con su contexto
/// (workflow, SLA, documentos, versiones, actividad) y decide qué acción
/// principal ofrece el modal ("Editar" o "Generar Nueva Versión").
/// </summary>
public class ObtenerDetallePropuestaCasoDeUso(IPropuestasRepositorio repositorio)
{
    private static readonly (string Codigo, string Etiqueta)[] PasosWorkflow =
    [
        ("borrador",    "Borrador"),
        ("preparacion", "Preparación"),
        ("visto_bueno", "Visto Bueno"),
        ("envio",       "Envío"),
        ("seguimiento", "Seguimiento"),
        ("aceptacion",  "Aceptación"),
    ];

    private const int PasoPreparacion = 1;
    private const int PasoSeguimiento = 4;
    private const int PasoAceptacion  = 5;

    /// <summary>
    /// Estados desde los que se puede generar una nueva versión (HU-10, igual que SP_CrearNuevaVersionPropuesta).
    /// pendiente_vb / aprobado: la versión actual se anula. enviado / rechazado / vencido: queda como historial.
    /// </summary>
    private static readonly string[] EstadosParaNuevaVersion = ["pendiente_vb", "aprobado", "enviado", "rechazado", "vencido"];

    public async Task<RespuestaDto<PropuestaDetalleModalDto>> EjecutarAsync(long idPropuesta, CancellationToken ct = default)
    {
        var propuesta = await repositorio.ObtenerPropuestaPorIdAsync(idPropuesta, ct);
        if (propuesta.IdTipoMensaje != 2 || propuesta.Datos is null)
            return new RespuestaDto<PropuestaDetalleModalDto>(propuesta.IdTipoMensaje, propuesta.Mensaje);

        var contexto = await repositorio.ObtenerContextoPropuestaAsync(idPropuesta, ct);
        if (contexto.IdTipoMensaje != 2 || contexto.Datos is null)
            return new RespuestaDto<PropuestaDetalleModalDto>(contexto.IdTipoMensaje, contexto.Mensaje);

        var c = contexto.Datos;

        foreach (var v in c.Versiones)
            v.EsActual = v.IdPropuesta == idPropuesta;

        var detalle = new PropuestaDetalleModalDto
        {
            Propuesta           = propuesta.Datos,
            Workflow            = ConstruirWorkflow(c),
            Sla                 = ConstruirSla(c),
            Acciones            = ConstruirAcciones(c),
            NumeroContratoMarco = c.NumeroContratoMarco,
            Documentos          = ConstruirDocumentos(c),
            Versiones           = c.Versiones,
            Actividad           = c.Actividad,
        };

        return new RespuestaDto<PropuestaDetalleModalDto>(2, propuesta.Mensaje, detalle);
    }

    private static WorkflowPropuestaDto ConstruirWorkflow(PropuestaContextoDto c)
    {
        string? terminal = null;
        int indice;

        if (c.TieneOc)
            indice = PasoAceptacion;
        else
            switch (c.Estado)
            {
                case "borrador":     indice = c.FechaPdf is null ? 0 : PasoPreparacion; break;
                case "pendiente_vb": indice = 2; break;
                case "aprobado":     indice = 3; break;
                case "enviado":      indice = PasoSeguimiento; break;
                default:
                    // rechazado | anulado | vencido: se marca el paso donde se detuvo
                    terminal = c.Estado;
                    indice   = c.FechaEnvio is not null ? PasoSeguimiento
                             : c.FechaPdf  is not null ? PasoPreparacion
                             : 0;
                    break;
            }

        var flujoCompleto = c.TieneOc;

        return new WorkflowPropuestaDto
        {
            EstadoTerminal = terminal,
            Pasos = PasosWorkflow.Select((p, i) => new PasoWorkflowDto
            {
                Codigo   = p.Codigo,
                Etiqueta = p.Etiqueta,
                Estado   = i < indice              ? "completado"
                         : i > indice              ? "pendiente"
                         : flujoCompleto           ? "completado"
                         : terminal ?? "actual",
            }).ToList(),
        };
    }

    private static SlaPropuestaDto? ConstruirSla(PropuestaContextoDto c)
    {
        if (c.SlaTipo is null || c.SlaVenceEn is null) return null;

        var minutos = (int)Math.Floor((c.SlaVenceEn.Value - c.Ahora).TotalMinutes);
        return new SlaPropuestaDto
        {
            Tipo             = c.SlaTipo,
            VenceEn          = c.SlaVenceEn.Value,
            MinutosRestantes = minutos,
            Vencido          = minutos < 0,
        };
    }

    private static AccionesPropuestaDto ConstruirAcciones(PropuestaContextoDto c)
    {
        var puedeEditar       = c.Estado == "borrador";
        var puedeNuevaVersion = c.EsUltimaVersion && EstadosParaNuevaVersion.Contains(c.Estado);

        return new AccionesPropuestaDto
        {
            PuedeEditar              = puedeEditar,
            PuedeGenerarNuevaVersion = puedeNuevaVersion,
            EsUltimaVersion          = c.EsUltimaVersion,
            AccionPrincipal          = puedeEditar ? "editar" : puedeNuevaVersion ? "nueva_version" : "ninguna",
        };
    }

    private static List<DocumentoVinculadoDto> ConstruirDocumentos(PropuestaContextoDto c)
    {
        var documentos = c.Documentos;

        // Marcador "OC (Pendiente)" desde que la propuesta está aprobada o enviada
        var esperaOc = c.Estado is "aprobado" or "enviado";
        if (esperaOc && documentos.All(d => d.Tipo != "orden_compra"))
            documentos.Add(new DocumentoVinculadoDto
            {
                Tipo        = "orden_compra",
                Descripcion = "Orden de compra",
                Estado      = "pendiente",
                EsPendiente = true,
            });

        return documentos;
    }
}

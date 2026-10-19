namespace TW.Intranet.Aplicacion.Dtos;

// ─────────────────────────────────────────────────────────────────────────────
// HU-10 — Edición y Gestión de Versiones de Propuesta
// POST /api/crm/propuestas/{id}/nueva-version
// ─────────────────────────────────────────────────────────────────────────────

/// <summary>Modal "Crear nueva versión".</summary>
public class CrearNuevaVersionPropuestaDto
{
    /// <summary>Num1 del catálogo MOTIVO_NUEVA_VERSION (GET /api/maestros/catalogos/MOTIVO_NUEVA_VERSION).</summary>
    public int    IdMotivoNuevaVersion { get; set; }
    /// <summary>Descripción breve de los cambios respecto a la versión anterior (máx. 500).</summary>
    public string DescripcionCambios   { get; set; } = "";
    /// <summary>Bloques a copiar de la versión anterior. Por defecto, todos.</summary>
    public BloquesCopiaVersionDto Copiar { get; set; } = new();
}

/// <summary>
/// "Opciones de copia desde vN". Requerimiento, cliente, moneda y responsable se heredan siempre.
/// </summary>
public class BloquesCopiaVersionDto
{
    /// <summary>Tipo, referencia, introducción, notas internas, sede, contacto, tercerización, IGV, vigencia y estructura del PDF.</summary>
    public bool Configuracion      { get; set; } = true;
    /// <summary>Textos de detalle, recomendaciones y suministros del cliente.</summary>
    public bool DetalleDescriptivo { get; set; } = true;
    /// <summary>Textos de condiciones, garantía y plazo de entrega.</summary>
    public bool Condiciones        { get; set; } = true;
    /// <summary>Ítems principales/opcionales y descuentos.</summary>
    public bool Items              { get; set; } = true;
    public bool FormaPago          { get; set; } = true;
    public bool Equipos            { get; set; } = true;
}

/// <param name="VersionAnteriorAnulada">
/// true si la versión anterior aún no se había enviado al cliente (pendiente de VB o aprobada)
/// y quedó anulada; false si se conserva como historial (enviada, rechazada o vencida).
/// </param>
public record NuevaVersionPropuestaResultadoDto(
    long   IdPropuesta,
    string Numero,
    int    Version,
    bool   VersionAnteriorAnulada
);

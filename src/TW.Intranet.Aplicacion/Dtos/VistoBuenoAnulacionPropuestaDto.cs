namespace TW.Intranet.Aplicacion.Dtos;

// ─────────────────────────────────────────────────────────────────────────────
// HU-12 — Envío a Visto Bueno y Anulación de Propuesta
//   GET  /api/crm/propuestas/{id}/visto-bueno/preparar
//   POST /api/crm/propuestas/{id}/visto-bueno
//   GET  /api/crm/propuestas/{id}/anulacion/preparar
//   POST /api/crm/propuestas/{id}/anular
// ─────────────────────────────────────────────────────────────────────────────

/// <summary>Modal "Enviar a Visto Bueno".</summary>
public class EnviarVistoBuenoPropuestaDto
{
    /// <summary>Comentarios para el aprobador. Obligatorio si la propuesta requiere aprobación especial.</summary>
    public string? Comentario { get; set; }
}

/// <summary>Lo que muestra el modal de VB (preparar) o el resultado del envío.</summary>
public class VistoBuenoPropuestaDto
{
    public long     IdPropuesta          { get; set; }
    public string   Numero               { get; set; } = "";
    public int      Version              { get; set; }
    public string   Estado               { get; set; } = "";
    public string?  Cliente              { get; set; }
    public string?  NumeroRequerimiento  { get; set; }
    public decimal  Total                { get; set; }
    public string?  MonedaSimbolo        { get; set; }

    /// <summary>Área del comercial autor: todos los supervisores y administradores activos de esa
    /// área reciben el VB en su bandeja compartida (modelo área + rol).</summary>
    public string?  AreaEquipoAprobador  { get; set; }

    public int      SlaHoras             { get; set; }
    public DateTime? FechaLimite         { get; set; }

    /// <summary>Alerta de aprobación especial (hoy: descuento sobre el subtotal mayor al umbral configurado).</summary>
    public bool     RequiereAprobacionEspecial { get; set; }
    public string?  MotivoAlerta         { get; set; }
    public decimal  DescuentoPct         { get; set; }
    public decimal  UmbralDescuentoPct   { get; set; }

    /// <summary>true si todas las validaciones obligatorias se cumplen.</summary>
    public bool     PuedeEnviar          { get; set; }
    /// <summary>Id del registro de visto bueno creado (solo al enviar).</summary>
    public long?    IdVistoBueno         { get; set; }

    public List<ValidacionVistoBuenoDto> Validaciones { get; set; } = new();
}

/// <summary>Una línea de "Validaciones del sistema".</summary>
public class ValidacionVistoBuenoDto
{
    public string Codigo      { get; set; } = "";
    public string Etiqueta    { get; set; } = "";
    public bool   Cumple      { get; set; }
    /// <summary>false = informativa (se muestra pero no bloquea el envío).</summary>
    public bool   Obligatoria { get; set; }
    public string? Detalle    { get; set; }
}

/// <summary>Modal "Anular Propuesta".</summary>
public class AnularPropuestaDto
{
    /// <summary>Num1 de MOTIVO_ANULACION (IdMaestro 9). La lista viene en /anulacion/preparar.</summary>
    public int?    IdMotivoAnulacion   { get; set; }
    /// <summary>Justificación detallada, mínimo 20 caracteres.</summary>
    public string  Justificacion       { get; set; } = "";
    /// <summary>Check "Confirmación Crítica". Debe ser true.</summary>
    public bool    ConfirmacionCritica { get; set; }
}

/// <summary>Lo que muestra el modal de anulación (preparar) o el resultado de anular.</summary>
public class AnulacionPropuestaDto
{
    public long     IdPropuesta          { get; set; }
    public string   Numero               { get; set; } = "";
    public int      Version              { get; set; }
    public string   Estado               { get; set; } = "";
    public string?  Cliente              { get; set; }
    public string?  NumeroRequerimiento  { get; set; }
    public string?  NumeroExpediente     { get; set; }
    public bool     TieneVbPendiente     { get; set; }
    public bool     PuedeAnular          { get; set; }
    public string?  MotivoBloqueo        { get; set; }
    /// <summary>Texto de "Impacto de la acción".</summary>
    public string?  Impacto              { get; set; }
    public string?  MotivoAnulacion      { get; set; }
    public string?  JustificacionAnulacion { get; set; }
    public DateTime? FechaAnulacion      { get; set; }
    /// <summary>Motivos de anulación (solo en preparar).</summary>
    public List<OpcionMotivoDto> Motivos { get; set; } = new();
}

public class OpcionMotivoDto
{
    public int    Id     { get; set; }
    public string Nombre { get; set; } = "";
}

// ─────────────────────────────────────────────────────────────────────────────
// HU-10b — Envío de propuesta al cliente (post VB aprobado)
//   POST /api/crm/propuestas/{id}/enviar-cliente
// ─────────────────────────────────────────────────────────────────────────────

/// <summary>Resultado de enviar la propuesta al cliente.</summary>
public class EnvioPropuestaClienteDto
{
    public long      IdPropuesta         { get; set; }
    public string    Numero              { get; set; } = "";
    public int       Version             { get; set; }
    public string    Estado              { get; set; } = "";
    public DateTime? FechaEnvioCliente   { get; set; }
    public long?     EnviadoClientePor   { get; set; }
    /// <summary>true si el correo salió por Brevo (puede ser false si falló aunque el estado sí cambió).</summary>
    public bool      CorreoEnviado       { get; set; }
    public string?   CorreoError         { get; set; }
}

/// <summary>Destinatario del correo (PARA / CC).</summary>
public record DestinatarioEnvioClienteDto(string Correo, string? Nombre = null, long? IdContacto = null);

/// <summary>Body del POST /enviar-cliente — datos del correo que acompañan al cambio de estado.</summary>
public class EnviarPropuestaClienteDto
{
    public int?    IdPlantilla { get; set; }
    public List<DestinatarioEnvioClienteDto> Para { get; set; } = new();
    public List<DestinatarioEnvioClienteDto> Cc   { get; set; } = new();
    public string  Asunto     { get; set; } = "";
    public string  CuerpoHtml { get; set; } = "";
}

// ── Preparación (GET /enviar-cliente/preparar) ──

public record CabeceraEnvioClienteDto(
    long      IdPropuesta,
    string    Numero,
    int       Version,
    long      IdCliente,
    string    RazonSocial,
    string?   Ruc,
    string?   Referencia,
    decimal   Total,
    int       IdMoneda,
    string?   MonedaSimbolo,
    string?   Moneda,
    long?     IdContacto,
    string?   Contacto,
    string?   CorreoContacto,
    long      IdUsuario,
    string?   Usuario,
    string?   CorreoUsuario,
    string?   CargoUsuario,
    DateTime? FechaServidor);

public record ContactoEnvioClienteDto(
    long    IdContacto,
    string  Nombres,
    string? Cargo,
    string? Correo,
    string? TelefonoMovil,
    string? TelefonoAnexo,
    bool    EsContactoPropuesta,
    bool    EsContactoPrincipal);

public record PlantillaEnvioClienteDto(
    int    IdPlantilla,
    string Codigo,
    string Nombre,
    string Asunto,
    string CuerpoHtml);

public record PreparacionEnvioClienteDto(
    CabeceraEnvioClienteDto           Cabecera,
    List<ContactoEnvioClienteDto>     Contactos,
    List<PlantillaEnvioClienteDto>    Plantillas);

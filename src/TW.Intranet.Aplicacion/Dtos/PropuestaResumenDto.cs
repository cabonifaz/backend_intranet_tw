namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>Fila de la bandeja de propuestas (HU-07 / HU-08).</summary>
public record PropuestaResumenDto(
    long      IdPropuesta,
    string    Numero,
    int       Version,
    long      IdRequerimiento,
    string    NumeroRequerimiento,
    long      IdCliente,
    string    RazonSocial,
    string?   Referencia,
    string?   Moneda,
    decimal   Total,
    decimal   TotalOpcionales,
    /// <summary>Estado en BD: borrador | pendiente_vb | enviado | aprobado | rechazado | anulado | vencido.</summary>
    string    Estado,
    DateTime? FechaCreacion,
    string?   Responsable,
    // ── HU-08 ──
    string?   Ruc,
    /// <summary>Pestaña: borrador | por_vb | en_seguimiento | aceptada | rechazada | cerrada.</summary>
    string    EstadoGrupo,
    /// <summary>Acción disponible: editar | nueva_version | ver_detalle.</summary>
    string    Accion,
    /// <summary>Días hasta el vencimiento de la vigencia (negativo = vencida). Null si no tiene vigencia.</summary>
    int?      SlaDiasRestantes,
    DateTime? FechaModificacion,
    long?     IdResponsable
);

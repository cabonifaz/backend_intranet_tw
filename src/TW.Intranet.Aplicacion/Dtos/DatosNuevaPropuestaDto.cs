namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>Datos heredados del requerimiento para iniciar una propuesta (HU-07).</summary>
public record DatosNuevaPropuestaDto(
    long    IdRequerimiento,
    string  NumeroRequerimiento,
    string  EstadoRequerimiento,
    long    IdCliente,
    string  RazonSocial,
    string  Ruc,
    long?   IdSede,
    string? NombreSede,
    long?   IdContacto,
    string? NombreContacto,
    string? CargoContacto,
    int?    IdArea,
    string? AreaLabel,
    int?    IdPrioridad,
    string? PrioridadLabel,
    string  Descripcion,
    /// <summary>Null si el RQ todavía no tiene propuesta.</summary>
    PropuestaExistenteDto? PropuestaExistente,
    /// <summary>El RQ entra al sistema de acreditación: habilita "Servicio metrológico" y exige adjunto en el RQ.</summary>
    bool    EsAcreditacion       = false,
    int     CantidadAdjuntos     = 0,
    /// <summary>Condición de pago habitual del cliente (texto de la ficha) y su código en CONDICION_PAGO.</summary>
    string? CondicionPagoCliente = null,
    string? CondicionPagoCodigo  = null
);

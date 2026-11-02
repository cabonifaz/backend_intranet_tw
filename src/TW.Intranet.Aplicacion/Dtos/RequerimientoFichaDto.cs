namespace TW.Intranet.Aplicacion.Dtos;

public record RequerimientoFichaDto(
    long      IdRequerimiento,
    string    Numero,
    long      IdCliente,
    string    RazonSocial,
    string    Ruc,
    long?     IdContacto,
    long?     IdSede,
    string?   NombreContacto,
    string?   NombreSede,
    string?   Responsable,
    DateTime  FechaCreacion,
    int       IdOrigen,
    string?   OrigenLabel,
    int       IdArea,
    string?   AreaLabel,
    int       IdPrioridad,
    string?   PrioridadLabel,
    DateTime? FechaNecesidad,
    string    Descripcion,
    bool      NotificarCorreo,
    bool      RequiereVisita,
    bool      ClienteDeuda,
    string    Estado,
    string?   EstadoLabel,
    IReadOnlyList<HistorialItemDto> Historial,
    long?     IdContactoSecundario = null,
    string?   NombreContactoSecundario = null,
    bool      EsAcreditacion = false,
    int       CantidadAdjuntos = 0,
    IReadOnlyList<AdjuntoRequerimientoDto>? Adjuntos = null
);

/// <summary>Documento adjunto del requerimiento (foto, video, correo, PDF, Office, texto).</summary>
public record AdjuntoRequerimientoDto(
    long     IdDocumento,
    string   NombreArchivo,
    string?  TipoContenido,
    long?    TamanoBytes,
    DateTime FechaCarga,
    string?  SubidoPor
);

/// <summary>Ruta interna de un adjunto del requerimiento (para abrirlo del almacenamiento).</summary>
public record RutaAdjuntoRequerimientoDto(string Ruta, string NombreArchivo, string TipoContenido);

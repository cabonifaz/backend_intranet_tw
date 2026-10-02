namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>Fila del listado de propuestas.</summary>
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
    string    Estado,
    DateTime? FechaCreacion,
    string?   Responsable
);

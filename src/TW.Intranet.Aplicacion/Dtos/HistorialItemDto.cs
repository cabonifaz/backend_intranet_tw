namespace TW.Intranet.Aplicacion.Dtos;

public record HistorialItemDto(
    long     IdHistorial,
    string   Tipo,
    string?  TipoLabel,
    string?  Icono,
    string   Descripcion,
    string?  Usuario,
    DateTime Fecha
);

namespace TW.Intranet.Aplicacion.Dtos;

public record NotificacionDto(
    int      IdNotificacion,
    string   Tipo,
    string   Titulo,
    string   Cuerpo,
    string   TipoDot,
    string   Tiempo,
    bool     Leida,
    DateTime CreadoEn
);

namespace TW.Intranet.Aplicacion.Dtos;

public record AlertaOperativaDto(
    int      IdAlerta,
    string   Nivel,
    string   NumeroExpediente,
    string   Cliente,
    string   TipoServicio,
    string   AreaResponsable,
    string   MotivoAlerta,
    string   TiempoDetenido,
    string   Estado,
    DateTime CreadoEn
);

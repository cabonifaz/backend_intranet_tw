namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>
/// App móvil sin señal — un registro de campo que la app envió después de tomarlo. Las horas van en hora de Lima. RetrasoSeg = lo que pasó entre que el técnico lo tomó
/// (CapturadoEn) y que llegó al servidor (RecibidoEn). Motivo: sin_senal · servidor_no_disponible · otro.
/// Tipo: llegada · demora · equipo_iniciar · equipo_pausar · equipo_reanudar · variables · ensayos · cabecera · evidencia · jornada · gasto · otro.
/// </summary>
public record EnvioDiferidoDto(
    long      IdEnvio,
    long      IdUsuario,
    string?   Tecnico,
    long?     IdOs,
    long?     IdOsEquipo,
    string    Tipo,
    string    Metodo,
    DateTime? CapturadoEn,
    DateTime? RecibidoEn,
    int       RetrasoSeg,
    string    Motivo,
    int       Intentos);

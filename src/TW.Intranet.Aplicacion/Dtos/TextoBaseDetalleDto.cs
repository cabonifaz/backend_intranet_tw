namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>Ficha del texto base (HU-85). Coincide con TextoBaseDetalle del front.</summary>
public record TextoBaseDetalleDto(
    // Datos del listado
    long      IdTextoBase,
    string    CodigoCorto,
    string    TipoCategoria,
    string    TipoCategoriaLabel,
    string    Nombre,
    string    TextoClausula,
    string    Estado,
    bool      EsPredeterminado,
    bool      EsNegritaPorDefecto,
    DateTime? FechaCreacion,
    string    UsuarioCreador,

    // Formato
    string?   SeccionDossier,
    int       OrdenAparicion,
    string    NivelSangria,

    // Aplicabilidad
    bool      AplicaTodosServicios,
    bool      AplicaCalibracionLab,
    bool      AplicaCalibracionPlanta,
    bool      AplicaMantenimiento,
    bool      AplicaVentaSuministros,

    // Visibilidad por perfil
    bool      VisibleGestoresComerciales,
    bool      VisibleTecnicosMetrologos,
    bool      VisibleSupervisores,

    // Auditoría
    int       Version,
    int       PropuestasAsociadas
);

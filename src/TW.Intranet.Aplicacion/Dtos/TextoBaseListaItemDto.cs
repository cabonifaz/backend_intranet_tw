namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>Fila del listado de textos base (HU-85). Coincide con TextoBaseListaItem del front.</summary>
public record TextoBaseListaItemDto(
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
    string    UsuarioCreador
);

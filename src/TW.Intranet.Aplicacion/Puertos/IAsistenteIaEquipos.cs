using TW.Intranet.Aplicacion.Dtos;

namespace TW.Intranet.Aplicacion.Puertos;

/// <summary>
/// IA de la importación de equipos de una propuesta (Gemini): reconoce qué columna del Excel trae cada dato y
/// ayuda a conciliar las filas que las reglas no resolvieron (serie parecida, equipo descrito con otras palabras,
/// suministro del catálogo). La IA no decide: sugiere, y el comercial confirma en la vista previa.
/// </summary>
public interface IAsistenteIaEquipos
{
    /// <summary>false si no hay API key (Gemini__ApiKey): la importación funciona solo con reglas.</summary>
    bool Disponible { get; }

    /// <summary>Nombre del motor (ej. "gemini-3.5-flash-lite").</summary>
    string Motor { get; }

    /// <summary>Reconoce la fila de encabezados y la columna de cada dato a partir de las primeras filas del archivo.</summary>
    Task<ResultadoIa<MapeoColumnasIaDto>> ReconocerColumnasAsync(IReadOnlyList<FilaLeida> muestra, CancellationToken ct);

    /// <summary>Para cada fila elige, entre los candidatos dados, el equipo del cliente o el suministro que corresponde.</summary>
    Task<ResultadoIa<List<ConciliacionIaDto>>> ConciliarAsync(IReadOnlyList<ConsultaConciliacionIaDto> consultas, CancellationToken ct);
}

/// <summary>
/// Columnas reconocidas: FilaEncabezado = número de fila (Excel) de los encabezados, 0 si no hay.
/// Columnas: campo (numSerie, codigoTw, codigoCliente, equipo, marca, modelo, capacidad, ubicacion, sede) → índice (0 = A).
/// </summary>
public record MapeoColumnasIaDto(int FilaEncabezado, IReadOnlyDictionary<string, int> Columnas, int Confianza);

/// <summary>Una fila por conciliar con sus candidatos (ya filtrados por parecido).</summary>
public record ConsultaConciliacionIaDto(
    int Fila,
    DatosLeidosEquipoDto Leido,
    IReadOnlyList<EquipoConciliadoDto>     Equipos,
    IReadOnlyList<SuministroConciliadoDto> Suministros);

/// <summary>
/// Respuesta de la IA para una fila: IdEquipo = equipo del cliente que es el mismo (null si ninguno),
/// IdSuministro = modelo del catálogo (null si ninguno), y marca / modelo / clasificación que deduce del texto.
/// </summary>
public record ConciliacionIaDto(
    int     Fila,
    long?   IdEquipo,
    long?   IdSuministro,
    string? Clasificacion,
    string? Marca,
    string? Modelo,
    int     Confianza,
    string? Motivo);

namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>Contacto del directorio interno (ticket #4303). Sin datos sensibles.</summary>
public record DirectorioItemDto(
    long   IdUsuario,
    string NombreCompleto,
    string Area,
    string AreaLabel,
    string Cargo,
    string Correo,
    string Telefono,
    string Anexo,
    string Troncal,
    /// <summary>Troncal + interno, ej. "5699750 - 207". Vacío si no tiene anexo.</summary>
    string AnexoCompleto,
    /// <summary>Día y mes ("15/05"). Vacío si no se registró.</summary>
    string Cumpleanos);

public record DirectorioPaginadoDto(List<DirectorioItemDto> Items, int Total, int Pagina, int PorPagina);

public record CumpleanosItemDto(long IdUsuario, string NombreCompleto, string AreaLabel, int Dia, string Cumpleanos);

/// <summary>Valor ya registrado parecido a lo que se está escribiendo (ticket #4290).</summary>
public record ValorSimilarDto(string Valor, string Detalle, int Usos, int Similitud, bool ProbableDuplicado);

/// <summary>Resultado de la verificación: si existe exacto y la lista de parecidos (de mayor a menor).</summary>
public record VerificacionDuplicadosDto(string Texto, bool ExisteExacto, List<ValorSimilarDto> Similares);

/// <summary>Valor existente tal como lo devuelve la BD (uso interno).</summary>
public record ValorExistenteDto(string Valor, string Detalle, int Usos);

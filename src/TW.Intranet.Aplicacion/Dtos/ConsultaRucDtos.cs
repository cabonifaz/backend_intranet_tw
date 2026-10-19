namespace TW.Intranet.Aplicacion.Dtos;

/// <summary>Opciones de la consulta de RUC (ConsultaRuc:* en appsettings / variables de entorno).</summary>
public record OpcionesConsultaRuc(int DiasVigenciaCache);

/// <summary>Datos que devuelve un proveedor externo de RUC, ya normalizados.</summary>
public record DatosRucProveedorDto(
    string    Ruc,
    string    RazonSocial,
    string?   Estado,
    string?   Condicion,
    string?   Direccion,
    string?   Ubigeo,
    string?   Fuente,
    DateOnly? FechaDato);

public enum ResultadoConsultaProveedor { Encontrado, NoEncontrado, Limite, Error }

/// <summary>Resultado de una llamada a un proveedor externo.</summary>
public record ResultadoProveedorRucDto(
    ResultadoConsultaProveedor Resultado,
    DatosRucProveedorDto?      Datos,
    int?                       CodigoHttp,
    string?                    Detalle,
    int                        DuracionMs);

/// <summary>Fila de la caché local (consulta_ruc + nombres de ubigeo).</summary>
public record RucEnCacheDto(
    string    Ruc,
    string    RazonSocial,
    string?   Estado,
    string?   Condicion,
    string?   Direccion,
    string?   Ubigeo,
    string?   Departamento,
    string?   Provincia,
    string?   Distrito,
    string?   Fuente,
    DateOnly? FechaDato,
    string    Proveedor,
    DateTime  ConsultadoEn);

public record ClienteExistenteRucDto(long IdCliente, string RazonSocial, string? Estado);

public record LecturaCacheRucDto(RucEnCacheDto? Cache, ClienteExistenteRucDto? ClienteExistente);

/// <summary>Respuesta de GET api/maestros/clientes/consulta-ruc/{ruc}.</summary>
public record ConsultaRucDto(
    string                  Ruc,
    string                  RazonSocial,
    string?                 Estado,
    string?                 Condicion,
    bool                    EsActivo,
    bool                    EsHabido,
    string?                 Direccion,
    string?                 Ubigeo,
    string?                 Departamento,
    string?                 Provincia,
    string?                 Distrito,
    string?                 DomicilioFiscal,
    string?                 Fuente,
    DateOnly?               FechaDato,
    string                  Proveedor,
    DateTime                ConsultadoEn,
    bool                    DesdeCache,
    List<string>            Advertencias,
    ClienteExistenteRucDto? ClienteExistente);

public record UsoConsultaRucPeriodoDto(
    string Periodo,
    string Proveedor,
    int    Llamadas,
    int    Encontrados,
    int    NoEncontrados,
    int    Limitados,
    int    Errores,
    int?   DuracionPromedioMs);

public record UsoConsultaRucDto(List<UsoConsultaRucPeriodoDto> Periodos, int RucsEnCache);

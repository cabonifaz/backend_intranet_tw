using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Dominio.Valores;

namespace TW.Intranet.Aplicacion.CasosDeUso;

/// <summary>
/// Consulta los datos de un contribuyente por RUC.
/// 1. Valida el RUC (formato, prefijo y dígito verificador).
/// 2. Si hay caché vigente la devuelve (no gasta llamadas externas).
/// 3. Si no, prueba los proveedores registrados que cubran ese RUC, en orden.
/// 4. Si todos fallan por límite o error, devuelve la caché vencida si existe.
/// Cada llamada externa queda registrada en consulta_ruc_log.
/// </summary>
public class ConsultarRucCasoDeUso(
    IConsultaRucRepositorio     repositorio,
    IEnumerable<IProveedorRuc>  proveedores,
    OpcionesConsultaRuc         opciones)
{
    private const int DiasSinLimite = 36500;

    public async Task<RespuestaDto<ConsultaRucDto>> EjecutarAsync(
        string? rucIngresado, bool forzar, long idUsuario, CancellationToken ct)
    {
        string ruc = ValidadorRuc.Normalizar(rucIngresado);

        if (!ValidadorRuc.TieneFormato(ruc))
            return new(1, "El RUC debe tener exactamente 11 dígitos.");
        if (!ValidadorRuc.TienePrefijoValido(ruc))
            return new(1, "El RUC debe empezar con 10, 15, 16, 17 o 20.");
        if (!ValidadorRuc.DigitoVerificadorCorrecto(ruc))
            return new(1, "El RUC no es válido: el dígito verificador no corresponde.");

        // ── Caché vigente ───────────────────────────────────────────────
        var lectura = await repositorio.ObtenerAsync(ruc, forzar ? 0 : opciones.DiasVigenciaCache, ct);
        if (lectura.IdTipoMensaje != 2) return new(lectura.IdTipoMensaje, lectura.Mensaje);

        var clienteExistente = lectura.Datos?.ClienteExistente;
        if (lectura.Datos?.Cache is { } vigente)
            return new(2, "Datos obtenidos de la caché.", Armar(vigente, true, clienteExistente, null));

        // ── Proveedores externos ────────────────────────────────────────
        var candidatos = proveedores.Where(p => p.Cubre(ruc)).ToList();
        if (candidatos.Count == 0)
            return new(1, ValidadorRuc.EsPersonaJuridica(ruc)
                ? "No hay un servicio de consulta de RUC configurado. Complete los datos manualmente."
                : "La consulta automática solo cubre empresas (RUC que empieza con 20). " +
                  "Para personas naturales con negocio (RUC 10) complete los datos manualmente.");

        bool algunoNoEncontro = false;
        foreach (var proveedor in candidatos)
        {
            var r = await proveedor.ConsultarAsync(ruc, ct);
            await RegistrarLogSeguroAsync(ruc, proveedor.Nombre, r, idUsuario, ct);

            if (r.Resultado == ResultadoConsultaProveedor.Encontrado && r.Datos is not null)
            {
                var guardado = await repositorio.GuardarAsync(r.Datos, proveedor.Nombre, idUsuario, ct);
                if (guardado.IdTipoMensaje == 2)
                {
                    var releida = await repositorio.ObtenerAsync(ruc, DiasSinLimite, ct);
                    if (releida.IdTipoMensaje == 2 && releida.Datos?.Cache is { } nueva)
                        return new(2, "Datos obtenidos de SUNAT.", Armar(nueva, false, releida.Datos.ClienteExistente, null));
                }

                // No se pudo guardar en caché: igual se devuelven los datos del proveedor.
                return new(2, "Datos obtenidos de SUNAT.", Armar(DesdeProveedor(r.Datos, proveedor.Nombre), false, clienteExistente, null));
            }

            if (r.Resultado == ResultadoConsultaProveedor.NoEncontrado)
                algunoNoEncontro = true;
        }

        if (algunoNoEncontro)
            return new(1, "El RUC no figura en el padrón de SUNAT. Verifique el número o complete los datos manualmente.");

        // ── Todos fallaron por límite/error: caché vencida como respaldo ─
        var respaldo = await repositorio.ObtenerAsync(ruc, DiasSinLimite, ct);
        if (respaldo.IdTipoMensaje == 2 && respaldo.Datos?.Cache is { } vencida)
            return new(2, "El servicio de consulta no respondió; se muestran los últimos datos guardados.",
                Armar(vencida, true, respaldo.Datos.ClienteExistente,
                      $"Datos guardados el {vencida.ConsultadoEn:dd/MM/yyyy}: el servicio de consulta no respondió."));

        return new(1, "El servicio de consulta de RUC no está disponible en este momento. " +
                      "Intente en unos minutos o complete los datos manualmente.");
    }

    private async Task RegistrarLogSeguroAsync(
        string ruc, string proveedor, ResultadoProveedorRucDto r, long idUsuario, CancellationToken ct)
    {
        string resultado = r.Resultado switch
        {
            ResultadoConsultaProveedor.Encontrado   => "encontrado",
            ResultadoConsultaProveedor.NoEncontrado => "no_encontrado",
            ResultadoConsultaProveedor.Limite       => "limite",
            _                                       => "error",
        };
        // El log nunca debe impedir la consulta: el repositorio ya captura errores.
        await repositorio.RegistrarLogAsync(ruc, proveedor, resultado, r.CodigoHttp, r.Detalle, r.DuracionMs, idUsuario, ct);
    }

    private static RucEnCacheDto DesdeProveedor(DatosRucProveedorDto d, string proveedor) => new(
        d.Ruc, d.RazonSocial, d.Estado, d.Condicion, d.Direccion, d.Ubigeo,
        null, null, null, d.Fuente, d.FechaDato, proveedor, DateTime.Now);

    public static ConsultaRucDto Armar(
        RucEnCacheDto c, bool desdeCache, ClienteExistenteRucDto? cliente, string? advertenciaExtra)
    {
        bool esActivo = string.Equals(c.Estado?.Trim(), "ACTIVO", StringComparison.OrdinalIgnoreCase);
        bool esHabido = string.Equals(c.Condicion?.Trim(), "HABIDO", StringComparison.OrdinalIgnoreCase);

        var advertencias = new List<string>();
        if (advertenciaExtra is not null) advertencias.Add(advertenciaExtra);
        if (!string.IsNullOrWhiteSpace(c.Estado) && !esActivo)
            advertencias.Add($"El contribuyente figura con estado {c.Estado.Trim().ToUpperInvariant()} en SUNAT.");
        if (!string.IsNullOrWhiteSpace(c.Condicion) && !esHabido)
            advertencias.Add($"Condición {c.Condicion.Trim().ToUpperInvariant()}: verifique antes de emitir propuestas o facturas.");
        if (cliente is not null)
            advertencias.Add($"El RUC ya está registrado como cliente: {cliente.RazonSocial} (ID {cliente.IdCliente}).");

        return new ConsultaRucDto(
            Ruc:              c.Ruc,
            RazonSocial:      c.RazonSocial,
            Estado:           c.Estado,
            Condicion:        c.Condicion,
            EsActivo:         esActivo,
            EsHabido:         esHabido,
            Direccion:        c.Direccion,
            Ubigeo:           c.Ubigeo,
            Departamento:     c.Departamento,
            Provincia:        c.Provincia,
            Distrito:         c.Distrito,
            DomicilioFiscal:  ArmarDomicilio(c),
            Fuente:           c.Fuente,
            FechaDato:        c.FechaDato,
            Proveedor:        c.Proveedor,
            ConsultadoEn:     c.ConsultadoEn,
            DesdeCache:       desdeCache,
            Advertencias:     advertencias,
            ClienteExistente: cliente);
    }

    /// <summary>"JR. X 123, LA MOLINA - LIMA - LIMA" (como lo muestra SUNAT).</summary>
    private static string? ArmarDomicilio(RucEnCacheDto c)
    {
        if (string.IsNullOrWhiteSpace(c.Direccion)) return null;
        var lugar = new[] { c.Distrito, c.Provincia, c.Departamento }
            .Where(s => !string.IsNullOrWhiteSpace(s)).ToArray();
        return lugar.Length == 0 ? c.Direccion.Trim() : $"{c.Direccion.Trim()}, {string.Join(" - ", lugar)}";
    }
}

/// <summary>Consumo de la consulta de RUC por mes y proveedor.</summary>
public class ObtenerUsoConsultaRucCasoDeUso(IConsultaRucRepositorio repositorio)
{
    public Task<RespuestaDto<UsoConsultaRucDto>> EjecutarAsync(int meses, CancellationToken ct)
        => repositorio.ObtenerUsoAsync(Math.Clamp(meses, 1, 24), ct);
}

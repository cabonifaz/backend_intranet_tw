using TW.Intranet.Aplicacion.Dtos;
using TW.Intranet.Aplicacion.Puertos;
using TW.Intranet.Aplicacion.Servicios;

namespace TW.Intranet.Aplicacion.CasosDeUso;

/// <summary>
/// Ficha de usuario: indica si el usuario de la app móvil está libre y, si no, propone una variante
/// (juan.perez2, juan.perez3...). Es una ayuda en línea: la unicidad real la valida el SP al guardar.
/// </summary>
public class ValidarNombreUsuarioCasoDeUso(IUsuariosRepositorio repositorio)
{
    private const int MaxVariantes = 99;

    public async Task<RespuestaDto<NombreUsuarioDisponibleDto>> EjecutarAsync(
        string? nombre, long? excluirIdUsuario, CancellationToken ct = default)
    {
        var nombreUsuario = FormatoNombreUsuarioMovil.Normalizar(nombre);
        if (!FormatoNombreUsuarioMovil.EsValido(nombreUsuario))
            return new RespuestaDto<NombreUsuarioDisponibleDto>(1, FormatoNombreUsuarioMovil.MensajeFormato);

        var enUso = await repositorio.ObtenerNombresUsuarioConPrefijoAsync(nombreUsuario, excluirIdUsuario, ct);
        if (enUso.IdTipoMensaje != 2 || enUso.Datos is null)
            return new RespuestaDto<NombreUsuarioDisponibleDto>(enUso.IdTipoMensaje, enUso.Mensaje);

        var ocupados = new HashSet<string>(enUso.Datos, StringComparer.OrdinalIgnoreCase);
        if (!ocupados.Contains(nombreUsuario))
            return new RespuestaDto<NombreUsuarioDisponibleDto>(2, "Éxito.", new NombreUsuarioDisponibleDto(true));

        return new RespuestaDto<NombreUsuarioDisponibleDto>(2, "Éxito.",
            new NombreUsuarioDisponibleDto(false, ProponerVariante(nombreUsuario, ocupados)));
    }

    /// <summary>Primera variante libre que cabe en el largo máximo; null si no se encuentra.</summary>
    private static string? ProponerVariante(string nombreUsuario, HashSet<string> ocupados)
    {
        for (var numero = 2; numero <= MaxVariantes; numero++)
        {
            var sufijo = numero.ToString();
            var baseNombre = nombreUsuario.Length + sufijo.Length > FormatoNombreUsuarioMovil.MaxLongitud
                ? nombreUsuario[..(FormatoNombreUsuarioMovil.MaxLongitud - sufijo.Length)]
                : nombreUsuario;
            var candidato = baseNombre + sufijo;

            if (!ocupados.Contains(candidato))
                return candidato;
        }
        return null;
    }
}

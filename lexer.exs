# Parte el texto de la expresión en tokens {tipo, texto}.
# Los tipos son :simbolo, :operador, :abre y :cierra.
defmodule Lexer do
  # los cuatro operadores que entiende el programa
  @operadores ["|", "*", "+", "?"]

  # ---------------------------------------------------------------------------(convierte el texto en una lista de tokens)
  def tokenizar(texto) do
    texto
    # separa el texto caracter por caracter, respetando ε que ocupa 2 bytes
    |> String.graphemes()
    # los espacios del archivo solo separan visualmente, no significan nada
    |> Enum.reject(&(&1 == " "))
    # cada caracter se convierte en un token con su tipo
    |> Enum.map(&clasificar/1)
  end

  # ---------------------------------------------------------------------------(le pone tipo a un solo caracter)
  defp clasificar("("), do: {:abre, "("}
  defp clasificar(")"), do: {:cierra, ")"}
  # si el caracter está en la lista de operadores es un operador
  defp clasificar(caracter) when caracter in @operadores, do: {:operador, caracter}
  # cualquier otra cosa (a, b, 0, 1, ε, ...) es un símbolo del alfabeto
  defp clasificar(caracter), do: {:simbolo, caracter}

  # ---------------------------------------------------------------------------(vuelve a juntar los tokens en un texto)
  def a_texto(tokens), do: Enum.map_join(tokens, "", fn {_tipo, texto} -> texto end)

  # ---------------------------------------------------------------------------(muestra los tokens separados por espacios)
  def a_lista(tokens), do: Enum.map_join(tokens, " ", fn {_tipo, texto} -> texto end)
end

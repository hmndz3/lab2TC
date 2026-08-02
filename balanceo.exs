defmodule Balanceo do
  @pares %{")" => "(", "]" => "[", "}" => "{"}
  @aperturas ["(", "[", "{"]

  @verde "\e[92m"
  @rojo "\e[91m"
  @gris "\e[90m"
  @negrita "\e[1m"
  @reset "\e[0m"
  @ancho 72

  def analizar(expresion) do
    expresion
    |> String.graphemes()
    |> Enum.with_index(1)
    |> recorrer([], [])
  end

  defp recorrer([], [], pasos), do: {Enum.reverse(pasos), nil}

  defp recorrer([], [{tope, pos} | _], pasos) do
    {Enum.reverse(pasos), "'#{tope}' en la posicion #{pos} nunca se cierra"}
  end

  defp recorrer([{simbolo, pos} | resto], pila, pasos) do
    cond do
      simbolo in @aperturas ->
        nueva = [{simbolo, pos} | pila]
        recorrer(resto, nueva, [{pos, simbolo, "push  #{simbolo}", formato(nueva)} | pasos])

      Map.has_key?(@pares, simbolo) ->
        cerrar(simbolo, pos, resto, pila, pasos)

      true ->
        recorrer(resto, pila, pasos)
    end
  end

  defp cerrar(simbolo, pos, _resto, [], pasos) do
    {Enum.reverse([{pos, simbolo, "error", formato([])} | pasos]),
     "'#{simbolo}' en la posicion #{pos} no tiene apertura"}
  end

  defp cerrar(simbolo, pos, resto, [{tope, pos_tope} | cola] = pila, pasos) do
    if Map.get(@pares, simbolo) == tope do
      recorrer(resto, cola, [{pos, simbolo, "pop   #{tope}", formato(cola)} | pasos])
    else
      {Enum.reverse([{pos, simbolo, "error", formato(pila)} | pasos]),
       "'#{simbolo}' en la posicion #{pos} no cierra a '#{tope}' de la posicion #{pos_tope}"}
    end
  end

  defp formato([]), do: "-"

  defp formato(pila) do
    pila
    |> Enum.reverse()
    |> Enum.map_join(" ", fn {simbolo, _} -> simbolo end)
  end

  def mostrar(numero, expresion, pasos, error) do
    linea = String.duplicate("=", @ancho)
    separador = String.duplicate("-", @ancho)

    IO.puts(@gris <> linea <> @reset)
    IO.puts("#{@negrita}Linea #{numero}#{@reset}  #{expresion}")
    IO.puts(@gris <> separador <> @reset)

    if pasos == [] do
      IO.puts(@gris <> "  (sin simbolos de agrupacion)" <> @reset)
    else
      IO.puts(@gris <> "   Pos  Simbolo Accion      Pila" <> @reset)

      Enum.each(pasos, fn {pos, simbolo, accion, pila} ->
        IO.puts(
          "  #{String.pad_leading(to_string(pos), 4)}  " <>
            "#{String.pad_trailing(simbolo, 8)}" <>
            "#{String.pad_trailing(accion, 12)}#{pila}"
        )
      end)
    end

    IO.puts(@gris <> separador <> @reset)

    case error do
      nil ->
        IO.puts("#{@verde}  BALANCEADA#{@reset}\n")
        true

      motivo ->
        IO.puts("#{@rojo}  NO BALANCEADA  ->  #{motivo}#{@reset}\n")
        false
    end
  end

  def resumen(balanceadas, total) do
    IO.puts(@gris <> String.duplicate("=", @ancho) <> @reset)
    IO.puts("#{@negrita}Resumen:#{@reset} #{balanceadas} de #{total} expresiones balanceadas\n")
  end

  def error_archivo(ruta) do
    IO.puts("#{@rojo}No se encontro el archivo: #{ruta}#{@reset}")
  end

  def encabezado(ruta) do
    IO.puts("\n#{@negrita}Archivo:#{@reset} #{ruta}\n")
  end
end

ruta =
  case System.argv() do
    [argumento | _] -> argumento
    [] -> "expresiones.txt"
  end

case File.read(ruta) do
  {:error, _} ->
    Balanceo.error_archivo(ruta)
    System.halt(1)

  {:ok, contenido} ->
    Balanceo.encabezado(ruta)

    {balanceadas, total} =
      contenido
      |> String.split(~r/\r?\n/)
      |> Enum.with_index(1)
      |> Enum.map(fn {linea, numero} -> {String.trim(linea), numero} end)
      |> Enum.reject(fn {expresion, _} ->
        expresion == "" or String.starts_with?(expresion, "#")
      end)
      |> Enum.reduce({0, 0}, fn {expresion, numero}, {balanceadas, total} ->
        {pasos, error} = Balanceo.analizar(expresion)
        exito = Balanceo.mostrar(numero, expresion, pasos, error)
        {balanceadas + if(exito, do: 1, else: 0), total + 1}
      end)

    Balanceo.resumen(balanceadas, total)
end

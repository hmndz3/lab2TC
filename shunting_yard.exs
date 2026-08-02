defmodule Lexer do
  @operadores ["|", "*", "+", "?", "^"]

  def tokenizar(expresion) do
    expresion |> String.graphemes() |> escanear([])
  end

  defp escanear([], acc), do: Enum.reverse(acc)

  defp escanear(["\\", c | resto], acc), do: escanear(resto, [{:lit, "\\" <> c} | acc])

  defp escanear(["[" | resto], acc) do
    {clase, siguiente} = leer_clase(resto, "[")
    escanear(siguiente, [{:lit, clase} | acc])
  end

  defp escanear(["(" | resto], acc), do: escanear(resto, [{:abre, "("} | acc])
  defp escanear([")" | resto], acc), do: escanear(resto, [{:cierra, ")"} | acc])
  defp escanear([" " | resto], acc), do: escanear(resto, acc)

  defp escanear([c | resto], acc) do
    tipo = if c in @operadores, do: :op, else: :lit
    escanear(resto, [{tipo, c} | acc])
  end

  defp leer_clase([], acc), do: {acc, []}
  defp leer_clase(["\\", c | resto], acc), do: leer_clase(resto, acc <> "\\" <> c)
  defp leer_clase(["]" | resto], acc), do: {acc <> "]", resto}
  defp leer_clase([c | resto], acc), do: leer_clase(resto, acc <> c)
end

defmodule Extensiones do
  @epsilon {:lit, "ε"}
  @abre {:abre, "("}
  @cierra {:cierra, ")"}

  def expandir(tokens), do: recorrer(tokens, [[]])

  defp recorrer([], [nivel]), do: aplanar(nivel)

  defp recorrer([{:abre, _} | resto], niveles), do: recorrer(resto, [[] | niveles])

  defp recorrer([{:cierra, _} | resto], [nivel, padre | otros]) do
    grupo = nivel |> aplanar() |> agrupar()
    recorrer(resto, [[grupo | padre] | otros])
  end

  defp recorrer([{:op, "*"} | resto], [[ultimo | previos] | otros]) do
    recorrer(resto, [[ultimo ++ [{:op, "*"}] | previos] | otros])
  end

  defp recorrer([{:op, "+"} | resto], [[ultimo | previos] | otros]) do
    copia = envolver(ultimo)
    recorrer(resto, [[copia ++ copia ++ [{:op, "*"}] | previos] | otros])
  end

  defp recorrer([{:op, "?"} | resto], [[ultimo | previos] | otros]) do
    opcional = [@abre] ++ ultimo ++ [{:op, "|"}, @epsilon, @cierra]
    recorrer(resto, [[opcional | previos] | otros])
  end

  defp recorrer([token | resto], [nivel | otros]) do
    recorrer(resto, [[[token] | nivel] | otros])
  end

  defp aplanar(nivel), do: nivel |> Enum.reverse() |> Enum.concat()

  defp agrupar(contenido) do
    if grupo_completo?(contenido), do: contenido, else: [@abre] ++ contenido ++ [@cierra]
  end

  defp envolver([token]), do: [token]
  defp envolver(atomo), do: agrupar(atomo)

  defp grupo_completo?([{:abre, _} | resto]) do
    case Enum.split(resto, -1) do
      {medio, [{:cierra, _}]} -> balanceado?(medio, 0)
      _ -> false
    end
  end

  defp grupo_completo?(_), do: false

  defp balanceado?([], nivel), do: nivel == 0
  defp balanceado?([{:abre, _} | resto], nivel), do: balanceado?(resto, nivel + 1)
  defp balanceado?([{:cierra, _} | _], 0), do: false
  defp balanceado?([{:cierra, _} | resto], nivel), do: balanceado?(resto, nivel - 1)
  defp balanceado?([_ | resto], nivel), do: balanceado?(resto, nivel)
end

defmodule Concatenacion do
  @concat {:op, "·"}

  def insertar(tokens), do: recorrer(tokens, [])

  defp recorrer([], acc), do: Enum.reverse(acc)
  defp recorrer([token], acc), do: Enum.reverse([token | acc])

  defp recorrer([a, b | resto], acc) do
    nuevo = if cierra?(a) and abre?(b), do: [@concat, a | acc], else: [a | acc]
    recorrer([b | resto], nuevo)
  end

  defp cierra?({:lit, _}), do: true
  defp cierra?({:cierra, _}), do: true
  defp cierra?({:op, op}), do: op in ["*", "+", "?"]
  defp cierra?(_), do: false

  defp abre?({:lit, _}), do: true
  defp abre?({:abre, _}), do: true
  defp abre?(_), do: false
end

defmodule ShuntingYard do
  @precedencias %{"(" => 1, "|" => 2, "·" => 3, "?" => 4, "*" => 4, "+" => 4, "^" => 5}

  def convertir(tokens) do
    {salida, _pila, pasos} = recorrer(tokens, [], [], [])
    {salida |> Enum.reverse() |> Enum.join(), Enum.reverse(pasos)}
  end

  defp recorrer([], salida, [], pasos), do: {salida, [], pasos}

  defp recorrer([], salida, [tope | pila], pasos) do
    nueva = [tope | salida]
    recorrer([], nueva, pila, [paso("fin", "pop #{tope}", pila, nueva) | pasos])
  end

  defp recorrer([{:lit, texto} | resto], salida, pila, pasos) do
    nueva = [texto | salida]
    recorrer(resto, nueva, pila, [paso(texto, "operando", pila, nueva) | pasos])
  end

  defp recorrer([{:abre, _} | resto], salida, pila, pasos) do
    nueva = ["(" | pila]
    recorrer(resto, salida, nueva, [paso("(", "push (", nueva, salida) | pasos])
  end

  defp recorrer([{:cierra, _} | resto], salida, pila, pasos) do
    {salida, pila, pasos} = vaciar_grupo(salida, pila, pasos)
    recorrer(resto, salida, pila, pasos)
  end

  defp recorrer([{:op, op} | resto], salida, pila, pasos) do
    {salida, pila, pasos} = sacar_mayores(op, salida, pila, pasos)
    nueva = [op | pila]
    recorrer(resto, salida, nueva, [paso(op, "push #{op}", nueva, salida) | pasos])
  end

  defp vaciar_grupo(salida, [], pasos), do: {salida, [], pasos}

  defp vaciar_grupo(salida, ["(" | pila], pasos) do
    {salida, pila, [paso(")", "pop ( y descartar", pila, salida) | pasos]}
  end

  defp vaciar_grupo(salida, [tope | pila], pasos) do
    nueva = [tope | salida]
    vaciar_grupo(nueva, pila, [paso(")", "pop #{tope}", pila, nueva) | pasos])
  end

  defp sacar_mayores(op, salida, [tope | pila], pasos) when tope != "(" do
    if precedencia(tope) >= precedencia(op) do
      nueva = [tope | salida]
      sacar_mayores(op, nueva, pila, [paso(op, "pop #{tope}", pila, nueva) | pasos])
    else
      {salida, [tope | pila], pasos}
    end
  end

  defp sacar_mayores(_op, salida, pila, pasos), do: {salida, pila, pasos}

  defp precedencia(op), do: Map.get(@precedencias, op, 0)

  defp paso(token, accion, pila, salida) do
    {token, accion, formato_pila(pila), formato_salida(salida)}
  end

  defp formato_pila([]), do: "-"
  defp formato_pila(pila), do: pila |> Enum.reverse() |> Enum.join(" ")

  defp formato_salida([]), do: "-"
  defp formato_salida(salida), do: salida |> Enum.reverse() |> Enum.join()
end

defmodule Reporte do
  @verde "\e[92m"
  @cian "\e[96m"
  @gris "\e[90m"
  @negrita "\e[1m"
  @reset "\e[0m"
  @ancho 78

  def procesar(numero, expresion, opciones) do
    tokens = Lexer.tokenizar(expresion)
    expandidos = Extensiones.expandir(tokens)
    con_concat = Concatenacion.insertar(expandidos)
    {postfix, pasos} = ShuntingYard.convertir(con_concat)

    IO.puts(@gris <> String.duplicate("=", @ancho) <> @reset)
    IO.puts("#{@negrita}Linea #{numero}#{@reset}  #{expresion}")
    IO.puts(@gris <> String.duplicate("-", @ancho) <> @reset)

    campo("Tokens", Enum.map_join(tokens, " ", &texto/1))
    campo("Sin + ni ?", Enum.map_join(expandidos, "", &texto/1))
    campo("Con concat", Enum.map_join(con_concat, "", &texto/1))
    campo("Pasos", "#{length(pasos)}")

    if not Keyword.get(opciones, :resumen, false) do
      IO.puts("")
      tabla(pasos)
    end

    IO.puts("")
    IO.puts("#{@verde}#{@negrita}  Postfix:#{@reset}#{@verde} #{postfix}#{@reset}\n")
  end

  def pausa do
    IO.write("#{@gris}  -- Enter para continuar --#{@reset}")
    IO.gets("")
  end

  def encabezado(ruta) do
    IO.puts("\n#{@negrita}Archivo:#{@reset} #{ruta}")
    IO.puts("#{@gris}Opciones: --pausa   --resumen   --linea N#{@reset}\n")
  end

  def no_encontrado(ruta), do: IO.puts("\e[91mNo se encontro el archivo: #{ruta}\e[0m")

  defp campo(etiqueta, valor) do
    IO.puts("  #{@cian}#{col(etiqueta <> ":", 13)}#{@reset}#{valor}")
  end

  defp texto({_tipo, valor}), do: valor

  defp tabla(pasos) do
    IO.puts(@gris <> "  #{col("Token", 8)}#{col("Accion", 20)}#{col("Pila", 20)}Salida" <> @reset)

    Enum.each(pasos, fn {token, accion, pila, salida} ->
      IO.puts("  #{col(token, 8)}#{col(accion, 20)}#{col(pila, 20)}#{salida}")
    end)
  end

  defp col(valor, ancho), do: String.pad_trailing(valor, ancho)
end

{opciones, argumentos, _} =
  OptionParser.parse(System.argv(),
    strict: [pausa: :boolean, resumen: :boolean, linea: :integer]
  )

ruta = List.first(argumentos) || "expresiones.txt"

case File.read(ruta) do
  {:error, _} ->
    Reporte.no_encontrado(ruta)
    System.halt(1)

  {:ok, contenido} ->
    Reporte.encabezado(ruta)

    expresiones =
      contenido
      |> String.split(~r/\r?\n/)
      |> Enum.with_index(1)
      |> Enum.map(fn {linea, numero} -> {String.trim(linea), numero} end)
      |> Enum.reject(fn {expresion, _} ->
        expresion == "" or String.starts_with?(expresion, "#")
      end)

    seleccion =
      case opciones[:linea] do
        nil -> expresiones
        n -> Enum.filter(expresiones, fn {_, numero} -> numero == n end)
      end

    total = length(seleccion)

    seleccion
    |> Enum.with_index(1)
    |> Enum.each(fn {{expresion, numero}, indice} ->
      Reporte.procesar(numero, expresion, opciones)
      if opciones[:pausa] && indice < total, do: Reporte.pausa()
    end)
end


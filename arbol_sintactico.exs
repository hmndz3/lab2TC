# Programa principal. Por cada línea del archivo hace el recorrido completo:
# texto -> tokens -> concatenación -> postfix -> árbol -> simplificado -> dibujo.
#
# Uso:  elixir arbol_sintactico.exs [archivo] [--linea N] [--png] [--sin-ventana]

# se cargan los otros archivos del proyecto, en el orden en que se necesitan
Code.require_file("lexer.exs", __DIR__)
Code.require_file("shunting_yard.exs", __DIR__)
Code.require_file("arbol.exs", __DIR__)
Code.require_file("ventana.exs", __DIR__)

# Todo lo que se imprime en la consola, aparte para que la lógica no se llene
# de IO.puts.
defmodule Reporte do
  @verde "\e[92m"
  @cian "\e[96m"
  @gris "\e[90m"
  @rojo "\e[91m"
  @negrita "\e[1m"
  @normal "\e[0m"
  @ancho 76

  # ---------------------------------------------------------------------------(escribe el encabezado de una expresión)
  def encabezado(numero, expresion) do
    IO.puts("\n" <> @gris <> String.duplicate("=", @ancho) <> @normal)
    IO.puts("#{@negrita}Expresión #{numero}#{@normal}   #{expresion}")
    IO.puts(@gris <> String.duplicate("=", @ancho) <> @normal)
  end

  # ---------------------------------------------------------------------------(escribe un paso numerado del proceso)
  def paso(numero, titulo) do
    IO.puts("\n#{@cian}#{numero}) #{titulo}#{@normal}")
  end

  # ---------------------------------------------------------------------------(escribe una línea con sangría)
  def linea(texto), do: IO.puts("    " <> texto)

  # ---------------------------------------------------------------------------(escribe el resultado importante resaltado)
  def resultado(etiqueta, valor) do
    IO.puts("    #{@verde}#{@negrita}#{etiqueta}#{@normal}#{@verde} #{valor}#{@normal}")
  end

  # ---------------------------------------------------------------------------(imprime la tabla de pasos del Shunting Yard)
  def tabla(pasos) do
    IO.puts(@gris <> "    #{col("Token", 8)}#{col("Acción", 20)}#{col("Pila", 22)}Salida" <> @normal)

    Enum.each(pasos, fn {token, accion, pila, salida} ->
      IO.puts("    #{col(token, 8)}#{col(accion, 20)}#{col(pila, 22)}#{salida}")
    end)
  end

  # ---------------------------------------------------------------------------(rellena un texto con espacios hasta cierto ancho)
  defp col(texto, ancho), do: String.pad_trailing(texto, ancho)

  # ---------------------------------------------------------------------------(avisa que el archivo no existe)
  def sin_archivo(ruta) do
    IO.puts("#{@rojo}No se encontró el archivo: #{ruta}#{@normal}")
  end
end

# Une todas las piezas: recibe una expresión en texto e imprime todo el proceso
# hasta el árbol.
defmodule Laboratorio do
  # ---------------------------------------------------------------------------(procesa una expresión de principio a fin)
  def procesar(numero, expresion, opciones) do
    Reporte.encabezado(numero, expresion)

    # --- paso 1: el texto se parte en tokens ---
    tokens = Lexer.tokenizar(expresion)
    Reporte.paso(1, "Tokens reconocidos")
    Reporte.linea(Lexer.a_lista(tokens))

    # --- paso 2: se hace visible la concatenación ---
    con_punto = Concatenacion.insertar(tokens)
    Reporte.paso(2, "Concatenación explícita con ·")
    Reporte.linea(Lexer.a_texto(con_punto))

    # --- paso 3: Shunting Yard, paso por paso ---
    {postfix, pasos} = ShuntingYard.convertir(con_punto)
    Reporte.paso(3, "Shunting Yard (#{length(pasos)} pasos)")
    Reporte.tabla(pasos)

    Reporte.paso(4, "Expresión en postfix")
    Reporte.resultado("Postfix:", Enum.join(postfix))

    # --- paso 5: el postfix se vuelve árbol ---
    arbol = postfix |> Arbol.construir() |> Arbol.numerar()
    Reporte.paso(5, "Árbol sintáctico (#{Arbol.contar(arbol)} nodos)")
    Arbol.imprimir(arbol)

    # --- paso 6: se quitan las extensiones + y ? ---
    simplificado = arbol |> Arbol.simplificar() |> Arbol.numerar()
    bloques = armar_bloques(arbol, simplificado)

    if length(bloques) == 2 do
      Reporte.paso(6, "Árbol simplificado, sin + ni ? (#{Arbol.contar(simplificado)} nodos)")
      Reporte.linea("X+  se cambia por  X·X*      y      X?  se cambia por  X|ε")
      IO.puts("")
      Arbol.imprimir(simplificado)
      Reporte.resultado("Postfix simplificado:", Enum.join(Arbol.a_postfix(simplificado)))
    else
      Reporte.paso(6, "Simplificación")
      Reporte.linea("La expresión no usa + ni ?, el árbol ya estaba simplificado.")
    end

    # --- paso 7: el dibujo ---
    dibujar(numero, expresion, bloques, opciones)
  end

  # ---------------------------------------------------------------------------(decide si hay que dibujar uno o dos árboles)
  defp armar_bloques(arbol, simplificado) do
    if Arbol.a_postfix(arbol) == Arbol.a_postfix(simplificado) do
      # no había + ni ?, así que los dos árboles son el mismo
      [{"Árbol sintáctico", arbol}]
    else
      [
        {"Árbol con las extensiones + y ?", arbol},
        {"Árbol simplificado (solo | · *)", simplificado}
      ]
    end
  end

  # ---------------------------------------------------------------------------(muestra el árbol en pantalla o lo guarda como imagen)
  defp dibujar(numero, expresion, bloques, opciones) do
    cond do
      opciones[:png] ->
        File.mkdir_p!("imagenes")
        ruta = Ventana.guardar(bloques, "imagenes/arbol_#{numero}.png")
        Reporte.paso(7, "Dibujo guardado")
        Reporte.linea(ruta)

      opciones[:sin_ventana] ->
        :ok

      true ->
        Reporte.paso(7, "Dibujo en pantalla")
        Reporte.linea("Cierre la ventana para continuar con la siguiente expresión.")
        Ventana.mostrar(bloques, "Expresión #{numero}:  #{expresion}")
    end
  end
end

# Arranque del programa

# se separan las banderas (--png, --linea 2, ...) del nombre del archivo
{opciones, argumentos, _ignorados} =
  OptionParser.parse(System.argv(),
    strict: [png: :boolean, sin_ventana: :boolean, linea: :integer]
  )

ruta = List.first(argumentos) || "expresiones.txt"

case File.read(ruta) do
  {:error, _motivo} ->
    Reporte.sin_archivo(ruta)
    System.halt(1)

  {:ok, contenido} ->
    expresiones =
      contenido
      # sirve tanto para saltos de línea de Windows como de Linux
      |> String.split(~r/\r?\n/)
      |> Enum.map(&String.trim/1)
      # fuera las líneas vacías y los comentarios
      |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
      |> Enum.with_index(1)

    seleccion =
      case opciones[:linea] do
        nil -> expresiones
        n -> Enum.filter(expresiones, fn {_expresion, numero} -> numero == n end)
      end

    Enum.each(seleccion, fn {expresion, numero} ->
      Laboratorio.procesar(numero, expresion, opciones)
    end)

    IO.puts("")
end

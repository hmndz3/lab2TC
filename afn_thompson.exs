# Programa principal. Por cada línea del archivo hace el recorrido completo:
# texto -> tokens -> postfix -> árbol -> AFN de Thompson -> dibujo -> simulación.
#
# Uso:  elixir afn_thompson.exs [archivo] [--cadena w] [--linea N] [--png] [--sin-ventana]

# se cargan los otros archivos del proyecto, en el orden en que se necesitan
Code.require_file("lexer.exs", __DIR__)
Code.require_file("shunting_yard.exs", __DIR__)
Code.require_file("arbol.exs", __DIR__)
Code.require_file("thompson.exs", __DIR__)
Code.require_file("simulacion.exs", __DIR__)
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
    IO.puts("#{@negrita}Expresión #{numero}#{@normal}   r = #{expresion}")
    IO.puts(@gris <> String.duplicate("=", @ancho) <> @normal)
  end

  # ---------------------------------------------------------------------------(escribe un paso numerado del proceso)
  def paso(numero, titulo), do: IO.puts("\n#{@cian}#{numero}) #{titulo}#{@normal}")

  # ---------------------------------------------------------------------------(escribe una línea con sangría)
  def linea(texto), do: IO.puts("    " <> texto)

  # ---------------------------------------------------------------------------(escribe el resultado importante resaltado)
  def resultado(etiqueta, valor) do
    IO.puts("    #{@verde}#{@negrita}#{etiqueta}#{@normal}#{@verde} #{valor}#{@normal}")
  end

  # ---------------------------------------------------------------------------(imprime una tabla con sus títulos)
  # columnas es una lista de {título, ancho} y filas una lista de listas de texto
  def tabla(columnas, filas) do
    IO.puts(@gris <> "    " <> fila(columnas, Enum.map(columnas, &elem(&1, 0))) <> @normal)
    Enum.each(filas, fn celdas -> IO.puts("    " <> fila(columnas, celdas)) end)
  end

  defp fila(columnas, celdas) do
    columnas
    |> Enum.zip(celdas)
    |> Enum.map_join(fn {{_titulo, ancho}, celda} -> String.pad_trailing(celda, ancho) end)
    |> String.trim_trailing()
  end

  # ---------------------------------------------------------------------------(la respuesta del laboratorio: sí o no)
  def veredicto(cadena, true) do
    IO.puts("    #{@verde}#{@negrita}sí#{@normal}#{@verde}   #{comillas(cadena)} ∈ L(r)#{@normal}")
  end

  def veredicto(cadena, false) do
    IO.puts("    #{@rojo}#{@negrita}no#{@normal}#{@rojo}   #{comillas(cadena)} ∉ L(r)#{@normal}")
  end

  # ---------------------------------------------------------------------------(cómo se escribe una cadena para que se vea)
  # la cadena vacía no se ve entre comillas, así que se muestra como ε
  def comillas(""), do: "w = ε"
  def comillas(cadena), do: ~s(w = "#{cadena}")

  # ---------------------------------------------------------------------------(avisa que el archivo no existe)
  def sin_archivo(ruta), do: IO.puts("#{@rojo}No se encontró el archivo: #{ruta}#{@normal}")
end

# Saca del archivo las expresiones y las cadenas con las que hay que probarlas.
# Cada línea es "expresión ; cadena, cadena, ..." y las cadenas son opcionales.
defmodule Entrada do
  # ---------------------------------------------------------------------------(convierte el texto del archivo en una lista de trabajos)
  def leer(contenido, opciones) do
    contenido
    |> sin_marca()
    # sirve tanto para saltos de línea de Windows como de Linux
    |> String.split(~r/\r?\n/)
    |> Enum.map(&String.trim/1)
    # fuera las líneas vacías y los comentarios
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
    |> Enum.with_index(1)
    |> escoger(opciones[:linea])
    |> Enum.map(fn {linea, numero} -> separar(numero, linea, opciones) end)
  end

  # ---------------------------------------------------------------------------(deja solo la línea que se pidió, si es que se pidió alguna)
  defp escoger(lineas, nil), do: lineas
  defp escoger(lineas, n), do: Enum.filter(lineas, fn {_linea, numero} -> numero == n end)

  # ---------------------------------------------------------------------------(parte la línea en expresión y cadenas)
  defp separar(numero, linea, opciones) do
    {expresion, cadenas} =
      case String.split(linea, ";", parts: 2) do
        [expresion] -> {String.trim(expresion), []}
        [expresion, resto] -> {String.trim(expresion), lista(resto)}
      end

    {numero, expresion, cadenas(cadenas, expresion, opciones)}
  end

  # ---------------------------------------------------------------------------(las cadenas van separadas por comas)
  defp lista(texto) do
    texto |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end

  # ---------------------------------------------------------------------------(decide con qué cadenas se va a probar la expresión)
  defp cadenas(_del_archivo, _expresion, %{cadena: cadena}), do: [cadena]
  defp cadenas([], expresion, _opciones), do: [preguntar(expresion)]
  defp cadenas(del_archivo, _expresion, _opciones), do: del_archivo

  # ---------------------------------------------------------------------------(si nadie dijo la cadena, se le pregunta al usuario)
  defp preguntar(expresion) do
    case IO.gets("\n    cadena w para  #{expresion}  (enter = ε): ") do
      :eof -> ""
      texto -> texto |> sin_marca() |> String.trim()
    end
  end

  # ---------------------------------------------------------------------------(quita la marca invisible que Windows le pone al texto)
  defp sin_marca(texto), do: String.trim_leading(texto, "﻿")
end

# Une todas las piezas: recibe una expresión en texto y una lista de cadenas, e
# imprime todo el proceso hasta decir si cada cadena está en el lenguaje.
defmodule Laboratorio do
  # ---------------------------------------------------------------------------(procesa una expresión de principio a fin)
  def procesar({numero, expresion, cadenas}, opciones) do
    Reporte.encabezado(numero, expresion)

    afn = construir(expresion)
    respuestas = Enum.map(cadenas, &simular(afn, &1))

    dibujar(numero, expresion, afn, respuestas, opciones)
  end

  # ---------------------------------------------------------------------------(de la expresión al AFN, mostrando cada etapa)
  defp construir(expresion) do
    # --- paso 1: el texto se parte en tokens y se le marca la concatenación ---
    tokens = Lexer.tokenizar(expresion)
    con_punto = Concatenacion.insertar(tokens)
    Reporte.paso(1, "Tokens y concatenación explícita")
    Reporte.linea(Lexer.a_lista(tokens))
    Reporte.linea(Lexer.a_texto(con_punto))

    # --- paso 2: Shunting Yard deja la expresión en postfix ---
    postfix = ShuntingYard.convertir(con_punto)
    Reporte.paso(2, "Postfix")
    Reporte.resultado("Postfix:", Enum.join(postfix))

    # --- paso 3: el postfix se vuelve árbol y se le quitan + y ? ---
    arbol = armar_arbol(postfix)

    # --- paso 4: Thompson convierte el árbol en autómata ---
    afn = Thompson.construir(arbol)
    mostrar_afn(afn)
    afn
  end

  # ---------------------------------------------------------------------------(arma el árbol y lo deja solo con | · y *)
  defp armar_arbol(postfix) do
    crudo = Arbol.construir(postfix)
    arbol = crudo |> Arbol.simplificar() |> Arbol.numerar()

    Reporte.paso(3, "Árbol sintáctico (#{Arbol.contar(arbol)} nodos)")

    # Thompson solo sabe de | · y *, así que + y ? se cambian por su equivalente
    if Arbol.a_postfix(crudo) != Arbol.a_postfix(arbol) do
      Reporte.linea("X+  se cambia por  X·X*      y      X?  se cambia por  X|ε")
      Reporte.linea("postfix del árbol: #{Enum.join(Arbol.a_postfix(arbol))}")
    end

    IO.puts("")
    Arbol.imprimir(arbol)
    arbol
  end

  # ---------------------------------------------------------------------------(escribe el AFN: sus estados y su tabla de transiciones)
  defp mostrar_afn(afn) do
    Reporte.paso(
      4,
      "AFN de Thompson (#{length(afn.estados)} estados, #{length(afn.transiciones)} transiciones)"
    )

    Reporte.linea("Estado inicial: #{afn.inicio}       Estado de aceptación: #{afn.aceptacion}")
    Reporte.linea("Alfabeto: #{Enum.join(AFN.alfabeto(afn), ", ")}    (ε no consume nada)")
    IO.puts("")

    filas =
      Enum.map(afn.transiciones, fn {desde, simbolo, hasta} ->
        ["#{desde}", simbolo, "#{hasta}"]
      end)

    Reporte.tabla([{"Desde", 9}, {"Símbolo", 11}, {"Hasta", 7}], filas)
  end

  # ---------------------------------------------------------------------------(corre una cadena en el AFN y muestra el recorrido)
  defp simular(afn, cadena) do
    {acepta?, pasos} = Simulacion.correr(afn, cadena)

    Reporte.paso(5, "Simulación con #{Reporte.comillas(cadena)}")

    filas =
      Enum.map(pasos, fn {leido, conjunto} ->
        [texto_leido(leido), Simulacion.a_texto(conjunto)]
      end)

    Reporte.tabla([{"Leído", 9}, {"Estados posibles", 40}], filas)
    IO.puts("")
    Reporte.veredicto(cadena, acepta?)

    {cadena, acepta?}
  end

  # ---------------------------------------------------------------------------(la primera fila es antes de leer nada)
  defp texto_leido(:inicio), do: "(inicio)"
  defp texto_leido(simbolo), do: simbolo

  # ---------------------------------------------------------------------------(muestra el AFN en pantalla o lo guarda como imagen)
  defp dibujar(numero, expresion, afn, respuestas, opciones) do
    titulo = "AFN de Thompson    r = #{expresion}"
    pie = Enum.map(respuestas, fn {cadena, acepta?} -> nota(cadena, acepta?) end)

    cond do
      opciones[:png] ->
        File.mkdir_p!("imagenes")
        ruta = Ventana.guardar(afn, "imagenes/afn_#{numero}.png", titulo, pie)
        Reporte.paso(6, "Dibujo guardado")
        Reporte.linea(ruta)

      opciones[:sin_ventana] ->
        :ok

      true ->
        Reporte.paso(6, "Dibujo en pantalla")
        Reporte.linea("Cierre la ventana para continuar con la siguiente expresión.")
        Ventana.mostrar(afn, titulo, pie)
    end
  end

  # ---------------------------------------------------------------------------(la línea que va debajo del dibujo)
  defp nota(cadena, acepta?) do
    "#{Reporte.comillas(cadena)}   →   " <> if acepta?, do: "sí", else: "no"
  end
end

# Arranque del programa

# se separan las banderas (--png, --cadena aab, ...) del nombre del archivo
{banderas, argumentos, _ignorados} =
  OptionParser.parse(System.argv(),
    strict: [png: :boolean, sin_ventana: :boolean, linea: :integer, cadena: :string]
  )

opciones = Map.new(banderas)
ruta = List.first(argumentos) || "expresiones.txt"

case File.read(ruta) do
  {:error, _motivo} ->
    Reporte.sin_archivo(ruta)
    System.halt(1)

  {:ok, contenido} ->
    contenido
    |> Entrada.leer(opciones)
    |> Enum.each(&Laboratorio.procesar(&1, opciones))

    IO.puts("")
end

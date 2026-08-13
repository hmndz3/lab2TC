# Dibuja el AFN con :wx, la librería gráfica que ya viene con Erlang/OTP.
#
# Thompson ya dejó dicho en qué fila y qué columna va cada estado, así que aquí
# lo único que se hace es pasar eso a pixeles: un círculo por estado y una
# flecha por transición. Lo mismo sirve para la ventana y para el PNG.
defmodule Ventana do
  @radio 20         # radio del círculo de cada estado
  @paso_x 96        # separación horizontal entre columnas
  @paso_y 86        # separación vertical entre filas
  @margen 30        # espacio en blanco alrededor de todo el dibujo
  @entrada 52       # espacio para la flecha que entra al estado inicial
  @aire 44          # espacio arriba y abajo de los estados, por donde dan la vuelta las flechas largas
  @arco 44          # qué tanto se arquean las flechas que solo esquivan a sus vecinos
  @alto_titulo 46   # espacio que ocupa el título de arriba
  @alto_linea 22    # alto de cada línea del pie
  @formato_png 15   # número con el que wx identifica el formato PNG

  @blanco {255, 255, 255}
  @relleno {223, 236, 252}      # estados normales
  @relleno_inicio {198, 238, 206}    # el estado inicial
  @relleno_aceptacion {255, 216, 168}   # el de aceptación, además con doble círculo
  @borde {60, 60, 70}
  @tinta {25, 25, 25}
  @gris {120, 120, 120}
  @azul {40, 85, 155}           # transiciones que consumen un símbolo
  @epsilon_gris {150, 150, 165} # transiciones ε

  # ---------------------------------------------------------------------------(abre una ventana con el AFN y espera a que la cierren)
  def mostrar(afn, titulo, pie) do
    {ancho, alto} = tamano(afn, titulo, pie)

    wx = :wx.new()

    # la ventana nunca se hace más grande que la pantalla típica
    frame =
      :wxFrame.new(wx, -1, String.to_charlist(titulo), size: {min(ancho, 1350), min(alto, 800)})

    # un ScrolledWindow permite arrastrar si el autómata no cabe completo
    lienzo = :wxScrolledWindow.new(frame)
    :wxScrolledWindow.setScrollbars(lienzo, 20, 20, div(ancho, 20) + 2, div(alto, 20) + 2)
    :wxWindow.setBackgroundColour(lienzo, @blanco)

    # wx avisa con el evento :paint cada vez que hay que redibujar
    :wxScrolledWindow.connect(lienzo, :paint,
      callback: fn _evento, _objeto ->
        dc = :wxPaintDC.new(lienzo)
        # ajusta el origen del dibujo según cuánto se haya arrastrado la barra
        :wxScrolledWindow.doPrepareDC(lienzo, dc)
        pintar(dc, afn, titulo, pie)
        :wxPaintDC.destroy(dc)
      end
    )

    # sin esto la ventana se cerraría pero el programa no se enteraría
    :wxFrame.connect(frame, :close_window)
    :wxFrame.center(frame)
    :wxFrame.show(frame)

    esperar_cierre()

    :wxFrame.destroy(frame)
    :wx.destroy()
  end

  # ---------------------------------------------------------------------------(se queda dormido hasta que el usuario cierra la ventana)
  defp esperar_cierre do
    receive do
      {:wx, _id, _obj, _dato, {:wxClose, :close_window}} -> :ok
    end
  end

  # ---------------------------------------------------------------------------(guarda el AFN en una imagen PNG en vez de mostrarlo)
  def guardar(afn, ruta, titulo, pie) do
    {ancho, alto} = tamano(afn, titulo, pie)

    _wx = :wx.new()

    # se dibuja sobre una imagen en memoria, no sobre una ventana
    imagen = :wxBitmap.new(ancho, alto)
    dc = :wxMemoryDC.new(imagen)
    :wxDC.setBackground(dc, :wxBrush.new(@blanco))
    :wxDC.clear(dc)

    pintar(dc, afn, titulo, pie)

    # hay que soltar el DC antes de guardar, si no la imagen sale incompleta
    :wxMemoryDC.destroy(dc)
    :wxBitmap.saveFile(imagen, String.to_charlist(ruta), @formato_png)
    :wxBitmap.destroy(imagen)
    :wx.destroy()

    ruta
  end

  # ---------------------------------------------------------------------------(cuánto mide el dibujo completo)
  defp tamano(afn, titulo, pie) do
    ancho = 2 * @margen + @entrada + 2 * @radio + round((afn.columnas - 1) * @paso_x)
    alto = 2 * @margen + @alto_titulo + 2 * @aire + 2 * @radio + round((afn.filas - 1) * @paso_y)

    # si el autómata es chiquito, el que manda el ancho es el texto más largo
    letras = [titulo | pie] |> Enum.map(&String.length/1) |> Enum.max()

    {max(ancho, 2 * @margen + 9 * letras), alto + length(pie) * @alto_linea}
  end

  # ---------------------------------------------------------------------------(pinta todo, en el orden en que se debe ver)
  defp pintar(dc, afn, titulo, pie) do
    limites = limites(afn)

    encabezado(dc, titulo)
    # las flechas van primero para que los círculos les queden encima
    Enum.each(afn.transiciones, &transicion(dc, afn, &1, limites))
    Enum.each(afn.estados, &estado(dc, afn, &1))
    flecha_de_entrada(dc, centro(afn, afn.inicio))
    notas(dc, afn, pie)
  end

  # ---------------------------------------------------------------------------(por dónde pueden dar la vuelta las flechas largas)
  # justo por fuera de la primera y de la última fila de estados
  defp limites(afn) do
    %{
      arriba: fila_y(0) - @radio - @aire / 2,
      abajo: fila_y(afn.filas - 1) + @radio + @aire / 2
    }
  end

  # ---------------------------------------------------------------------------(el título de arriba)
  defp encabezado(dc, texto) do
    # 92 = negrita en la escala de pesos de wx
    :wxDC.setFont(dc, :wxFont.new(12, 74, 90, 92))
    :wxDC.setTextForeground(dc, {50, 50, 60})
    :wxDC.drawText(dc, String.to_charlist(texto), {@margen, @margen})
  end

  # ---------------------------------------------------------------------------(las líneas de abajo con el resultado de la simulación)
  defp notas(dc, afn, pie) do
    arriba = fila_y(afn.filas - 1) + @radio + @aire + 4

    :wxDC.setFont(dc, :wxFont.new(10, 74, 90, 400))
    :wxDC.setTextForeground(dc, @gris)

    pie
    |> Enum.with_index()
    |> Enum.each(fn {texto, indice} ->
      :wxDC.drawText(dc, String.to_charlist(texto), {@margen, arriba + indice * @alto_linea})
    end)
  end

  # ---------------------------------------------------------------------------(el círculo de un estado con su número adentro)
  defp estado(dc, afn, estado) do
    {x, y} = centro(afn, estado)

    :wxDC.setBrush(dc, :wxBrush.new(relleno(afn, estado)))
    :wxDC.setPen(dc, :wxPen.new(@borde, width: 2))
    :wxDC.drawCircle(dc, {x, y}, @radio)

    # el de aceptación lleva doble círculo, como en los libros
    if estado == afn.aceptacion, do: :wxDC.drawCircle(dc, {x, y}, @radio - 5)

    :wxDC.setFont(dc, :wxFont.new(12, 74, 90, 92))
    :wxDC.setTextForeground(dc, @tinta)
    texto_centrado(dc, "#{estado}", {x, y})
  end

  # ---------------------------------------------------------------------------(el color de un estado según su papel)
  defp relleno(afn, estado) do
    cond do
      estado == afn.inicio -> @relleno_inicio
      estado == afn.aceptacion -> @relleno_aceptacion
      true -> @relleno
    end
  end

  # ---------------------------------------------------------------------------(la flechita que señala cuál es el estado inicial)
  defp flecha_de_entrada(dc, {x, y}) do
    desde = {x - @radio - @entrada + 14, y}
    hasta = {x - @radio - 2, y}

    :wxDC.setPen(dc, :wxPen.new(@borde, width: 2))
    :wxDC.drawLine(dc, redondear(desde), redondear(hasta))
    punta(dc, @borde, desde, hasta)

    :wxDC.setFont(dc, :wxFont.new(9, 74, 90, 400))
    :wxDC.setTextForeground(dc, @gris)
    :wxDC.drawText(dc, ~c"inicio", {x - @radio - @entrada + 12, y - 24})
  end

  # ---------------------------------------------------------------------------(la flecha de una transición, con su símbolo encima)
  defp transicion(dc, afn, {desde, simbolo, hasta}, limites) do
    origen = centro(afn, desde)
    destino = centro(afn, hasta)
    color = if AFN.epsilon?(simbolo), do: @epsilon_gris, else: @azul

    puntos = curva(origen, destino, limites)

    # se le quitan los pedazos que quedarían tapados por los dos círculos
    visibles =
      puntos
      |> Enum.reject(&(pegado?(&1, origen) or pegado?(&1, destino)))
      |> asegurar_dos(origen, destino)

    :wxDC.setPen(dc, :wxPen.new(color, width: 2))
    :wxDC.drawLines(dc, Enum.map(visibles, &redondear/1))
    punta(dc, color, Enum.at(visibles, -2), Enum.at(visibles, -1))

    etiqueta(dc, simbolo, color, medio(puntos))
  end

  # ---------------------------------------------------------------------------(si no sobró línea entre los dos círculos, se deja un trocito)
  defp asegurar_dos([_, _ | _] = visibles, _origen, _destino), do: visibles
  defp asegurar_dos(_pocos, origen, destino), do: [origen, destino]

  # ---------------------------------------------------------------------------(los puntos por donde pasa la flecha)
  # la forma la decide el punto de control:
  #   * los regresos del * se van por abajo y los saltos largos por arriba,
  #     rodeando todos los estados para no pasarles encima
  #   * los regresos cortos hacen una pancita hacia abajo
  #   * el resto son líneas rectas
  defp curva({x1, y1} = origen, {x2, y2} = destino, limites) do
    avance = x2 - x1
    # un salto de más de tres columnas ya no cabe por el hueco entre dos filas
    muy_largo = abs(avance) > 3.5 * @paso_x
    salto = avance > 1.3 * @paso_x
    misma_fila = abs(y2 - y1) < 4

    control =
      cond do
        avance <= 0 and muy_largo -> control_para(origen, destino, limites.abajo)
        avance <= 0 -> {(x1 + x2) / 2, (y1 + y2) / 2 + @arco}
        misma_fila and muy_largo -> control_para(origen, destino, limites.arriba)
        misma_fila and salto -> {(x1 + x2) / 2, y1 - @arco}
        true -> {(x1 + x2) / 2, (y1 + y2) / 2}
      end

    # se parte la curva en pedacitos para poder dibujarla con líneas rectas
    Enum.map(0..24, &bezier(origen, control, destino, &1 / 24))
  end

  # ---------------------------------------------------------------------------(el punto de control para que la curva pase por cierta altura)
  # en la mitad la curva queda a un cuarto de cada punta y a la mitad del
  # control, así que el control tiene que ir al doble de lejos
  defp control_para({x1, y1}, {x2, y2}, altura) do
    {(x1 + x2) / 2, 2 * altura - (y1 + y2) / 2}
  end

  # ---------------------------------------------------------------------------(un punto de la curva, con t entre 0 y 1)
  defp bezier({x1, y1}, {cx, cy}, {x2, y2}, t) do
    resto = 1 - t
    {resto * resto * x1 + 2 * resto * t * cx + t * t * x2,
     resto * resto * y1 + 2 * resto * t * cy + t * t * y2}
  end

  # ---------------------------------------------------------------------------(el triangulito del final de la flecha)
  defp punta(dc, color, {x1, y1}, {x2, y2}) do
    {dx, dy} = unitario({x2 - x1, y2 - y1})
    # la base del triángulo va 12 pixeles atrás, y sus esquinas a los lados
    {bx, by} = {x2 - dx * 12, y2 - dy * 12}

    :wxDC.setBrush(dc, :wxBrush.new(color))
    :wxDC.setPen(dc, :wxPen.new(color, width: 1))

    :wxDC.drawPolygon(dc, [
      redondear({x2, y2}),
      redondear({bx - dy * 5, by + dx * 5}),
      redondear({bx + dy * 5, by - dx * 5})
    ])
  end

  # ---------------------------------------------------------------------------(el símbolo escrito sobre la flecha)
  defp etiqueta(dc, simbolo, color, {x, y}) do
    :wxDC.setFont(dc, :wxFont.new(11, 74, 90, 92))
    {ancho, alto} = :wxDC.getTextExtent(dc, String.to_charlist(simbolo))

    # un recuadro blanco debajo para que la línea no cruce la letra
    :wxDC.setBrush(dc, :wxBrush.new(@blanco))
    :wxDC.setPen(dc, :wxPen.new(@blanco, width: 1))
    :wxDC.drawRectangle(dc, {round(x) - div(ancho, 2) - 3, round(y) - div(alto, 2), ancho + 6, alto})

    :wxDC.setTextForeground(dc, color)
    texto_centrado(dc, simbolo, {x, y})
  end

  # ---------------------------------------------------------------------------(escribe un texto centrado en un punto)
  defp texto_centrado(dc, texto, {x, y}) do
    letras = String.to_charlist(texto)
    # se mide el texto para poder centrarlo de verdad y no a ojo
    {ancho, alto} = :wxDC.getTextExtent(dc, letras)
    :wxDC.drawText(dc, letras, {round(x) - div(ancho, 2), round(y) - div(alto, 2)})
  end

  # ---------------------------------------------------------------------------(pasa de fila y columna a coordenadas en pixeles)
  defp centro(afn, estado) do
    {columna, fila} = Map.fetch!(afn.posiciones, estado)
    {@margen + @entrada + @radio + round(columna * @paso_x), fila_y(fila)}
  end

  defp fila_y(fila), do: @margen + @alto_titulo + @aire + @radio + round(fila * @paso_y)

  # ---------------------------------------------------------------------------(dice si un punto caería dentro de un círculo)
  defp pegado?({x, y}, {cx, cy}), do: :math.sqrt(:math.pow(x - cx, 2) + :math.pow(y - cy, 2)) < @radio + 3

  # ---------------------------------------------------------------------------(el punto de en medio de la flecha)
  defp medio(puntos), do: Enum.at(puntos, div(length(puntos), 2))

  # ---------------------------------------------------------------------------(un vector de largo 1, para saber hacia dónde apunta la flecha)
  defp unitario({dx, dy}) do
    largo = max(:math.sqrt(dx * dx + dy * dy), 0.001)
    {dx / largo, dy / largo}
  end

  # ---------------------------------------------------------------------------(wx solo entiende coordenadas enteras)
  defp redondear({x, y}), do: {round(x), round(y)}
end

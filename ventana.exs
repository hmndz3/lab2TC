# Dibuja el árbol con :wx, la librería gráfica que ya viene con Erlang/OTP.
# Primero acomodar le da columna y nivel a cada nodo, después pintar los
# convierte en pixeles. Lo mismo sirve para la ventana y para el PNG.
defmodule Ventana do
  @radio 20        # radio del círculo de cada nodo
  @paso_x 64       # separación horizontal entre columnas
  @paso_y 78       # separación vertical entre niveles
  @margen 30       # espacio en blanco alrededor de todo el dibujo
  @alto_titulo 34  # espacio que ocupa el título de cada árbol
  @separacion 30   # aire entre un árbol y el título del siguiente
  @formato_png 15  # número con el que wx identifica el formato PNG

  # un color de relleno por cada tipo de nodo, para distinguirlos de un vistazo
  @colores %{
    "simbolo" => {189, 220, 255},
    "union" => {255, 214, 165},
    "concatenacion" => {186, 235, 197},
    "estrella" => {214, 198, 255},
    "mas" => {255, 189, 189},
    "opcional" => {255, 189, 189}
  }

  # ---------------------------------------------------------------------------(abre una ventana con los árboles y espera a que la cierren)
  def mostrar(bloques, titulo) do
    planos = preparar(bloques)
    {ancho, alto} = tamano(planos)

    wx = :wx.new()

    # la ventana nunca se hace más grande que la pantalla típica
    frame =
      :wxFrame.new(wx, -1, String.to_charlist(titulo),
        size: {min(ancho, 1350), min(alto, 800)}
      )

    # un ScrolledWindow permite arrastrar si el árbol no cabe completo
    lienzo = :wxScrolledWindow.new(frame)
    :wxScrolledWindow.setScrollbars(lienzo, 20, 20, div(ancho, 20) + 2, div(alto, 20) + 2)
    :wxWindow.setBackgroundColour(lienzo, {255, 255, 255})

    # wx avisa con el evento :paint cada vez que hay que redibujar
    :wxScrolledWindow.connect(lienzo, :paint,
      callback: fn _evento, _objeto ->
        dc = :wxPaintDC.new(lienzo)
        # ajusta el origen del dibujo según cuánto se haya arrastrado la barra
        :wxScrolledWindow.doPrepareDC(lienzo, dc)
        pintar(dc, planos)
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

  # ---------------------------------------------------------------------------(guarda los árboles en una imagen PNG en vez de mostrarlos)
  def guardar(bloques, ruta) do
    planos = preparar(bloques)
    {ancho, alto} = tamano(planos)

    _wx = :wx.new()

    # se dibuja sobre una imagen en memoria, no sobre una ventana
    imagen = :wxBitmap.new(ancho, alto)
    dc = :wxMemoryDC.new(imagen)
    :wxDC.setBackground(dc, :wxBrush.new({255, 255, 255}))
    :wxDC.clear(dc)

    pintar(dc, planos)

    # hay que soltar el DC antes de guardar, si no la imagen sale incompleta
    :wxMemoryDC.destroy(dc)
    :wxBitmap.saveFile(imagen, String.to_charlist(ruta), @formato_png)
    :wxBitmap.destroy(imagen)
    :wx.destroy()

    ruta
  end

  # ---------------------------------------------------------------------------(calcula posiciones y medidas de cada árbol antes de pintar)
  defp preparar(bloques) do
    Enum.map(bloques, fn {titulo, nodo} ->
      {posiciones, columnas, niveles} = acomodar(nodo)

      %{
        titulo: titulo,
        nodo: nodo,
        posiciones: posiciones,
        ancho: columnas * @paso_x,
        alto: @alto_titulo + niveles * @paso_y + @separacion
      }
    end)
  end

  # ---------------------------------------------------------------------------(suma el tamaño de todos los árboles juntos)
  defp tamano(planos) do
    # el ancho lo manda el árbol más ancho; el alto es la suma de todos
    ancho = planos |> Enum.map(& &1.ancho) |> Enum.max()
    alto = planos |> Enum.map(& &1.alto) |> Enum.sum()
    {ancho + 2 * @margen, alto + 2 * @margen}
  end

  # ---------------------------------------------------------------------------(le da columna y nivel a cada nodo del árbol)
  def acomodar(nodo) do
    {posiciones, columnas} = ubicar(nodo, 0, 0, %{})

    niveles =
      posiciones
      |> Map.values()
      |> Enum.map(fn {_columna, nivel} -> nivel end)
      |> Enum.max()

    {posiciones, columnas, niveles + 1}
  end

  # ---------------------------------------------------------------------------(recorre el árbol repartiendo las columnas)
  # las hojas se van poniendo una tras otra de izquierda a derecha, y cada
  # padre queda centrado justo encima de sus hijos
  defp ubicar(nodo, nivel, columna, posiciones) do
    case Arbol.hijos(nodo) do
      # una hoja ocupa su propia columna y deja libre la siguiente
      [] ->
        {Map.put(posiciones, nodo.id, {columna, nivel}), columna + 1}

      hijos ->
        # primero se acomodan todos los hijos, uno después del otro
        {posiciones, siguiente} =
          Enum.reduce(hijos, {posiciones, columna}, fn hijo, {mapa, libre} ->
            ubicar(hijo, nivel + 1, libre, mapa)
          end)

        # el padre se pone en el punto medio entre el primer y el último hijo
        columnas = Enum.map(hijos, fn hijo -> elem(Map.fetch!(posiciones, hijo.id), 0) end)
        propia = (Enum.min(columnas) + Enum.max(columnas)) / 2

        {Map.put(posiciones, nodo.id, {propia, nivel}), siguiente}
    end
  end

  # ---------------------------------------------------------------------------(pinta todos los árboles uno debajo del otro)
  defp pintar(dc, planos) do
    Enum.reduce(planos, @margen, fn plano, arriba ->
      titulo(dc, plano.titulo, arriba)
      # las líneas se pintan primero para que los círculos queden encima
      lineas(dc, plano.nodo, plano.posiciones, arriba + @alto_titulo)
      circulos(dc, plano.nodo, plano.posiciones, arriba + @alto_titulo)
      # el siguiente árbol empieza donde termina este
      arriba + plano.alto
    end)
  end

  # ---------------------------------------------------------------------------(escribe el título de un árbol)
  defp titulo(dc, texto, arriba) do
    # 92 = negrita en la escala de pesos de wx
    :wxDC.setFont(dc, :wxFont.new(11, 74, 90, 92))
    :wxDC.setTextForeground(dc, {60, 60, 60})
    :wxDC.drawText(dc, String.to_charlist(texto), {@margen, arriba})
  end

  # ---------------------------------------------------------------------------(pinta las líneas que unen cada padre con sus hijos)
  defp lineas(dc, nodo, posiciones, arriba) do
    :wxDC.setPen(dc, :wxPen.new({120, 120, 120}, width: 2))

    Enum.each(Arbol.hijos(nodo), fn hijo ->
      :wxDC.drawLine(dc, centro(posiciones, nodo, arriba), centro(posiciones, hijo, arriba))
      # y lo mismo para los hijos de ese hijo, hasta llegar a las hojas
      lineas(dc, hijo, posiciones, arriba)
    end)
  end

  # ---------------------------------------------------------------------------(pinta el círculo y la etiqueta de cada nodo)
  defp circulos(dc, nodo, posiciones, arriba) do
    {x, y} = centro(posiciones, nodo, arriba)

    # el color depende del tipo de nodo
    :wxDC.setBrush(dc, :wxBrush.new(Map.fetch!(@colores, Arbol.tipo(nodo))))
    :wxDC.setPen(dc, :wxPen.new({70, 70, 70}, width: 2))
    :wxDC.drawCircle(dc, {x, y}, @radio)

    etiqueta(dc, Arbol.etiqueta(nodo), x, y)
    numero(dc, nodo.id, x, y)

    Enum.each(Arbol.hijos(nodo), &circulos(dc, &1, posiciones, arriba))
  end

  # ---------------------------------------------------------------------------(escribe el símbolo centrado dentro del círculo)
  defp etiqueta(dc, texto, x, y) do
    letras = String.to_charlist(texto)
    :wxDC.setFont(dc, :wxFont.new(13, 74, 90, 92))
    :wxDC.setTextForeground(dc, {20, 20, 20})
    # se mide el texto para poder centrarlo de verdad y no a ojo
    {ancho, alto} = :wxDC.getTextExtent(dc, letras)
    :wxDC.drawText(dc, letras, {x - div(ancho, 2), y - div(alto, 2)})
  end

  # ---------------------------------------------------------------------------(escribe el número del nodo al lado del círculo)
  defp numero(dc, id, x, y) do
    letras = String.to_charlist("#{id}")
    :wxDC.setFont(dc, :wxFont.new(8, 74, 90, 400))
    :wxDC.setTextForeground(dc, {150, 150, 150})
    # va abajo y a la derecha para no chocar con la línea que baja al hijo
    :wxDC.drawText(dc, letras, {x + @radio - 4, y + @radio - 6})
  end

  # ---------------------------------------------------------------------------(pasa de columna y nivel a coordenadas en pixeles)
  defp centro(posiciones, nodo, arriba) do
    {columna, nivel} = Map.fetch!(posiciones, nodo.id)
    # la columna puede ser un decimal (padre centrado), por eso se redondea
    {@margen + round(columna * @paso_x) + div(@paso_x, 2), arriba + nivel * @paso_y + div(@paso_y, 2)}
  end
end

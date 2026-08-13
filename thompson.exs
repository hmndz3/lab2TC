# El autómata que sale de aplicar Thompson: los estados son números, las
# transiciones son {desde, símbolo, hasta} y siempre hay un solo estado inicial
# y uno solo de aceptación.
#
# En posiciones viene además la fila y la columna que le toca a cada estado en
# el dibujo. Se guarda aquí porque quien conoce la forma del autómata es la
# construcción, no el que pinta.
defmodule AFN do
  defstruct [:inicio, :aceptacion, :estados, :transiciones, :posiciones, :columnas, :filas]

  # la transición que no consume nada de la cadena
  @epsilon "ε"

  # ---------------------------------------------------------------------------(el símbolo de la transición vacía)
  def epsilon, do: @epsilon

  def epsilon?(simbolo), do: simbolo == @epsilon

  # ---------------------------------------------------------------------------(los símbolos que sí se consumen, sin repetir)
  def alfabeto(%AFN{transiciones: transiciones}) do
    transiciones
    |> Enum.map(fn {_desde, simbolo, _hasta} -> simbolo end)
    |> Enum.reject(&epsilon?/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  # ---------------------------------------------------------------------------(a dónde se llega desde un conjunto de estados con un símbolo)
  def destinos(%AFN{transiciones: transiciones}, estados, simbolo) do
    for {desde, s, hasta} <- transiciones, s == simbolo, desde in estados, do: hasta
  end
end

# Construcción de Thompson: cada nodo del árbol se cambia por un pedacito de
# autómata con una sola entrada y una sola salida, y esos pedacitos se van
# pegando con transiciones ε hasta llegar a la raíz.
#
# Un fragmento es ese pedacito a medio armar:
#
#   %{inicio, fin, transiciones, posiciones, ancho, alto}
#
# ancho y alto se miden en columnas y filas, no en pixeles, y el inicio y el fin
# siempre quedan en la fila de en medio del fragmento. Gracias a eso pegar dos
# fragmentos es solo correr uno a la derecha del otro.
defmodule Thompson do
  alias Nodo.{Simbolo, Union, Concatenacion, Estrella, Mas, Opcional}

  @epsilon AFN.epsilon()

  # ---------------------------------------------------------------------------(arma el AFN completo a partir del árbol)
  def construir(arbol) do
    {fragmento, total} = fragmento(arbol, 0)

    %AFN{
      inicio: fragmento.inicio,
      aceptacion: fragmento.fin,
      estados: Enum.to_list(0..(total - 1)),
      transiciones: fragmento.transiciones,
      posiciones: fragmento.posiciones,
      columnas: fragmento.ancho,
      filas: fragmento.alto
    }
    |> renumerar()
  end

  # ---------------------------------------------------------------------------(un símbolo: dos estados y una flecha entre ellos)
  #   ──(n)──a──>(n+1)
  # si el símbolo es ε la flecha queda siendo justamente una transición vacía
  defp fragmento(%Simbolo{valor: valor}, n) do
    {%{
       inicio: n,
       fin: n + 1,
       transiciones: [{n, valor, n + 1}],
       posiciones: %{n => {0, 0}, n + 1 => {1, 0}},
       ancho: 2,
       alto: 1
     }, n + 2}
  end

  # ---------------------------------------------------------------------------(concatenación: el fin del primero se pega con el inicio del segundo)
  #   ──[ izquierda ]──ε──>[ derecha ]──>
  defp fragmento(%Concatenacion{izquierda: izquierda, derecha: derecha}, n) do
    {a, n} = fragmento(izquierda, n)
    {b, n} = fragmento(derecha, n)

    alto = max(a.alto, b.alto)

    # los dos van uno detrás del otro, centrados para que la ε salga derechita
    posiciones =
      Map.merge(
        mover(a.posiciones, 0, (alto - a.alto) / 2),
        mover(b.posiciones, a.ancho, (alto - b.alto) / 2)
      )

    {%{
       inicio: a.inicio,
       fin: b.fin,
       transiciones: a.transiciones ++ b.transiciones ++ [{a.fin, @epsilon, b.inicio}],
       posiciones: posiciones,
       ancho: a.ancho + b.ancho,
       alto: alto
     }, n}
  end

  # ---------------------------------------------------------------------------(unión: un estado que se abre en dos caminos y otro donde se vuelven a juntar)
  #          ε──>[ izquierda ]──ε
  #   ──>(i)                      (f)──>
  #          ε──>[  derecha  ]──ε
  defp fragmento(%Union{izquierda: izquierda, derecha: derecha}, n) do
    {a, n} = fragmento(izquierda, n)
    {b, n} = fragmento(derecha, n)
    {inicio, fin} = {n, n + 1}

    alto = a.alto + b.alto
    interior = max(a.ancho, b.ancho)
    ancho = interior + 2
    # la fila de en medio, donde van el estado que abre y el que cierra
    medio = (alto - 1) / 2

    # una rama arriba y la otra abajo, las dos centradas entre los dos estados nuevos
    posiciones =
      a.posiciones
      |> mover(1 + (interior - a.ancho) / 2, 0)
      |> Map.merge(mover(b.posiciones, 1 + (interior - b.ancho) / 2, a.alto))
      |> Map.put(inicio, {0, medio})
      |> Map.put(fin, {ancho - 1, medio})

    transiciones =
      a.transiciones ++
        b.transiciones ++
        [
          {inicio, @epsilon, a.inicio},
          {inicio, @epsilon, b.inicio},
          {a.fin, @epsilon, fin},
          {b.fin, @epsilon, fin}
        ]

    {%{
       inicio: inicio,
       fin: fin,
       transiciones: transiciones,
       posiciones: posiciones,
       ancho: ancho,
       alto: alto
     }, n + 2}
  end

  # ---------------------------------------------------------------------------(estrella: se puede entrar, dar vueltas y salir sin entrar)
  #        ┌───────── ε ─────────┐        el de arriba se salta el hijo
  #   ──>(i)──ε──>[ hijo ]──ε──>(f)
  #             └──── ε ────┘             el de abajo lo repite
  defp fragmento(%Estrella{hijo: hijo}, n) do
    {a, n} = fragmento(hijo, n)
    {inicio, fin} = {n, n + 1}

    ancho = a.ancho + 2
    medio = (a.alto - 1) / 2

    posiciones =
      a.posiciones
      |> mover(1, 0)
      |> Map.put(inicio, {0, medio})
      |> Map.put(fin, {ancho - 1, medio})

    transiciones =
      a.transiciones ++
        [
          {inicio, @epsilon, a.inicio},
          {a.fin, @epsilon, fin},
          {a.fin, @epsilon, a.inicio},
          {inicio, @epsilon, fin}
        ]

    {%{
       inicio: inicio,
       fin: fin,
       transiciones: transiciones,
       posiciones: posiciones,
       ancho: ancho,
       alto: a.alto
     }, n + 2}
  end

  # ---------------------------------------------------------------------------(+ y ? no tienen construcción propia)
  # se cambian por lo mismo de siempre, X+ = X·X* y X? = X|ε, y ya el árbol
  # simplificado sí sabe construirse
  defp fragmento(%Mas{} = nodo, n), do: fragmento(Arbol.simplificar(nodo), n)
  defp fragmento(%Opcional{} = nodo, n), do: fragmento(Arbol.simplificar(nodo), n)

  # ---------------------------------------------------------------------------(corre un fragmento entero a otra columna y otra fila)
  defp mover(posiciones, dx, dy) do
    Map.new(posiciones, fn {estado, {columna, fila}} -> {estado, {columna + dx, fila + dy}} end)
  end

  # ---------------------------------------------------------------------------(vuelve a numerar los estados siguiendo el dibujo)
  # los estados se crean de adentro hacia afuera, así que los números salen
  # revueltos; aquí el de más a la izquierda pasa a ser el 0 y así hasta el final
  defp renumerar(%AFN{} = afn) do
    nuevo =
      afn.posiciones
      |> Enum.sort_by(fn {_estado, posicion} -> posicion end)
      |> Enum.with_index()
      |> Map.new(fn {{estado, _posicion}, indice} -> {estado, indice} end)

    %AFN{
      afn
      | inicio: nuevo[afn.inicio],
        aceptacion: nuevo[afn.aceptacion],
        posiciones: Map.new(afn.posiciones, fn {estado, p} -> {nuevo[estado], p} end),
        transiciones:
          afn.transiciones
          |> Enum.map(fn {desde, simbolo, hasta} -> {nuevo[desde], simbolo, nuevo[hasta]} end)
          |> Enum.sort()
    }
  end
end

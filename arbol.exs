# Un struct distinto por cada tipo de nodo, así el tipo del objeto ya dice qué
# operación representa. El id se asigna al final, con Arbol.numerar.

# hoja del árbol: una letra, un dígito o ε
defmodule Nodo.Simbolo, do: defstruct([:id, :valor])

# unión, el operador |
defmodule Nodo.Union, do: defstruct([:id, :izquierda, :derecha])

# concatenación, el operador ·
defmodule Nodo.Concatenacion, do: defstruct([:id, :izquierda, :derecha])

# cerradura de Kleene, el operador *
defmodule Nodo.Estrella, do: defstruct([:id, :hijo])

# cerradura positiva, el operador + (desaparece al simplificar)
defmodule Nodo.Mas, do: defstruct([:id, :hijo])

# opcional, el operador ? (desaparece al simplificar)
defmodule Nodo.Opcional, do: defstruct([:id, :hijo])

# Todo lo que se le hace al árbol: construirlo desde el postfix, simplificar
# + y ?, numerar los nodos e imprimirlo en la consola.
defmodule Arbol do
  alias Nodo.{Simbolo, Union, Concatenacion, Estrella, Mas, Opcional}

  # el símbolo de la cadena vacía, se necesita al simplificar el ?
  @epsilon "ε"

  # ---------------------------------------------------------------------------(arma el árbol leyendo el postfix de izquierda a derecha)
  def construir(postfix) do
    # se recorre el postfix apilando nodos; al final debe quedar solo la raíz
    case Enum.reduce(postfix, [], &apilar/2) do
      [raiz] -> raiz
      pila -> raise "postfix inválido: la pila quedó con #{length(pila)} nodos"
    end
  end

  # ---------------------------------------------------------------------------(procesa un símbolo del postfix usando la pila de nodos)
  # los operadores de dos operandos sacan dos nodos: el de arriba es el derecho
  defp apilar("|", [derecha, izquierda | resto]) do
    [%Union{izquierda: izquierda, derecha: derecha} | resto]
  end

  defp apilar("·", [derecha, izquierda | resto]) do
    [%Concatenacion{izquierda: izquierda, derecha: derecha} | resto]
  end

  # los operadores de un solo operando sacan un nodo y lo vuelven a meter envuelto
  defp apilar("*", [hijo | resto]), do: [%Estrella{hijo: hijo} | resto]
  defp apilar("+", [hijo | resto]), do: [%Mas{hijo: hijo} | resto]
  defp apilar("?", [hijo | resto]), do: [%Opcional{hijo: hijo} | resto]

  # cualquier otra cosa es un símbolo del alfabeto, o sea una hoja nueva
  defp apilar(simbolo, pila), do: [%Simbolo{valor: simbolo} | pila]

  # ---------------------------------------------------------------------------(quita + y ? cambiándolos por su equivalente con * y |)
  #   X+  ->  X · X*    una vez obligatoria y después cero o más veces
  #   X?  ->  X | ε     o está X, o está la cadena vacía
  def simplificar(%Mas{hijo: hijo}) do
    hijo = simplificar(hijo)
    # el subárbol se repite: una copia suelta y otra dentro de la estrella
    %Concatenacion{izquierda: hijo, derecha: %Estrella{hijo: hijo}}
  end

  def simplificar(%Opcional{hijo: hijo}) do
    %Union{izquierda: simplificar(hijo), derecha: %Simbolo{valor: @epsilon}}
  end

  # los demás nodos se quedan igual, pero hay que revisar a sus hijos
  def simplificar(%Estrella{hijo: hijo}), do: %Estrella{hijo: simplificar(hijo)}

  def simplificar(%Union{izquierda: izq, derecha: der}) do
    %Union{izquierda: simplificar(izq), derecha: simplificar(der)}
  end

  def simplificar(%Concatenacion{izquierda: izq, derecha: der}) do
    %Concatenacion{izquierda: simplificar(izq), derecha: simplificar(der)}
  end

  # una hoja ya no tiene nada que simplificar
  def simplificar(%Simbolo{} = hoja), do: hoja

  # ---------------------------------------------------------------------------(devuelve la lista de hijos de un nodo)
  def hijos(%Simbolo{}), do: []
  def hijos(%Estrella{hijo: hijo}), do: [hijo]
  def hijos(%Mas{hijo: hijo}), do: [hijo]
  def hijos(%Opcional{hijo: hijo}), do: [hijo]
  def hijos(%Union{izquierda: izq, derecha: der}), do: [izq, der]
  def hijos(%Concatenacion{izquierda: izq, derecha: der}), do: [izq, der]

  # ---------------------------------------------------------------------------(cambia los hijos de un nodo sin cambiar su tipo)
  defp con_hijos(nodo, []), do: nodo
  defp con_hijos(nodo, [hijo]), do: %{nodo | hijo: hijo}
  defp con_hijos(nodo, [izq, der]), do: %{nodo | izquierda: izq, derecha: der}

  # ---------------------------------------------------------------------------(le pone un número distinto a cada nodo)
  def numerar(nodo) do
    {numerado, _siguiente} = poner_id(nodo, 1)
    numerado
  end

  defp poner_id(nodo, id) do
    # el padre se queda con el id actual y los hijos siguen contando desde id + 1
    {hijos, siguiente} = Enum.map_reduce(hijos(nodo), id + 1, &poner_id/2)
    {con_hijos(%{nodo | id: id}, hijos), siguiente}
  end

  # ---------------------------------------------------------------------------(dice qué símbolo se escribe dentro del nodo)
  def etiqueta(%Simbolo{valor: valor}), do: valor
  def etiqueta(%Union{}), do: "|"
  def etiqueta(%Concatenacion{}), do: "·"
  def etiqueta(%Estrella{}), do: "*"
  def etiqueta(%Mas{}), do: "+"
  def etiqueta(%Opcional{}), do: "?"

  # ---------------------------------------------------------------------------(dice de qué tipo es el nodo, en palabras)
  def tipo(%Simbolo{}), do: "simbolo"
  def tipo(%Union{}), do: "union"
  def tipo(%Concatenacion{}), do: "concatenacion"
  def tipo(%Estrella{}), do: "estrella"
  def tipo(%Mas{}), do: "mas"
  def tipo(%Opcional{}), do: "opcional"

  # ---------------------------------------------------------------------------(vuelve a sacar el postfix recorriendo el árbol)
  # primero los hijos y de último el padre: eso es exactamente el orden postfix
  def a_postfix(nodo), do: Enum.flat_map(hijos(nodo), &a_postfix/1) ++ [etiqueta(nodo)]

  # ---------------------------------------------------------------------------(cuenta cuántos nodos tiene el árbol)
  def contar(nodo), do: 1 + Enum.sum(Enum.map(hijos(nodo), &contar/1))

  # ---------------------------------------------------------------------------(imprime el árbol en la consola con rayitas)
  def imprimir(nodo) do
    IO.puts("    " <> descripcion(nodo))
    ramas(hijos(nodo), "    ")
  end

  defp ramas([], _sangria), do: :ok

  defp ramas(hijos, sangria) do
    ultimo = length(hijos) - 1

    hijos
    |> Enum.with_index()
    |> Enum.each(fn {hijo, indice} ->
      # el último hijo lleva la esquina, los demás llevan la te
      {rama, continuacion} =
        if indice == ultimo, do: {"└── ", "    "}, else: {"├── ", "│   "}

      IO.puts(sangria <> rama <> descripcion(hijo))
      # los nietos se dibujan más adentro, alineados debajo de su padre
      ramas(hijos(hijo), sangria <> continuacion)
    end)
  end

  # ---------------------------------------------------------------------------(arma el texto que se ve de cada nodo)
  defp descripcion(nodo) do
    "#{etiqueta(nodo)}   (#{tipo(nodo)}, nodo #{nodo.id})"
  end
end

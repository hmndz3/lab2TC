# Simula el AFN sin convertirlo a AFD: se lleva el conjunto de estados en los
# que el autómata podría estar, y por cada símbolo de la cadena ese conjunto se
# mueve y se vuelve a cerrar con ε.
defmodule Simulacion do
  @epsilon AFN.epsilon()

  # ---------------------------------------------------------------------------(corre la cadena y dice si el AFN la acepta)
  # devuelve {acepta?, pasos}, donde cada paso es {símbolo leído, conjunto de estados}
  def correr(afn, cadena) do
    inicial = clausura(afn, [afn.inicio])

    {conjunto, pasos} =
      cadena
      |> simbolos()
      |> Enum.reduce({inicial, []}, fn simbolo, {actual, pasos} ->
        siguiente = avanzar(afn, actual, simbolo)
        {siguiente, [{simbolo, siguiente} | pasos]}
      end)

    # se acepta si al terminar la cadena el estado de aceptación es alcanzable
    {MapSet.member?(conjunto, afn.aceptacion), [{:inicio, inicial} | Enum.reverse(pasos)]}
  end

  # ---------------------------------------------------------------------------(parte la cadena en símbolos sueltos)
  # la cadena vacía se puede escribir "" o "ε", las dos quieren decir lo mismo
  def simbolos(cadena) when cadena in ["", "ε"], do: []
  def simbolos(cadena), do: String.graphemes(cadena)

  # ---------------------------------------------------------------------------(consume un símbolo desde un conjunto de estados)
  defp avanzar(afn, estados, simbolo) do
    afn
    |> AFN.destinos(estados, simbolo)
    |> then(&clausura(afn, &1))
  end

  # ---------------------------------------------------------------------------(ε-clausura: todo lo que se alcanza sin consumir nada)
  def clausura(afn, estados), do: recorrer(afn, estados, MapSet.new())

  # ya no quedan estados por revisar
  defp recorrer(_afn, [], visitados), do: visitados

  defp recorrer(afn, [estado | pendientes], visitados) do
    if MapSet.member?(visitados, estado) do
      # ya se había revisado, se salta (así los ciclos del * no dan vueltas infinitas)
      recorrer(afn, pendientes, visitados)
    else
      vecinos = AFN.destinos(afn, [estado], @epsilon)
      recorrer(afn, vecinos ++ pendientes, MapSet.put(visitados, estado))
    end
  end

  # ---------------------------------------------------------------------------(escribe un conjunto de estados como {0, 1, 3})
  def a_texto(conjunto) do
    case Enum.sort(conjunto) do
      [] -> "∅"
      estados -> "{" <> Enum.join(estados, ", ") <> "}"
    end
  end
end

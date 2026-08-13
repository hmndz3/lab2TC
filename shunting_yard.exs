# En regex la concatenación es invisible ("abb" es "a·b·b"), pero Shunting Yard
# necesita verla. Aquí se escribe ese · de forma explícita.
defmodule Concatenacion do
  # el operador que se va a insertar
  @punto {:operador, "·"}

  # ---------------------------------------------------------------------------(mete el operador · donde la concatenación estaba implícita)
  def insertar(tokens), do: recorrer(tokens, [])

  # ---------------------------------------------------------------------------(revisa los tokens de dos en dos)
  # ya no quedan tokens: se devuelve el resultado en el orden correcto
  defp recorrer([], resultado), do: Enum.reverse(resultado)

  # queda uno solo: no tiene vecino a la derecha, así que se copia tal cual
  defp recorrer([token], resultado), do: Enum.reverse([token | resultado])

  defp recorrer([actual, siguiente | resto], resultado) do
    # si el primero cierra algo y el segundo abre algo, entre ellos falta un ·
    resultado =
      if termina?(actual) and empieza?(siguiente) do
        [@punto, actual | resultado]
      else
        [actual | resultado]
      end

    # se avanza dejando "siguiente" como el nuevo "actual"
    recorrer([siguiente | resto], resultado)
  end

  # ---------------------------------------------------------------------------(dice si un token termina una subexpresión)
  defp termina?({:simbolo, _}), do: true
  defp termina?({:cierra, _}), do: true
  # las cerraduras van después de su operando, así que también cierran
  defp termina?({:operador, operador}), do: operador in ["*", "+", "?"]
  defp termina?(_), do: false

  # ---------------------------------------------------------------------------(dice si un token empieza una subexpresión)
  defp empieza?({:simbolo, _}), do: true
  defp empieza?({:abre, _}), do: true
  defp empieza?(_), do: false
end

# Pasa la expresión de infix a postfix usando una salida y una pila de
# operadores. Devuelve una lista de símbolos, no un texto.
defmodule ShuntingYard do
  # entre más alto el número, más fuerte amarra el operador
  @precedencias %{"·" => 2, "|" => 1}

  # operadores que van después de su operando y por eso no pasan por la pila
  @unarios ["*", "+", "?"]

  # ---------------------------------------------------------------------------(convierte los tokens de infix a postfix)
  def convertir(tokens) do
    # la salida se va llenando al revés, hay que voltearla al final
    tokens |> recorrer([], []) |> Enum.reverse()
  end

  # ---------------------------------------------------------------------------(lee los tokens uno por uno aplicando las reglas)
  # caso final: ya no hay tokens ni operadores pendientes
  defp recorrer([], salida, []), do: salida

  # ya no hay tokens pero la pila tiene operadores: se vacían a la salida
  defp recorrer([], salida, [tope | pila]), do: recorrer([], [tope | salida], pila)

  # un símbolo nunca espera, se escribe de una vez
  defp recorrer([{:simbolo, simbolo} | resto], salida, pila) do
    recorrer(resto, [simbolo | salida], pila)
  end

  # * + ? aplican al operando que ya se escribió, así que tampoco esperan
  defp recorrer([{:operador, operador} | resto], salida, pila) when operador in @unarios do
    recorrer(resto, [operador | salida], pila)
  end

  # "(" solo sirve de marca, no llega nunca a la salida
  defp recorrer([{:abre, _} | resto], salida, pila), do: recorrer(resto, salida, ["(" | pila])

  # ")" cierra el grupo que abrió el "(" más reciente
  defp recorrer([{:cierra, _} | resto], salida, pila) do
    {salida, pila} = cerrar_grupo(salida, pila)
    recorrer(resto, salida, pila)
  end

  # | y · sí pasan por la pila, respetando la precedencia
  defp recorrer([{:operador, operador} | resto], salida, pila) do
    {salida, pila} = sacar_mayores(operador, salida, pila)
    recorrer(resto, salida, [operador | pila])
  end

  # ---------------------------------------------------------------------------(vacía la pila hasta encontrar el paréntesis que abre)
  # pila vacía: la expresión venía mal balanceada, se corta sin hacer nada
  defp cerrar_grupo(salida, []), do: {salida, []}

  # apareció el "(": se descarta porque los paréntesis no existen en postfix
  defp cerrar_grupo(salida, ["(" | pila]), do: {salida, pila}

  # cualquier otro operador sale a la salida y se sigue buscando el "("
  defp cerrar_grupo(salida, [tope | pila]), do: cerrar_grupo([tope | salida], pila)

  # ---------------------------------------------------------------------------(saca de la pila los operadores más fuertes o iguales)
  defp sacar_mayores(operador, salida, [tope | pila]) when tope != "(" do
    if precedencia(tope) >= precedencia(operador) do
      # el de la pila debía evaluarse primero, entonces sale primero
      sacar_mayores(operador, [tope | salida], pila)
    else
      # el de la pila es más débil, se queda esperando su turno
      {salida, [tope | pila]}
    end
  end

  # la pila está vacía o el tope es "(": aquí ya no se saca nada
  defp sacar_mayores(_operador, salida, pila), do: {salida, pila}

  # ---------------------------------------------------------------------------(devuelve qué tan fuerte es un operador)
  defp precedencia(operador), do: Map.get(@precedencias, operador, 0)
end

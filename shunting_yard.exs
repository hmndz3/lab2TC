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
    {salida, pasos} = recorrer(tokens, [], [], [])
    # las dos listas se fueron llenando al revés, hay que voltearlas
    {Enum.reverse(salida), Enum.reverse(pasos)}
  end

  # ---------------------------------------------------------------------------(lee los tokens uno por uno aplicando las reglas)
  # caso final: ya no hay tokens ni operadores pendientes
  defp recorrer([], salida, [], pasos), do: {salida, pasos}

  # ya no hay tokens pero la pila tiene operadores: se vacían a la salida
  defp recorrer([], salida, [tope | pila], pasos) do
    salida = [tope | salida]
    recorrer([], salida, pila, [paso("fin", "saca #{tope}", pila, salida) | pasos])
  end

  # un símbolo nunca espera, se escribe de una vez
  defp recorrer([{:simbolo, simbolo} | resto], salida, pila, pasos) do
    salida = [simbolo | salida]
    recorrer(resto, salida, pila, [paso(simbolo, "a la salida", pila, salida) | pasos])
  end

  # * + ? aplican al operando que ya se escribió, así que tampoco esperan
  defp recorrer([{:operador, operador} | resto], salida, pila, pasos)
       when operador in @unarios do
    salida = [operador | salida]
    recorrer(resto, salida, pila, [paso(operador, "a la salida", pila, salida) | pasos])
  end

  # "(" solo sirve de marca, no llega nunca a la salida
  defp recorrer([{:abre, _} | resto], salida, pila, pasos) do
    pila = ["(" | pila]
    recorrer(resto, salida, pila, [paso("(", "guarda (", pila, salida) | pasos])
  end

  # ")" cierra el grupo que abrió el "(" más reciente
  defp recorrer([{:cierra, _} | resto], salida, pila, pasos) do
    {salida, pila, pasos} = cerrar_grupo(salida, pila, pasos)
    recorrer(resto, salida, pila, pasos)
  end

  # | y · sí pasan por la pila, respetando la precedencia
  defp recorrer([{:operador, operador} | resto], salida, pila, pasos) do
    {salida, pila, pasos} = sacar_mayores(operador, salida, pila, pasos)
    pila = [operador | pila]
    recorrer(resto, salida, pila, [paso(operador, "guarda #{operador}", pila, salida) | pasos])
  end

  # ---------------------------------------------------------------------------(vacía la pila hasta encontrar el paréntesis que abre)
  # pila vacía: la expresión venía mal balanceada, se corta sin hacer nada
  defp cerrar_grupo(salida, [], pasos), do: {salida, [], pasos}

  # apareció el "(": se descarta porque los paréntesis no existen en postfix
  defp cerrar_grupo(salida, ["(" | pila], pasos) do
    {salida, pila, [paso(")", "saca ( y la tira", pila, salida) | pasos]}
  end

  # cualquier otro operador sale a la salida y se sigue buscando el "("
  defp cerrar_grupo(salida, [tope | pila], pasos) do
    salida = [tope | salida]
    cerrar_grupo(salida, pila, [paso(")", "saca #{tope}", pila, salida) | pasos])
  end

  # ---------------------------------------------------------------------------(saca de la pila los operadores más fuertes o iguales)
  defp sacar_mayores(operador, salida, [tope | pila], pasos) when tope != "(" do
    if precedencia(tope) >= precedencia(operador) do
      # el de la pila debía evaluarse primero, entonces sale primero
      salida = [tope | salida]
      sacar_mayores(operador, salida, pila, [paso(operador, "saca #{tope}", pila, salida) | pasos])
    else
      # el de la pila es más débil, se queda esperando su turno
      {salida, [tope | pila], pasos}
    end
  end

  # la pila está vacía o el tope es "(": aquí ya no se saca nada
  defp sacar_mayores(_operador, salida, pila, pasos), do: {salida, pila, pasos}

  # ---------------------------------------------------------------------------(devuelve qué tan fuerte es un operador)
  defp precedencia(operador), do: Map.get(@precedencias, operador, 0)

  # ---------------------------------------------------------------------------(guarda una fila de la tabla de pasos)
  defp paso(token, accion, pila, salida) do
    {token, accion, texto_pila(pila), texto_salida(salida)}
  end

  # ---------------------------------------------------------------------------(escribe la pila con el fondo a la izquierda)
  defp texto_pila([]), do: "-"
  defp texto_pila(pila), do: pila |> Enum.reverse() |> Enum.join(" ")

  # ---------------------------------------------------------------------------(escribe la salida parcial)
  defp texto_salida([]), do: "-"
  defp texto_salida(salida), do: salida |> Enum.reverse() |> Enum.join()
end

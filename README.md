# Laboratorio 2 — Teoría de la Computación

## Problema 3: Shunting Yard

Convierte expresiones regulares de notación **infix** a **postfix** usando el algoritmo de
Shunting Yard, mostrando cada paso de la pila.

---

## ¿Qué es el algoritmo de Shunting Yard?

Es un algoritmo publicado por **Edsger Dijkstra en 1961** para convertir expresiones en
notación infix a notación postfix (también llamada polaca inversa). El nombre viene de las
*shunting yards* de los ferrocarriles: los vagones entran por una vía, algunos se desvían a
un apartadero y luego se reincorporan en otro orden.

El problema que resuelve es que en infix el orden de evaluación **no es explícito**: depende
de reglas de precedencia y de los paréntesis. En `a|b·c` hay que saber que `·` se evalúa
antes que `|`. En postfix ese orden ya viene codificado en la posición de los símbolos, así
que se puede evaluar recorriendo de izquierda a derecha con una sola pila, sin retroceder.
Por eso es el paso previo a la construcción de Thompson.

### La idea central

Se usan dos estructuras:

- **Salida** — donde se va formando la expresión postfix.
- **Pila de operadores** — un "apartadero" donde los operadores esperan su turno.

Se recorre la expresión símbolo por símbolo y se aplica una regla según lo que se lee:

```
Operando            a, [ae], \(, ε, ...
                    -> va directo a la salida

Paréntesis abre     (
                    -> se apila, marca el inicio de un grupo

Paréntesis cierra   )
                    -> desapila hacia la salida todo hasta encontrar '('
                       y descarta ese '('

Operador            |, ·, *
                    -> mientras el tope de la pila tenga precedencia
                       MAYOR O IGUAL, lo desapila hacia la salida.
                       Luego apila el operador actual.

Fin de expresión    -> vacía la pila restante hacia la salida
```

La regla clave es la de *precedencia mayor o igual*: garantiza que un operador nunca salga a
la salida antes que otro que debía evaluarse primero.

### Precedencias usadas

```
5   ^           definido en el pseudocódigo, no aparece en estas expresiones
4   ?  *  +     cerraduras
3   ·           concatenación
2   |           alternación (unión)
1   (           marcador de grupo
```

### Ejemplo trazado: `(a | t)c`

Después del preprocesamiento queda `(a|t)·c`:

```
Token   Acción                Pila      Salida
─────────────────────────────────────────────────
(       push (                (         -
a       operando              (         a
|       push |                ( |       a
t       operando              ( |       at
)       pop |                 (         at|
)       pop ( y descartar     -         at|
·       push ·                ·         at|
c       operando              ·         at|c
fin     pop ·                 -         at|c·
─────────────────────────────────────────────────
Postfix: at|c·
```

---

## Adaptaciones para expresiones regulares

El pseudocódigo base asume aritmética simple. Para regex hicieron falta cuatro ajustes:

### 1. Verificador de caracteres escapados (`\`)

El lexer lee `\` junto con el carácter siguiente y los convierte en **un solo token literal**.
Así `\(` en `if\([ae]+\)` es el paréntesis literal del código fuente, no un agrupador, y `\n`
es un literal de salto de línea. Sin esto, la expresión (g) rompería el balanceo de paréntesis.

### 2. Clases de caracteres `[...]` como un solo token

`[ae03]` se trata como un átomo indivisible, no como cinco símbolos sueltos. Dentro de la
clase también se respetan los escapes.

### 3. Conversión de las extensiones `+` y `?`

Antes de aplicar Shunting Yard, se reescriben en términos de las tres operaciones básicas
(`|`, `·`, `*`), que son las únicas que la construcción de Thompson necesita:

```
X+   ->   XX*        una vez obligatoria, luego cero o más
X?   ->   (X|ε)      o está, o está vacío
```

`X` puede ser un carácter, una clase o un grupo completo, así que la expansión se hace con
una pila de niveles que sabe dónde empieza y termina el átomo anterior.

Ejemplo: `0?(1?)?0*` se reescribe como `(0|ε)((1|ε)|ε)0*`

### 4. Concatenación explícita y el carácter `.`

En regex la concatenación es implícita (`abb` significa `a·b·b`), pero Shunting Yard necesita
un operador visible. Se inserta `·` entre dos tokens cuando el primero **cierra** una
subexpresión (literal, `)`, `*`) y el segundo **abre** una (literal, `(`).

Se usa `·` y no `.` a propósito: la expresión (h) contiene puntos literales
(`[ae03]+@[ae03]+.(com | net | org)`). Si `.` fuera el operador de concatenación, esa
expresión se interpretaría mal. Con `·` como operador interno, el `.` del archivo siempre es
un carácter literal.

Los espacios del archivo se ignoran, ya que en estas expresiones solo separan visualmente
(`(a | t)` es lo mismo que `(a|t)`).

---

## Ejecución

```bash
elixir shunting_yard.exs expresiones.txt
```

Si no se pasa argumento, usa `expresiones.txt` por defecto. Cada línea del archivo es una
expresión regular; las líneas que empiezan con `#` se ignoran.

Para cada expresión el programa imprime:

1. Los tokens reconocidos, mostrando escapes y clases como unidades
2. La expresión tras expandir `+` y `?`
3. La expresión con la concatenación explícita
4. El número total de pasos
5. La tabla completa de pasos: token, acción, estado de la pila y salida parcial
6. **La expresión en formato postfix**

### Opciones

```
--pausa       espera Enter entre una expresión y la siguiente
--resumen     omite la tabla de pasos, solo muestra el postfix
--linea N     procesa únicamente la línea N del archivo
```

Las expresiones (g) y (h) generan 70 y 79 pasos, así que la salida completa es larga.
Para revisarlas con calma:

```bash
elixir shunting_yard.exs expresiones.txt --linea 8
elixir shunting_yard.exs expresiones.txt --pausa
elixir shunting_yard.exs expresiones.txt --resumen
```

## Archivos

- `shunting_yard.exs` — implementación en Elixir
- `expresiones.txt` — las 8 expresiones regulares del Problema 1
- `README.md` — este documento

## Resultados

```
(a)  (a | t)c
     -> at|c·

(b)  (a | b)*
     -> ab|*

(c)  (a* | b*)*
     -> a*b*|*

(d)  ((ε | a) | b*)*
     -> εa|b*|*

(e)  (a | b)*abb(a | b)*
     -> ab|*a·b·b·ab|*·

(f)  0?(1?)?0*
     -> 0ε|1ε|ε|·0*·

(g)  if\([ae]+\)\{[ei]+\}(\n(else\{[jl]+}))?
     -> if·\(·[ae]·[ae]*·\)·\{·[ei]·[ei]*·\}·\nel·s·e·\{·[jl]·[jl]*·}··ε|·

(h)  [ae03]+@[ae03]+.(com | net | org)(.(gt | cr | co))?
     -> [ae03][ae03]*·@·[ae03]·[ae03]*·.·co·m·ne·t·|or·g·|·.gt·cr·|co·|·ε|·
```

## Video


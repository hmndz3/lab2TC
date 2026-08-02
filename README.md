# Laboratorio 2 — Teoría de la Computación

## Problema 2: Balanceo de expresiones

Este programa revisa si una expresión tiene bien puestos sus paréntesis, corchetes y llaves.

Lee un archivo de texto y, por cada línea, dice si está balanceada o no. Además muestra
paso a paso lo que va pasando en la pila, para que se vea cómo llegó a esa conclusión.

## Cómo funciona

Usa una pila, que es una lista donde solo se puede meter y sacar por arriba.

Recorre la expresión carácter por carácter:

- Si encuentra un símbolo que abre — `(`, `[`, `{` — lo mete en la pila.
- Si encuentra uno que cierra — `)`, `]`, `}` — revisa qué hay arriba de la pila.
  Si corresponde, lo saca. Si no corresponde, la expresión está mal.
- Cualquier otro carácter lo ignora, porque no afecta el balanceo.

Al terminar, si la pila quedó vacía, todo cerró bien. Si quedó algo adentro, es porque
había un símbolo que se abrió y nunca se cerró.

Cuando algo falla, el programa dice exactamente en qué posición y por qué.

## Cómo usarlo

```bash
elixir balanceo.exs expresiones.txt
```

Si no se le pasa el nombre del archivo, usa `expresiones.txt`.

Cada línea del archivo es una expresión. Las líneas que empiezan con `#` se ignoran, así
que sirven para poner comentarios.

## Archivos

- `balanceo.exs` — el programa, escrito en Elixir
- `expresiones.txt` — las expresiones del enunciado más dos casos de prueba

## Video

Demostración de la ejecución: https://youtu.be/lsWYwakYTRs

## Ramas del repositorio

- `main` — Problema 2, balanceo de expresiones
- `ShuntingYard` — Problema 3, conversión de infix a postfix

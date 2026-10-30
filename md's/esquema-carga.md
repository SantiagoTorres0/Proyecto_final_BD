# S14. Laboratorio: el esquema del proyecto en PostgreSQL y la carga desde CSV

**Módulo 4, semana 7, sesión 14 · Laboratorio sincrónico (videollamada, salas por grupo de proyecto)**

En S11 cada grupo dejó su `biblioteca-v2.sql` corriendo sin errores y en S13 se vio el DML que faltaba. Este laboratorio junta las dos cosas: el esquema pasa a ser el script de arranque del entorno Docker (`postgres/init/`) y se llena con los libros y lectores de los CSV semilla del curso, **incluidos los archivos con errores a propósito**. Lo que salga de hoy es la mitad del Hito 2 (se entrega en S16); la otra mitad son las consultas de los cuatro reportes (S15 y S16).

## Objetivos de la sesión

Al terminar, cada estudiante debe poder:

- Explicar por qué un `COPY` directo a la tabla final no sirve para cargar un archivo que puede traer errores.
- Cargar un CSV con el patrón **tabla de paso → validación → tabla final → bitácora de rechazos**, dentro de una transacción.
- Escribir reglas de validación en SQL (`CASE`, expresiones regulares con `~`, `EXISTS`) que atrapen una fila mala **antes** de que la rechace una restricción del esquema.
- Detectar duplicados contra la tabla y dentro del mismo archivo.
- Adaptar la carga a un esquema propio cuyas tablas no coinciden una a una con las columnas del CSV.

## Guía corta de pre-lectura (antes de la sesión)

### 1. Por qué no basta con un `COPY` directo

`COPY` es la sentencia de PostgreSQL para leer un archivo y meterlo en una tabla. Si se intenta cargar `libros_semilla_con_errores.csv` directamente en una tabla `libro` con sus restricciones, pasa esto:

```sql
COPY libro FROM '/scripts/datos/libros_semilla_con_errores.csv'
     WITH (FORMAT csv, HEADER true);
```

```
ERROR:  null value in column "titulo" of relation "libro" violates not-null constraint
DETAIL:  Failing row contains (9780000000033, null, Julio Cortázar, Novela, 1963, 3).
CONTEXT:  COPY libro, line 3: "9780000000033,,Julio Cortázar,Novela,1963,3"
```

Tres problemas:

1. **Es todo o nada.** `COPY` es una sola sentencia: al fallar la línea 3 se deshace también la línea 2, que estaba bien. Con 10 000 filas y una mala, no entra ninguna.
2. **Solo se ve el primer error.** Para encontrar el siguiente hay que corregir, volver a correr, fallar otra vez… El archivo trae 8 filas malas, todas por motivos distintos.
3. **El mensaje es del motor, no del negocio.** "violates not-null constraint" no le sirve a un bibliotecario. Además, varios errores ni siquiera llegan a la restricción: `"dos"` en una columna `integer` falla antes, al convertir el tipo, y una fila con una columna de más falla al partir la línea.

Un detalle que explica el mensaje: en `FORMAT csv`, un campo vacío sin comillas se lee como `NULL`, no como texto vacío. Por eso el título vacío choca con el `NOT NULL` y no con el `CHECK (titulo <> '')`.

La conclusión es la idea central del laboratorio: **las restricciones del esquema son la última línea de defensa, no el validador de la carga.** Si una fila llega a chocar con un `CHECK`, la validación ya falló.

### 2. El patrón: tabla de paso, validación, tabla final y bitácora

```
archivo .csv
   │  COPY (todo como texto, sin restricciones: no se pierde ninguna línea)
   ▼
tabla de paso (stg_…)  ──►  UPDATE … SET motivo = CASE …   (validar cada fila)
   │                                │
   │ motivo IS NULL                 │ motivo IS NOT NULL
   ▼                                ▼
tabla final (libro)          bitácora (rechazo_carga)
```

- La **tabla de paso** (*staging*) tiene todas las columnas como `text` y ninguna restricción, más una columna `motivo`. Cualquier línea del archivo cabe ahí, por rara que sea.
- La **validación** es un `UPDATE` que le pone a cada fila el motivo de rechazo (o lo deja en `NULL` si pasó).
- Las filas con `motivo IS NULL` pasan a la tabla final con un `INSERT … SELECT`, convirtiendo cada texto a su tipo real.
- Las demás van a una **bitácora** que conserva el archivo, la línea, el contenido original y el motivo, para poder corregirlas y volver a cargarlas.
- Todo dentro de `BEGIN … COMMIT` (S13, sección 5.4): si algo inesperado falla a mitad de camino, la base queda como estaba.

### 3. El script de referencia

El profesor deja tres scripts que implementan el patrón sobre un esquema mínimo (`carga_demo`) con una tabla por archivo y las mismas columnas del CSV:

| Script | Qué hace |
|---|---|
| [`S14-esquema-demo.sql`](S14-esquema-demo.sql) | Crea el esquema `carga_demo`: tablas finales `libro` y `lector` con sus restricciones, la bitácora `rechazo_carga` y las tablas de paso. Se puede correr cuantas veces se quiera. |
| [`S14-carga-libros.sql`](S14-carga-libros.sql) | Carga un CSV de libros. Por defecto `libros_semilla.csv`; otro archivo con `-v archivo=…`. |
| [`S14-carga-lectores.sql`](S14-carga-lectores.sql) | Lo mismo para lectores. |

Para correrlos (desde `entorno-docker/`), copiar los tres `.sql` a `postgres/scripts/` y los cuatro CSV de [`../proyecto-final/datos-semilla/`](../proyecto-final/datos-semilla/) a `postgres/scripts/datos/`:

```bash
docker compose exec postgres psql -U curso -d curso -f /scripts/S14-esquema-demo.sql
docker compose exec postgres psql -U curso -d curso -f /scripts/S14-carga-libros.sql
docker compose exec postgres psql -U curso -d curso \
  -v archivo=/scripts/datos/libros_semilla_con_errores.csv \
  -f /scripts/S14-carga-libros.sql
```

Los pasos de `S14-carga-libros.sql`, en orden:

**Paso 1. Leer el archivo tal cual, una fila por línea.**

```sql
COPY stg_linea (linea) FROM :'archivo' WITH (FORMAT text);
DELETE FROM stg_linea WHERE n = 1;          -- la línea 1 es el encabezado
```

El truco está en `FORMAT text`: su separador es el tabulador, que no aparece en los CSV, así que cada línea entera queda en una sola columna y ni una fila con columnas de más detiene la lectura. `stg_linea.n` es una columna `GENERATED ALWAYS AS IDENTITY` que numera las líneas en el orden en que llegan, y ese número es el que después se reporta.

**Paso 2. Partir cada línea en sus campos, todavía como texto.**

```sql
SELECT n, linea,
       array_length(string_to_array(linea, ','), 1),   -- cuántos campos trae
       trim(split_part(linea, ',', 1)),                -- isbn
       trim(split_part(linea, ',', 2)),                -- titulo
       …
```

`split_part(texto, ',', k)` devuelve el campo número `k` (texto vacío si no existe) y `trim` quita los espacios de los bordes. Aquí un campo vacío queda como `''`, no como `NULL`.

**Paso 3. Validar: la primera regla que falla da el motivo.**

```sql
UPDATE stg_libro SET motivo = CASE
    WHEN num_campos <> 6                          THEN 'tiene ' || num_campos || ' columnas, se esperaban 6'
    WHEN isbn = ''                                THEN 'isbn vacío'
    WHEN isbn !~ '^[0-9]{13}$'                    THEN 'isbn no tiene 13 dígitos'
    …
    WHEN anio_publicacion !~ '^[0-9]{1,4}$'       THEN 'año no numérico'
    WHEN anio_publicacion::integer NOT BETWEEN 1450 AND 2100
                                                  THEN 'año fuera de rango'
    …
    WHEN EXISTS (SELECT 1 FROM libro l WHERE l.isbn = stg_libro.isbn)
                                                  THEN 'isbn ya existe en el catálogo'
END;
```

- `~` y `!~` comparan contra una expresión regular: `'^[0-9]{13}$'` es "exactamente 13 dígitos, de principio (`^`) a fin (`$`)".
- El `CASE` se evalúa **en orden** y se detiene en la primera condición verdadera. Por eso el `::integer` del rango de años es seguro: solo se intenta si la línea anterior ya comprobó que el texto son dígitos. Invertir esas dos líneas hace fallar la carga entera con `invalid input syntax for type integer: "MCMXLIX"`.
- Si ninguna regla falla, el `CASE` sin `ELSE` devuelve `NULL`: la fila pasó.
- La última regla busca el duplicado **contra la tabla final** (un libro que ya estaba en el catálogo).

**Paso 4. Duplicados dentro del mismo archivo.** Si el mismo ISBN aparece dos veces en el archivo, ninguna de las dos está todavía en `libro`, así que el `EXISTS` del paso 3 no lo ve. Este `UPDATE` marca cada aparición que tenga otra válida en una línea anterior: se conserva la primera y se rechazan las demás.

**Pasos 5 y 6. Pasar las válidas y registrar las rechazadas.**

```sql
INSERT INTO libro (isbn, titulo, autor, categoria, anio_publicacion, ejemplares_disponibles)
SELECT isbn, titulo, autor, categoria,
       anio_publicacion::smallint, ejemplares_disponibles::integer
FROM stg_libro
WHERE motivo IS NULL;

INSERT INTO rechazo_carga (archivo, linea, contenido, motivo)
SELECT :'archivo', linea_csv, contenido, motivo
FROM stg_libro
WHERE motivo IS NOT NULL;
```

La salida con el archivo con errores es esta (después de haber cargado el limpio):

```
 cargadas | rechazadas
----------+------------
        0 |          8

 linea |              motivo              |                       contenido
-------+----------------------------------+--------------------------------------------------------
     2 | isbn ya existe en el catálogo    | 9780000000001,Cien años de soledad (edición duplicada),…
     3 | título vacío                     | 9780000000033,,Julio Cortázar,Novela,1963,3
     4 | ejemplares no numérico           | 9780000000034,Relato sin ejemplares numéricos,…,2003,dos
     5 | año no numérico                  | 9780000000035,Relato con año inválido,…,MCMXLIX,2
     6 | tiene 7 columnas, se esperaban 6 | 9780000000036,Relato con columna de más,…,columna_sobrante
     7 | autor vacío                      | 9780000000037,Relato sin autor,,Novela,2005,1
     8 | isbn vacío                       | ,Relato sin ISBN,Autor de Prueba,Novela,2010,1
     9 | ejemplares negativo              | 9780000000038,Relato con ejemplares negativos,…,-3
```

`S14-carga-lectores.sql` sigue los mismos pasos; la diferencia más visible es que normaliza el correo a minúsculas (`lower`) antes de compararlo, para que `Ana@X.co` y `ana@x.co` cuenten como el mismo.

**Limitaciones conocidas** (documentadas en el script, y a tener en cuenta con los CSV propios):

- **Comas dentro de comillas.** `"Libro, con coma"` se parte en dos campos y la fila sale rechazada por tener 7 columnas. Los CSV del curso no traen comas dentro de un campo. Si los suyos sí, hay que cambiar el paso 1 y el paso 2 (ver sección 5).
- **Punto y coma como separador.** Excel con configuración regional en español guarda los CSV con `;`. El script no se rompe: rechaza **todas** las filas por "tiene 1 columnas, se esperaban 6", que es la pista para revisar el separador.
- Los finales de línea de Windows (CRLF) sí se manejan bien: `COPY` los reconoce solo.

### 4. Decidir qué hacer con cada error

El [`README de los datos semilla`](../proyecto-final/datos-semilla/README.md) lo dice explícitamente: no hay una única respuesta correcta para cada fila mala, y lo que se evalúa es que el grupo tenga un criterio **consistente** y lo documente. Las tres opciones habituales:

| Opción | Cuándo tiene sentido | Ejemplo |
|---|---|---|
| **Rechazar** la fila y registrarla | El dato falta o no se puede adivinar | ISBN vacío, título vacío, correo sin `@` |
| **Corregir** (normalizar) y cargar | La corrección es mecánica y no cambia el significado | Espacios sobrantes, correo en mayúsculas, ISBN con guiones (`978-0-00…`) |
| **Actualizar** el registro existente | El archivo es una actualización del catálogo, no un alta | Un ISBN que ya existe con más ejemplares (`INSERT … ON CONFLICT (isbn) DO UPDATE`) |

El script de referencia rechaza todo lo que no puede normalizar con `trim` o `lower`. Un grupo puede decidir distinto (por ejemplo, que un ISBN repetido **sume** ejemplares en vez de rechazarse), siempre que lo escriba y lo aplique a todos los casos iguales.

### 5. De `carga_demo` al esquema propio

El esquema de demostración tiene una tabla por archivo con las mismas columnas del CSV. El `biblioteca-v2.sql` de cada grupo casi seguro no es así. Los tres casos que más aparecen y cómo resolverlos con un `INSERT … SELECT` desde la tabla de paso:

**a) Las copias físicas son una tabla aparte** (`ejemplar`, con una fila por copia, para poder prestar cada una). La columna `ejemplares_disponibles` del CSV se convierte en *n* filas con `generate_series`:

```sql
INSERT INTO ejemplar (isbn, numero_copia)
SELECT s.isbn, g.n
FROM stg_libro s
CROSS JOIN LATERAL generate_series(1, s.ejemplares_disponibles::integer) AS g(n)
WHERE s.motivo IS NULL;
```

**b) La categoría (o el autor) es una tabla con clave propia.** Primero se dan de alta las que no existan y después se busca su clave al insertar el libro:

```sql
INSERT INTO categoria (nombre)
SELECT DISTINCT s.categoria FROM stg_libro s WHERE s.motivo IS NULL
ON CONFLICT (nombre) DO NOTHING;            -- requiere UNIQUE (nombre)

INSERT INTO libro (isbn, titulo, id_categoria, …)
SELECT s.isbn, s.titulo, c.id_categoria, …
FROM stg_libro s JOIN categoria c ON c.nombre = s.categoria
WHERE s.motivo IS NULL;
```

**c) El lector es un perfil de una tabla general de usuarios** (la opción 2 de S11: `usuario` + `lector`). Se inserta primero en `usuario` y después en `lector`, recuperando la clave generada por medio de un dato único que venga en el CSV (el documento):

```sql
INSERT INTO usuario (documento, nombres, apellidos, correo, perfil)
SELECT documento, nombres, apellidos, correo, 'lector'
FROM stg_lector WHERE motivo IS NULL;

INSERT INTO lector (id_usuario, telefono)
SELECT u.id_usuario, s.telefono
FROM stg_lector s JOIN usuario u ON u.documento = s.documento
WHERE s.motivo IS NULL;
```

Los nombres de tablas y columnas de estos ejemplos son ilustrativos: cada grupo los cambia por los de su esquema. Dos cosas más que dependen del modelo de cada grupo:

- **Reglas propias.** Cada `CHECK`, `UNIQUE` y `NOT NULL` del `biblioteca-v2.sql` necesita su regla equivalente en el `CASE` de validación, con un motivo legible. Si el esquema tiene una regla que el script de referencia no tiene (un año máximo igual al año actual, una lista cerrada de categorías), hay que agregarla.
- **Contraseña inicial de los lectores.** Los CSV no la traen a propósito (ver el README de los datos semilla). Si el esquema tiene una columna de contraseña obligatoria, el grupo decide cómo se provisiona (por ejemplo, el documento como clave inicial que se pide cambiar), pero **nunca en texto plano**: o se guarda con hash desde la carga (en PostgreSQL, con la extensión `pgcrypto`: `crypt(documento, gen_salt('bf'))`) o se deja la columna admitiendo `NULL` hasta el Hito 5 y se anota como pendiente.

### 6. Dónde va cada archivo en el entorno Docker

| Archivo | Carpeta | Por qué |
|---|---|---|
| `biblioteca-v2.sql`, renombrado `01_esquema.sql` | `postgres/init/` | El Hito 2 pide el esquema como script de arranque: se ejecuta solo, una vez, cuando la base se crea vacía. |
| `carga-libros.sql`, `carga-lectores.sql` | `postgres/scripts/` | Se corren a mano, cuantas veces haga falta, sin borrar la base. |
| Los CSV (semilla y propios) | `postgres/scripts/datos/` | Dentro del contenedor quedan en `/scripts/datos/…`. |

Dos detalles que generan la mayoría de las preguntas:

- **`init/` solo corre con la base vacía.** Después de mover el esquema hay que borrar los datos para que se ejecute (`docker compose down`, `rm -rf postgres/data/*`, `docker compose up -d postgres`), y lo mismo cada vez que se cambie `01_esquema.sql`. Si el script tiene un error, la base queda a medias: revisar `docker compose logs postgres`.
- **`COPY … FROM '/scripts/…'` lee el archivo en el servidor**, es decir, dentro del contenedor de PostgreSQL; la ruta es la del contenedor, no la del computador del estudiante. El comando `\copy` de `psql` hace lo mismo pero leyendo del lado del cliente; con el entorno del curso no hace falta, porque la carpeta `scripts/` ya está montada en el contenedor.

**Pre-trabajo (20 min, antes de la sesión):**

1. Leer esta guía y correr la demostración de la sección 3 en el entorno propio: el esquema, la carga limpia de libros y lectores, y la carga de los dos archivos con errores. Revisar `SELECT * FROM carga_demo.rechazo_carga;` al final.
2. Tener a mano el `biblioteca-v2.sql` del grupo (S11) corriendo sin errores y la lista de reglas que el esquema no cubre.
3. Referencia de consulta: [documentación de `COPY` en PostgreSQL 16](https://www.postgresql.org/docs/16/sql-copy.html).

## Mecánica (2 horas)

1. **(10 min) Encuadre.** El profesor corre la demo en vivo: carga limpia, carga con errores, la bitácora de rechazos. Termina con una pregunta para todos: ¿qué pasa si se vuelve a correr la carga **limpia** de libros? (Respuesta: las 32 filas salen rechazadas por "isbn ya existe en el catálogo"; la carga se puede repetir sin duplicar nada.)
2. **(15 min) El esquema como script de arranque.** Cada grupo copia su `biblioteca-v2.sql` a `postgres/init/01_esquema.sql`, borra los datos, levanta PostgreSQL y comprueba con `\dt biblioteca.*` que las tablas se crearon. Si el script empieza como se pidió en S11 (`DROP SCHEMA IF EXISTS biblioteca CASCADE; CREATE SCHEMA biblioteca;`), sirve igual en `init/` sin cambios.
3. **(15 min) Mapeo y criterios.** Antes de escribir SQL, el grupo llena dos tablas:

   **Mapeo CSV → esquema**, una fila por columna de cada CSV:

   | Columna del CSV | Tabla.columna destino | Transformación | Regla de validación (motivo) |
   |---|---|---|---|
   | `ejemplares_disponibles` | `ejemplar` (n filas) | `generate_series(1, n)` | entero ≥ 0 ("ejemplares negativo") |

   **Criterios por tipo de error**, una fila por cada problema de los archivos con errores (14 en total) más los que el grupo agregue: qué se hace (rechazar, corregir, actualizar) y por qué.
4. **(45 min) Construcción.** Cada grupo escribe `carga-libros.sql` y `carga-lectores.sql` para **su** esquema, partiendo de los scripts de referencia: tablas de paso (pueden vivir en el mismo esquema `biblioteca` o en uno aparte), validaciones con las reglas del mapeo, inserción en las tablas propias y bitácora. Se prueba en este orden: archivo limpio, archivo con errores, archivo limpio otra vez. El profesor/monitor circula por las salas.
5. **(20 min) CSV propio y prueba de la última línea de defensa.**
   - El grupo arma un CSV propio (de libros o de lectores) con al menos 5 filas válidas que no estén en la semilla y 3 filas con errores que **no** aparezcan en los archivos del curso. Ideas: el mismo ISBN dos veces en el archivo, un año en el futuro, un correo repetido con otra mayúscula, un archivo guardado con `;`.
   - Después, comentar a propósito **una** regla del `CASE` (por ejemplo, la de ejemplares negativos) y volver a cargar el archivo con errores. La fila mala ahora llega a la tabla final y choca con el `CHECK` del esquema: ¿qué pasa con las demás filas de esa carga? ¿Y con la bitácora? Anotar la respuesta y restaurar la regla.
6. **(15 min) Cierre.** Uno o dos grupos comparten pantalla con su bitácora de rechazos y explican un criterio que hayan decidido distinto al del script de referencia. El profesor recuerda lo que falta para el Hito 2 en S16: probar con datos propios suficientes (préstamos incluidos, para que los reportes devuelvan algo) y las consultas de los cuatro reportes, que se ven en S15.

## Entregable

**Por grupo**, subido antes de terminar la sesión (y en el repositorio del grupo, que es lo que se revisa en el Hito 2):

1. `postgres/init/01_esquema.sql` y los dos scripts de carga.
2. Las dos tablas del paso 3 de la mecánica: mapeo CSV → esquema y criterios por tipo de error.
3. El CSV propio.
4. La salida de `psql` (texto o captura) de cuatro cargas: libros limpio, libros con errores, lectores con errores y el CSV propio, más la respuesta a la prueba de la última línea de defensa (paso 5).

## Rúbrica (checklist, calificación por grupo)

| Criterio | 0 | 1 | 2 |
|---|---|---|---|
| **Esquema como script de arranque** | No está en `init/`, o no corre con la base vacía | Corre, pero hubo que ajustar algo a mano después | Se crea completo desde `init/` con la base vacía, sin intervención |
| **Carga de los CSV semilla** | No carga, o carga en tablas que no son las del esquema del grupo | Carga los archivos limpios, pero falla o no se puede repetir | Carga libros y lectores en las tablas propias, y repetirla no duplica datos |
| **Validación y bitácora** | Los archivos con errores rompen la carga o meten filas malas | Atrapa la mayoría de los 14 errores, con motivos poco claros o sin bitácora | Atrapa los 14, cada uno con un motivo legible registrado en la bitácora, y las válidas del mismo archivo sí entran |
| **Criterio documentado y CSV propio** | No hay tabla de criterios ni CSV propio | Hay criterios, o CSV propio, pero no ambos; o los errores propios repiten los del curso | Criterios consistentes para todos los casos y CSV propio con 3 errores nuevos atrapados |

Máximo 8 puntos por grupo. Los cuatro criterios corresponden a los tres primeros del Hito 2 (esquema, carga, manejo de errores): lo que se califica hoy es un avance de esa entrega, no la reemplaza.
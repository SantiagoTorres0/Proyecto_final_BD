# Documentación técnica: esquema y carga de datos de la Biblioteca (S14)

Documentación línea por línea de los cuatro scripts SQL del laboratorio S14 (PostgreSQL + `psql`).

## 1. Visión general

El proyecto crea una base de datos de biblioteca y carga datos desde archivos CSV usando un patrón clásico de **ETL con tablas de paso (staging)**. Los scripts se ejecutan en este orden:

| Orden | Archivo | Rol |
| --- | --- | --- |
| 1 | `01_esquema.sql` | Crea el esquema `biblioteca`, el tipo enumerado y las tablas del modelo. |
| 2 | `02_staging.sql` | Crea la bitácora de rechazos y las tablas temporales de paso. |
| 3 | `S14-carga-libros.sql` | Carga `libros_semilla.csv` → tabla `libro`. |
| 4 | `S14-carga-lectores.sql` | Carga `lectores_semilla.csv` → tablas `cuenta_usuario` y `lector`. |

Flujo de los scripts de carga:

1. Se lee el CSV completo, una línea por fila, en `stg_linea`.
2. Cada línea se parte en campos de texto en `stg_libro` / `stg_lector`.
3. Se validan las reglas de negocio y se escribe el motivo del error en la columna `motivo`.
4. Las filas sin motivo (válidas) se insertan en las tablas finales; las que tienen motivo se guardan en `rechazo_carga`.

La idea central: **nunca se rechaza todo el archivo por una fila mala**; cada fila se clasifica como válida o rechazada con una explicación.

## 2. Conceptos y herramientas usadas

### 2.1 Meta-comandos de `psql` (no son SQL, los interpreta el cliente)

- `\set ON_ERROR_STOP on`: si cualquier sentencia falla, `psql` detiene el script. Sin esto, continuaría ejecutando el resto tras un error.
- `\set nombre valor`: define una variable de `psql`.
- `\if :{?archivo}` / `\else` / `\endif`: condicional de `psql`. `:{?archivo}` es verdadero si la variable `archivo` está definida (por ejemplo con `psql -v archivo=/ruta/x.csv`).
- `:'archivo'`: interpola la variable como **literal de texto entre comillas simples** (escapando lo necesario). Es la forma segura de pasar rutas a SQL.

### 2.2 Construcción del esquema (DDL)

- `CREATE SCHEMA` / `DROP SCHEMA ... CASCADE`: espacio de nombres; `CASCADE` borra también todo lo que contiene.
- `SET search_path TO ...`: indica en qué esquema se buscan (y crean) objetos sin prefijo.
- `CREATE TYPE ... AS ENUM`: tipo con lista cerrada de valores.
- `CREATE TABLE`, `PRIMARY KEY`, `UNIQUE`, `NOT NULL`, `DEFAULT`.
- `GENERATED ALWAYS AS IDENTITY`: columna autonumérica estándar SQL (reemplaza a `serial`); `ALWAYS` impide insertar valores manuales sin `OVERRIDING SYSTEM VALUE`.
- `ALTER TABLE ... ADD FOREIGN KEY ... REFERENCES`: llave foránea.
- `DEFERRABLE INITIALLY IMMEDIATE`: la restricción puede aplazarse al final de la transacción con `SET CONSTRAINTS ... DEFERRED`, pero por defecto se verifica en cada sentencia.
- Tipos: `integer`, `varchar`, `text`, `boolean`, `date`, `timestamptz` (fecha-hora con zona horaria).

### 2.3 Consulta y manipulación de datos (DML)

- `BEGIN` / `COMMIT`: transacción; todo se aplica o nada.
- `TRUNCATE ... RESTART IDENTITY`: vacía tablas rápidamente y reinicia sus contadores identity.
- `COPY ... FROM`: carga masiva de archivo a tabla.
- `INSERT ... SELECT`, `UPDATE`, `DELETE`.
- `CASE WHEN ... END`: condicional que devuelve el primer caso verdadero (aquí se usa como una cascada de reglas con prioridad).
- `EXISTS (subconsulta)` y subconsultas correlacionadas.
- Funciones de texto: `split_part`, `string_to_array`, `array_length`, `trim`, `lower`, `right`, `||` (concatenación).
- Operador regex `!~` ("no coincide con la expresión regular"), cast `::integer`, `BETWEEN`.
- Agregados con `FILTER (WHERE ...)`: cuenta condicionada.

## 3. `01_esquema.sql`: esquema del modelo

### Líneas 1–5: preparación

```sql
\set ON_ERROR_STOP on

DROP SCHEMA IF EXISTS biblioteca CASCADE;
CREATE SCHEMA biblioteca;
SET search_path TO biblioteca;
```

- Detiene el script ante cualquier error.
- Elimina el esquema `biblioteca` si existe, con todas sus tablas y tipos. Esto hace el script **reejecutable** (idempotente) pero **destructivo**: borra todos los datos cada vez.
- Crea el esquema vacío y lo fija como destino de las siguientes creaciones.

### Enum `tipo_perfil`

```sql
CREATE TYPE tipo_perfil AS ENUM ('bibliotecario','administrador','lector','auditor');
```

Define los cuatro roles posibles de una cuenta. PostgreSQL rechaza cualquier otro valor y almacena el enum de forma compacta.

### Tabla `lector`

| Columna | Tipo | Significado |
| --- | --- | --- |
| `documento` | `integer PRIMARY KEY` | Documento de identidad; identifica al lector. |
| `id_cuenta` | `integer UNIQUE NOT NULL` | Cuenta de acceso asociada; relación 1 a 1. |
| `nombre` | `varchar NOT NULL` | Nombre completo. |
| `correo` | `varchar UNIQUE` | Correo; único, pero admite NULL. |
| `telefono` | `varchar NOT NULL` | Teléfono como texto. |

Luego `ALTER TABLE lector ADD FOREIGN KEY (id_cuenta) REFERENCES cuenta_usuario (id_cuenta) DEFERRABLE INITIALLY IMMEDIATE;` vincula cada lector con su cuenta. Como `id_cuenta` es `UNIQUE`, una cuenta no puede pertenecer a dos lectores.

### Tabla `bibliotecario`

Campos `id_empleado` (PK), `id_cuenta` (único, obligatorio) y `nombre`. Igual que `lector`, se enlaza a `cuenta_usuario` mediante llave foránea diferible.

### Tabla `libro`

Representa el título como obra (no el ejemplar físico): `codigo` (PK; el `UNIQUE` es redundante porque la PK ya es única), `autor`, `titulo`, `edicion`, `genero`, `editorial`, todos obligatorios.

### Tabla `unidad`

Representa cada **ejemplar físico** de un libro: `codigo`, `codigo_libro` (FK a `libro.codigo`), `codigo_unit` (PK varchar, identificador del ejemplar), `disponibilidad` (boolean) y `estado` (varchar, por ejemplo "bueno" o "dañado"). La relación es libro 1 : N unidades.

### Tabla `prestamo`

Registra cada préstamo: `id_prestamo` (PK), `fecha_prestamo`, `codigo_libro`, `id_lector`, `codigo` (la unidad prestada) e `id_empleado` (quién lo registró). Tres llaves foráneas:

- `id_lector` → `lector(documento)`
- `codigo` → `unidad(codigo_unit)`
- `id_empleado` → `bibliotecario(id_empleado)`

### Tabla `usuarios_instancias`

Cuatro columnas `varchar` (una por perfil) sin clave ni relaciones. Es una tabla auxiliar; no participa en las cargas.

### Tabla `cuenta_usuario`

Credenciales de acceso: `id_cuenta` (PK), `perfil` (tipo `tipo_perfil`), `login_nombre` (único) y `login_contrasena`. Es la tabla "padre" de `lector` y `bibliotecario`: toda persona del sistema tiene una cuenta.

### Tabla `creado_por`

Auditoría de creación: `id_empleado` (FK a `bibliotecario`) e `id_cuenta` (único, FK a `cuenta_usuario`). Indica qué bibliotecario creó cada cuenta; como `id_cuenta` es único, cada cuenta tiene a lo sumo un creador.

### Observaciones sobre este script

1. **Orden de creación (error probable):** `lector` y `bibliotecario` declaran llaves foráneas hacia `cuenta_usuario` **antes** de que esa tabla exista. Con `ON_ERROR_STOP on` el script fallará con `relation "cuenta_usuario" does not exist`. Solución: mover `CREATE TABLE cuenta_usuario` (y `tipo_perfil`) antes de `lector`, o declarar las FK al final del archivo.
2. `unidad.codigo` es un campo `NOT NULL` sin función clara, y `codigo_libro` permite NULL (una unidad podría quedar huérfana).
3. `prestamo.codigo_libro` es `varchar` y no tiene FK, mientras `libro.codigo` es `integer`: es redundante con `unidad.codigo_libro` y de tipo inconsistente.
4. `usuarios_instancias` no tiene clave primaria.
5. Las contraseñas se almacenan en columna de texto simple (ver sección 6).

## 4. `02_staging.sql`: bitácora y tablas de paso

```sql
\set ON_ERROR_STOP on
SET search_path TO biblioteca;
```

Mismo patrón de arranque: parar ante errores y trabajar dentro del esquema `biblioteca` (debe haberse ejecutado antes `01_esquema.sql`).

### `rechazo_carga` (bitácora permanente)

| Columna | Detalle |
| --- | --- |
| `id` | `integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY`: número automático. |
| `archivo` | Ruta del CSV de origen. |
| `linea` | Número de línea que falló. |
| `contenido` | Texto original de la línea. |
| `motivo` | Razón del rechazo. |
| `fecha` | `timestamptz NOT NULL DEFAULT now()`: se rellena sola con la hora de inserción. |

Es la única tabla de este archivo que **conserva** datos entre ejecuciones, ya que los scripts de carga nunca la truncan.

### `stg_linea` (lectura cruda)

- `n integer GENERATED ALWAYS AS IDENTITY`: número de línea, asignado automáticamente en el orden en que `COPY` inserta las filas. Esto permite luego identificar el encabezado (n = 1) y reportar el número de línea de cada error.
- `linea text`: la línea completa, sin separar.

### `stg_libro` y `stg_lector` (campos separados)

Ambas tienen `linea_csv` (número de línea), `contenido` (línea original), `num_campos` (cantidad de columnas detectadas), los campos del CSV como **`text`** y `motivo` (NULL si es válida).

Todo es `text` a propósito: así la lectura nunca falla por un dato mal formado (por ejemplo, letras en una columna numérica). Los tipos reales se validan y convierten después, en un paso controlado.

- `stg_libro`: `isbn`, `titulo`, `autor`, `categoria`, `anio_publicacion`, `ejemplares_disponibles`.
- `stg_lector`: `documento`, `nombres`, `apellidos`, `correo`, `telefono`.

## 5. `S14-carga-libros.sql`: carga del catálogo

### Parámetros de entrada

```sql
\set ON_ERROR_STOP on
\if :{?archivo}
\else
    \set archivo /scripts/datos/libros_semilla.csv
\endif
```

Si se invocó `psql -v archivo=/otra/ruta.csv -f S14-carga-libros.sql`, se respeta esa ruta; si no, se usa la ruta por defecto `/scripts/datos/libros_semilla.csv` (nótese que es una ruta de contenedor/servidor).

### Preparación

```sql
SET search_path TO biblioteca;
BEGIN;
TRUNCATE stg_linea, stg_libro RESTART IDENTITY;
```

Se fija el esquema, se abre una transacción (todo el proceso es atómico) y se vacían las tablas de paso reiniciando `n` en 1, para que cada ejecución empiece limpia y la numeración de líneas sea correcta.

### Paso 1: lectura cruda

```sql
COPY stg_linea (linea) FROM :'archivo' WITH (FORMAT text);
DELETE FROM stg_linea WHERE n = 1;
```

- `COPY ... FROM 'ruta'` lee el archivo **en el servidor** de PostgreSQL (requiere permisos `pg_read_server_files` o superusuario; si el archivo está en la máquina del cliente se usaría `\copy`).
- Con `FORMAT text` el delimitador por defecto es el tabulador. Como el CSV usa comas, cada línea completa cae en la única columna `linea`. Es el truco que permite procesar la línea manualmente.
- En formato `text`, la barra invertida (`\`) es carácter de escape; si los datos la contienen, pueden alterarse.
- Se elimina la línea 1, que es el encabezado.

### Paso 2: separar campos

```sql
INSERT INTO stg_libro (linea_csv, contenido, num_campos, isbn, titulo, autor, categoria, anio_publicacion, ejemplares_disponibles)
SELECT n, linea,
       array_length(string_to_array(linea, ','), 1),
       trim(split_part(linea, ',', 1)), ... trim(split_part(linea, ',', 6))
FROM stg_linea;
```

- `string_to_array(linea, ',')` convierte la línea en un arreglo; `array_length(..., 1)` cuenta los elementos, es decir, las columnas reales.
- `split_part(linea, ',', k)` devuelve el k-ésimo trozo (o cadena vacía si no existe). `trim` quita espacios.
- Limitación: separar por `,` ignora CSV con campos entre comillas que contengan comas (p. ej. `"García, Gabriel"`), que se contarían como columnas extra y serían rechazadas por número de columnas.

### Paso 3: validación en cascada

```sql
UPDATE stg_libro SET motivo = CASE ... END;
```

`CASE` evalúa de arriba abajo y se queda con la **primera** regla que se cumple; si ninguna, `motivo` queda NULL (fila válida). El orden importa: las comprobaciones de formato van antes de los casts para evitar errores de conversión.

| Regla | Qué comprueba |
| --- | --- |
| `num_campos <> 6` | Número de columnas distinto de 6. El mensaje usa \` |
| `isbn = ''` | ISBN vacío. |
| `isbn !~ '^[0-9]{13}$'` | El ISBN no es exactamente 13 dígitos (`^`/`$` anclan inicio y fin). |
| `titulo = ''`, `autor = ''`, `categoria = ''` | Campos obligatorios vacíos. |
| `anio_publicacion !~ '^[0-9]{1,4}$'` | El año no es numérico de 1 a 4 dígitos. |
| `anio_publicacion::integer NOT BETWEEN 1450 AND 2100` | Año fuera de rango (1450 aprox. imprenta de Gutenberg). El cast es seguro porque la regla anterior ya garantizó que es numérico. |
| `ejemplares_disponibles !~ '^-?[0-9]{1,6}$'` | No es entero (admite signo `-`, por eso se detecta luego el negativo). |
| `ejemplares_disponibles::integer < 0` | Ejemplares negativos. |
| `EXISTS (... l.codigo = right(isbn, 9)::integer)` | Ya hay un libro con ese código en el catálogo. |

El **código** del libro se deriva del ISBN: `right(isbn, 9)` toma los últimos 9 dígitos y `::integer` los convierte (cabe en `integer`, máximo 999 999 999 < 2 147 483 647). La subconsulta `EXISTS` es correlacionada: usa `stg_libro.isbn` de la fila que se está evaluando.

### Paso 4: duplicados dentro del archivo

```sql
UPDATE stg_libro SET motivo = 'isbn repetido en el archivo (línea ' || (SELECT min(s2.linea_csv) ...) || ')'
WHERE motivo IS NULL
  AND EXISTS (SELECT 1 FROM stg_libro s2
              WHERE s2.isbn = stg_libro.isbn AND s2.motivo IS NULL
                AND s2.linea_csv < stg_libro.linea_csv);
```

Se marcan como duplicadas las filas aún válidas para las que existe otra fila válida **anterior** con el mismo ISBN. Así se conserva la primera aparición y se rechazan las siguientes. El mensaje indica la línea de la primera ocurrencia con `min(...)`. Dentro de un mismo `UPDATE` todas las subconsultas ven los datos tal como estaban antes de la sentencia, por lo que el resultado es consistente.

### Paso 5: insertar en `libro`

```sql
INSERT INTO libro (codigo, autor, titulo, edicion, genero, editorial)
SELECT (right(isbn, 9))::integer, autor, titulo, '1ra Edición', categoria, 'Editorial General'
FROM stg_libro WHERE motivo IS NULL;
```

`INSERT ... SELECT` copia solo las filas válidas. Como el CSV no trae edición ni editorial (columnas `NOT NULL` en `libro`), se rellenan con valores fijos, y `categoria` se mapea a `genero`.

**Observaciones:**

- `anio_publicacion` y `ejemplares_disponibles` se validan pero **no se guardan**: ninguna tabla del esquema los almacena. En particular, no se crean filas en `unidad` según los ejemplares.
- Dos ISBN distintos con los mismos 9 últimos dígitos pasarían el paso 4 (que compara el ISBN completo) y violarían la PK de `libro` en el paso 5, abortando toda la transacción. Sería más robusto detectar duplicados por `right(isbn, 9)`.

### Paso 6: bitácora de rechazos

```sql
INSERT INTO rechazo_carga (archivo, linea, contenido, motivo)
SELECT :'archivo', linea_csv, contenido, motivo FROM stg_libro WHERE motivo IS NOT NULL;
COMMIT;
```

Cada fila rechazada se guarda con su archivo de origen, número de línea, texto original y motivo. `COMMIT` confirma la transacción: libros nuevos y bitácora se aplican juntos.

### Resumen final (consultas de reporte)

```sql
SELECT count(*) FILTER (WHERE motivo IS NULL) AS cargadas,
       count(*) FILTER (WHERE motivo IS NOT NULL) AS rechazadas
FROM stg_libro;
```

`FILTER` aplica una condición distinta a cada `count` en una sola pasada. La segunda consulta lista las filas rechazadas con línea, motivo y contenido, ordenadas por línea. Estas dos consultas corren **después** del `COMMIT`; leen `stg_libro`, que sigue disponible en la sesión hasta el próximo `TRUNCATE`.

## 6. `S14-carga-lectores.sql`: carga de lectores y cuentas

Sigue la misma estructura que la de libros; aquí se documentan solo las diferencias.

### Parámetros y preparación

Igual manejo de `archivo` (ruta por defecto `/scripts/datos/lectores_semilla.csv`). Aquí `BEGIN` va **antes** de `SET search_path`; funciona igual, ya que `SET` dentro de una transacción dura hasta el final de la sesión salvo que la transacción se revierta. Además, las tablas se califican con `biblioteca.` por seguridad. Se hace `TRUNCATE stg_linea, stg_lector RESTART IDENTITY`.

### Pasos 1 y 2: lectura y separación

Idéntico a libros, con 5 campos: `documento`, `nombres`, `apellidos`, `correo`, `telefono`. El correo se normaliza con `lower(trim(...))` para que `Ana@X.com` y `ana@x.com` se traten como el mismo.

### Paso 3: reglas de validación

| Regla | Qué comprueba |
| --- | --- |
| `num_campos <> 5` | Número de columnas incorrecto. |
| `documento = ''` / `!~ '^[0-9]{6,15}$'` | Documento vacío, no numérico o de 6 a 15 dígitos. |
| `nombres = ''`, `apellidos = ''`, `correo = ''` | Campos obligatorios vacíos. |
| `correo !~ '^[^@ ]+@[^@ ]+\.[^@ ]+$'` | Formato básico: texto sin `@` ni espacios, una `@`, texto, un punto literal (`\.`) y texto. |
| `telefono !~ '^[0-9]{7,15}$'` | Teléfono numérico de 7 a 15 dígitos (también rechaza vacío). |
| `EXISTS ... l.documento = documento::integer` | El documento ya está registrado en `lector`. |
| `EXISTS ... l.correo = correo` | El correo ya está registrado. |

**Observación importante:** la regex admite documentos de hasta 15 dígitos, pero `lector.documento` es `integer` (máximo 2 147 483 647, 10 dígitos). El cast `documento::integer` en la validación (y en el paso 5b) provocará un error de "integer out of range" con documentos de más de 10 dígitos o mayores a ese límite, abortando el script. Se debería usar `bigint` en el esquema o limitar la regex.

### Paso 4: duplicados dentro del archivo

```sql
UPDATE stg_lector SET motivo = 'documento o correo repetido en el archivo'
WHERE motivo IS NULL AND EXISTS (SELECT 1 FROM stg_lector s2
  WHERE (s2.documento = stg_lector.documento OR s2.correo = stg_lector.correo)
    AND s2.motivo IS NULL AND s2.linea_csv < stg_lector.linea_csv);
```

Igual lógica que en libros, pero con dos criterios (`OR`): coincide el documento o el correo con una fila válida anterior. Se conserva la primera aparición.

### Paso 5a: crear la cuenta (tabla padre)

```sql
INSERT INTO biblioteca.cuenta_usuario (id_cuenta, perfil, login_nombre, login_contrasena)
SELECT linea_csv, 'lector'::tipo_perfil, correo, '123456' FROM stg_lector WHERE motivo IS NULL;
```

Primero se inserta la cuenta porque `lector.id_cuenta` es una llave foránea hacia ella. Se usa el número de línea como `id_cuenta`, el perfil fijo `'lector'` (cast explícito al enum), el correo como nombre de inicio de sesión y una contraseña por defecto.

### Paso 5b: crear el lector

```sql
INSERT INTO biblioteca.lector (documento, id_cuenta, nombre, correo, telefono)
SELECT documento::integer, linea_csv, nombres || ' ' || apellidos, correo, telefono
FROM stg_lector WHERE motivo IS NULL;
```

Cada lector enlaza con la cuenta creada mediante el mismo `linea_csv`; `nombres` y `apellidos` se concatenan en el campo único `nombre`.

**Observaciones sobre 5a y 5b:**

- Usar `linea_csv` como `id_cuenta` puede chocar con cuentas ya existentes (por ejemplo de bibliotecarios cargados antes) y violar la PK. Una secuencia o columna identity sería más segura.
- La contraseña `'123456'` se guarda en texto plano. En un sistema real deben guardarse hashes (por ejemplo con `crypt()` de la extensión `pgcrypto`) y forzar el cambio al primer inicio de sesión.
- No se verifica que `login_nombre` (el correo) no exista ya en `cuenta_usuario` con otro perfil; el paso 3 solo mira la tabla `lector`.

### Pasos 6 y resumen

Idénticos a libros: rechazos a `rechazo_carga`, `COMMIT`, conteo con `FILTER` y listado de líneas rechazadas.

## 7. Resumen de buenas prácticas del diseño

- **Staging en texto:** separa la lectura de la validación y evita fallos de conversión.
- **Validación en cascada con `CASE`:** un único motivo por fila, claro y ordenado por prioridad.
- **Bitácora de rechazos:** trazabilidad completa (archivo, línea, texto, motivo, fecha).
- **Transacción única:** si algo inesperado falla, no queda carga a medias.
- **Parametrización:** el archivo puede cambiarse sin editar el script.
- **Idempotencia parcial:** las tablas de paso se truncan cada vez, y las reglas de existencia evitan reinsertar datos ya cargados.

## 8. Lista de mejoras sugeridas

1. Reordenar `01_esquema.sql` para crear `cuenta_usuario` antes de las FK que la referencian.
2. Cambiar `lector.documento` a `bigint` (o ajustar la regex a 10 dígitos).
3. Detectar duplicados de libros por `right(isbn, 9)` y no solo por ISBN completo.
4. Crear filas en `unidad` a partir de `ejemplares_disponibles`, o descartar esa columna del CSV.
5. Generar `id_cuenta` con identity/secuencia y guardar contraseñas con hash.
6. Usar `\copy` si el CSV está en la máquina del cliente y `COPY ... FORMAT csv` con un delimitador poco común si se necesita soportar comillas.

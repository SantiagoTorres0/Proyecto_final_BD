# Documento de normalización — Sistema de gestión de biblioteca

750006C Bases de Datos · Hito 3 (Normalización) · Esquema `biblioteca` en PostgreSQL

Este documento analiza el esquema de `01_esquema.sql` hasta BCNF, escribe cada dependencia funcional (DF) junto con la regla que la justifica, y describe los ajustes aplicados (antes/después). Se parte de la definición del proyecto (`definicion-proyecto-final.md`): catálogo de libros, lectores, ciclo de préstamo/devolución, mora y cuatro perfiles de usuario.

**Decisión del equipo:** no se separa `nombre` en nombres y apellidos en `lector` ni en `bibliotecario`. `nombre` se trata como un atributo atómico del dominio (nos damos esta libertad dado que ninguna regla del negocio pide acceder a nombre y apellido por separado, si se quisiera hacer un sistema de busqueda por apellidos o por nombre, se debería separar nombre y apellidos).

## 1. Reglas utilizadas

Cada dependencia de las secciones siguientes cita una de estas reglas.

| Código | Regla |
|---|---|
| **R-1FN** | Todos los atributos son atómicos: sin listas ni grupos repetidos en una celda. |
| **R-2FN** | 1FN y ningún atributo no primo depende de una parte de una clave compuesta. |
| **R-3FN** | 2FN y, para toda DF no trivial X → A, X es superclave o A es atributo primo (no hay dependencias transitivas no clave → no clave). |
| **R-BCNF** | Para toda DF no trivial X → A, X es superclave. |
| **R-DER** | Criterio de diseño: un dato que se puede calcular desde otros datos del esquema no se almacena, porque puede desincronizarse (anomalía de actualización). No es una forma normal formal. |
| **R-NEG** | Regla de negocio tomada de la definición del proyecto (se indica la sección). |
| **R-PK / R-UQ** | La DF viene declarada por la clave primaria (PK) o por una restricción UNIQUE. |

## 2. Resumen antes / después

| Tabla | Forma normal antes | Problema detectado | Acción | Forma normal después |
|---|---|---|---|---|
| `cuenta_usuario` | BCNF | Sintaxis rota (coma faltante, `ALTER_TABLE`); `creado_por` varchar sin tipo coherente y FK circular a `bibliotecario` | `creado_por` pasa a `integer` con auto-FK a `cuenta_usuario` (este cambio lo hacemos debido a que apunta a un id, por lo que es más congruente que al apuntar a un número, se use INTEGER como tipo de dato) | BCNF |
| `libro` | 1FN no garantizada | `autor` admite varios valores(en caso de tener multiples autores un solo libro); `genero`, `editorial` y `autor` son texto libre repetido; `codigo` truncado sin ISBN completo | Se agrega `isbn`; se extraen `editorial`, `genero`, `autor`(de esta forma se evita posibles errores de actualización o insersión, el cambio lo hicimos basados en la sesión de formas normales, evitar errores como los propuestos en los casos del taller de dicha sesión, por ejemplo Terror sería distinto de terror) y la tabla puente `libro_autor` | BCNF (y 3FN en `libro_autor`) |
| `unidad` | BCNF formal, pero con datos derivados almacenados | `disponibilidad` y `estado` se calculan desde `prestamo`; columna sustituta `codigo` redundante; libro repetido dentro de `codigo_unit` | Se eliminan `disponibilidad`, `estado` y `codigo`; CHECK de coherencia; vista `v_unidad`(este tema de las vistas, no tengo muy claro si lo hemos abordado en el curso, fue una sugerencia de la IA para hacer más faciles de consultar datos calculados a partir de otros, en resumidas palabras la vista es una minitabla que se calcula cada vez que se la llama con un select, de esta forma, los datos derivados de la fecha de prestamo no rompen ninguna de las formas normales de las tablas fisicas ) | BCNF sin datos derivados |
| `prestamo` | 2FN, no 3FN (versión previa con `codigo_libro`) | `codigo → codigo_libro` transitiva | `codigo_libro` eliminado; la regla «un solo préstamo abierto por unidad» se verifica tras la carga y la hace cumplir el Hito 4 (ver §4.1) | BCNF |
| `creado_por` (tabla) | Sin PK, columnas nullable | Tabla innecesaria (relación 1:N que cabe en una columna) | Se elimina; pasa a `cuenta_usuario.creado_por` | — |
| `usuarios_instancias` | No cumple 1FN | Mencionada en el análisis previo; **no existe** en el `01_esquema.sql` actual | No se crea (los perfiles viven en el ENUM `tipo_perfil`) | — |

## 3. Análisis por tabla (esquema final)

La notación es `X → Y`. «Superclave» incluye a toda clave candidata y a cualquier conjunto que la contenga.

### 3.1 `cuenta_usuario`

Claves candidatas: `{id_cuenta}`, `{login_nombre}`.

| DF | Origen | Regla verificada |
|---|---|---|
| id_cuenta → perfil, login_nombre, login_contrasena, creado_por | R-PK | R-BCNF: el determinante es clave |
| login_nombre → id_cuenta, perfil, login_contrasena, creado_por | R-UQ (`login_nombre` UNIQUE NOT NULL) | R-BCNF: el determinante es clave candidata |
| login_nombre → creado_por (derivada) | R-ARM (transitividad vía id_cuenta) | R-BCNF: el determinante es clave |

No existe `creado_por → x`: una misma cuenta creadora puede crear muchas cuentas, así que `creado_por` no determina otros atributos y no introduce dependencia transitiva. Conclusión: **BCNF**.

Sobre el perfil: la definición (§4) exige cuatro perfiles. `perfil` es un atributo de dominio fijo (ENUM `tipo_perfil`), por lo que no requiere tabla aparte. Sobre la seguridad (§6.2): `login_contrasena` debe almacenar el hash (por ejemplo bcrypt), nunca texto plano (ver §8: las cargas actuales usan una contraseña inicial provisional).

### 3.2 `lector`

Claves candidatas: `{documento}`, `{id_cuenta}`, `{correo}` (cuando no es NULL).

| DF | Origen | Regla verificada |
|---|---|---|
| documento → id_cuenta, nombre, correo, telefono | R-PK | R-BCNF |
| id_cuenta → documento, nombre, correo, telefono | R-UQ + R-NEG §3.1: cada lector tiene exactamente una cuenta | R-BCNF |
| correo → documento, id_cuenta, nombre, telefono (si correo no es NULL) | R-UQ | R-BCNF |

No existen `nombre → x` (hay homónimos) ni `telefono → x` (un teléfono familiar puede repetirse). `nombre` se acepta como atómico por la decisión del equipo (R-1FN). Conclusión: **BCNF**.

### 3.3 `bibliotecario`

Claves candidatas: `{id_empleado}`, `{id_cuenta}`.

| DF | Origen | Regla verificada |
|---|---|---|
| id_empleado → id_cuenta, nombre | R-PK | R-BCNF |
| id_cuenta → id_empleado, nombre | R-UQ + R-NEG §3.1 (cada bibliotecario tiene una cuenta) | R-BCNF |

Conclusión: **BCNF**.

### 3.4 Catálogos `editorial`, `genero`, `autor`

Se crearon al normalizar `libro`. Cada uno tiene la forma `(id, nombre)` con claves candidatas `{id}` y `{nombre}`.

| DF | Origen | Regla verificada |
|---|---|---|
| id_editorial → nombre; nombre → id_editorial | R-PK, R-UQ | R-BCNF |
| id_genero → nombre; nombre → id_genero | R-PK, R-UQ | R-BCNF |
| id_autor → nombre; nombre → id_autor | R-PK, R-UQ | R-BCNF |

Supuesto declarado: el nombre del autor es único en el catálogo. Dos autores homónimos distintos se tendrían que distinguir en el propio nombre (por ejemplo, con un calificador).

### 3.5 `libro`

Claves candidatas: `{codigo}`, `{isbn}`.

| DF | Origen | Regla verificada |
|---|---|---|
| codigo → isbn, titulo, edicion, id_genero, id_editorial | R-PK | R-BCNF |
| isbn → codigo, titulo, edicion, id_genero, id_editorial | R-UQ; `codigo` se deriva del ISBN al cargar (R-NEG: carga CSV, últimos 9 dígitos) | R-BCNF |

No existen `titulo → x` (hay títulos repetidos en ediciones distintas), `id_genero → id_editorial` ni `id_editorial → id_genero`. Conclusión: **BCNF**.

### 3.6 `libro_autor`

Clave: `{codigo_libro, id_autor}` (todos los atributos son clave).

| DF / dependencia | Origen | Regla verificada |
|---|---|---|
| (codigo_libro, id_autor) → ∅ (solo triviales) | R-PK compuesta | R-BCNF, R-2FN: no hay atributos no primos |
| codigo_libro →→ id_autor (multivaluada) | Un libro tiene varios autores independientes de cualquier otro atributo | 3FN: la multivaluada queda aislada en su propia relación |

### 3.7 `unidad`

Clave candidata: `{codigo_unit}`.

| DF | Origen | Regla verificada |
|---|---|---|
| codigo_unit → codigo_libro | R-PK. Además, R-NEG (nomenclatura U-LLL-N, cuyo LLL es el libro) reforzada con el CHECK `unidad_libro_coincide` | R-BCNF |

No existe `codigo_libro → codigo_unit`: un libro tiene varios ejemplares. Conclusión: **BCNF** y sin datos derivados.

### 3.8 `prestamo`

Clave candidata: `{id_prestamo}`.

| DF | Origen | Regla verificada |
|---|---|---|
| id_prestamo → fecha_prestamo, fecha_devolucion, id_lector, codigo, id_empleado | R-PK; R-NEG §3.2: un préstamo es de UNA unidad a UN lector atendido por UN bibliotecario | R-BCNF |

No hay DF entre atributos no clave: `id_lector`, `codigo` e `id_empleado` son independientes entre sí. Conclusión: **BCNF**.

Restricciones que no son DF pero protegen el dominio:

- `fecha_devolucion >= fecha_prestamo` (CHECK `prestamo_fechas_ok`).
- «Una unidad solo puede tener un préstamo abierto (`fecha_devolucion IS NULL`) a la vez» (R-NEG). Es una restricción de unicidad condicional, no una DF, y **no se declara como índice único parcial**: `prestamo.csv` no trae `fecha_devolucion` (las devoluciones se aplican después con `devoluciones.csv`), de modo que durante la carga todos los préstamos están abiertos y el índice rechazaría los préstamos históricos de una misma unidad. La regla se verifica al terminar la carga de devoluciones (consulta 2 del §7) y la hará cumplir el trigger o procedimiento del Hito 4. Para acelerar las consultas de disponibilidad y mora existe un índice parcial no único (`prestamo_abiertos_idx`).

### 3.9 Dependencias derivadas (calculadas en vistas)

Estas dependencias no se almacenan; se calculan con las vistas `v_unidad` y `v_prestamo_en_mora`. `v_unidad` usa `EXISTS` sobre los préstamos abiertos, de modo que devuelve una fila por unidad aunque, de forma transitoria durante la carga, una unidad tenga varios préstamos abiertos.

| Dependencia | Origen | Regla |
|---|---|---|
| codigo_unit → disponibilidad (true si no hay préstamo abierto) | R-NEG §3.1 (disponibilidad) calculada desde `prestamo` | R-DER |
| (codigo_unit, fecha actual) → estado de mora | R-NEG §3.2: mora = plazo vencido y libro no devuelto | R-DER |
| (id_prestamo, fecha actual) → en mora; fecha esperada = fecha_prestamo + 14 días | R-NEG §3.2 (plazo de 14 días, función `plazo_prestamo_dias()`) | R-DER |

## 4. Anomalías encontradas y correcciones

### 4.1 `unidad`: datos derivados almacenados

`disponibilidad` y `estado` repetían información que ya está en `prestamo`. Si se registraba un préstamo sin actualizar la unidad (o viceversa), la base quedaba inconsistente (anomalía de actualización). Además, `estado` depende de la fecha actual: un indicador almacenado queda desactualizado cada día que pasa, salvo que un proceso lo recalcule. Con la regla `unidad_disponible_no_mora` esta inconsistencia solo se detectaba parcialmente.

**Corrección:** se eliminan ambas columnas; la vista `v_unidad` las calcula. La regla «disponible no puede estar en mora» se cumple por construcción (sin préstamo abierto no hay mora).

**Garantía de «un préstamo abierto por unidad».** La columna `disponibilidad` evitaba, de forma indirecta, prestar dos veces la misma unidad. Al eliminarla, esa garantía debe darla otro mecanismo. Se evaluó un índice único parcial sobre `prestamo(codigo) WHERE fecha_devolucion IS NULL` y se descartó, porque la carga por CSV en dos pasos (primero `prestamo.csv`, luego `devoluciones.csv`) deja temporalmente abiertos todos los préstamos y el índice abortaría la carga. En su lugar: (1) la carga de devoluciones termina con una verificación que debe devolver cero filas; (2) el Hito 4 debe incluir un trigger o procedimiento que impida registrar un préstamo sobre una unidad que ya tiene uno abierto.

### 4.2 `unidad`: claves y redundancia

La tabla tenía dos identificadores (`codigo` sustituto y `codigo_unit`) y el libro aparecía dos veces (en `codigo_libro` y dentro del texto `U-LLL-N`). **Corrección:** `codigo_unit` es la única clave; se elimina `codigo`; el CHECK `unidad_libro_coincide` obliga a que el libro codificado coincida con `codigo_libro`.

### 4.3 `prestamo`: dependencia transitiva

Con `codigo_libro` en `prestamo` existía `id_prestamo → codigo → codigo_libro` (transitividad, R-ARM), que viola R-3FN: `codigo_libro` depende de un atributo no clave. Podía producir préstamos cuya unidad no pertenece al libro registrado. **Corrección:** se elimina `codigo_libro`; el libro se obtiene con `JOIN unidad`.

### 4.4 `libro`: 1FN, repetición de texto y clave truncada

- `autor` es un solo varchar: con coautoría se almacenarían varios valores en una celda (viola R-1FN). Se crean `autor` y `libro_autor`.
- `genero` y `editorial` son texto libre: variantes como «Planeta» y «planeta » se tratarían como entidades distintas, y renombrar una editorial exigiría actualizar muchas filas (anomalía de actualización). Con un solo atributo descriptivo estas columnas no violan R-3FN en sentido estricto; se extraen por integridad referencial y para evitar anomalías de actualización (decisión de diseño, no obligación de forma normal).
- `codigo` conserva solo los últimos 9 dígitos del ISBN y se pierde el ISBN completo. Se agrega `isbn` (13 dígitos, UNIQUE, NOT NULL).

### 4.5 `creado_por` y `cuenta_usuario`

La tabla `creado_por` no tenía PK y permitía filas con NULL; además, su contenido es una relación N:1 (una cuenta tiene un creador) que cabe en una columna. **Corrección:** se elimina y se agrega `cuenta_usuario.creado_por`.

Diferencia frente al análisis previo: la propuesta original era una FK a `bibliotecario(id_empleado)`. Según la definición (§4), el **administrador** crea las cuentas de bibliotecario y no tiene fila en `bibliotecario`; esa FK no podría representarlo, y además generaba una referencia circular con `bibliotecario.id_cuenta`. Por eso la FK apunta a `cuenta_usuario(id_cuenta)` (auto-referencia), válida para cualquier perfil creador. El valor es NULL en cuentas iniciales.

## 5. Desnormalización evaluada y descartada

Se consideró conservar `disponibilidad` y `estado` en `unidad` como desnormalización deliberada. Se descartó por estas razones:

- Ahorraría una subconsulta o `JOIN`, pero el volumen del proyecto es pequeño y el costo de la vista es insignificante.
- Exigiría mantener sincronizados tres lugares (alta de préstamo, devolución y paso del tiempo para la mora), con riesgo de inconsistencia.
- `estado` cambia sin que ocurra ningún evento en la base (solo pasa el tiempo), por lo que necesitaría un proceso programado.

Si en el futuro el rendimiento lo exigiera, se recomienda una vista materializada en lugar de columnas en la tabla base.

## 6. Scripts de carga adaptados y Hito 4

Los scripts de carga `S14-*.sql` ya se ajustaron al esquema normalizado y se probaron de punta a punta con CSV de prueba (carga, recarga y limpieza). Orden de ejecución: libros → lectores → bibliotecarios → unidades → préstamos → devoluciones.

1. **`S14-carga-libros.sql`:** inserta en `editorial`, `genero` y `autor` con `ON CONFLICT (nombre) DO NOTHING`, luego en `libro` (con `isbn` completo, `edicion` por defecto «1ra Edición» y editorial por defecto «Editorial General», que existe como fila de catálogo) y por último en `libro_autor`. Los coautores se escriben separados por `;` dentro de la columna `autor` del CSV. Rechaza además los elementos de autor vacíos (`A;;B`) y los `isbn` ya existentes.
2. **`S14-carga-unidades.sql`:** inserta solo `codigo_unit` y `codigo_libro`. Las columnas `disponibilidad` y `estado` del CSV se siguen validando (formato y regla «disponible no puede estar en mora») pero ya no se guardan.
3. **`S14-carga-prestamos.sql`:** ya no inserta `codigo_libro`; el valor del CSV se usa solo para validar que coincida con `unidad.codigo_libro`. Debe correr antes que las devoluciones.
4. **`S14-carga-devoluciones.sql`:** al final verifica que ninguna unidad quede con más de un préstamo abierto (debe devolver cero filas).
5. **`S14-limpiar-datos.sql`:** ya no menciona la tabla `creado_por` y vacía también `editorial`, `genero`, `autor` y `libro_autor`.
6. **`S14-carga-lectores.sql` y `S14-carga-bibliotecarios.sql`:** sin cambios.
7. **Hito 4:** el trigger de ejemplo «marcar el préstamo como en mora» ya no es necesario (la mora se calcula). Siguen siendo reglas con propósito real: impedir un préstamo sobre una unidad que ya tiene uno abierto (§4.1), impedir un préstamo si el lector tiene uno en mora (`v_prestamo_en_mora`), limitar a 3 préstamos activos por lector, y el procedimiento que registra una devolución.

## 7. Consultas de evidencia

Deben devolver cero filas sobre datos válidos.

```sql
-- 1. Unidades cuyo libro codificado no coincide con codigo_libro (garantizado por CHECK)
SELECT codigo_unit FROM biblioteca.unidad
WHERE split_part(codigo_unit, '-', 2)::int <> codigo_libro;

-- 2. Unidades con más de un préstamo abierto
--    (se verifica tras cargar las devoluciones; lo hará cumplir el Hito 4)
SELECT codigo, COUNT(*) FROM biblioteca.prestamo
WHERE fecha_devolucion IS NULL GROUP BY codigo HAVING COUNT(*) > 1;

-- 3. Libros sin autor registrado
SELECT l.codigo FROM biblioteca.libro l
LEFT JOIN biblioteca.libro_autor la ON la.codigo_libro = l.codigo
WHERE la.codigo_libro IS NULL;

-- 4. Mora calculada (reporte de morosos)
SELECT DISTINCT id_lector FROM biblioteca.v_prestamo_en_mora;
```

## 8. Observaciones fuera del alcance de la normalización (pendientes de aplicar para proximas entregas del proyecto)

- La definición (§3.1) pide baja/inactivación de libros, lectores y cuentas, pero el esquema no tiene indicadores de actividad (por ejemplo `activo boolean`). Conviene agregarlos antes del Hito 5.
- Nada obliga a que la cuenta de un `lector` tenga `perfil = 'lector'` (ni la de un `bibliotecario`, `perfil = 'bibliotecario'`). Puede reforzarse con un trigger o una clave compuesta.
- Los scripts de carga de lectores y bibliotecarios guardan la contraseña inicial `123456` en texto plano en `login_contrasena`. Es provisional: la definición (§6.2) exige hash (por ejemplo bcrypt) y debe resolverse antes del Hito 5.
- Las tablas de entrada `stg_*` de `02_staging.sql` no se modificaron: son tablas de paso en texto y no forman parte del modelo normalizado.

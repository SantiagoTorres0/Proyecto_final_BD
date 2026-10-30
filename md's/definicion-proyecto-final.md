# Proyecto integrador — Sistema de gestión de biblioteca

**750006C Bases de Datos · Universidad del Valle**
Documento de definición · v1 (borrador para revisión, aún no convertido a .docx)

> Este documento fija un **dominio único para todos los equipos** (una biblioteca). Referencia técnica del entorno de trabajo: [`../entorno-docker/README.md`](../entorno-docker/README.md). Referencia del cronograma y los hitos originales: [`../plan-curso.md`](../plan-curso.md), sección 7.

---

## 1. Qué es este documento

La definición formal del proyecto integrador del curso: qué deben construir los equipos, con qué reglas, en qué entregas parciales (hitos) y con qué rúbrica se califica cada una. Se entrega ahora, en la semana del módulo 2, para que los equipos empiecen a trabajar de inmediato — el primer hito formal (modelo E-R) vence en S8, como ya estaba previsto en el cronograma general.

## 2. Modalidad de trabajo

- **Equipos de 4 estudiantes**, ya conformados en la sesión anterior.
- **Un solo dominio para todo el curso** (ambas cohortes): un sistema de gestión de biblioteca. Decisión deliberada: con un dominio único es más fácil dar retroalimentación consistente entre ~20-26 equipos y asegurar que el alcance es algo que todos pueden terminar en el tiempo del curso. Lo que varía entre equipos son las decisiones de diseño (modelo E-R, reglas de negocio afinadas, arquitectura de la API, la GUI), no el problema a resolver.
- Calificación **por equipo** en todas las entregas de hitos, siguiendo la política ya establecida para el curso (`plan-curso.md`, sección 8). La sustentación final incluye, además, una componente breve de preguntas individuales (ver sección 8) para verificar que los 4 integrantes conocen el proyecto completo.
- Organización interna del equipo: libre. Se sugiere (no se exige) repartir responsabilidades por capa — alguien más enfocado en BD, alguien en la API, alguien en la GUI, alguien en pruebas/documentación — pero todos deben poder explicar cualquier parte del sistema en la sustentación.

### 2.1 Ponderación en la nota final del curso

| Componente | % |
|---|---|
| Proyecto integrador (este documento) | **30%** |
| Examen 1 (parcial 1, S12) | 25% |
| Examen 2 (parcial 2, S24) | 25% |
| Talleres, laboratorios y quizzes | 20% |

Dentro de ese 30% del proyecto, cada hito de la sección 8 pesa proporcionalmente a sus puntos de rúbrica (sección 9) — ver la tabla de conversión al inicio de la sección 9.

## 3. Descripción general del sistema

Un sistema que administra el préstamo de libros de una biblioteca: catálogo de libros, usuarios lectores, el ciclo de préstamo/devolución, y un conjunto de reportes de uso. El sistema tiene cuatro perfiles de usuario con distintos privilegios (sección 4), una API REST como única vía de acceso a los datos (sección 6), y una interfaz web sencilla (sección 6.4).

### 3.1 Alcance funcional

El sistema debe permitir:

1. **Gestión de libros** — alta, edición, baja/inactivación, consulta del catálogo, y **carga masiva desde un archivo CSV**.
2. **Gestión de usuarios lectores** — alta, edición, baja/inactivación, consulta, y **carga masiva desde un archivo CSV**.
3. **Gestión de cuentas de bibliotecario** — el administrador puede crear, editar y desactivar cuentas de bibliotecario.
4. **Préstamos** — registrar el préstamo de un libro a un lector, respetando las reglas de negocio de la sección 3.2.
5. **Devoluciones** — registrar la devolución de un libro, actualizando disponibilidad y, si aplica, el estado de mora del préstamo.
6. **Reportes** (los cuatro son obligatorios):
   - Los 20 libros más prestados.
   - El o los usuarios que más libros han leído (préstamos completados, no abiertos — ver sección 3.2).
   - Lista de usuarios morosos (con al menos un préstamo vencido y no devuelto).
   - Notificación de préstamos en mora — dentro de la aplicación (ver nota de alcance abajo), no por correo/SMS.
7. **Login** — cada perfil inicia sesión con usuario y contraseña (sección 6.3).

**Nota de alcance — "notificación de mora":** es una **lista** (no un envío real) que muestra, por cada préstamo en mora, el nombre del lector, su correo y su teléfono, junto con un botón **"Enviar notificación"** que no ejecuta ninguna acción real (no hay envío de correo/SMS de por medio — es deliberadamente un botón sin efecto). El curso **no** pide implementar un sistema de notificación real; si algún equipo quisiera hacerlo de todas formas, es una extensión opcional sin puntos adicionales garantizados, no un requisito.

### 3.2 Reglas de negocio por defecto

Estas reglas son un punto de partida razonable, **no un requisito rígido**: cada equipo puede ajustarlas (plazo de préstamo, límite de libros simultáneos, etc.) siempre que las deje documentadas y justificadas en su entrega — es una decisión de diseño más, igual que el modelo E-R.

- Un lector tiene un máximo de **3 préstamos activos simultáneos**.
- El plazo estándar de préstamo es de **14 días** desde la fecha de entrega.
- Un préstamo se considera **en mora** cuando la fecha esperada de devolución ya pasó y el libro no ha sido devuelto.
- Un lector con **al menos un préstamo en mora** no puede solicitar nuevos préstamos hasta ponerse al día.
- El reporte de "usuario que más lee" cuenta **préstamos ya devueltos** (completados), no préstamos abiertos, para no premiar a quien simplemente tiene muchos libros retenidos.
- El registro de un préstamo o devolución lo realiza el **bibliotecario** (modela el flujo real de mostrador); el lector consulta su propio historial pero no se auto-gestiona el préstamo dentro del alcance mínimo del proyecto.

## 4. Perfiles de usuario y privilegios

| Perfil | Puede hacer | No puede hacer |
|---|---|---|
| **Lector** | Consultar el catálogo de libros y su disponibilidad; ver su propio historial y estado de préstamos (incluida su propia mora, si la tiene). | Gestionar libros, otros usuarios, ni ver reportes agregados o datos de otros lectores. |
| **Bibliotecario** | Gestionar (alta/edición/baja) libros y usuarios lectores, incluida la carga masiva por CSV de ambos; registrar préstamos y devoluciones. | Crear/gestionar cuentas de bibliotecario o auditor; ver los reportes agregados de la sección 3.1 (su función es operar el mostrador, no auditar el uso del sistema). |
| **Administrador** | Crear, editar y desactivar cuentas de **bibliotecario**; administrar la configuración general de cuentas del sistema. | Operar el día a día de libros/préstamos (eso es tarea del bibliotecario) ni ver los reportes agregados (eso es tarea del auditor) — salvo que el equipo justifique una excepción razonada. |
| **Auditor** | Ver **todos** los reportes de la sección 3.1 (solo lectura). | Modificar cualquier dato: libros, usuarios, préstamos, cuentas. Acceso estrictamente de lectura. |

Esta tabla es intencionalmente de **mínimo privilegio por función** — es material directo del módulo 7 (roles y permisos, GRANT/REVOKE). El requisito técnico correspondiente está en la sección 6.2: cada perfil de la aplicación debe respaldarse en un **rol real de PostgreSQL** con exactamente los privilegios que necesita, no en un único usuario de base de datos compartido por toda la aplicación.

## 5. Datos de entrada (CSV)

Libros y usuarios lectores deben poder cargarse masivamente desde un archivo `.csv`. Queda a criterio de cada equipo el mecanismo (`COPY` de PostgreSQL invocado desde un script, un endpoint de la API que parsee el archivo, etc.) — lo que se evalúa es que la carga funcione, valide errores razonables (filas mal formadas, duplicados) y quede documentada, no la herramienta específica usada.

El curso entrega un CSV de ejemplo (libros + lectores) como semilla mínima común a todos los equipos, en [`datos-semilla/`](datos-semilla/) — incluye además una versión con errores intencionales de cada archivo, pensada específicamente para probar la validación de la carga (ver `datos-semilla/README.md`). Cada equipo puede ampliar los archivos limpios con más datos propios para sus pruebas y su demo de sustentación.

## 6. Requisitos técnicos

### 6.1 Base de datos

- Motor: **PostgreSQL**, corriendo sobre el entorno Docker ya entregado del curso ([`entorno-docker/`](../entorno-docker/)). El esquema del proyecto vive en `postgres/init/` de la copia del entorno que use cada equipo.
- El modelo de datos (entidades, atributos, claves, normalización) es responsabilidad de diseño del equipo — es, de hecho, el contenido de los Hitos 1 y 3 (sección 8). Este documento define **qué debe hacer el sistema**, no el esquema; modelarlo es parte de la evaluación.
- Al menos un procedimiento almacenado y un disparador (trigger) con propósito real de negocio (no un ejemplo de relleno) — ver Hito 4.

### 6.2 Seguridad y mínimo privilegio

- Cada perfil de la sección 4 debe respaldarse en un **rol de PostgreSQL** propio, con privilegios (`GRANT`/`REVOKE`) acotados exactamente a lo que ese perfil necesita — ni la aplicación completa ni ningún perfil debe conectarse a la base con un usuario superusuario (el `curso` del entorno del curso es superusuario y sirve para administración/desarrollo, **no** para que la aplicación se conecte con él en producción del proyecto).
- Las contraseñas de login de la aplicación (sección 6.3) se guardan **con hash** (ej. `bcrypt`), nunca en texto plano. Nota de precisión conceptual para la sustentación: un hash no es lo mismo que "cifrado" (encriptado) en sentido estricto — es una función de un solo sentido, no reversible — y se espera que el equipo pueda explicar la diferencia.

### 6.3 Login

- Sistema de login simple con usuario y contraseña. **No se exige** autenticación avanzada (JWT, OAuth, 2FA, expiración/refresco de tokens) — eso no es contenido evaluado en este curso. Una sesión simple (cookie de sesión, o incluso reenviar credenciales en cada request) es aceptable.
- El login debe distinguir el perfil del usuario autenticado y exponer en la GUI solo las operaciones permitidas para ese perfil (sección 4) — la restricción real de datos, sin embargo, debe estar en la base de datos (sección 6.2), no solo escondida en la interfaz.

### 6.4 API REST

- Toda comunicación entre la GUI y la base de datos pasa por una **API REST en Node.js** (Express, mismo stack ya sugerido para el curso en `plan-curso.md` §7) — la GUI nunca se conecta directamente a PostgreSQL.
- La API corre sobre el servicio `node` del entorno Docker del curso, con el proyecto montado en `node/proyecto/`.
- Debe exponer el CRUD principal (libros, usuarios, préstamos, devoluciones, reportes) y estar documentada (OpenAPI, con `swagger-jsdoc` + Scalar u otra herramienta equivalente).

### 6.5 GUI

- Interfaz web sencilla en HTML/CSS/JS que cubra las operaciones básicas de cada perfil: login, y según corresponda, gestión de libros/usuarios, registrar préstamo/devolución, y visualización de reportes.
- **Se sugiere explícitamente apoyarse en herramientas de IA generativa para construir la GUI** — no es contenido evaluado de este curso, y el tiempo del equipo rinde más invertido en el modelo de datos, la API y la seguridad. Lo que se evalúa de la GUI es que funcione y consuma correctamente la API, no su diseño visual.

### 6.6 Fuera de alcance

Para que quede explícito qué **no** se espera (y evitar que un equipo invierta tiempo de más donde no se califica):

- Autenticación avanzada (JWT, OAuth, 2FA), notificaciones reales por correo/SMS, diseño visual elaborado de la GUI, pruebas de carga/rendimiento, despliegue en la nube o en un dominio público. Todo el proyecto corre localmente sobre el entorno Docker del curso.

## 7. Trazabilidad con el curso

| Hito | Corresponde a | RA / Módulo |
|---|---|---|
| 1. Modelo E-R | S8 | RA2 / M2 |
| 2. Esquema + carga de datos | S16 | RA3-RA4 / M4 |
| 3. Normalización | S20 | RA3 / M5 |
| 4. Procedimiento + trigger | Semana 12 (cierre M6) | RA4 / M6 |
| 5. Roles + API REST | S28 | RA4 / M7 |
| 6. Integración + sustentación | S29–S32 | RA1–RA4 (integrador) |

## 8. Hitos y entregas

| # | Cuándo | Qué se entrega | Cómo |
|---|---|---|---|
| **1** | **S8** (sem. 4) | Modelo E-R completo del sistema de biblioteca (entidades, atributos, claves candidatas, cardinalidad/participación de cada relación), modelado en dbdiagram.io, con DDL generado. Incluye cómo se modelan los 4 perfiles de usuario. | Enlace a dbdiagram.io + exportación (PDF o imagen) + documento breve (máx. 1 página) justificando 2-3 decisiones clave de modelado. |
| **2** | **S16** (sem. 8) | Esquema implementado en PostgreSQL (script en `postgres/init/`) + mecanismo de carga masiva de libros y lectores desde CSV, probado con el CSV semilla del curso + al menos uno propio + consultas SQL base para los 4 reportes (aunque falten reglas de negocio finas). | Repositorio del equipo con el esquema, el/los script(s)/mecanismo de carga, y las consultas documentadas (qué hace cada una). |
| **3** | **S20** (sem. 10) | Esquema revisado: análisis de formas normales (mínimo 3FN) con evidencia de dependencias funcionales; ajustes aplicados si se encontraron anomalías, o desnormalización deliberada y justificada. | Documento breve de normalización (antes/después si hubo cambios) + esquema SQL actualizado. |
| **4** | **Semana 12** | Al menos un procedimiento almacenado y un trigger con propósito real (ej.: trigger que marque un préstamo como "en mora" al vencer el plazo, o que impida un nuevo préstamo si el lector ya está en mora; procedimiento para registrar una devolución completa con sus efectos). | Scripts SQL + demo corta (video de 2-3 min o secuencia de pantallazos) mostrando el trigger disparándose. |
| **5** | **S28** (sem. 14) | Roles de PostgreSQL con privilegios mínimos por perfil (sección 6.2) + API REST funcionando con el CRUD principal + documentación OpenAPI + login con contraseñas hasheadas. | API corriendo sobre el entorno Docker + colección de pruebas (Postman/Thunder Client/curl) + doc OpenAPI accesible. |
| **6** | **S29–S32** (sem. 15-16) | Integración completa: GUI conectada a la API, funcional para los 4 perfiles según la sección 4; README del proyecto (cómo levantarlo con el entorno Docker, usuarios de prueba de cada perfil); sustentación en vivo. | Repositorio completo + sustentación (demo + preguntas). |

## 9. Rúbricas

Calificación por equipo salvo donde se indica lo contrario (sustentación). Escala checklist 0/1/2 por criterio, igual que el resto del curso.

**Conversión de puntos de hito a % de la nota final** (sobre el 30% del proyecto, sección 2.1):

| Hito | Puntos máx. | % de la nota final del curso |
|---|---|---|
| 1. Modelo E-R | 8 | 4.8% |
| 2. Esquema + carga de datos | 8 | 4.8% |
| 3. Normalización | 6 | 3.6% |
| 4. Procedimiento + trigger | 6 | 3.6% |
| 5. Roles + API REST | 10 | 6.0% |
| 6. Integración + sustentación | 12 | 7.2% |
| **Total** | **50** | **30%** |

### Hito 1 — Modelo E-R (máx. 8 pts)

| Criterio | 0 | 1 | 2 |
|---|---|---|---|
| Cobertura funcional | Faltan entidades/atributos necesarios para el alcance de la sección 3.1 | Cobertura parcial, con vacíos menores | Modelo cubre todo el alcance funcional descrito |
| Cardinalidad/participación | Errores frecuentes | Aciertos parciales | Correctas en la gran mayoría de relaciones |
| Modelado de los 4 perfiles | No se distingue cómo se representan los perfiles | Se representan pero de forma ambigua o incompleta | Representación clara y justificada de los 4 perfiles y sus diferencias |
| Justificación de decisiones | Ausente | Superficial | Explica el porqué de 2-3 decisiones de diseño no triviales |

### Hito 2 — Esquema + carga de datos (máx. 8 pts)

| Criterio | 0 | 1 | 2 |
|---|---|---|---|
| Esquema ejecuta sin errores | No corre | Corre con advertencias/ajustes manuales | Corre limpio en el entorno Docker del curso |
| Carga CSV funcional | No funciona o no se probó | Funciona solo con el CSV semilla | Funciona con el CSV semilla y datos propios adicionales |
| Manejo de errores de carga | No valida nada | Valida algunos casos | Valida filas mal formadas/duplicados de forma razonable |
| Consultas base de los 4 reportes | Faltan una o más | Todas presentes pero con errores | Las 4 consultas devuelven resultados correctos |

### Hito 3 — Normalización (máx. 6 pts)

| Criterio | 0 | 1 | 2 |
|---|---|---|---|
| Análisis de formas normales | Ausente o incorrecto | Superficial | Identifica correctamente el nivel de normalización y las dependencias funcionales relevantes |
| Corrección de anomalías (o justificación de desnormalización) | No se aborda | Se aborda parcialmente | Esquema ajustado y justificado, o desnormalización explícita y bien argumentada |
| Esquema actualizado y consistente | Desactualizado respecto al análisis | Parcialmente actualizado | Coherente con el análisis presentado |

### Hito 4 — Procedimiento y trigger (máx. 6 pts)

| Criterio | 0 | 1 | 2 |
|---|---|---|---|
| Procedimiento almacenado funcional | Ausente o no ejecuta | Ejecuta con errores/casos no cubiertos | Ejecuta correctamente y cubre el caso de uso descrito |
| Trigger con propósito real de negocio | Ausente, o es un ejemplo de relleno sin relación con el dominio | Se dispara pero la lógica es cuestionable | Se dispara correctamente y resuelve una regla de negocio real del proyecto |
| Evidencia de funcionamiento | No hay demo | Demo incompleta | Demo clara del disparo del trigger con datos reales del proyecto |

### Hito 5 — Roles, seguridad y API REST (máx. 10 pts)

| Criterio | 0 | 1 | 2 |
|---|---|---|---|
| Roles de Postgres por perfil | Un solo usuario de BD para todo | Roles creados pero con privilegios de más | 4 roles con privilegios mínimos correctamente acotados |
| Login con contraseñas hasheadas | Contraseñas en texto plano | Hash presente pero mal aplicado (ej. sin *salt*) | Hash correctamente implementado (ej. bcrypt con *salt*) |
| API cubre el CRUD principal | Faltan operaciones clave | CRUD incompleto en algún recurso | Cubre libros, usuarios, préstamos, devoluciones y reportes |
| Documentación OpenAPI | Ausente | Incompleta o desactualizada | Completa y accesible (ej. Scalar/Swagger UI) |
| API nunca expone acceso directo a Postgres desde la GUI | La GUI se conecta directo a la BD | Mezcla de accesos directos y por API | Toda comunicación pasa por la API |

### Hito 6 — Integración y sustentación (máx. 12 pts, incluye componente individual)

| Criterio | 0 | 1 | 2 | ¿Grupal o individual? |
|---|---|---|---|---|
| GUI funcional para los 4 perfiles | Falta uno o más perfiles | Todos presentes, con fallas notorias | Los 4 perfiles operan correctamente sus funciones (sección 4) | Grupal |
| README / instrucciones de instalación | Ausente o insuficiente | Incompleto | Permite levantar el proyecto desde cero con el entorno Docker del curso | Grupal |
| Demo en vivo coherente con lo entregado en los hitos anteriores | No coincide con lo entregado antes | Coincide parcialmente | Coincide y muestra el sistema integrado end-to-end | Grupal |
| Respuesta individual a preguntas de sustentación | El estudiante no puede explicar partes básicas del proyecto | Explica con ayuda del equipo | Explica con soltura cualquier parte del proyecto que se le pregunte | **Individual** (por estudiante, puede ajustar la nota grupal ± hacia arriba o abajo por persona) |

## 10. Decisiones ya confirmadas (para trazabilidad)

- **Ponderación:** proyecto 30%, examen 1 25%, examen 2 25%, talleres/labs/quizzes 20% (sección 2.1).
- **"Notificación de mora":** lista con nombre/correo/teléfono del lector + botón "Enviar notificación" sin acción real; no se implementa un sistema de notificación real (sección 3.1).
- **Reglas de negocio de la sección 3.2:** quedan como valores por defecto, editables por cada equipo si los justifican.
- **Auditor y Administrador sin acceso cruzado** (sección 4): confirmado tal como estaba propuesto.
- **Dominio único para todos los equipos:** confirmado; en consecuencia se actualiza S7 (y se revisa S8 y `plan-curso.md` §7) para que dejen de asumir elección libre de dominio.
- **CSV semilla común:** construido, en [`datos-semilla/`](datos-semilla/) (32 libros + 20 lectores válidos, más un archivo de cada uno con errores intencionales para probar la validación de la carga).

## 11. Supuestos aún pendientes

Ninguno por ahora — todos los supuestos abiertos de la v1 quedaron resueltos (sección 10).

---

*Siguiente paso: revisión de este documento. Una vez aprobado, se convierte a `.docx` con la plantilla del curso (`plantilla-word-arial12.docx`) para distribución formal a los equipos.*

-- TOP 20 LIBROS MAS LEIDOS
-- Se usa COUNT(*) para contar todas las veces que un libro ha sido prestado y presumiblemente leido, ya sea en estado de prestado, mora o devuelto
-- Agrupamos por libro en vez de unidad, asi si se presta 2 veces el Quijote edicion 1 y 18 veces el Quijote edicion 2, se cuentan 20 en total, en vez de contarse por unidad/edicion
-- En caso de empates y por practicidad, se ordena alfabeticamente por el titulo 

SET search_path TO biblioteca;
SELECT 
       l.codigo,
       l.titulo,
       l.autor,
       COUNT(*) AS total_prestamos
FROM libro l
JOIN prestamo p ON p.codigo_libro = l.codigo
GROUP BY l.codigo, l.titulo, l.autor
ORDER BY total_prestamos DESC, l.titulo
LIMIT 20;

-- TOP USUARIOS MAS COME LIBROS COMO MI AMIX VALERY
-- Se usa una subconsulta para armar la lista de lectores con su num de devoluciones y posteriormente se filtra y arma una con aquellos usuarios que empatan en la cantidad maxima de devoluciones

SET search_path TO biblioteca;
WITH conteo AS (
    SELECT p.id_lector,
           COUNT(*) AS libros_devueltos
    FROM prestamo p
    WHERE p.fecha_devolucion IS NOT NULL
    GROUP BY p.id_lector
)
SELECT l.nombre AS lector,
       c.libros_devueltos
FROM conteo c
JOIN lector l ON l.documento = c.id_lector
WHERE c.libros_devueltos = (SELECT MAX(libros_devueltos) FROM conteo);

-- LECTORES MOROSOS ANP
-- Se usa distinct para evitar repetir lectores con diferentes moras, con una es suficiente para aparecer en la lista, se cuentan los prestamos que todavia no tienen fecha de devolucion (o sea, estaran en estado de prestamo o mora) y se confirma si esta en mora con fecha_prestamo + 14 < CURRENT_DATE;

SET search_path TO biblioteca;
SELECT DISTINCT l.documento,
                l.nombre 
FROM prestamo p
JOIN lector l ON l.documento = p.id_lector
WHERE p.fecha_devolucion IS NULL
AND p.fecha_prestamo + 14 < CURRENT_DATE;

-- PRESTAMOS EN ESTADO DE MORA
-- Se rehusan las condiciones de mora de la consulta de lectores morosos y se calculan los dias que un titulo lleva en mora junto con la informacion de contacto de la persona que tiene posesion del libro (o mejor dicho quien lo pidio prestado) 

SET search_path TO biblioteca;
SELECT 
       l.nombre AS nombre_lector,
       l.correo,
       l.telefono
       ,b.titulo
       , p.fecha_prestamo + 14 AS fecha_esperada
       , CURRENT_DATE - (p.fecha_prestamo + 14) AS dias_de_mora
FROM prestamo p
JOIN libro b ON b.codigo = p.codigo_libro
JOIN lector l ON l.documento = p.id_lector
WHERE p.fecha_devolucion IS NULL
  AND p.fecha_prestamo + 14 < CURRENT_DATE
ORDER BY fecha_esperada;

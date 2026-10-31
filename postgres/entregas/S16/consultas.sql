--Evan David Arregocés Delgado - 202517690
--Santiago Torres Martinez - 202521423
--Lissette Johana Patiño Quinayas - 202520977



-- 1
SET search_path TO tienda;

SELECT c.nombre AS cliente, pr.nombre AS producto, p.id_pedido
FROM pedido p
JOIN cliente c ON p.id_cliente = c.id_cliente
JOIN detalle d ON p.id_pedido = d.id_pedido
JOIN producto pr ON d.id_producto = pr.id_producto
WHERE p.id_pedido = 1003;

--2.
SET search_path TO tienda;

SELECT 
    c.nombre AS cliente,
    r.nombre AS referido_por
FROM 
    cliente c
LEFT JOIN 
    cliente r ON c.referido_por = r.id_cliente;

--3.
SET search_path TO tienda;

 SELECT p.id_producto, d.id_producto, p.nombre
 FROM producto p
 LEFT JOIN 
 	detalle d ON p.id_producto = d.id_producto
WHERE d.id_producto IS NULL;

--4
SET search_path TO tienda;

SELECT c.id_cliente, c.nombre AS cliente, COUNT(p.id_pedido) AS total_pedidos
FROM cliente c
LEFT JOIN pedido p ON c.id_cliente = p.id_cliente
GROUP BY c.id_cliente, c.nombre
ORDER BY total_pedidos DESC;

-- 5
SET search_path TO tienda;

SELECT pr.categoria,
		SUM(d.cantidad * d.precio_unitario) AS total_vendido
FROM producto pr
JOIN detalle d ON d.id_producto = pr.id_producto
JOIN pedido p  ON p.id_pedido   = d.id_pedido
WHERE p.estado <> 'cancelado'
GROUP BY pr.categoria
ORDER BY total_vendido DESC;

-- 6
SET search_path TO tienda;

SELECT extract(month FROM p.fecha) AS mes,
       SUM(d.cantidad * d.precio_unitario) AS total
FROM pedido p
JOIN detalle d ON d.id_pedido = p.id_pedido
WHERE p.estado <> 'cancelado'
  AND extract(year FROM p.fecha) = 2026
GROUP BY extract(month FROM p.fecha)
HAVING SUM(d.cantidad * d.precio_unitario) > 200000
ORDER BY mes;

--7.
SET search_path TO tienda;

SELECT 
    p1.id_producto,
    p1.nombre,
    p1.categoria,
    p1.precio
FROM 
    producto p1
WHERE 
    p1.precio > (
        SELECT AVG(p2.precio)
        FROM producto p2
        WHERE p2.categoria = p1.categoria
    );

--8.
SET search_path TO tienda;

SELECT c.id_cliente, c.nombre, c.ciudad
FROM   cliente c
WHERE  c.ciudad = 'Cali'
  AND  EXISTS (
          SELECT 1
          FROM   pedido p
          JOIN   detalle dp ON dp.id_pedido = p.id_pedido
          JOIN   producto prod     ON prod.id_producto = dp.id_producto
          WHERE  p.id_cliente = c.id_cliente          -- ← Relación con el cliente de afuera
            AND  prod.categoria = 'Accesorio'          -- Un accesorio
            AND  p.estado <> 'cancelado'               -- Sin cancelados
       );


--9
SET search_path TO tienda;

SELECT nombre 
FROM cliente 
WHERE id_cliente
NOT IN (SELECT referido_por FROM cliente);

-- No devuelve nada debido a la columna "referido_por" no es NOT NULL, o sea que permite valores nulos, al usar el operador NOT IN, si hay un valor nulo, no devuelve nada

--9 correcion
SET search_path TO tienda;

SELECT nombre 
FROM cliente c 
WHERE NOT EXISTS (
SELECT 1
FROM cliente ref
WHERE ref.referido_por = c.id_cliente
);

-- 10
SET search_path TO tienda;

WITH GastoRecord AS (
SELECT
c.id_cliente, c.nombre, SUM(d.cantidad * d.precio_unitario) AS GastoIndividual
FROM cliente c
JOIN pedido p ON c.id_cliente = p.id_cliente
JOIN detalle d ON p.id_pedido = d.id_pedido

GROUP BY c.id_cliente, c.nombre
) 
SELECT nombre, GastoIndividual
FROM GastoRecord
WHERE GastoIndividual = (SELECT MAX(GastoIndividual) FROM GastoRecord);

-- 11
SET search_path TO tienda;

SELECT c.nombre
FROM cliente c
WHERE NOT EXISTS (
    SELECT 1
    FROM producto pr
    WHERE pr.categoria = 'Grano'
      AND NOT EXISTS (
          SELECT 1
          FROM pedido p
          JOIN detalle d ON d.id_pedido = p.id_pedido
          WHERE p.id_cliente  = c.id_cliente
            AND d.id_producto = pr.id_producto
            AND p.estado <> 'cancelado'
      )
);

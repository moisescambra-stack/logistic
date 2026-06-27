-- ═══════════════════════════════════════════════════════════════════
-- SQL OPERATIVO — LOGÍSTICA Y SUPPLY CHAIN
-- Casos de uso reales en operaciones logísticas
-- Stack: SQL Server · T-SQL
-- ═══════════════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────────────
-- TABLAS DE REFERENCIA (estructura simplificada)
-- ───────────────────────────────────────────────────────────────────

-- pedidos: id_pedido, id_cliente, id_ruta, fecha_pedido,
--          fecha_entrega_prometida, fecha_entrega_real,
--          estado, importe, unidades, transportista

-- rutas:   id_ruta, origen, destino, km, tipo (urbana/interurbana)

-- stock:   id_producto, descripcion, familia,
--          stock_actual, stock_minimo, stock_maximo, coste_unitario

-- movimientos: id_mov, id_producto, tipo (Entrada/Salida),
--              cantidad, fecha, id_pedido


-- ───────────────────────────────────────────────────────────────────
-- 1. OTD — On-Time Delivery por transportista
--    ¿Qué % de entregas llegaron a tiempo?
-- ───────────────────────────────────────────────────────────────────

SELECT
    transportista,
    COUNT(*)                                                AS total_entregas,
    SUM(CASE WHEN fecha_entrega_real <= fecha_entrega_prometida
             THEN 1 ELSE 0 END)                             AS entregas_a_tiempo,
    ROUND(
        SUM(CASE WHEN fecha_entrega_real <= fecha_entrega_prometida
                 THEN 1.0 ELSE 0 END)
        / COUNT(*) * 100, 1)                                AS otd_pct
FROM pedidos
WHERE estado = 'Entregado'
  AND YEAR(fecha_entrega_real) = 2026
GROUP BY transportista
ORDER BY otd_pct DESC;


-- ───────────────────────────────────────────────────────────────────
-- 2. LEAD TIME medio por ruta
--    ¿Cuántos días tarda de media cada ruta?
-- ───────────────────────────────────────────────────────────────────

SELECT
    r.origen,
    r.destino,
    r.tipo,
    COUNT(p.id_pedido)                                      AS num_entregas,
    ROUND(AVG(CAST(
        DATEDIFF(DAY, p.fecha_pedido, p.fecha_entrega_real)
    AS FLOAT)), 1)                                          AS lead_time_medio_dias,
    MAX(DATEDIFF(DAY, p.fecha_pedido, p.fecha_entrega_real)) AS lead_time_maximo
FROM pedidos p
JOIN rutas r ON p.id_ruta = r.id_ruta
WHERE p.estado = 'Entregado'
GROUP BY r.origen, r.destino, r.tipo
ORDER BY lead_time_medio_dias DESC;


-- ───────────────────────────────────────────────────────────────────
-- 3. STOCK CRÍTICO — productos por debajo del mínimo
--    Alerta de reposición urgente
-- ───────────────────────────────────────────────────────────────────

SELECT
    id_producto,
    descripcion,
    familia,
    stock_actual,
    stock_minimo,
    stock_maximo,
    stock_minimo - stock_actual                             AS unidades_a_reponer,
    CASE
        WHEN stock_actual = 0              THEN '🔴 Rotura de stock'
        WHEN stock_actual <= stock_minimo  THEN '🟡 Stock crítico'
        ELSE                                    '🟢 OK'
    END                                                     AS alerta
FROM stock
WHERE stock_actual <= stock_minimo
ORDER BY stock_actual ASC;


-- ───────────────────────────────────────────────────────────────────
-- 4. ROTACIÓN DE INVENTARIO
--    ¿Qué productos rotan rápido y cuáles se quedan parados?
-- ───────────────────────────────────────────────────────────────────

SELECT
    s.id_producto,
    s.descripcion,
    s.familia,
    s.stock_actual,
    COALESCE(SUM(ABS(m.cantidad)), 0)                       AS unidades_salidas_30d,
    CASE
        WHEN s.stock_actual = 0 THEN 0
        ELSE ROUND(
            COALESCE(SUM(ABS(m.cantidad)), 0)
            / CAST(s.stock_actual AS FLOAT), 2)
    END                                                     AS rotacion,
    CASE
        WHEN s.stock_actual = 0 THEN 'Sin stock'
        WHEN COALESCE(SUM(ABS(m.cantidad)), 0) = 0 THEN '🔴 Sin movimiento'
        WHEN COALESCE(SUM(ABS(m.cantidad)), 0)
             / CAST(s.stock_actual AS FLOAT) >= 2 THEN '🟢 Alta rotación'
        WHEN COALESCE(SUM(ABS(m.cantidad)), 0)
             / CAST(s.stock_actual AS FLOAT) >= 0.5 THEN '🟡 Rotación media'
        ELSE '🔴 Baja rotación'
    END                                                     AS clasificacion
FROM stock s
LEFT JOIN movimientos m
    ON s.id_producto = m.id_producto
    AND m.tipo = 'Salida'
    AND m.fecha >= DATEADD(DAY, -30, GETDATE())
GROUP BY s.id_producto, s.descripcion, s.familia, s.stock_actual
ORDER BY rotacion DESC;


-- ───────────────────────────────────────────────────────────────────
-- 5. PEDIDOS CON RETRASO — detección de incidencias activas
--    Pedidos que llevan más días de lo prometido sin entregarse
-- ───────────────────────────────────────────────────────────────────

SELECT
    id_pedido,
    id_cliente,
    transportista,
    fecha_pedido,
    fecha_entrega_prometida,
    GETDATE()                                               AS hoy,
    DATEDIFF(DAY, fecha_entrega_prometida, GETDATE())       AS dias_retraso,
    importe,
    CASE
        WHEN DATEDIFF(DAY, fecha_entrega_prometida, GETDATE()) > 5
            THEN '🔴 Retraso crítico'
        WHEN DATEDIFF(DAY, fecha_entrega_prometida, GETDATE()) > 2
            THEN '🟡 Retraso moderado'
        ELSE '🟠 Retraso leve'
    END                                                     AS nivel_alerta
FROM pedidos
WHERE estado NOT IN ('Entregado', 'Cancelado')
  AND fecha_entrega_prometida < GETDATE()
ORDER BY dias_retraso DESC;

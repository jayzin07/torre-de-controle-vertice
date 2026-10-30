-- Silver · entregas das consultorias: prometido × entregue

CREATE OR REFRESH MATERIALIZED VIEW entregas_fornecedor
COMMENT 'Entregas das consultorias contratadas: prometido × entregue, prazos em dias e atraso. A CodeForge, que chega com 4 grafias, foi normalizada (fornecedor_como_veio guarda a original). Entrega sem data = em aberto; em_atraso = em aberto com a data prometida antes de 16/10/2026.'
AS
WITH base AS (
  SELECT
    entrega_id,
    projeto_id,
    CASE WHEN replace(lower(fornecedor), ' ', '') LIKE '%codeforge%'
         THEN 'CodeForge Consultoria Ltda'
         ELSE fornecedor END                       AS fornecedor,
    fornecedor                                     AS fornecedor_como_veio,
    item,
    CAST(replace(valor, ',', '.') AS DECIMAL(15, 2)) AS valor,
    to_date(data_pedido)                           AS data_pedido,
    to_date(data_prometida)                        AS data_prometida,
    to_date(nullif(trim(data_entrega), ''))        AS data_entrega,   -- vazia = em aberto (não é sujeira)
    CAST(prazo_contratado_dias AS INT)             AS prazo_contratado_dias,
    status
  FROM lakehouse_vertice.bronze.entregas_fornecedor
)
SELECT
  *,
  datediff(data_prometida, data_pedido)  AS prazo_prometido_dias,
  datediff(data_entrega, data_pedido)    AS prazo_real_dias,
  datediff(data_entrega, data_prometida) AS dias_de_atraso_na_entrega,   -- negativo = entregou antes
  data_entrega IS NULL                   AS em_aberto,
  data_entrega IS NULL AND data_prometida < DATE'2026-10-16' AS em_atraso
FROM base;

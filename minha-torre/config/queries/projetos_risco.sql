-- Projetos em andamento, do pior para o melhor, com a causa no status.
-- Fontes: gold.projeto_situacao_atual (KPIs de hoje) e gold.status_estruturado
-- (o texto livre do status classificado pela IA). "Hoje" = 16/10/2026.
WITH status_90d AS (
  -- os status dos últimos 90 dias, só os que relatam um bloqueio de verdade
  SELECT projeto_id, causa_bloqueio, dias_impacto
  FROM lakehouse_vertice.gold.status_estruturado
  WHERE data_status >= date_sub(DATE'2026-10-16', 90)
    AND causa_bloqueio NOT IN ('sem_bloqueio', 'nao_reportado', 'nao_classificado')
),

causas AS (
  SELECT
    projeto_id,
    causa_bloqueio,
    COUNT(*)                         AS semanas,
    coalesce(SUM(dias_impacto), 0)   AS dias_impacto
  FROM status_90d
  GROUP BY projeto_id, causa_bloqueio
),

-- a causa mais frequente (empate: a de mais dias de impacto)
causa_ordenada AS (
  SELECT
    *,
    row_number() OVER (PARTITION BY projeto_id ORDER BY semanas DESC, dias_impacto DESC) AS ordem
  FROM causas
),

-- os dias de impacto das duas causas que o simulador resolve com gente
impacto_por_causa AS (
  SELECT
    projeto_id,
    coalesce(SUM(CASE WHEN causa_bloqueio = 'falta_sre'    THEN dias_impacto END), 0) AS dias_falta_sre,
    coalesce(SUM(CASE WHEN causa_bloqueio = 'rotatividade' THEN dias_impacto END), 0) AS dias_rotatividade
  FROM causas
  GROUP BY projeto_id
)

SELECT
  p.projeto_id,
  p.projeto,
  p.cliente,
  p.gerente_projeto,
  p.valor_contrato,
  p.situacao,
  p.spi,
  p.cpi,
  p.estouro_previsto,
  p.atraso_projetado_dias,
  p.farol_do_gerente,
  p.farol_calculado,
  p.melancia,
  c.causa_bloqueio                       AS causa_principal,
  coalesce(c.semanas, 0)                 AS semanas_causa,
  coalesce(i.dias_falta_sre, 0)          AS dias_falta_sre,
  coalesce(i.dias_rotatividade, 0)       AS dias_rotatividade
FROM lakehouse_vertice.gold.projeto_situacao_atual p
LEFT JOIN causa_ordenada c
  ON c.projeto_id = p.projeto_id AND c.ordem = 1
LEFT JOIN impacto_por_causa i
  ON i.projeto_id = p.projeto_id
WHERE p.status = 'em_andamento'
ORDER BY
  CASE p.situacao WHEN 'crítico' THEN 1 WHEN 'atenção' THEN 2 ELSE 3 END,
  least(p.spi, p.cpi),
  p.projeto_id

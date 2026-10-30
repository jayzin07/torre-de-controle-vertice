-- Gente parada: pessoas com utilização < 20% nas últimas 12 semanas (até 16/10/2026).
-- Fonte: gold.utilizacao_pessoa_semana (timesheet) + silver.colaboradores (custo por hora).
-- Horas paradas e custo ocioso são MÉDIAS por semana: o simulador multiplica por 4.
WITH ultimas_12_semanas AS (
  SELECT *
  FROM lakehouse_vertice.gold.utilizacao_pessoa_semana
  WHERE semana > date_sub(DATE'2026-10-16', 84)
),

por_pessoa AS (
  SELECT
    colaborador_id,
    nome,
    papel,
    senioridade,
    concat_ws(', ', array_sort(collect_set(projeto_id)))          AS projetos,
    COUNT(DISTINCT semana)                                         AS semanas,
    try_divide(SUM(horas_apontadas), SUM(horas_disponiveis))       AS utilizacao,
    SUM(horas_ociosas) / COUNT(DISTINCT semana)                    AS horas_ociosas_semana,
    SUM(custo_ocioso)  / COUNT(DISTINCT semana)                    AS custo_ocioso_semana
  FROM ultimas_12_semanas
  GROUP BY colaborador_id, nome, papel, senioridade
)

SELECT
  p.colaborador_id,
  p.nome,
  p.papel,
  p.senioridade,
  p.projetos,
  p.semanas,
  round(p.utilizacao, 4)               AS utilizacao,
  round(p.horas_ociosas_semana, 1)     AS horas_ociosas_semana,
  round(p.custo_ocioso_semana, 2)      AS custo_ocioso_semana,
  c.custo_hora
FROM por_pessoa p
JOIN lakehouse_vertice.silver.colaboradores c
  ON c.colaborador_id = p.colaborador_id
WHERE p.utilizacao < 0.2
ORDER BY p.utilizacao

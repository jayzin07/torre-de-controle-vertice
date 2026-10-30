-- Gold · fato_projeto_semana: a série semanal de cada projeto (PV, EV, AC, SPI, CPI).
-- O histórico do avanço vem do status semanal (as ferramentas só guardam o % de hoje).
-- O "hoje" do dataset é DATE'2026-10-16' (sexta). Funções de janela ficam num CTE
-- separado da agregação (o pipeline não aceita janela dentro de agregação).

CREATE OR REFRESH MATERIALIZED VIEW lakehouse_vertice.gold.fato_projeto_semana (
  CONSTRAINT pv_nao_negativo     EXPECT (pv >= 0)         ON VIOLATION FAIL UPDATE,
  CONSTRAINT ev_ate_o_orcamento  EXPECT (ev <= orcamento) ON VIOLATION FAIL UPDATE
)
COMMENT 'Uma linha por projeto e semana (sexta-feira), da semana do início até 16/10/2026. pv = valor planejado (orçamento × fração do baseline decorrida, ponderada pelas horas das tarefas), ev = valor agregado (orçamento × % do status semanal daquela sexta, ou o último publicado), ac = custo real acumulado, spi = ev/pv, cpi = ev/ac, eac = orçamento/cpi. Traz também o farol do gerente e as horas do timesheet da semana.'
AS
WITH semanas AS (
  -- da sexta da semana do início até hoje, de 7 em 7 dias
  SELECT
    projeto_id,
    orcamento_custo AS orcamento,
    explode(sequence(date_add(to_date(date_trunc('WEEK', data_inicio)), 4),
                     DATE'2026-10-16',
                     INTERVAL 1 WEEK)) AS semana
  FROM projetos
  WHERE data_inicio <= DATE'2026-10-16'
),

primeira_semana AS (
  SELECT projeto_id, min(semana) AS semana_inicial
  FROM semanas
  GROUP BY projeto_id
),

-- PV: fração do baseline decorrida em cada sexta, ponderada pelas horas das tarefas
planejado AS (
  SELECT
    s.projeto_id,
    s.semana,
    try_divide(
      SUM(t.horas * CASE
                      WHEN s.semana >= t.fim_baseline    THEN 1
                      WHEN s.semana <= t.inicio_baseline THEN 0
                      ELSE greatest(0, least(1, datediff(s.semana, t.inicio_baseline)
                                              / datediff(t.fim_baseline, t.inicio_baseline)))
                    END),
      SUM(t.horas)) AS fracao_planejada
  FROM semanas s
  JOIN tarefas t ON t.projeto_id = s.projeto_id
  GROUP BY s.projeto_id, s.semana
),

-- EV e farol: o status daquela sexta; sem status (projeto concluído não publica mais), o último
status_da_semana AS (
  SELECT s.projeto_id, s.semana, st.pct_concluido, st.farol
  FROM semanas s
  LEFT JOIN status_semanal st
    ON st.projeto_id = s.projeto_id AND st.data_status = s.semana
),
status_preenchido AS (
  SELECT
    projeto_id,
    semana,
    last_value(pct_concluido, true) OVER w AS pct_concluido_status,
    last_value(farol, true)         OVER w AS farol_do_gerente
  FROM status_da_semana
  WINDOW w AS (PARTITION BY projeto_id ORDER BY semana ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
),

-- AC: custo real por semana (até hoje); lançamento anterior à 1ª semana conta na 1ª semana
custo_semana AS (
  SELECT
    c.projeto_id,
    greatest(c.semana, ps.semana_inicial) AS semana,
    SUM(c.valor)                          AS custo
  FROM custos c
  JOIN primeira_semana ps ON ps.projeto_id = c.projeto_id
  WHERE c.data <= DATE'2026-10-16'
  GROUP BY c.projeto_id, greatest(c.semana, ps.semana_inicial)
),
custo_acumulado AS (
  SELECT
    s.projeto_id,
    s.semana,
    SUM(coalesce(cs.custo, 0)) OVER (PARTITION BY s.projeto_id ORDER BY s.semana
                                     ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS ac
  FROM semanas s
  LEFT JOIN custo_semana cs ON cs.projeto_id = s.projeto_id AND cs.semana = s.semana
),

-- horas do timesheet da semana
horas_semana AS (
  SELECT
    projeto_id,
    semana,
    SUM(horas_disponiveis) AS horas_disponiveis,
    SUM(horas_apontadas)   AS horas_apontadas
  FROM apontamentos
  GROUP BY projeto_id, semana
),

valores AS (
  SELECT
    s.projeto_id,
    s.semana,
    s.orcamento,
    round(s.orcamento * coalesce(pl.fracao_planejada, 0), 2)        AS pv,
    round(s.orcamento * coalesce(sp.pct_concluido_status, 0) / 100, 2) AS ev,
    round(ca.ac, 2)                                                  AS ac,
    sp.pct_concluido_status,
    sp.farol_do_gerente,
    coalesce(h.horas_disponiveis, 0)                                 AS horas_disponiveis,
    coalesce(h.horas_apontadas, 0)                                   AS horas_apontadas
  FROM semanas s
  LEFT JOIN planejado         pl ON pl.projeto_id = s.projeto_id AND pl.semana = s.semana
  LEFT JOIN status_preenchido sp ON sp.projeto_id = s.projeto_id AND sp.semana = s.semana
  LEFT JOIN custo_acumulado   ca ON ca.projeto_id = s.projeto_id AND ca.semana = s.semana
  LEFT JOIN horas_semana      h  ON h.projeto_id  = s.projeto_id AND h.semana  = s.semana
),

indices AS (
  SELECT
    *,
    round(try_divide(ev, pv), 4) AS spi,
    round(try_divide(ev, ac), 4) AS cpi
  FROM valores
)

SELECT
  projeto_id,
  semana,
  orcamento,
  pct_concluido_status,
  pv,
  ev,
  ac,
  spi,
  cpi,
  round(try_divide(orcamento, cpi), 2)               AS eac,
  farol_do_gerente,
  horas_disponiveis,
  horas_apontadas,
  greatest(horas_disponiveis - horas_apontadas, 0)   AS horas_ociosas
FROM indices;

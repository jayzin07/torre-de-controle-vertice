-- Gold · a fotografia de hoje de cada projeto e a utilização das pessoas.
-- O "hoje" do dataset é DATE'2026-10-16'. A fotografia usa o % de hoje das
-- ferramentas (silver.tarefas); a série semanal está em gold.fato_projeto_semana.

-- ---------------------------------------------------------------------------
-- projeto_situacao_atual: 60 linhas, cadastro + KPIs de hoje
-- ---------------------------------------------------------------------------
CREATE OR REFRESH MATERIALIZED VIEW lakehouse_vertice.gold.projeto_situacao_atual
COMMENT 'A fotografia de 16/10/2026 de cada um dos 60 projetos: o cadastro (cliente, segmento, tipo, ferramenta, gerente, contrato, orçamento, prazo) e os KPIs calculados sobre as tarefas das ferramentas (pv, ev, ac, spi, cpi, eac, estouro previsto, margem projetada, atraso e término projetados). situacao: concluído, crítico (SPI ou CPI < 0,8), atenção (< 0,9) ou ok. farol_calculado segue o manual (verde SPI >= 0,95, amarelo >= 0,90). melancia = em andamento, farol do gerente verde e SPI < 0,9.'
AS
WITH tarefas_hoje AS (
  -- horas totais, horas que já deveriam estar feitas (baseline) e horas agregadas (% de hoje)
  SELECT
    projeto_id,
    SUM(horas) AS horas_totais,
    SUM(horas * CASE
                  WHEN DATE'2026-10-16' >= fim_baseline    THEN 1
                  WHEN DATE'2026-10-16' <= inicio_baseline THEN 0
                  ELSE greatest(0, least(1, datediff(DATE'2026-10-16', inicio_baseline)
                                          / datediff(fim_baseline, inicio_baseline)))
                END)              AS horas_planejadas,
    SUM(horas * pct_concluido / 100) AS horas_agregadas
  FROM tarefas
  GROUP BY projeto_id
),

custo_hoje AS (
  SELECT projeto_id, SUM(valor) AS ac
  FROM custos
  WHERE data <= DATE'2026-10-16'
  GROUP BY projeto_id
),

-- o farol do último status publicado até hoje (projeto concluído parou de publicar)
status_ordenado AS (
  SELECT
    projeto_id,
    farol,
    row_number() OVER (PARTITION BY projeto_id ORDER BY data_status DESC) AS ordem
  FROM status_semanal
  WHERE data_status <= DATE'2026-10-16'
),
ultimo_status AS (
  SELECT projeto_id, farol AS farol_do_gerente
  FROM status_ordenado
  WHERE ordem = 1
),

kpis AS (
  SELECT
    p.*,
    datediff(p.data_fim_baseline, p.data_inicio)                              AS duracao_baseline_dias,
    round(p.orcamento_custo * try_divide(th.horas_planejadas, th.horas_totais), 2) AS pv,
    round(p.orcamento_custo * try_divide(th.horas_agregadas,  th.horas_totais), 2) AS ev,
    round(coalesce(ch.ac, 0), 2)                                              AS ac,
    us.farol_do_gerente
  FROM projetos p
  LEFT JOIN tarefas_hoje  th ON th.projeto_id = p.projeto_id
  LEFT JOIN custo_hoje    ch ON ch.projeto_id = p.projeto_id
  LEFT JOIN ultimo_status us ON us.projeto_id = p.projeto_id
),

indices AS (
  SELECT
    *,
    round(try_divide(ev, pv), 4) AS spi,
    round(try_divide(ev, ac), 4) AS cpi
  FROM kpis
),

projecoes AS (
  SELECT
    *,
    round(try_divide(orcamento_custo, cpi), 2)                                     AS eac,
    CAST(round(try_divide(duracao_baseline_dias, spi) - duracao_baseline_dias) AS INT) AS atraso_projetado_dias
  FROM indices
)

SELECT
  projeto_id,
  concat(projeto_id, ' · ', nome_projeto)                    AS projeto,
  nome_projeto,
  cliente,
  segmento,
  tipo_projeto,
  ferramenta,
  gerente_projeto,
  valor_contrato,
  orcamento_custo                                            AS orcamento,
  data_inicio,
  data_fim_baseline,
  duracao_baseline_dias,
  status,
  pv,
  ev,
  ac,
  spi,
  cpi,
  eac,
  greatest(eac - orcamento_custo, 0)                         AS estouro_previsto,
  round(try_divide(valor_contrato - eac, valor_contrato), 4) AS margem_projetada,
  atraso_projetado_dias,
  date_add(data_fim_baseline, atraso_projetado_dias)         AS termino_projetado,
  CASE
    WHEN status <> 'em_andamento'  THEN 'concluído'
    WHEN spi < 0.8 OR cpi < 0.8    THEN 'crítico'
    WHEN spi < 0.9 OR cpi < 0.9    THEN 'atenção'
    ELSE 'ok'
  END                                                        AS situacao,
  farol_do_gerente,
  CASE
    WHEN spi IS NULL  THEN NULL
    WHEN spi >= 0.95  THEN 'verde'
    WHEN spi >= 0.90  THEN 'amarelo'
    ELSE 'vermelho'
  END                                                        AS farol_calculado,
  coalesce(status = 'em_andamento' AND farol_do_gerente = 'verde' AND spi < 0.9, false) AS melancia
FROM projecoes;

-- ---------------------------------------------------------------------------
-- utilizacao_pessoa_semana: pessoa × projeto × semana
-- ---------------------------------------------------------------------------
CREATE OR REFRESH MATERIALIZED VIEW lakehouse_vertice.gold.utilizacao_pessoa_semana
COMMENT 'Utilização de cada pessoa por projeto e semana (sexta-feira), do timesheet: horas disponíveis, apontadas e ociosas, utilização (apontadas ÷ disponíveis), custo ocioso (horas ociosas × custo por hora) e o SPI do projeto naquela semana, para cruzar gente parada com projeto atrasado.'
AS
SELECT
  a.colaborador_id,
  c.nome,
  c.papel,
  c.senioridade,
  a.projeto_id,
  a.semana,
  a.horas_disponiveis,
  a.horas_apontadas,
  greatest(a.horas_disponiveis - a.horas_apontadas, 0)                         AS horas_ociosas,
  round(try_divide(a.horas_apontadas, a.horas_disponiveis), 4)                 AS utilizacao,
  round(greatest(a.horas_disponiveis - a.horas_apontadas, 0) * c.custo_hora, 2) AS custo_ocioso,
  f.spi                                                                        AS spi_do_projeto
FROM apontamentos a
LEFT JOIN colaboradores c
  ON c.colaborador_id = a.colaborador_id
LEFT JOIN lakehouse_vertice.gold.fato_projeto_semana f
  ON f.projeto_id = a.projeto_id AND f.semana = a.semana;

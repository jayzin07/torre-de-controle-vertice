-- Silver · tarefas: AS TRÊS FERRAMENTAS VIRAM UMA.
-- Uma visão temporária por ferramenta, todas com as MESMAS 13 colunas, e uma
-- materialized view com o UNION ALL. O projeto vem do de-para em silver.projetos.

-- ---------------------------------------------------------------------------
-- Excel: 20 planilhas, tudo texto
-- ---------------------------------------------------------------------------
CREATE TEMPORARY VIEW tarefas_excel
COMMENT 'Tarefas das planilhas Excel, já limpas (sem a linha TOTAL)'
AS
SELECT
  -- de-para pelo arquivo; se não casar (código vazio ou arquivo sem acento), o PRJ-xxx do nome do arquivo
  coalesce(p.projeto_id, nullif(regexp_extract(e.arquivo, 'PRJ-[0-9]{3}', 0), '')) AS projeto_id,
  'excel'                                     AS ferramenta,
  CAST(e.id AS STRING)                        AS id_na_ferramenta,
  e.fase,
  e.tarefa,
  e.responsavel,

  -- data com '/' é dd/MM/yyyy; sem '/' é número de série do Excel (dias desde 30/12/1899)
  CASE WHEN e.inicio_previsto  LIKE '%/%' THEN to_date(e.inicio_previsto,  'dd/MM/yyyy')
       ELSE date_add(DATE'1899-12-30', CAST(e.inicio_previsto  AS INT)) END AS inicio_baseline,
  CASE WHEN e.termino_previsto LIKE '%/%' THEN to_date(e.termino_previsto, 'dd/MM/yyyy')
       ELSE date_add(DATE'1899-12-30', CAST(e.termino_previsto AS INT)) END AS fim_baseline,
  CASE WHEN e.inicio_real      LIKE '%/%' THEN to_date(e.inicio_real,      'dd/MM/yyyy')
       ELSE date_add(DATE'1899-12-30', CAST(e.inicio_real      AS INT)) END AS inicio_real,
  CASE WHEN e.termino_real     LIKE '%/%' THEN to_date(e.termino_real,     'dd/MM/yyyy')
       ELSE date_add(DATE'1899-12-30', CAST(e.termino_real     AS INT)) END AS fim_real,

  -- '45%' e '10,5%': tira o '%' e troca a vírgula; 0.45 (sem '%') é fração
  CASE WHEN contains(e.pct_concluido, '%')
       THEN CAST(replace(replace(e.pct_concluido, '%', ''), ',', '.') AS DOUBLE)
       ELSE CAST(e.pct_concluido AS DOUBLE) * 100 END                     AS pct_como_veio,

  CAST(replace(e.horas_previstas, 'h', '') AS DOUBLE)                     AS horas,
  CAST(NULL AS STRING)                                                    AS status_na_ferramenta
FROM lakehouse_vertice.bronze.excel_tarefas e
LEFT JOIN projetos p
  ON p.ferramenta = 'excel' AND p.codigo_ferramenta = e.arquivo
WHERE e.tarefa <> 'TOTAL';

-- ---------------------------------------------------------------------------
-- ClickUp: 25 listas, datas em milissegundos, % e baseline em custom_fields
-- ---------------------------------------------------------------------------
CREATE TEMPORARY VIEW tarefas_clickup
COMMENT 'Tarefas das listas do ClickUp, com datas, % e baseline tirados de custom_fields'
AS
WITH campos AS (
  SELECT
    c.*,
    -- try_element_at (1 = primeiro) devolve NULL se a tarefa não tiver o campo
    try_element_at(filter(c.custom_fields, f -> f.name = 'Fase'), 1).value            AS cf_fase,
    try_element_at(filter(c.custom_fields, f -> f.name = 'Progresso (%)'), 1).value   AS cf_progresso,
    try_element_at(filter(c.custom_fields, f -> f.name = 'Início baseline'), 1).value AS cf_inicio_baseline,
    try_element_at(filter(c.custom_fields, f -> f.name = 'Fim baseline'), 1).value    AS cf_fim_baseline
  FROM lakehouse_vertice.bronze.clickup_tarefas c
)
SELECT
  -- de-para pelo id da lista; se o código faltar, pelo nome da lista
  coalesce(p_codigo.projeto_id, p_nome.projeto_id)                       AS projeto_id,
  'clickup'                                                              AS ferramenta,
  c.id                                                                   AS id_na_ferramenta,
  c.cf_fase                                                              AS fase,
  c.name                                                                 AS tarefa,
  try_element_at(c.assignees, 1).username                                AS responsavel,
  to_date(timestamp_millis(CAST(c.cf_inicio_baseline AS BIGINT)))        AS inicio_baseline,
  to_date(timestamp_millis(CAST(c.cf_fim_baseline    AS BIGINT)))        AS fim_baseline,
  to_date(timestamp_millis(CAST(c.start_date         AS BIGINT)))        AS inicio_real,
  to_date(timestamp_millis(CAST(c.date_done          AS BIGINT)))        AS fim_real,
  CAST(c.cf_progresso AS DOUBLE)                                         AS pct_como_veio,
  c.time_estimate / 3600000                                              AS horas,   -- ms → horas

  -- o status chega escrito de 12 jeitos
  CASE
    WHEN lower(c.status.status) IN ('done', 'closed', 'concluído')                    THEN 'concluida'
    WHEN lower(c.status.status) IN ('to do', 'a fazer', 'backlog')                    THEN 'a_fazer'
    WHEN lower(c.status.status) IN ('in progress', 'doing', 'em andamento', 'review') THEN 'em_andamento'
  END                                                                    AS status_na_ferramenta
FROM campos c
LEFT JOIN projetos p_codigo
  ON p_codigo.ferramenta = 'clickup' AND p_codigo.codigo_ferramenta = c.list_id
LEFT JOIN projetos p_nome
  ON p_nome.ferramenta = 'clickup' AND p_nome.codigo_ferramenta IS NULL AND p_nome.nome_projeto = c.list_name;

-- ---------------------------------------------------------------------------
-- MS Project: 15 XML; as tarefas-resumo (Summary = 1) somam as de baixo
-- ---------------------------------------------------------------------------
CREATE TEMPORARY VIEW tarefas_msproject
COMMENT 'Tarefas dos cronogramas do MS Project, sem as tarefas-resumo, com a fase herdada do resumo de nível 1'
AS
WITH com_fase AS (
  -- a fase é a última tarefa-resumo de nível 1 antes da tarefa (a janela vê todas as linhas)
  SELECT
    m.*,
    last_value(CASE WHEN m.OutlineLevel = 1 THEN m.Name END, true)
      OVER (PARTITION BY m.arquivo ORDER BY m.UID) AS fase
  FROM lakehouse_vertice.bronze.msproject_tarefas m
)
SELECT
  p.projeto_id,
  'msproject'                                                 AS ferramenta,
  CAST(m.UID AS STRING)                                       AS id_na_ferramenta,
  m.fase,
  m.Name                                                      AS tarefa,
  CAST(NULL AS STRING)                                        AS responsavel,
  to_date(m.Baseline.Start)                                   AS inicio_baseline,
  to_date(m.Baseline.Finish)                                  AS fim_baseline,
  to_date(m.ActualStart)                                      AS inicio_real,
  to_date(m.ActualFinish)                                     AS fim_real,
  CAST(m.PercentComplete AS DOUBLE)                           AS pct_como_veio,
  CAST(regexp_extract(m.Work, 'PT([0-9]+)H', 1) AS DOUBLE)    AS horas,   -- 'PT40H0M0S' → 40
  CAST(NULL AS STRING)                                        AS status_na_ferramenta
FROM com_fase m
LEFT JOIN projetos p
  ON p.ferramenta = 'msproject' AND p.codigo_ferramenta = m.arquivo
WHERE m.Summary = 0;

-- ---------------------------------------------------------------------------
-- As três num modelo só
-- ---------------------------------------------------------------------------
CREATE OR REFRESH MATERIALIZED VIEW tarefas (
  CONSTRAINT achou_o_projeto EXPECT (projeto_id IS NOT NULL)              ON VIOLATION FAIL UPDATE,
  CONSTRAINT pct_entre_0_e_100 EXPECT (pct_concluido BETWEEN 0 AND 100)   ON VIOLATION FAIL UPDATE,
  CONSTRAINT horas_positivas EXPECT (horas > 0)                           ON VIOLATION FAIL UPDATE
)
COMMENT 'Tarefas de todos os projetos, das três ferramentas (Excel, ClickUp, MS Project) num modelo só: fase, responsável, datas baseline e reais, % concluído (limitado a 100, com flag de quando veio acima) e horas previstas. Uma linha por tarefa (tarefa_id = projeto-ferramenta-id).'
AS
WITH todas AS (
            SELECT * FROM tarefas_excel
  UNION ALL SELECT * FROM tarefas_clickup
  UNION ALL SELECT * FROM tarefas_msproject
)
SELECT
  concat_ws('-', projeto_id, ferramenta, id_na_ferramenta) AS tarefa_id,
  projeto_id,
  ferramenta,
  id_na_ferramenta,
  fase,
  tarefa,
  responsavel,
  inicio_baseline,
  fim_baseline,
  inicio_real,
  fim_real,
  pct_como_veio,
  least(pct_como_veio, 100)                                AS pct_concluido,
  pct_como_veio > 100                                      AS pct_veio_acima_de_100,
  horas,
  status_na_ferramenta
FROM todas;

-- Silver · pessoas: colaboradores e timesheet

-- COL0102, COL0257 e COL0433 vêm duas vezes; o cadastro certo tem o papel em minúsculas
CREATE OR REFRESH MATERIALIZED VIEW colaboradores
COMMENT 'Cadastro das 520 pessoas da Vértice: papel, senioridade, custo por hora, admissão e desligamento. Uma linha por colaborador (as 3 duplicadas da origem foram resolvidas).'
AS
WITH ordenado AS (
  SELECT
    *,
    row_number() OVER (
      PARTITION BY colaborador_id
      ORDER BY CASE WHEN papel = lower(papel) THEN 0 ELSE 1 END
    ) AS ordem
  FROM lakehouse_vertice.bronze.colaboradores
)
SELECT
  colaborador_id,
  nome,
  papel,
  senioridade,
  CAST(custo_hora AS DECIMAL(10, 2))          AS custo_hora,
  to_date(nullif(trim(data_admissao), ''))     AS data_admissao,
  to_date(nullif(trim(data_desligamento), '')) AS data_desligamento
FROM ordenado
WHERE ordem = 1;

-- Timesheet semanal
CREATE OR REFRESH MATERIALIZED VIEW apontamentos
COMMENT 'Timesheet semanal: horas disponíveis e horas apontadas por pessoa e projeto. semana = a sexta da semana (semana_inicio + 4), a mesma chave do status semanal.'
AS
SELECT
  colaborador_id,
  projeto_id,
  to_date(semana_inicio)                AS semana_inicio,
  date_add(to_date(semana_inicio), 4)   AS semana,
  CAST(horas_disponiveis AS DOUBLE)     AS horas_disponiveis,
  CAST(horas_apontadas   AS DOUBLE)     AS horas_apontadas
FROM lakehouse_vertice.bronze.apontamentos;

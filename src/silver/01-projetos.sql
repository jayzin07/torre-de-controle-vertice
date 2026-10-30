-- Silver · projetos: o cadastro do PMO.
-- É o de-para da integração: diz em qual ferramenta cada projeto é controlado
-- (excel, clickup, msproject) e com qual código (arquivo ou id da lista).

CREATE OR REFRESH MATERIALIZED VIEW projetos (
  CONSTRAINT data_inicio_valida   EXPECT (data_inicio IS NOT NULL)                            ON VIOLATION FAIL UPDATE,
  CONSTRAINT ferramenta_conhecida EXPECT (ferramenta IN ('excel', 'clickup', 'msproject'))    ON VIOLATION FAIL UPDATE
)
COMMENT 'Cadastro dos 60 projetos da Vértice (PMO): cliente, segmento, contrato, orçamento, datas e a ferramenta onde o projeto é controlado, com o código nela (o de-para para silver.tarefas). Uma linha por projeto.'
AS
SELECT
  projeto_id,
  nome_projeto,
  cliente,
  segmento,
  tipo_projeto,

  -- a ferramenta chega escrita de 8 jeitos (ClickUp, Clickup, Planilha, Project...)
  CASE
    WHEN lower(ferramenta) LIKE '%click%'                                  THEN 'clickup'
    WHEN lower(ferramenta) LIKE '%excel%' OR lower(ferramenta) LIKE '%planilha%' THEN 'excel'
    WHEN lower(ferramenta) LIKE '%project%'                                THEN 'msproject'
  END                                         AS ferramenta,
  ferramenta                                  AS ferramenta_como_veio,

  -- 2 projetos chegam sem código: a integração resolve pelo nome (ver 02-tarefas.sql)
  nullif(trim(codigo_ferramenta), '')         AS codigo_ferramenta,

  CAST(valor_contrato  AS DECIMAL(15, 2))     AS valor_contrato,
  CAST(orcamento_custo AS DECIMAL(15, 2))     AS orcamento_custo,

  -- data em yyyy-MM-dd ou dd/MM/yyyy
  coalesce(try_to_date(data_inicio, 'yyyy-MM-dd'),
           try_to_date(data_inicio, 'dd/MM/yyyy'))       AS data_inicio,
  coalesce(try_to_date(data_fim_baseline, 'yyyy-MM-dd'),
           try_to_date(data_fim_baseline, 'dd/MM/yyyy')) AS data_fim_baseline,

  status,
  gerente_projeto
FROM lakehouse_vertice.bronze.projetos;

-- Conferência da bronze, antes da silver.
-- As 9 tabelas que a tarefa ingestao_data_lake recria têm de chegar com a contagem
-- esperada (seed 42). bronze.feriados fica de fora: cresce a cada execução.
-- A sql_task roda um statement por vez (corta no ';').

-- 1. Uma linha por tabela: esperado × obtido
WITH esperado (tabela, esperado) AS (
  VALUES ('projetos', 60), ('status_semanal', 3911), ('excel_tarefas', 1663),
         ('clickup_tarefas', 2119), ('msproject_tarefas', 1260), ('colaboradores', 523),
         ('apontamentos', 30883), ('custos', 23640), ('entregas_fornecedor', 640)
),
obtido AS (
            SELECT 'projetos'            AS tabela, COUNT(*) AS obtido FROM lakehouse_vertice.bronze.projetos
  UNION ALL SELECT 'status_semanal',               COUNT(*)           FROM lakehouse_vertice.bronze.status_semanal
  UNION ALL SELECT 'excel_tarefas',                COUNT(*)           FROM lakehouse_vertice.bronze.excel_tarefas
  UNION ALL SELECT 'clickup_tarefas',              COUNT(*)           FROM lakehouse_vertice.bronze.clickup_tarefas
  UNION ALL SELECT 'msproject_tarefas',            COUNT(*)           FROM lakehouse_vertice.bronze.msproject_tarefas
  UNION ALL SELECT 'colaboradores',                COUNT(*)           FROM lakehouse_vertice.bronze.colaboradores
  UNION ALL SELECT 'apontamentos',                 COUNT(*)           FROM lakehouse_vertice.bronze.apontamentos
  UNION ALL SELECT 'custos',                       COUNT(*)           FROM lakehouse_vertice.bronze.custos
  UNION ALL SELECT 'entregas_fornecedor',          COUNT(*)           FROM lakehouse_vertice.bronze.entregas_fornecedor
)
SELECT e.tabela, e.esperado, o.obtido,
       CASE WHEN e.esperado = o.obtido THEN 'ok' ELSE 'DIVERGE' END AS situacao
FROM esperado e
JOIN obtido o USING (tabela)
ORDER BY e.esperado DESC;

-- 2. Se alguma divergir, a tarefa falha dizendo qual e onde olhar
WITH esperado (tabela, esperado) AS (
  VALUES ('projetos', 60), ('status_semanal', 3911), ('excel_tarefas', 1663),
         ('clickup_tarefas', 2119), ('msproject_tarefas', 1260), ('colaboradores', 523),
         ('apontamentos', 30883), ('custos', 23640), ('entregas_fornecedor', 640)
),
obtido AS (
            SELECT 'projetos'            AS tabela, COUNT(*) AS obtido FROM lakehouse_vertice.bronze.projetos
  UNION ALL SELECT 'status_semanal',               COUNT(*)           FROM lakehouse_vertice.bronze.status_semanal
  UNION ALL SELECT 'excel_tarefas',                COUNT(*)           FROM lakehouse_vertice.bronze.excel_tarefas
  UNION ALL SELECT 'clickup_tarefas',              COUNT(*)           FROM lakehouse_vertice.bronze.clickup_tarefas
  UNION ALL SELECT 'msproject_tarefas',            COUNT(*)           FROM lakehouse_vertice.bronze.msproject_tarefas
  UNION ALL SELECT 'colaboradores',                COUNT(*)           FROM lakehouse_vertice.bronze.colaboradores
  UNION ALL SELECT 'apontamentos',                 COUNT(*)           FROM lakehouse_vertice.bronze.apontamentos
  UNION ALL SELECT 'custos',                       COUNT(*)           FROM lakehouse_vertice.bronze.custos
  UNION ALL SELECT 'entregas_fornecedor',          COUNT(*)           FROM lakehouse_vertice.bronze.entregas_fornecedor
),
divergencias AS (
  SELECT concat('bronze.', e.tabela, ': esperado ', e.esperado, ', obtido ', o.obtido) AS detalhe
  FROM esperado e
  JOIN obtido o USING (tabela)
  WHERE e.esperado <> o.obtido
)
SELECT CASE
         WHEN COUNT(*) = 0 THEN 'ok: as 9 tabelas da bronze batem com a contagem esperada'
         ELSE raise_error(concat(
           'Conferência da bronze falhou (', COUNT(*), ' tabela(s)): ',
           array_join(collect_list(detalhe), ' | '),
           '. Veja a saída da tarefa ingestao_data_lake.'))
       END AS resultado
FROM divergencias;

-- Testes de qualidade da silver e da gold (tarefa testes_de_qualidade).
-- Um teste por statement: devolve 'ok · ...' ou falha a tarefa com raise_error
-- dizendo o que quebrou. A sql_task corta no ponto e vírgula: nenhum dentro de texto.
-- O "hoje" do dataset é DATE'2026-10-16'.

-- 1. Os 60 projetos têm cronograma na silver.tarefas
SELECT CASE
         WHEN COUNT(DISTINCT t.projeto_id) = 60 THEN 'ok · 1: os 60 projetos têm cronograma em silver.tarefas'
         ELSE raise_error(concat('teste 1 falhou: só ', COUNT(DISTINCT t.projeto_id),
                                 ' projetos têm tarefas em silver.tarefas (esperado 60)'))
       END AS resultado
FROM lakehouse_vertice.silver.projetos p
JOIN lakehouse_vertice.silver.tarefas t ON t.projeto_id = p.projeto_id;

-- 2. Cada projeto veio de UMA ferramenta, a do cadastro do PMO
WITH por_projeto AS (
  SELECT projeto_id, COUNT(DISTINCT ferramenta) AS ferramentas, max(ferramenta) AS ferramenta
  FROM lakehouse_vertice.silver.tarefas
  GROUP BY projeto_id
),
erros AS (
  SELECT pp.projeto_id, pp.ferramentas, pp.ferramenta, p.ferramenta AS ferramenta_do_cadastro
  FROM por_projeto pp
  JOIN lakehouse_vertice.silver.projetos p ON p.projeto_id = pp.projeto_id
  WHERE pp.ferramentas <> 1 OR pp.ferramenta <> p.ferramenta
)
SELECT CASE
         WHEN COUNT(*) = 0 THEN 'ok · 2: cada projeto veio de uma ferramenta só, a do cadastro'
         ELSE raise_error(concat('teste 2 falhou: ', array_join(collect_list(
                concat(projeto_id, ' (', ferramentas, ' ferramentas, cadastro = ', ferramenta_do_cadastro, ')')), ' | ')))
       END AS resultado
FROM erros;

-- 3. As horas do Excel na silver = a soma das linhas de TOTAL das planilhas
WITH silver_horas AS (
  SELECT projeto_id, SUM(horas) AS horas
  FROM lakehouse_vertice.silver.tarefas
  WHERE ferramenta = 'excel'
  GROUP BY projeto_id
),
total_planilha AS (
  SELECT regexp_extract(arquivo, 'PRJ-[0-9]{3}', 0)                  AS projeto_id,
         SUM(CAST(replace(horas_previstas, 'h', '') AS DOUBLE))     AS horas
  FROM lakehouse_vertice.bronze.excel_tarefas
  WHERE tarefa = 'TOTAL'
  GROUP BY regexp_extract(arquivo, 'PRJ-[0-9]{3}', 0)
),
erros AS (
  SELECT coalesce(s.projeto_id, t.projeto_id) AS projeto_id, s.horas AS horas_silver, t.horas AS horas_total
  FROM silver_horas s
  FULL JOIN total_planilha t ON t.projeto_id = s.projeto_id
  WHERE abs(coalesce(s.horas, 0) - coalesce(t.horas, 0)) > 0.01
)
SELECT CASE
         WHEN COUNT(*) = 0 THEN 'ok · 3: as horas do Excel na silver batem com a linha TOTAL de cada planilha'
         ELSE raise_error(concat('teste 3 falhou: ', array_join(collect_list(
                concat(projeto_id, ' silver=', coalesce(CAST(horas_silver AS STRING), 'nulo'),
                       ' TOTAL=', coalesce(CAST(horas_total AS STRING), 'nulo'))), ' | ')))
       END AS resultado
FROM erros;

-- 4. Uma linha por pessoa na silver
SELECT CASE
         WHEN COUNT(*) = COUNT(DISTINCT colaborador_id) THEN concat('ok · 4: uma linha por pessoa (', COUNT(*), ' colaboradores)')
         ELSE raise_error(concat('teste 4 falhou: ', COUNT(*), ' linhas para ', COUNT(DISTINCT colaborador_id),
                                 ' colaboradores em silver.colaboradores'))
       END AS resultado
FROM lakehouse_vertice.silver.colaboradores;

-- 5. A CodeForge virou um fornecedor só
SELECT CASE
         WHEN COUNT(DISTINCT fornecedor) = 1 THEN 'ok · 5: a CodeForge virou um fornecedor só'
         ELSE raise_error(concat('teste 5 falhou: a CodeForge aparece como ',
                                 array_join(collect_set(fornecedor), ' | ')))
       END AS resultado
FROM lakehouse_vertice.silver.entregas_fornecedor
WHERE replace(lower(fornecedor), ' ', '') LIKE '%codeforge%';

-- 6. A limpeza não mudou o custo total (bronze com replace = silver)
WITH bronze AS (
  SELECT SUM(CAST(replace(valor, ',', '.') AS DECIMAL(15, 2))) AS total FROM lakehouse_vertice.bronze.custos
),
silver AS (
  SELECT SUM(valor) AS total FROM lakehouse_vertice.silver.custos
)
SELECT CASE
         WHEN b.total = s.total THEN concat('ok · 6: custo total igual na bronze e na silver (R$ ', b.total, ')')
         ELSE raise_error(concat('teste 6 falhou: bronze R$ ', b.total, ' × silver R$ ', s.total))
       END AS resultado
FROM bronze b CROSS JOIN silver s;

-- 7. Os 60 projetos têm fotografia de hoje
SELECT CASE
         WHEN COUNT(*) = 60 AND COUNT(DISTINCT projeto_id) = 60 THEN 'ok · 7: os 60 projetos têm fotografia de hoje'
         ELSE raise_error(concat('teste 7 falhou: gold.projeto_situacao_atual tem ', COUNT(*), ' linhas e ',
                                 COUNT(DISTINCT projeto_id), ' projetos (esperado 60 e 60)'))
       END AS resultado
FROM lakehouse_vertice.gold.projeto_situacao_atual;

-- 8. Todo projeto em andamento tem SPI e CPI
SELECT CASE
         WHEN COUNT(*) = 0 THEN 'ok · 8: todo projeto em andamento tem SPI e CPI'
         ELSE raise_error(concat('teste 8 falhou: sem SPI ou CPI: ', array_join(collect_list(projeto_id), ', ')))
       END AS resultado
FROM lakehouse_vertice.gold.projeto_situacao_atual
WHERE status = 'em_andamento' AND (spi IS NULL OR cpi IS NULL);

-- 9. O EV de hoje do status semanal bate com o das ferramentas (diferença < 1%, na carteira)
WITH status AS (
  SELECT SUM(ev) AS ev FROM lakehouse_vertice.gold.fato_projeto_semana WHERE semana = DATE'2026-10-16'
),
ferramentas AS (
  SELECT SUM(ev) AS ev FROM lakehouse_vertice.gold.projeto_situacao_atual
)
SELECT CASE
         WHEN abs(s.ev - f.ev) / f.ev < 0.01
           THEN concat('ok · 9: EV de hoje do status (R$ ', s.ev, ') e das ferramentas (R$ ', f.ev,
                       ') diferem ', round(abs(s.ev - f.ev) / f.ev * 100, 2), '%')
         ELSE raise_error(concat('teste 9 falhou: EV de hoje do status R$ ', s.ev, ' × das ferramentas R$ ', f.ev,
                                 ' (diferença de ', round(abs(s.ev - f.ev) / f.ev * 100, 2), '%)'))
       END AS resultado
FROM status s CROSS JOIN ferramentas f;

-- 10. AC de hoje no fato = soma dos lançamentos até hoje
WITH fato AS (
  SELECT SUM(ac) AS ac FROM lakehouse_vertice.gold.fato_projeto_semana WHERE semana = DATE'2026-10-16'
),
lancamentos AS (
  SELECT SUM(valor) AS ac FROM lakehouse_vertice.silver.custos WHERE data <= DATE'2026-10-16'
)
SELECT CASE
         WHEN abs(f.ac - l.ac) < 0.01 THEN concat('ok · 10: AC de hoje no fato = lançamentos até hoje (R$ ', l.ac, ')')
         ELSE raise_error(concat('teste 10 falhou: AC no fato R$ ', f.ac, ' × lançamentos até hoje R$ ', l.ac))
       END AS resultado
FROM fato f CROSS JOIN lancamentos l;

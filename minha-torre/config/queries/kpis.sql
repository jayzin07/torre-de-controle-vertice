-- Os números do topo da tela "Projetos em risco", numa linha só.
-- Fonte: gold.projeto_situacao_atual (a fotografia de 16/10/2026).
-- Em risco = atenção + crítico (SPI ou CPI < 0,9). O score do modelo NÃO entra aqui:
-- ele vem da rota /api/score-estouro, porque a tabela pode ainda não existir.
SELECT
  count_if(status = 'em_andamento')                                              AS em_andamento,
  count_if(situacao IN ('atenção', 'crítico'))                                   AS em_risco,
  count_if(situacao = 'crítico')                                                 AS criticos,
  count_if(melancia)                                                             AS melancias,
  coalesce(sum(CASE WHEN status = 'em_andamento' THEN estouro_previsto END), 0)  AS estouro_previsto,
  sum(valor_contrato)                                                            AS carteira,
  coalesce(sum(CASE WHEN situacao IN ('atenção', 'crítico') THEN valor_contrato END), 0) AS carteira_em_risco
FROM lakehouse_vertice.gold.projeto_situacao_atual

-- Métricas governadas · gold.mv_projetos
-- A fórmula de cada KPI num lugar só: o dashboard, o app e o Genie leem daqui
-- em vez de cada um escrever o seu SUM(ev) / SUM(pv).
-- Roda como sql_task (tarefa metricas_governadas) ou com:
--   python3 scripts/run_sql.py src/metricas/metricas.sql --profile <perfil>
-- ATENÇÃO: a sql_task corta o arquivo em todo ponto e vírgula, inclusive dentro
-- do $$ ... $$. Por isso o YAML abaixo não tem nenhum, nem nos comments.
-- E o YAML precisa da indentação intacta (não rode pelo aitools tools query).

CREATE OR REPLACE VIEW lakehouse_vertice.gold.mv_projetos
WITH METRICS
LANGUAGE YAML
COMMENT 'Métricas governadas dos projetos EM ANDAMENTO na fotografia de 16/10/2026: SPI e CPI da carteira (razão das somas, nunca média de índices), EAC, estouro previsto, margem projetada, atraso médio e contagens de projetos em risco, críticos e melancias. Use MEASURE(nome) para os totais de hoje.'
AS $$
version: 1.1
comment: "Projetos em andamento na fotografia de 16/10/2026 (gold.projeto_situacao_atual). Índices da carteira são razão das somas."
source: lakehouse_vertice.gold.projeto_situacao_atual
filter: status = 'em_andamento'

dimensions:
  - name: projeto_id
    expr: projeto_id
    comment: "Código do projeto, no formato PRJ-000"
    synonyms: ["código do projeto", "id do projeto", "PRJ"]
  - name: projeto
    expr: projeto
    comment: "Código e nome do projeto, por exemplo PRJ-011 · Checkout e meios de pagamento - Supermercados Bom Preço"
    synonyms: ["nome do projeto", "projeto"]
  - name: cliente
    expr: cliente
    synonyms: ["cliente", "empresa cliente", "conta"]
  - name: segmento
    expr: segmento
    comment: "Segmento do cliente: varejo, financeiro, saude, logistica ou industria"
    synonyms: ["setor", "mercado", "vertical"]
  - name: ferramenta
    expr: ferramenta
    comment: "Onde o gerente controla o projeto: excel, clickup ou msproject"
    synonyms: ["ferramenta de gestão", "sistema de controle"]
  - name: situacao
    expr: situacao
    comment: "crítico (SPI ou CPI abaixo de 0,80), atenção (abaixo de 0,90) ou ok"
    synonyms: ["situação", "status de risco", "nível de risco", "gravidade"]
  - name: farol_do_gerente
    expr: farol_do_gerente
    comment: "O farol que o gerente publicou no último status semanal: verde, amarelo ou vermelho"
    synonyms: ["farol do gerente", "farol reportado", "farol declarado"]
  - name: farol_calculado
    expr: farol_calculado
    comment: "O farol pela regra do manual: verde com SPI a partir de 0,95, amarelo a partir de 0,90, vermelho abaixo"
    synonyms: ["farol real", "farol pelo SPI", "farol do manual"]
  - name: gerente_projeto
    expr: gerente_projeto
    synonyms: ["gerente", "gerente do projeto", "responsável", "GP"]

measures:
  - name: projetos
    expr: COUNT(1)
    comment: "Quantidade de projetos em andamento"
    synonyms: ["quantidade de projetos", "número de projetos", "total de projetos"]
  - name: carteira
    expr: SUM(valor_contrato)
    comment: "Soma do valor dos contratos, em reais"
    synonyms: ["valor da carteira", "valor contratado", "receita contratada"]
  - name: spi
    expr: SUM(ev) / SUM(pv)
    comment: "Índice de prazo da carteira = soma do valor agregado dividida pela soma do valor planejado. Abaixo de 1 é atraso, abaixo de 0,9 atenção, abaixo de 0,8 crítico"
    synonyms: ["índice de prazo", "índice de desempenho de prazo", "schedule performance index"]
  - name: cpi
    expr: SUM(ev) / SUM(ac)
    comment: "Índice de custo da carteira = soma do valor agregado dividida pela soma do custo real. Abaixo de 1 é estouro de custo"
    synonyms: ["índice de custo", "índice de desempenho de custo", "cost performance index"]
  - name: eac
    expr: SUM(eac)
    comment: "Estimativa no término = orçamento dividido pelo CPI, somada por projeto, em reais"
    synonyms: ["estimativa no término", "custo final previsto", "estimate at completion"]
  - name: estouro_previsto
    expr: SUM(estouro_previsto)
    comment: "EAC menos orçamento, só quando positivo, somado por projeto, em reais"
    synonyms: ["estouro", "estouro de custo", "custo acima do orçamento", "quanto o atraso vai custar"]
  - name: margem_projetada
    expr: (SUM(valor_contrato) - SUM(eac)) / SUM(valor_contrato)
    comment: "Margem projetada da carteira = (valor dos contratos menos EAC) dividido pelo valor dos contratos"
    synonyms: ["margem", "margem prevista", "lucratividade projetada"]
  - name: atraso_projetado_medio_dias
    expr: AVG(atraso_projetado_dias)
    comment: "Média do atraso projetado por projeto, em dias (duração baseline dividida pelo SPI menos a duração baseline)"
    synonyms: ["atraso médio", "dias de atraso", "atraso projetado"]
  - name: projetos_em_risco
    expr: COUNT(1) FILTER (WHERE situacao IN ('atenção', 'crítico'))
    comment: "Projetos em atenção ou críticos (SPI ou CPI abaixo de 0,90)"
    synonyms: ["projetos em risco", "projetos atrasados", "projetos em atenção ou críticos"]
  - name: projetos_criticos
    expr: COUNT(1) FILTER (WHERE situacao = 'crítico')
    comment: "Projetos críticos (SPI ou CPI abaixo de 0,80)"
    synonyms: ["projetos críticos", "projetos em situação crítica"]
  - name: projetos_melancia
    expr: COUNT(1) FILTER (WHERE melancia)
    comment: "Melancia = farol do gerente verde com SPI abaixo de 0,90 (verde por fora, vermelho por dentro)"
    synonyms: ["melancias", "projetos melancia", "farol verde atrasado"]
$$

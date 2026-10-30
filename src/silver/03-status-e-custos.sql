-- Silver · status semanal e custos

-- O status de toda sexta, escrito pelo gerente
CREATE OR REFRESH MATERIALIZED VIEW status_semanal (
  CONSTRAINT farol_conhecido EXPECT (farol IN ('verde', 'amarelo', 'vermelho')) ON VIOLATION FAIL UPDATE
)
COMMENT 'Status semanal de cada projeto (toda sexta): % concluído informado, farol do gerente (verde, amarelo, vermelho) e o texto livre com entregas e bloqueios. status_vazio marca os textos sem conteúdo (vazio, N/A, "ver ata da reunião"), que são mantidos.'
AS
SELECT
  projeto_id,
  to_date(data_status)                     AS data_status,
  gerente,
  lower(trim(farol))                       AS farol,          -- 'Verde', 'VERDE' → 'verde'
  CAST(pct_concluido AS INT)               AS pct_concluido,
  texto_status,
  -- não descarta: só sinaliza
  coalesce(lower(trim(texto_status)), '') IN ('', 'n/a', 'ver ata da reunião') AS status_vazio
FROM lakehouse_vertice.bronze.status_semanal;

-- Lançamentos de custo real
CREATE OR REFRESH MATERIALIZED VIEW custos
COMMENT 'Lançamentos de custo real por projeto (pessoal, consultoria, cloud, licenças, despesas), em reais. Estornos (valor negativo) ficam, porque o custo é líquido, e são sinalizados em estorno. semana = a sexta da semana do lançamento.'
AS
SELECT
  lancamento_id,
  projeto_id,
  to_date(data)                                        AS data,
  to_date(date_add(date_trunc('WEEK', to_date(data)), 4)) AS semana,   -- segunda + 4 = sexta
  categoria,
  descricao,
  -- 671 valores com vírgula decimal: troca ANTES do CAST (try_cast perderia R$ 5,4 mi em silêncio)
  CAST(replace(valor, ',', '.') AS DECIMAL(15, 2))     AS valor,
  CAST(replace(valor, ',', '.') AS DECIMAL(15, 2)) < 0 AS estorno,
  centro_custo
FROM lakehouse_vertice.bronze.custos;

-- Gold · status_estruturado: o texto livre do status semanal vira coluna.
-- Roda como sql_task (tarefa status_com_ia). A tabela ACUMULA: cada execução só
-- classifica os status que ainda não estão nela, porque a IA leva uns 5 s por texto
-- e não pode ser refeita toda segunda.
-- Três métodos, do mais barato ao mais caro:
--   regra          status vazio ou "sem bloqueio" escrito no texto
--   palavra_chave  status antigos (antes de 18/07/2026), por RLIKE
--   ia             os últimos 90 dias com bloqueio: ai_classify + ai_extract (versão 2.0)
-- A sql_task corta o arquivo em todo ponto e vírgula: nenhum dentro de texto ou comentário.

-- a. A tabela (uma vez só: nunca CREATE OR REPLACE)
CREATE TABLE IF NOT EXISTS lakehouse_vertice.gold.status_estruturado (
  projeto_id       STRING    COMMENT 'Projeto do status (PRJ-xxx)',
  data_status      DATE      COMMENT 'A sexta-feira do status semanal',
  farol            STRING    COMMENT 'Farol do gerente naquela semana: verde, amarelo ou vermelho',
  causa_bloqueio   STRING    COMMENT 'Causa do bloqueio: change_freeze, falta_sre, dependencia_fornecedor, rotatividade, mudanca_escopo, bug_retrabalho, aprovacao_cliente, sem_bloqueio ou nao_reportado (status vazio)',
  bloqueio         STRING    COMMENT 'O bloqueio em poucas palavras (só no método ia)',
  quem_destrava    STRING    COMMENT 'Quem precisa agir para destravar: pessoa, área, cliente ou fornecedor (só no método ia)',
  dias_impacto     DOUBLE    COMMENT 'Dias de impacto no prazo declarados no texto (1 semana = 7)',
  metodo           STRING    COMMENT 'Como a linha foi classificada: regra, ia ou palavra_chave',
  texto_status     STRING    COMMENT 'O texto livre original do status semanal',
  _classificado_em TIMESTAMP COMMENT 'Quando a linha foi classificada (auditoria da carga incremental)'
)
COMMENT 'Status semanais com o texto livre estruturado em colunas: causa do bloqueio, o bloqueio, quem destrava e os dias de impacto. Carga incremental: cada execução classifica só os status novos da silver.status_semanal. Os últimos 90 dias com bloqueio passam pela IA (ai_classify + ai_extract), os antigos por palavra-chave e os sem bloqueio por regra.';

-- b. Só os status que ainda não estão na tabela
MERGE INTO lakehouse_vertice.gold.status_estruturado AS alvo
USING (
  WITH novos AS (
    SELECT s.*
    FROM lakehouse_vertice.silver.status_semanal s
    LEFT ANTI JOIN lakehouse_vertice.gold.status_estruturado e
      ON e.projeto_id = s.projeto_id AND e.data_status = s.data_status
  ),

  com_metodo AS (
    SELECT
      projeto_id,
      data_status,
      farol,
      texto_status,
      status_vazio,
      lower(coalesce(texto_status, '')) AS texto,
      CASE
        WHEN status_vazio
          OR lower(coalesce(texto_status, '')) RLIKE 'bloqueios: nenhum|sem bloqueios|nada relevante' THEN 'regra'
        WHEN data_status >= DATE'2026-07-18'                                                         THEN 'ia'
        ELSE 'palavra_chave'
      END AS metodo
    FROM novos
  ),

  -- a IA roda SÓ nestas linhas (os últimos 90 dias com bloqueio)
  ia_bruta AS (
    SELECT
      *,
      ai_classify(
        texto_status,
        '["change_freeze", "falta_sre", "dependencia_fornecedor", "rotatividade", "mudanca_escopo", "bug_retrabalho", "aprovacao_cliente", "sem_bloqueio"]',
        map('version', '2.0')
      ) AS classificacao,
      ai_extract(
        texto_status,
        '{"bloqueio": {"type": "string", "description": "o bloqueio relatado no status, em poucas palavras"},
          "quem_destrava": {"type": "string", "description": "quem precisa agir para destravar: pessoa, área, cliente ou fornecedor"},
          "dias_impacto": {"type": "number", "description": "dias de impacto no prazo declarados no texto, 1 semana = 7"}}',
        map('version', '2.0')
      ) AS extracao
    FROM com_metodo
    WHERE metodo = 'ia'
  ),

  via_ia AS (
    SELECT
      projeto_id,
      data_status,
      farol,
      classificacao:response[0]::STRING        AS causa_bloqueio,
      extracao:response:bloqueio::STRING       AS bloqueio,
      extracao:response:quem_destrava::STRING  AS quem_destrava,
      extracao:response:dias_impacto::DOUBLE   AS dias_impacto,
      metodo,
      texto_status
    FROM ia_bruta
  ),

  -- regra e palavra-chave: sem IA
  sem_ia AS (
    SELECT
      projeto_id,
      data_status,
      farol,
      CASE
        WHEN status_vazio                                                          THEN 'nao_reportado'
        WHEN metodo = 'regra'                                                      THEN 'sem_bloqueio'
        WHEN texto RLIKE 'freeze|congelamento|janela de deploy'                    THEN 'change_freeze'
        WHEN texto RLIKE 'sre|infraestrutura|ambiente de homologação'              THEN 'falta_sre'
        WHEN texto RLIKE 'forge|consultoria|fornecedor'                            THEN 'dependencia_fornecedor'
        WHEN texto RLIKE 'saída de|rotatividade|onboarding'                        THEN 'rotatividade'
        WHEN texto RLIKE 'escopo|change request|regra de negócio'                  THEN 'mudanca_escopo'
        WHEN texto RLIKE 'bugs|regressão|refazendo'                                THEN 'bug_retrabalho'
        WHEN texto RLIKE 'aprovação do cliente|homologação do cliente'             THEN 'aprovacao_cliente'
        ELSE 'nao_classificado'
      END                                                                          AS causa_bloqueio,
      CAST(NULL AS STRING)                                                         AS bloqueio,
      CAST(NULL AS STRING)                                                         AS quem_destrava,
      CASE
        WHEN texto RLIKE 'impacto estimado de [0-9]+ dias'
          THEN CAST(regexp_extract(texto, 'impacto estimado de ([0-9]+) dias', 1) AS DOUBLE)
        WHEN texto RLIKE 'impacto estimado: [0-9]+ semana'
          THEN CAST(regexp_extract(texto, 'impacto estimado: ([0-9]+) semana', 1) AS DOUBLE) * 7
      END                                                                          AS dias_impacto,
      metodo,
      texto_status
    FROM com_metodo
    WHERE metodo <> 'ia'
  )

  SELECT * FROM via_ia
  UNION ALL
  SELECT * FROM sem_ia
) AS novo
ON alvo.projeto_id = novo.projeto_id AND alvo.data_status = novo.data_status
WHEN NOT MATCHED THEN INSERT (
  projeto_id, data_status, farol, causa_bloqueio, bloqueio, quem_destrava,
  dias_impacto, metodo, texto_status, _classificado_em
) VALUES (
  novo.projeto_id, novo.data_status, novo.farol, novo.causa_bloqueio, novo.bloqueio, novo.quem_destrava,
  novo.dias_impacto, novo.metodo, novo.texto_status, current_timestamp()
);

-- c. Leitura: quantos status por método e causa
SELECT metodo, causa_bloqueio, COUNT(*) AS status
FROM lakehouse_vertice.gold.status_estruturado
GROUP BY metodo, causa_bloqueio
ORDER BY metodo, status DESC;

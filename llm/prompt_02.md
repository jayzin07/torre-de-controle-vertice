Leia o CLAUDE.md da raiz e aulas/aula-04-produtos-de-dados-ia/prd/CLAUDE.md.
Continue o bundle vertice na raiz deste repositório. Agora a fórmula de
cada KPI num lugar só, e o agente (Genie) que o dono vai usar.

1. Métricas governadas: src/metricas/metricas.sql (sql_task)
   CREATE OR REPLACE VIEW lakehouse_vertice.gold.mv_projetos WITH METRICS
   LANGUAGE YAML AS $$ ... $$ (version 1.1), comment em toda dimensão e
   medida que não for óbvia, e synonyms em português.
   - source: lakehouse_vertice.gold.projeto_situacao_atual, com
     filter status = 'em_andamento'.
   - Dimensões: projeto_id, projeto, cliente, segmento, ferramenta, situacao,
     farol_do_gerente, farol_calculado, gerente_projeto.
   - Medidas: projetos, carteira (SUM valor_contrato), spi (SUM(ev)/SUM(pv)),
     cpi (SUM(ev)/SUM(ac)), eac, estouro_previsto, margem_projetada
     ((SUM(valor_contrato) - SUM(eac)) / SUM(valor_contrato)),
     atraso_projetado_medio_dias, projetos_em_risco, projetos_criticos,
     projetos_melancia (COUNT FILTER WHERE melancia).
   ARMADILHAS MEDIDAS: o YAML precisa da indentação intacta (teste com
   python3 scripts/run_sql.py <arquivo> --profile <perfil>), e NUNCA use ';'
   dentro do YAML, nem num comment: a sql_task do job corta o arquivo em todo ';'.
   Acrescente ao job a tarefa metricas_governadas, depois de
   testes_de_qualidade E status_com_ia.

2. Genie Agent como código
   - scripts/gerar_genie.py gera resources/farol.geniespace.json
     (serialized_space versão 2; ids de 32 caracteres hex, únicos e em ordem):
     tabelas gold.fato_projeto_semana, gold.projeto_situacao_atual,
     gold.status_estruturado, gold.utilizacao_pessoa_semana e
     silver.entregas_fornecedor, e a metric view gold.mv_projetos; as 4
     perguntas do dono como perguntas de exemplo.
     gold.score_estouro_30d (o modelo) entra SÓ se existir: confira com
     databricks tables exists lakehouse_vertice.gold.score_estouro_30d
     --profile <perfil>. Sem ela, nada de instrução nem exemplo sobre score.
   - Instruções de texto: quem pergunta (o dono e a diretoria); HOJE =
     2026-10-16 e o que é "últimos 90 dias / 12 semanas / próximo mês"; as
     fórmulas e as regras de corte; mv_projetos para totais de hoje e
     projeto_situacao_atual para ranking; PV/EV/AC acumulados no fato (nunca
     somar semanas); farol e melancia; "por que o projeto X atrasou" responde
     com status_estruturado dos últimos 90 dias (sem sem_bloqueio e
     nao_reportado), mais o SPI e SREs ociosos se a causa for falta_sre;
     gente parada = utilização < 20% em 12 semanas; fornecedor = prazo real ÷
     prometido na silver.entregas_fornecedor; "o que vai dar errado no
     próximo mês" junta as entregas de consultoria em atraso, o change
     freeze de varejo (01/11/2026 a 10/01/2027) nos projetos de e-commerce
     e, se o score existir, os projetos com situacao = 'ok' e faixa alto ou
     medio (com principais_fatores, na data_referencia mais recente);
     "quais clientes" devolve cada cliente uma vez.
   - Um exemplo de SQL para cada uma das 4 perguntas do dono (e, se o
     score existir, um para "qual a chance de o PRJ-024 estourar?").
   - resources/genie.genie_space.yml: recurso genie_farol, título
     "Farol · Diretoria", warehouse ${var.warehouse_id}.

Rode e me mostre a saída:
  databricks bundle deploy --profile <perfil>
  databricks bundle run vertice_farol --only metricas_governadas --profile <perfil>
  databricks bundle deploy --profile <perfil>
  databricks bundle summary --profile <perfil>
  python3 scripts/genie.py perguntar "Farol · Diretoria" "O que vai dar errado no próximo mês, e o que eu faço agora?" --profile <perfil>
  python3 scripts/genie.py benchmark "Farol · Diretoria" aulas/aula-04-produtos-de-dados-ia/prd/genie-benchmark-diretoria.json --profile <perfil>
Se o benchmark der menos de 16/20, mostre os erros e ajuste a INSTRUÇÃO
(não a pergunta), gere o JSON, faça deploy e rode de novo.

3. Plugue o agente no app minha-torre/ (o do prompt 1), como a tela Perguntar:
   - databricks.yml do app: variáveis genie_space_id e genie_space_name
     (o id do "Farol · Diretoria", pelo bundle summary); no recurso do app,
     user_api_scopes: [dashboards.genie] e o recurso
     { name: genie-space, genie_space: { name, space_id, permission: CAN_RUN } }.
   - app.yaml: env DATABRICKS_GENIE_SPACE_ID com valueFrom: genie-space.
   - server: genie() nos plugins do createApp.
   - client: tela Perguntar com <GenieChat alias="default" /> e o item no menu.
   Nenhum arquivo *.geniespace.json dentro da pasta do app.
   Dentro de minha-torre/: npm run typecheck, databricks bundle deploy e
   databricks apps deploy --profile <perfil>. Me mostre a URL.
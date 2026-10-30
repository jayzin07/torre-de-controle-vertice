#!/usr/bin/env python3
"""Gera resources/farol.geniespace.json: o Genie "Farol · Diretoria" como código.

O JSON é o `serialized_space` (versão 2) que o recurso do bundle
(resources/genie.genie_space.yml) sobe no deploy. Não edite o JSON à mão nem o
Genie no workspace: edite este script, rode de novo e faça o deploy.

Uso:
  python3 scripts/gerar_genie.py --profile <perfil>

O score do modelo (gold.score_estouro_30d) só entra se a tabela existir:
o script confere com `databricks tables exists`.
"""
from __future__ import annotations

import argparse
import itertools
import json
import subprocess
from pathlib import Path

CATALOGO = "lakehouse_vertice"
SAIDA = Path(__file__).resolve().parent.parent / "resources" / "farol.geniespace.json"

# ids de 32 caracteres hex, únicos e em ordem crescente (a API exige os arrays ordenados por id)
_contador = itertools.count(1)


def novo_id() -> str:
    return f"{next(_contador):032x}"


def score_existe(profile: str) -> bool:
    r = subprocess.run(
        ["databricks", "tables", "exists", f"{CATALOGO}.gold.score_estouro_30d",
         "--profile", profile, "-o", "json"],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        raise SystemExit(f"não consegui conferir o score: {r.stderr.strip()}")
    return bool(json.loads(r.stdout).get("table_exists"))


# ---------------------------------------------------------------------------
# As 4 perguntas do dono
# ---------------------------------------------------------------------------
PERGUNTAS_DO_DONO = [
    "Quais projetos estão atrasados, e de quais clientes?",
    "Quanto esse atraso vai me custar?",
    "Tenho gente parada enquanto outro projeto pede gente?",
    "O que vai dar errado no próximo mês?",
]

SQL_ATRASADOS = f"""SELECT projeto_id, projeto, cliente, situacao,
       ROUND(spi, 2) AS spi, ROUND(cpi, 2) AS cpi,
       ROUND(estouro_previsto, 2) AS estouro_previsto, atraso_projetado_dias
FROM {CATALOGO}.gold.projeto_situacao_atual
WHERE status = 'em_andamento'
  AND situacao IN ('crítico', 'atenção')
ORDER BY CASE situacao WHEN 'crítico' THEN 1 ELSE 2 END, LEAST(spi, cpi)"""

SQL_CUSTO = f"""SELECT ROUND(MEASURE(estouro_previsto), 2)  AS estouro_previsto,
       ROUND(MEASURE(eac), 2)               AS eac,
       ROUND(MEASURE(carteira), 2)          AS carteira,
       ROUND(MEASURE(margem_projetada), 4)  AS margem_projetada,
       ROUND(MEASURE(cpi), 2)               AS cpi,
       MEASURE(projetos_em_risco)           AS projetos_em_risco
FROM {CATALOGO}.gold.mv_projetos"""

SQL_GENTE_PARADA = f"""WITH ociosos AS (
  SELECT colaborador_id, nome, papel, senioridade,
         ROUND(SUM(horas_apontadas) / SUM(horas_disponiveis), 4) AS utilizacao,
         ROUND(SUM(custo_ocioso) / COUNT(DISTINCT semana), 2)     AS custo_ocioso_semana
  FROM {CATALOGO}.gold.utilizacao_pessoa_semana
  WHERE semana > DATE'2026-07-24'
  GROUP BY colaborador_id, nome, papel, senioridade
  HAVING SUM(horas_apontadas) / SUM(horas_disponiveis) < 0.2
),
pedindo_gente AS (
  SELECT projeto_id, causa_bloqueio, COUNT(*) AS semanas, SUM(dias_impacto) AS dias_impacto
  FROM {CATALOGO}.gold.status_estruturado
  WHERE data_status >= DATE'2026-07-18'
    AND causa_bloqueio IN ('falta_sre', 'rotatividade')
  GROUP BY projeto_id, causa_bloqueio
)
SELECT o.colaborador_id, o.nome, o.papel, o.utilizacao, o.custo_ocioso_semana,
       p.projeto_id AS projeto_que_pede_gente, p.causa_bloqueio, p.semanas, p.dias_impacto
FROM ociosos o
JOIN pedindo_gente p
  ON (o.papel = 'sre' AND p.causa_bloqueio = 'falta_sre')
  OR (o.papel <> 'sre' AND p.causa_bloqueio = 'rotatividade')
ORDER BY p.dias_impacto DESC, o.utilizacao"""

SQL_PROXIMO_MES = f"""SELECT 'entrega de consultoria em atraso' AS risco,
       e.projeto_id,
       concat(e.fornecedor, ' · ', e.item, ' · prometida para ', CAST(e.data_prometida AS STRING)) AS detalhe
FROM {CATALOGO}.silver.entregas_fornecedor e
WHERE e.em_atraso
UNION ALL
SELECT 'change freeze da Black Friday (01/11/2026 a 10/01/2027)' AS risco,
       p.projeto_id,
       concat(p.projeto, ' · situação ', p.situacao) AS detalhe
FROM {CATALOGO}.gold.projeto_situacao_atual p
WHERE p.status = 'em_andamento'
  AND (lower(p.tipo_projeto) LIKE '%commerce%'
       OR lower(p.tipo_projeto) LIKE '%checkout%'
       OR lower(p.tipo_projeto) LIKE '%marketplace%')
ORDER BY risco, projeto_id"""

# Com o score: os projetos ok hoje que o modelo vê estourando no próximo mês
SQL_PROXIMO_MES_COM_SCORE = SQL_PROXIMO_MES.replace(
    "ORDER BY risco, projeto_id",
    f"""UNION ALL
SELECT concat('modelo: risco ', s.faixa_risco, ' de estouro em 30 dias') AS risco,
       s.projeto_id,
       concat(p.projeto, ' · ', CAST(ROUND(s.prob_estouro_30d * 100) AS STRING), '% · ', s.principais_fatores) AS detalhe
FROM {CATALOGO}.gold.score_estouro_30d s
JOIN {CATALOGO}.gold.projeto_situacao_atual p ON p.projeto_id = s.projeto_id
WHERE p.situacao = 'ok'
  AND s.faixa_risco IN ('alto', 'medio')
  AND s.data_referencia = (SELECT MAX(data_referencia) FROM {CATALOGO}.gold.score_estouro_30d)
ORDER BY risco, projeto_id""",
)

SQL_CHANCE_PRJ_024 = f"""SELECT s.projeto_id, p.projeto, p.situacao, ROUND(p.spi, 2) AS spi,
       ROUND(s.prob_estouro_30d, 2) AS prob_estouro_30d, s.faixa_risco, s.principais_fatores, s.data_referencia
FROM {CATALOGO}.gold.score_estouro_30d s
JOIN {CATALOGO}.gold.projeto_situacao_atual p ON p.projeto_id = s.projeto_id
WHERE s.projeto_id = 'PRJ-024'
  AND s.data_referencia = (SELECT MAX(data_referencia) FROM {CATALOGO}.gold.score_estouro_30d)"""


# ---------------------------------------------------------------------------
# A instrução de texto
# ---------------------------------------------------------------------------
def instrucoes(com_score: bool) -> list[str]:
    linhas = [
        "QUEM PERGUNTA: o dono e a diretoria da Vértice Tecnologia, que não escrevem SQL. Responda em português, "
        "curto e direto, com valores em R$ e índices (SPI, CPI) com 2 casas decimais.\n",

        "DATAS: HOJE é 2026-10-16 (sexta-feira). NUNCA use current_date() nem now(): escreva DATE'2026-10-16'. "
        "'Últimos 90 dias' = data_status >= DATE'2026-07-18'. "
        "'Últimas 12 semanas' = semana > DATE'2026-07-24' (as 12 sextas de 31/07 a 16/10/2026). "
        "'Próximo mês' = de 17/10/2026 a 16/11/2026. Toda semana é identificada pela sexta-feira.\n",

        "PROJETO: projeto_id é o código (PRJ-011). A coluna projeto é o código seguido do nome "
        "('PRJ-011 · Checkout e meios de pagamento - Supermercados Bom Preço'). Para filtrar um projeto use "
        "projeto_id = 'PRJ-011'. Ao LISTAR projetos, devolva SEMPRE projeto_id e projeto juntos.\n",

        "QUAL TABELA: totais e índices da carteira de HOJE (SPI, CPI, EAC, estouro previsto, margem, carteira, "
        "quantos projetos em risco, críticos, melancias) vêm da metric view gold.mv_projetos com MEASURE(), "
        "por exemplo SELECT MEASURE(spi) FROM lakehouse_vertice.gold.mv_projetos. Ela já filtra os projetos em "
        "andamento. Ranking, lista ou o valor de UM projeto vêm de gold.projeto_situacao_atual com "
        "status = 'em_andamento' (os 19 concluídos ficam de fora, salvo pedido explícito). "
        "Histórico semana a semana vem de gold.fato_projeto_semana.\n",

        "FÓRMULAS: SPI = EV / PV (abaixo de 1 é atraso). CPI = EV / AC (abaixo de 1 é estouro de custo). "
        "EAC = orçamento / CPI. Estouro previsto = EAC - orçamento, só quando positivo. "
        "Margem projetada = (valor do contrato - EAC) / valor do contrato. "
        "Atraso projetado (dias) = duração baseline / SPI - duração baseline. "
        "Índice da carteira é razão das somas (SUM(ev) / SUM(pv)), nunca média dos índices dos projetos.\n",

        "REGRAS DE CORTE: SPI ou CPI abaixo de 0,90 = atenção, abaixo de 0,80 = crítico. A coluna situacao já "
        "traz isso: 'crítico', 'atenção', 'ok' ou 'concluído' (com acento). 'Em risco' = situacao IN "
        "('atenção', 'crítico'). 'Atrasado' = situação atenção ou crítico.\n",

        "FATO SEMANAL: em gold.fato_projeto_semana PV, EV e AC são ACUMULADOS até aquela sexta. Nunca some "
        "semanas: para o SPI, CPI ou custo de uma semana, pegue a linha daquela semana "
        "(semana = DATE'2026-09-25'). Para a evolução, liste a série.\n",

        "FAROL: farol_do_gerente é o que o gerente publicou no status (verde, amarelo, vermelho). "
        "farol_calculado segue o manual: verde com SPI >= 0,95, amarelo >= 0,90, vermelho abaixo. "
        "MELANCIA = farol do gerente verde com SPI abaixo de 0,90 (verde por fora, vermelho por dentro): "
        "use a coluna melancia = true de gold.projeto_situacao_atual. 'Farol verde mas atrasado' é melancia.\n",

        "POR QUE O PROJETO X ATRASOU: use gold.status_estruturado dos últimos 90 dias "
        "(data_status >= DATE'2026-07-18'), sem causa_bloqueio 'sem_bloqueio' e 'nao_reportado'. A principal "
        "causa é a mais frequente (COUNT(*) por causa_bloqueio). Traga também quantas semanas, a soma de "
        "dias_impacto, quem_destrava e o SPI de hoje do projeto. Se a causa for falta_sre, mostre os SREs "
        "ociosos (papel = 'sre' com utilização abaixo de 20% nas últimas 12 semanas).\n",

        "GENTE PARADA: utilização = SUM(horas_apontadas) / SUM(horas_disponiveis) por pessoa em "
        "gold.utilizacao_pessoa_semana nas últimas 12 semanas (semana > DATE'2026-07-24'). Parada = abaixo de 0,2 "
        "(20%). Agrupe por colaborador_id (uma linha por pessoa). Quem pede gente = projetos com causa_bloqueio "
        "'falta_sre' ou 'rotatividade' no status dos últimos 90 dias.\n",

        "FORNECEDOR: use silver.entregas_fornecedor. Quem mais atrasa = maior AVG(prazo_real_dias / "
        "prazo_prometido_dias) por fornecedor (a CodeForge Consultoria Ltda entrega em 1,41 vez o prazo). "
        "Entrega em atraso hoje = em_atraso = true.\n",

        "O QUE VAI DAR ERRADO NO PRÓXIMO MÊS: junte (1) TODAS as entregas de consultoria em atraso "
        "(silver.entregas_fornecedor com em_atraso = true, SEM filtro de data: já passaram do prazo prometido, "
        "continuam abertas e por isso atrasam o próximo mês) e (2) o change freeze de varejo da Black Friday, de "
        "01/11/2026 a 10/01/2027, que trava deploy nos projetos de e-commerce em andamento: "
        "lower(tipo_projeto) LIKE '%commerce%' OR LIKE '%checkout%' OR LIKE '%marketplace%'. "
        "Projetos de e-commerce = esses três tipos.\n",

        "CLIENTES: 'quais clientes' devolve cada cliente UMA vez (SELECT DISTINCT cliente), sem repetir o "
        "cliente que tem mais de um projeto.\n",

        "FERRAMENTA: os valores de ferramenta são 'excel', 'clickup' e 'msproject' (minúsculas).\n",
    ]
    if com_score:
        linhas.append(
            "SCORE DO MODELO: gold.score_estouro_30d traz a chance de o projeto terminar o próximo mês com SPI "
            "ou CPI abaixo de 0,90 (prob_estouro_30d, de 0 a 1), faixa_risco (alto >= 0,5, medio >= 0,2, baixo) e "
            "principais_fatores. Use sempre a data_referencia mais recente. No 'o que vai dar errado no próximo "
            "mês', inclua (3) os projetos com situacao = 'ok' hoje e faixa_risco alto ou medio, com os "
            "principais_fatores. 'Qual a chance de o PRJ-xxx estourar' = prob_estouro_30d em porcentagem.\n"
        )
    return linhas


def gerar(com_score: bool) -> dict:
    tabelas = [
        f"{CATALOGO}.gold.fato_projeto_semana",
        f"{CATALOGO}.gold.projeto_situacao_atual",
        f"{CATALOGO}.gold.status_estruturado",
        f"{CATALOGO}.gold.utilizacao_pessoa_semana",
        f"{CATALOGO}.silver.entregas_fornecedor",
    ]
    if com_score:
        tabelas.append(f"{CATALOGO}.gold.score_estouro_30d")

    exemplos = [
        (PERGUNTAS_DO_DONO[0], SQL_ATRASADOS),
        (PERGUNTAS_DO_DONO[1], SQL_CUSTO),
        (PERGUNTAS_DO_DONO[2], SQL_GENTE_PARADA),
        (PERGUNTAS_DO_DONO[3], SQL_PROXIMO_MES_COM_SCORE if com_score else SQL_PROXIMO_MES),
    ]
    if com_score:
        exemplos.append(("Qual a chance de o PRJ-024 estourar?", SQL_CHANCE_PRJ_024))

    # os ids saem do mesmo contador, nesta ordem: únicos no espaço inteiro e crescentes em cada array
    return {
        "version": 2,
        "config": {
            "sample_questions": [{"id": novo_id(), "question": [p]} for p in PERGUNTAS_DO_DONO],
        },
        "data_sources": {
            "tables": [{"identifier": t} for t in sorted(tabelas)],
            "metric_views": [{"identifier": f"{CATALOGO}.gold.mv_projetos"}],
        },
        "instructions": {
            "text_instructions": [{"id": novo_id(), "content": instrucoes(com_score)}],
            "example_question_sqls": [
                {"id": novo_id(), "question": [p], "sql": [sql]} for p, sql in exemplos
            ],
        },
    }


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--profile", required=True)
    a = ap.parse_args()

    com_score = score_existe(a.profile)
    espaco = gerar(com_score)
    SAIDA.write_text(json.dumps(espaco, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"gerado: {SAIDA.relative_to(SAIDA.parent.parent)}")
    print(f"  score do modelo: {'incluído' if com_score else 'não existe, ficou de fora'}")
    print(f"  tabelas: {len(espaco['data_sources']['tables'])} + metric view mv_projetos")
    print(f"  exemplos de SQL: {len(espaco['instructions']['example_question_sqls'])}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Gera o dashboard AI/BI do Projeto Farol: resources/dashboard-portfolio.lvdash.json.

Três páginas, uma pergunta do dono em cada:
  Portfólio     quais projetos estão atrasados e quanto isso vai custar
  Pessoas       tenho gente parada enquanto outro projeto pede gente
  Fornecedores  o que vai dar errado no próximo mês (entregas de consultoria)

As queries da gold usam o nome PURO da tabela: o catálogo e o schema vêm do
recurso do bundle (dataset_catalog / dataset_schema em resources/dashboard.dashboard.yml).
A silver.entregas_fornecedor vai com o nome completo.

Uso:
  python3 scripts/gerar_dashboard.py                          # escreve o JSON
  python3 scripts/gerar_dashboard.py --testar --profile DEFAULT  # roda cada query antes do deploy
"""
import argparse, json, os, re, subprocess, sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
SAIDA = RAIZ / "resources" / "dashboard-portfolio.lvdash.json"
TABELAS_GOLD = ["projeto_situacao_atual", "fato_projeto_semana", "utilizacao_pessoa_semana", "status_estruturado"]

# cores da situação (as mesmas em todo o dashboard)
CRITICO, ATENCAO, OK = "#FF5F46", "#F6C344", "#22C2F4"
CORES_SITUACAO = [{"value": "crítico", "color": CRITICO},
                  {"value": "atenção", "color": ATENCAO},
                  {"value": "ok", "color": OK}]

BRL = {"type": "number-currency", "currencyCode": "BRL",
       "abbreviation": "compact", "decimalPlaces": {"type": "max", "places": 2}}
INDICE = {"type": "number-plain", "decimalPlaces": {"type": "exact", "places": 2}}
PERCENT = {"type": "number-percent", "decimalPlaces": {"type": "max", "places": 1}}


# ---------------------------------------------------------------------------
# Datasets (uma query por dataset, nome de tabela puro na gold)
# ---------------------------------------------------------------------------
DATASETS = {
    # 1 linha: os KPIs da carteira em andamento. Razão é SUM/SUM, nunca AVG de razão.
    "ds_kpis": ("KPIs da carteira", """
SELECT
  SUM(valor_contrato)                                   AS carteira,
  SUM(ev) / SUM(pv)                                     AS spi,
  SUM(ev) / SUM(ac)                                     AS cpi,
  SUM(estouro_previsto)                                 AS estouro_previsto,
  COUNT_IF(situacao IN ('atenção', 'crítico'))          AS projetos_em_risco,
  COUNT_IF(situacao = 'crítico')                        AS criticos,
  COUNT_IF(melancia)                                    AS melancias
FROM projeto_situacao_atual
WHERE status = 'em_andamento'
"""),

    # uma linha por projeto em andamento: barra de estouro, dispersão e tabela
    "ds_projetos": ("Projetos em andamento", """
SELECT
  projeto_id,
  concat(projeto_id, ' · ', cliente)                    AS rotulo,
  nome_projeto,
  cliente,
  segmento,
  ferramenta,
  gerente_projeto,
  situacao,
  spi,
  cpi,
  estouro_previsto,
  margem_projetada,
  atraso_projetado_dias,
  termino_projetado,
  farol_do_gerente,
  farol_calculado,
  CASE WHEN melancia THEN 'sim' ELSE 'não' END          AS melancia
FROM projeto_situacao_atual
WHERE status = 'em_andamento'
ORDER BY estouro_previsto DESC
"""),

    # SPI e CPI semanais da carteira (SUM/SUM por semana)
    "ds_carteira_semanal": ("SPI e CPI semanais", """
SELECT
  semana,
  SUM(ev) / SUM(pv)                                     AS spi,
  SUM(ev) / SUM(ac)                                     AS cpi
FROM fato_projeto_semana
WHERE semana >= DATE'2025-03-07'
GROUP BY semana
ORDER BY semana
"""),

    # top 15 pessoas pelo custo da hora parada nas últimas 12 semanas
    "ds_top_parados": ("Top 15 custo parado", """
SELECT
  concat(nome, ' (', papel, ')')                        AS pessoa,
  SUM(custo_ocioso)                                     AS custo_ocioso,
  SUM(horas_ociosas)                                    AS horas_ociosas,
  SUM(horas_apontadas) / SUM(horas_disponiveis)         AS utilizacao
FROM utilizacao_pessoa_semana
WHERE semana > DATE'2026-07-24'
GROUP BY nome, papel
ORDER BY custo_ocioso DESC
LIMIT 15
"""),

    # utilização por pessoa e projeto, da mais parada à mais ocupada (12 semanas)
    "ds_utilizacao": ("Utilização por pessoa e projeto", """
SELECT
  colaborador_id,
  nome,
  papel,
  senioridade,
  projeto_id,
  SUM(horas_disponiveis)                                AS horas_disponiveis,
  SUM(horas_apontadas)                                  AS horas_apontadas,
  SUM(horas_ociosas)                                    AS horas_ociosas,
  SUM(horas_apontadas) / SUM(horas_disponiveis)         AS utilizacao,
  SUM(custo_ocioso)                                     AS custo_ocioso,
  ROUND(AVG(spi_do_projeto), 2)                         AS spi_do_projeto
FROM utilizacao_pessoa_semana
WHERE semana > DATE'2026-07-24'
GROUP BY colaborador_id, nome, papel, senioridade, projeto_id
ORDER BY utilizacao ASC, custo_ocioso DESC
"""),

    # causas de bloqueio por projeto nos últimos 90 dias
    "ds_causas": ("Causas de bloqueio", """
SELECT
  projeto_id,
  causa_bloqueio,
  COUNT(*)                                              AS status_com_bloqueio,
  SUM(dias_impacto)                                     AS dias_impacto
FROM status_estruturado
WHERE data_status >= DATE'2026-07-18'
  AND causa_bloqueio NOT IN ('sem_bloqueio', 'nao_reportado')
GROUP BY projeto_id, causa_bloqueio
ORDER BY projeto_id
"""),

    # um resumo por fornecedor (silver, nome completo)
    "ds_fornecedores": ("Fornecedores", """
SELECT
  fornecedor,
  COUNT(DISTINCT fornecedor_como_veio)                  AS grafias_no_cadastro,
  array_join(array_sort(collect_set(fornecedor_como_veio)), ' · ') AS como_aparece,
  COUNT(*)                                              AS entregas,
  SUM(CASE WHEN data_entrega IS NOT NULL THEN prazo_real_dias END)
    / SUM(CASE WHEN data_entrega IS NOT NULL THEN prazo_prometido_dias END) AS prazo_real_sobre_prometido,
  COUNT_IF(data_entrega <= data_prometida)
    / COUNT_IF(data_entrega IS NOT NULL)                AS pct_no_prazo,
  COUNT_IF(em_atraso)                                   AS em_atraso_hoje
FROM lakehouse_vertice.silver.entregas_fornecedor
GROUP BY fornecedor
ORDER BY prazo_real_sobre_prometido DESC
"""),

    # as entregas em atraso hoje (16/10/2026)
    "ds_atrasos": ("Entregas em atraso", """
SELECT
  entrega_id,
  projeto_id,
  fornecedor,
  item,
  valor,
  data_pedido,
  data_prometida,
  datediff(DATE'2026-10-16', data_prometida)            AS dias_em_atraso
FROM lakehouse_vertice.silver.entregas_fornecedor
WHERE em_atraso
ORDER BY dias_em_atraso DESC
"""),
}


def dataset(nome):
    display, sql = DATASETS[nome]
    linhas = [l + "\n" for l in sql.strip().splitlines()]   # cada linha termina em \n (são concatenadas)
    return {"name": nome, "displayName": display, "queryLines": linhas}


# ---------------------------------------------------------------------------
# Widgets
# ---------------------------------------------------------------------------
def campo(nome):
    return {"name": nome, "expression": f"`{nome}`"}


def query(ds, campos, filtros=None):
    q = {"datasetName": ds, "fields": [campo(c) for c in campos], "disaggregated": True}
    if filtros:
        q["filters"] = [{"expression": f} for f in filtros]
    return [{"name": "main_query", "query": q}]


def texto(nome, titulo, subtitulo, y):
    return {"widget": {"name": nome, "multilineTextboxSpec": {"lines": [f"## {titulo}\n", "\n", subtitulo]}},
            "position": {"x": 0, "y": y, "width": 12, "height": 2}}


def contador(nome, titulo, coluna, fmt, x, y, w, descricao=None):
    value = {"fieldName": coluna, "displayName": titulo}
    if fmt:
        value["format"] = fmt
    frame = {"showTitle": True, "title": titulo}
    if descricao:
        frame.update({"description": descricao, "showDescription": True})
    return {"widget": {"name": nome, "queries": query("ds_kpis", [coluna]),
                       "spec": {"version": 2, "widgetType": "counter",
                                "encodings": {"value": value}, "frame": frame}},
            "position": {"x": x, "y": y, "width": w, "height": 3}}


def tabela(nome, titulo, ds, colunas, x, y, w, h, descricao=None):
    """colunas: lista de (campo, rótulo, formato ou None)"""
    cols = []
    for c, rotulo, fmt in colunas:
        col = {"fieldName": c, "displayName": rotulo}
        if fmt:
            col["format"] = fmt
        cols.append(col)
    frame = {"showTitle": True, "title": titulo}
    if descricao:
        frame.update({"description": descricao, "showDescription": True})
    return {"widget": {"name": nome, "queries": query(ds, [c for c, _, _ in colunas]),
                       "spec": {"version": 2, "widgetType": "table",
                                "encodings": {"columns": cols}, "frame": frame}},
            "position": {"x": x, "y": y, "width": w, "height": h}}


# ---------------------------------------------------------------------------
# Página 1 · Portfólio
# ---------------------------------------------------------------------------
portfolio = [
    texto("titulo_portfolio", "Quais projetos estão atrasados, de quais clientes, e quanto isso vai custar?",
          "Carteira em andamento em 16/10/2026. SPI < 0,9 = atenção, < 0,8 = crítico. "
          "Melancia = farol do gerente verde com SPI < 0,9.", 0),

    contador("kpi_carteira", "Carteira em andamento", "carteira", BRL, 0, 2, 3, "Σ valor dos contratos"),
    contador("kpi_spi", "SPI da carteira", "spi", INDICE, 3, 2, 3, "Σ EV ÷ Σ PV · < 1 é atraso"),
    contador("kpi_cpi", "CPI da carteira", "cpi", INDICE, 6, 2, 3, "Σ EV ÷ Σ AC · < 1 é estouro"),
    contador("kpi_estouro", "Estouro previsto", "estouro_previsto", BRL, 9, 2, 3, "Σ (EAC − orçamento), quando positivo"),
    contador("kpi_em_risco", "Projetos em risco", "projetos_em_risco", None, 0, 5, 4, "atenção + crítico"),
    contador("kpi_criticos", "Críticos", "criticos", None, 4, 5, 4, "SPI ou CPI < 0,8"),
    contador("kpi_melancias", "Melancias", "melancias", None, 8, 5, 4, "verde por fora, vermelho por dentro"),

    # barra horizontal: estouro previsto por projeto, colorida pela situação
    {"widget": {"name": "estouro_por_projeto",
                "queries": query("ds_projetos", ["rotulo", "estouro_previsto", "situacao"],
                                 filtros=["`estouro_previsto` > 0"]),
                "spec": {"version": 3, "widgetType": "bar",
                         "encodings": {
                             "x": {"fieldName": "estouro_previsto", "scale": {"type": "quantitative"},
                                   "displayName": "Estouro previsto (R$)", "format": BRL},
                             "y": {"fieldName": "rotulo", "scale": {"type": "categorical", "sort": {"by": "value"}},
                                   "displayName": "Projeto"},
                             "color": {"fieldName": "situacao", "displayName": "Situação",
                                       "scale": {"type": "categorical", "mappings": CORES_SITUACAO}}},
                         "frame": {"showTitle": True, "title": "Estouro previsto por projeto",
                                   "description": "Só projetos em andamento com estouro", "showDescription": True}}},
     "position": {"x": 0, "y": 8, "width": 6, "height": 8}},

    # dispersão SPI × CPI, um ponto por projeto
    {"widget": {"name": "spi_x_cpi",
                "queries": query("ds_projetos", ["spi", "cpi", "situacao", "rotulo"]),
                "spec": {"version": 3, "widgetType": "scatter",
                         "encodings": {
                             "x": {"fieldName": "spi", "scale": {"type": "quantitative"}, "displayName": "SPI (prazo)"},
                             "y": {"fieldName": "cpi", "scale": {"type": "quantitative"}, "displayName": "CPI (custo)"},
                             "color": {"fieldName": "situacao", "displayName": "Situação",
                                       "scale": {"type": "categorical", "mappings": CORES_SITUACAO}},
                             "extra": [{"fieldName": "rotulo", "displayName": "Projeto"}]},
                         "annotations": [
                             {"type": "vertical-line",
                              "encodings": {"x": {"dataValue": "0.9", "dataType": "DOUBLE"},
                                            "label": {"value": "SPI 0,9"}, "color": {"value": ATENCAO}}},
                             {"type": "horizontal-line",
                              "encodings": {"y": {"dataValue": "0.9", "dataType": "DOUBLE"},
                                            "label": {"value": "CPI 0,9"}, "color": {"value": ATENCAO}}}],
                         "frame": {"showTitle": True, "title": "SPI × CPI por projeto",
                                   "description": "Embaixo e à esquerda: atrasado e estourado", "showDescription": True}}},
     "position": {"x": 6, "y": 8, "width": 6, "height": 8}},

    # linha: SPI e CPI semanais da carteira
    {"widget": {"name": "spi_cpi_semanal",
                "queries": query("ds_carteira_semanal", ["semana", "spi", "cpi"]),
                "spec": {"version": 3, "widgetType": "line",
                         "encodings": {
                             "x": {"fieldName": "semana", "scale": {"type": "temporal"}, "displayName": "Semana (sexta)"},
                             "y": {"scale": {"type": "quantitative"}, "format": INDICE,
                                   "fields": [{"fieldName": "spi", "displayName": "SPI"},
                                              {"fieldName": "cpi", "displayName": "CPI"}]}},
                         "annotations": [
                             {"type": "horizontal-line",
                              "encodings": {"y": {"dataValue": "0.9", "dataType": "DOUBLE"},
                                            "label": {"value": "atenção (0,9)"}, "color": {"value": ATENCAO}}},
                             {"type": "horizontal-line",
                              "encodings": {"y": {"dataValue": "0.8", "dataType": "DOUBLE"},
                                            "label": {"value": "crítico (0,8)"}, "color": {"value": CRITICO}}}],
                         "frame": {"showTitle": True, "title": "SPI e CPI semanais da carteira",
                                   "description": "Σ EV ÷ Σ PV e Σ EV ÷ Σ AC por sexta, desde 07/03/2025",
                                   "showDescription": True}}},
     "position": {"x": 0, "y": 16, "width": 12, "height": 6}},

    tabela("tabela_projetos", "Projetos em andamento: o farol do gerente × o farol pelo número", "ds_projetos", [
        ("projeto_id", "Projeto", None),
        ("nome_projeto", "Nome", None),
        ("cliente", "Cliente", None),
        ("gerente_projeto", "Gerente", None),
        ("situacao", "Situação", None),
        ("farol_do_gerente", "Farol do gerente", None),
        ("farol_calculado", "Farol pelo número", None),
        ("melancia", "Melancia", None),
        ("spi", "SPI", INDICE),
        ("cpi", "CPI", INDICE),
        ("estouro_previsto", "Estouro previsto", BRL),
        ("atraso_projetado_dias", "Atraso projetado (dias)", None),
        ("termino_projetado", "Término projetado", None),
    ], 0, 22, 12, 9),
]

# ---------------------------------------------------------------------------
# Página 2 · Pessoas
# ---------------------------------------------------------------------------
pessoas = [
    texto("titulo_pessoas", "Tenho gente parada enquanto outro projeto pede gente?",
          "Timesheet das últimas 12 semanas (depois de 24/07/2026) e as causas de bloqueio "
          "declaradas nos status dos últimos 90 dias.", 0),

    {"widget": {"name": "top15_custo_parado",
                "queries": query("ds_top_parados", ["pessoa", "custo_ocioso"]),
                "spec": {"version": 3, "widgetType": "bar",
                         "encodings": {
                             "x": {"fieldName": "custo_ocioso", "scale": {"type": "quantitative"},
                                   "displayName": "Custo da hora parada (R$)", "format": BRL},
                             "y": {"fieldName": "pessoa", "scale": {"type": "categorical", "sort": {"by": "value"}},
                                   "displayName": "Pessoa"}},
                         "frame": {"showTitle": True, "title": "Top 15 pessoas por custo da hora parada",
                                   "description": "Horas disponíveis não apontadas × custo/hora, 12 semanas",
                                   "showDescription": True}}},
     "position": {"x": 0, "y": 2, "width": 6, "height": 9}},

    {"widget": {"name": "causas_por_projeto",
                "queries": query("ds_causas", ["projeto_id", "status_com_bloqueio", "causa_bloqueio"]),
                "spec": {"version": 3, "widgetType": "bar",
                         "encodings": {
                             "x": {"fieldName": "status_com_bloqueio", "scale": {"type": "quantitative"},
                                   "displayName": "Status com bloqueio"},
                             "y": {"fieldName": "projeto_id", "scale": {"type": "categorical"}, "displayName": "Projeto"},
                             "color": {"fieldName": "causa_bloqueio", "scale": {"type": "categorical"},
                                       "displayName": "Causa"}},
                         "frame": {"showTitle": True, "title": "Causas de bloqueio por projeto",
                                   "description": "Status dos últimos 90 dias, classificados pela IA",
                                   "showDescription": True}}},
     "position": {"x": 6, "y": 2, "width": 6, "height": 9}},

    tabela("tabela_utilizacao", "Utilização por pessoa e projeto: da mais parada à mais ocupada", "ds_utilizacao", [
        ("colaborador_id", "Colaborador", None),
        ("nome", "Nome", None),
        ("papel", "Papel", None),
        ("senioridade", "Senioridade", None),
        ("projeto_id", "Projeto", None),
        ("horas_disponiveis", "Horas disponíveis", None),
        ("horas_apontadas", "Horas apontadas", None),
        ("horas_ociosas", "Horas ociosas", None),
        ("utilizacao", "Utilização", PERCENT),
        ("custo_ocioso", "Custo ocioso", BRL),
        ("spi_do_projeto", "SPI do projeto (média)", INDICE),
    ], 0, 11, 12, 9, "Últimas 12 semanas"),
]

# ---------------------------------------------------------------------------
# Página 3 · Fornecedores
# ---------------------------------------------------------------------------
fornecedores = [
    texto("titulo_fornecedores", "O que vai dar errado no próximo mês?",
          "As entregas das consultorias: prometido × entregue, e o que está em atraso em 16/10/2026.", 0),

    tabela("tabela_fornecedores", "Por fornecedor", "ds_fornecedores", [
        ("fornecedor", "Fornecedor", None),
        ("grafias_no_cadastro", "Grafias no cadastro", None),
        ("como_aparece", "Como aparece na origem", None),
        ("entregas", "Entregas", None),
        ("prazo_real_sobre_prometido", "Prazo real ÷ prometido", INDICE),
        ("pct_no_prazo", "% no prazo", PERCENT),
        ("em_atraso_hoje", "Em atraso hoje", None),
    ], 0, 2, 12, 6),

    tabela("tabela_atrasos", "Entregas em atraso hoje", "ds_atrasos", [
        ("entrega_id", "Entrega", None),
        ("projeto_id", "Projeto", None),
        ("fornecedor", "Fornecedor", None),
        ("item", "Item", None),
        ("valor", "Valor", BRL),
        ("data_pedido", "Pedido em", None),
        ("data_prometida", "Prometida para", None),
        ("dias_em_atraso", "Dias em atraso", None),
    ], 0, 8, 12, 6),
]


def pagina(nome, titulo, layout):
    return {"name": nome, "displayName": titulo, "pageType": "PAGE_TYPE_CANVAS",
            "layoutVersion": "GRID_V1", "layout": layout}


DASHBOARD = {
    "datasets": [dataset(n) for n in DATASETS],
    "pages": [pagina("portfolio", "Portfólio", portfolio),
              pagina("pessoas", "Pessoas", pessoas),
              pagina("fornecedores", "Fornecedores", fornecedores)],
    # cores da Jornada: azul #0059DB e ciano #22C2F4; fundo #14141A no escuro
    "uiSettings": {"theme": {
        "canvasBackgroundColor": {"light": "#F5F7FB", "dark": "#14141A"},
        "widgetBackgroundColor": {"light": "#FFFFFF", "dark": "#1C1C24"},
        "widgetBorderColor":     {"light": "#FFFFFF", "dark": "#1C1C24"},
        "fontColor":             {"light": "#14141A", "dark": "#EEF1F6"},
        "selectionColor":        {"light": "#0059DB", "dark": "#22C2F4"},
        "visualizationColors": ["#0059DB", "#22C2F4", "#F6C344", "#FF5F46",
                                "#8B5CF6", "#2BD9A0", "#F78FB3", "#9AA4B2"],
        "widgetHeaderAlignment": "LEFT",
    }},
}


# ---------------------------------------------------------------------------
# --testar: roda cada query com o nome completo da gold, antes do deploy
# ---------------------------------------------------------------------------
def com_prefixo(sql):
    padrao = r"\b(FROM|JOIN)\s+(" + "|".join(TABELAS_GOLD) + r")\b"
    return re.sub(padrao, r"\1 lakehouse_vertice.gold.\2", sql)


def testar(profile, warehouse):
    nomes = list(DATASETS)
    sqls = [com_prefixo(DATASETS[n][1].strip()) for n in nomes]
    env = dict(os.environ)
    if warehouse:
        env["DATABRICKS_WAREHOUSE_ID"] = warehouse
    r = subprocess.run(["databricks", "experimental", "aitools", "tools", "query", "--output", "json",
                        *sqls, "--profile", profile],
                       capture_output=True, text=True, encoding="utf-8", env=env)
    if r.returncode != 0 and not r.stdout.strip():
        sys.exit(r.stderr.strip())
    resultados = json.loads(r.stdout)
    falhas = 0
    print(f"{'dataset':<22} {'estado':<10} linhas")
    for nome, res in zip(nomes, resultados):
        linhas = res.get("rows") or []
        print(f"{nome:<22} {res.get('state', '?'):<10} {len(linhas)}")
        if res.get("state") != "SUCCEEDED":
            falhas += 1
            print(f"   erro: {res.get('error')}")
    res_kpis = resultados[nomes.index("ds_kpis")]
    kpis = res_kpis.get("rows") or []
    if kpis:
        linha = kpis[0]
        if not isinstance(linha, dict):   # linha como lista: os nomes vêm em "columns"
            colunas = [c["name"] if isinstance(c, dict) else c for c in res_kpis.get("columns", [])]
            linha = dict(zip(colunas, linha))
        print("\nKPIs da carteira em andamento:")
        for k, v in linha.items():
            print(f"  {k:<20} {v}")
    return 1 if falhas else 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--testar", action="store_true", help="roda as queries no warehouse em vez de gerar o JSON")
    ap.add_argument("--profile", help="profile do ~/.databrickscfg (obrigatório com --testar)")
    ap.add_argument("--warehouse", default="590c38ed4db4bb3d", help="id do SQL warehouse")
    args = ap.parse_args()
    if args.testar:
        if not args.profile:
            sys.exit("--testar precisa de --profile")
        return testar(args.profile, args.warehouse)
    SAIDA.write_text(json.dumps(DASHBOARD, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    widgets = sum(len(p["layout"]) for p in DASHBOARD["pages"])
    print(f"{SAIDA.relative_to(RAIZ)}: {len(DASHBOARD['datasets'])} datasets, "
          f"{len(DASHBOARD['pages'])} páginas, {widgets} widgets")
    return 0


if __name__ == "__main__":
    sys.exit(main())

import { createApp, analytics, genie, server } from '@databricks/appkit';

// O score do modelo (noite 4) mora em gold.score_estouro_30d, que pode ainda não
// existir. Por isso ele NÃO é uma query de config/queries (o typegen e o build
// quebrariam): a rota tenta ler a tabela e, se falhar, responde disponivel=false
// e a tela mostra "—".
const SQL_SCORE = 'SELECT * FROM lakehouse_vertice.gold.score_estouro_30d';

type LinhaScore = {
  projeto_id: string;
  probabilidade: number | null;
  faixa_risco: string | null;
};

type Linha = Record<string, unknown>;

function linhasDoResultado(resultado: unknown): Linha[] {
  if (typeof resultado !== 'object' || resultado === null) return [];
  const data = (resultado as { data?: unknown }).data;
  return Array.isArray(data) ? (data as Linha[]) : [];
}

// O nome exato da coluna de probabilidade é do modelo da noite 4: aceita a
// primeira coluna com "prob" ou "score" no nome.
function paraLinhaScore(linha: Linha): LinhaScore {
  const colunaProbabilidade = Object.keys(linha).find((nome) => /prob|score/i.test(nome));
  const valor = colunaProbabilidade ? linha[colunaProbabilidade] : null;
  const probabilidade = valor === null || valor === undefined ? null : Number(valor);
  return {
    projeto_id: String(linha.projeto_id),
    probabilidade: Number.isFinite(probabilidade) ? probabilidade : null,
    faixa_risco: typeof linha.faixa_risco === 'string' ? linha.faixa_risco : null,
  };
}

createApp({
  // genie() lê o DATABRICKS_GENIE_SPACE_ID (app.yaml) e registra o alias 'default'
  plugins: [analytics(), genie(), server()],
  onPluginsReady(appkit) {
    appkit.server.extend((app) => {
      // Quem está perguntando: a plataforma injeta o e-mail de quem abriu o app.
      app.get('/api/whoami', (req, res) => {
        res.json({
          email: req.header('x-forwarded-email') ?? null,
          user: req.header('x-forwarded-user') ?? null,
        });
      });

      app.get('/api/score-estouro', async (_req, res) => {
        try {
          const resultado: unknown = await appkit.analytics.query(SQL_SCORE);
          const linhas = linhasDoResultado(resultado).map(paraLinhaScore);
          res.json({ disponivel: true, linhas });
        } catch (erro) {
          console.warn('score_estouro_30d indisponível:', erro instanceof Error ? erro.message : erro);
          res.json({ disponivel: false, linhas: [] });
        }
      });
    });
  },
}).catch(console.error);

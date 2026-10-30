import {
  Badge,
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
  useAnalyticsQuery,
} from '@databricks/appkit-ui/react';
import { Carregando, Erro, Kpi, Vazio } from '../components/Estados';
import {
  SEM_VALOR,
  causa,
  dias,
  indice,
  inteiroPt,
  numero,
  percentual,
  reais,
  reaisCompacto,
} from '../lib/formatters';
import { useScoreEstouro } from '../lib/useScoreEstouro';

const FONTE = 'Fotografia de 16/10/2026 · gold.projeto_situacao_atual';

// Situação: crítico em vermelho, atenção em âmbar (tokens do tema, nada de hex).
function SituacaoBadge({ situacao }: { situacao: string }) {
  if (situacao === 'crítico') {
    return <Badge className="bg-destructive text-destructive-foreground">crítico</Badge>;
  }
  if (situacao === 'atenção') {
    return <Badge className="bg-warning text-warning-foreground">atenção</Badge>;
  }
  return <Badge variant="outline">{situacao}</Badge>;
}

const COR_FAROL: Record<string, string> = {
  verde: 'bg-success',
  amarelo: 'bg-warning',
  vermelho: 'bg-destructive',
};

function Farol({ cor }: { cor: string | null }) {
  if (!cor) return <span className="text-muted-foreground">{SEM_VALOR}</span>;
  return (
    <span className="inline-flex items-center gap-1.5">
      <span className={`inline-block h-2.5 w-2.5 rounded-full ${COR_FAROL[cor] ?? 'bg-muted'}`} aria-hidden />
      {cor}
    </span>
  );
}

export function ProjetosRiscoPage() {
  const kpis = useAnalyticsQuery('kpis');
  const projetos = useAnalyticsQuery('projetos_risco');
  const score = useScoreEstouro();

  const k = kpis.data?.[0];
  const altoRisco = score.linhas.filter((l) => l.faixa_risco === 'alto').length;

  return (
    <div className="mx-auto w-full max-w-7xl space-y-6">
      <div>
        <h2 className="text-2xl font-semibold text-foreground">
          {k
            ? `${inteiroPt(k.em_risco)} de ${inteiroPt(k.em_andamento)} projetos em andamento estão em risco`
            : 'Projetos em risco'}
        </h2>
        <p className="text-sm text-muted-foreground">
          Atenção: SPI ou CPI abaixo de 0,90. Crítico: abaixo de 0,80. Ordenados do pior para o melhor.
        </p>
      </div>

      {kpis.error && <Erro mensagem={kpis.error} />}

      <div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">
        <Kpi
          titulo="Em risco (atenção + crítico)"
          carregando={kpis.loading}
          valor={k ? inteiroPt(k.em_risco) : SEM_VALOR}
          detalhe={
            k && `${inteiroPt(k.criticos)} críticos · ${inteiroPt(k.melancias)} melancias 🍉 de ${inteiroPt(k.em_andamento)} em andamento`
          }
          fonte={FONTE}
        />
        <Kpi
          titulo="Estouro previsto"
          carregando={kpis.loading}
          valor={k ? reaisCompacto(k.estouro_previsto) : SEM_VALOR}
          detalhe="EAC − orçamento, projetos em andamento"
          fonte={FONTE}
        />
        <Kpi
          titulo="Carteira"
          carregando={kpis.loading}
          valor={k ? reaisCompacto(k.carteira) : SEM_VALOR}
          detalhe={k && `${reaisCompacto(k.carteira_em_risco)} em projetos em risco`}
          fonte={FONTE}
        />
        <Kpi
          titulo="Alto risco em 30 dias"
          carregando={score.carregando}
          valor={score.disponivel ? inteiroPt(altoRisco) : SEM_VALOR}
          detalhe={score.disponivel ? 'projetos com faixa de risco alta' : 'o modelo ainda não rodou'}
          fonte="Modelo de estouro · gold.score_estouro_30d"
        />
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Projetos em andamento</CardTitle>
          <CardDescription>
            Causa: a mais frequente no status semanal dos últimos 90 dias (classificada pela IA em
            gold.status_estruturado). 🍉 = melancia: farol do gerente verde com SPI abaixo de 0,90.
          </CardDescription>
        </CardHeader>
        <CardContent>
          {projetos.loading && <Carregando />}
          {projetos.error && <Erro mensagem={projetos.error} />}
          {projetos.data && projetos.data.length === 0 && (
            <Vazio titulo="Nenhum projeto em andamento" descricao="Rode o job vertice_farol para recarregar a gold." />
          )}
          {projetos.data && projetos.data.length > 0 && (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead className="min-w-64">Projeto</TableHead>
                  <TableHead>Situação</TableHead>
                  <TableHead className="text-right">SPI</TableHead>
                  <TableHead className="text-right">CPI</TableHead>
                  <TableHead className="text-right">Estouro previsto</TableHead>
                  <TableHead className="text-right">Atraso projetado</TableHead>
                  <TableHead>Farol gerente × calculado</TableHead>
                  <TableHead>Causa (90 dias)</TableHead>
                  <TableHead className="text-right">P(estouro)</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {projetos.data.map((p) => {
                  const s = score.porProjeto.get(p.projeto_id);
                  const atraso = numero(p.atraso_projetado_dias);
                  return (
                    <TableRow key={p.projeto_id}>
                      {/* o TableCell vem com whitespace-nowrap: o nome longo quebra linha aqui */}
                      <TableCell className="min-w-64 max-w-xs whitespace-normal">
                        <div className="font-medium">{p.projeto}</div>
                        <div className="text-xs text-muted-foreground">
                          {p.cliente} · {p.gerente_projeto}
                        </div>
                      </TableCell>
                      <TableCell>
                        <SituacaoBadge situacao={p.situacao} />
                      </TableCell>
                      <TableCell className="text-right tabular-nums">{indice(p.spi)}</TableCell>
                      <TableCell className="text-right tabular-nums">{indice(p.cpi)}</TableCell>
                      <TableCell className="text-right tabular-nums">{reais(p.estouro_previsto)}</TableCell>
                      <TableCell className="text-right tabular-nums">
                        {atraso === null ? SEM_VALOR : `${inteiroPt(atraso)} dias`}
                      </TableCell>
                      <TableCell>
                        <div className="flex items-center gap-2">
                          <Farol cor={p.farol_do_gerente} />
                          {String(p.melancia) === 'true' && <span title="melancia">🍉</span>}
                          <span className="text-muted-foreground">×</span>
                          <Farol cor={p.farol_calculado} />
                        </div>
                      </TableCell>
                      <TableCell>
                        <div>{causa(p.causa_principal)}</div>
                        {numero(p.semanas_causa) ? (
                          <div className="text-xs text-muted-foreground">
                            {inteiroPt(p.semanas_causa)} semanas
                            {numero(p.dias_falta_sre) ? ` · falta de SRE: ${dias(p.dias_falta_sre)}` : ''}
                            {numero(p.dias_rotatividade) ? ` · rotatividade: ${dias(p.dias_rotatividade)}` : ''}
                          </div>
                        ) : null}
                      </TableCell>
                      <TableCell className="text-right tabular-nums">
                        {s?.probabilidade != null ? percentual(s.probabilidade) : SEM_VALOR}
                      </TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </div>
  );
}

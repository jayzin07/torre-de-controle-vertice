import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
  Input,
  Label,
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
  useAnalyticsQuery,
} from '@databricks/appkit-ui/react';
import { useState } from 'react';
import { Carregando, Erro, Vazio } from '../components/Estados';
import { causa, dias, horas, indice, numero, percentual, reais } from '../lib/formatters';

// Simulador: tirar uma pessoa ociosa do projeto onde está parada e colocá-la
// num projeto em atenção ou crítico. A conta está explicada no <details> da tela.

const SEMANAS_NO_MES = 4;
const JANELA_DIAS = 90; // os dias de impacto vêm dos status dos últimos 90 dias
const DIAS_NO_MES = 30;

function Linha({ rotulo, valor, destaque }: { rotulo: string; valor: string; destaque?: string }) {
  return (
    <div className="flex items-baseline justify-between gap-4 border-b py-2 last:border-b-0">
      <span className="text-sm text-muted-foreground">{rotulo}</span>
      <span className={`text-lg font-semibold tabular-nums ${destaque ?? ''}`}>{valor}</span>
    </div>
  );
}

export function SimuladorPage() {
  const pessoas = useAnalyticsQuery('pessoas_ociosas');
  const projetos = useAnalyticsQuery('projetos_risco');
  const [pessoaId, setPessoaId] = useState<string>('');
  const [projetoId, setProjetoId] = useState<string>('');
  const [horasOnboarding, setHorasOnboarding] = useState<string>('40');

  if (pessoas.loading || projetos.loading) {
    return (
      <div className="mx-auto w-full max-w-5xl">
        <Carregando linhas={8} />
      </div>
    );
  }
  if (pessoas.error || projetos.error) {
    return (
      <div className="mx-auto w-full max-w-5xl">
        <Erro mensagem={pessoas.error ?? projetos.error ?? ''} />
      </div>
    );
  }

  const listaPessoas = pessoas.data ?? [];
  if (listaPessoas.length === 0) {
    return (
      <div className="mx-auto w-full max-w-5xl">
        <Vazio
          titulo="Ninguém com utilização abaixo de 20%"
          descricao="Nas últimas 12 semanas todo mundo apontou pelo menos 20% das horas disponíveis."
        />
      </div>
    );
  }

  const pessoa = listaPessoas.find((p) => p.colaborador_id === pessoaId) ?? listaPessoas[0];
  const ehSre = pessoa.papel === 'sre';

  // destino: só projetos em atenção ou crítico. Para SRE, quem mais sofre com falta de SRE primeiro.
  const destinos = (projetos.data ?? []).filter((p) => p.situacao === 'crítico' || p.situacao === 'atenção');
  if (ehSre) {
    destinos.sort((a, b) => (numero(b.dias_falta_sre) ?? 0) - (numero(a.dias_falta_sre) ?? 0));
  }
  const projeto = destinos.find((p) => p.projeto_id === projetoId) ?? destinos[0];

  // a conta
  const horasNoMes = (numero(pessoa.horas_ociosas_semana) ?? 0) * SEMANAS_NO_MES;
  const ociosidadeEvitada = (numero(pessoa.custo_ocioso_semana) ?? 0) * SEMANAS_NO_MES;
  const causaResolvida = ehSre ? 'falta_sre' : 'rotatividade';
  const diasDaCausa = projeto ? numero(ehSre ? projeto.dias_falta_sre : projeto.dias_rotatividade) ?? 0 : 0;
  const diasRecuperados = (diasDaCausa / JANELA_DIAS) * DIAS_NO_MES;
  const horasMobilizacao = Math.max(numero(horasOnboarding) ?? 0, 0);
  const custoHora = numero(pessoa.custo_hora) ?? 0;
  const mobilizacao = horasMobilizacao * custoHora;
  const saldo = ociosidadeEvitada - mobilizacao;

  return (
    <div className="mx-auto w-full max-w-5xl space-y-6">
      <div>
        <h2 className="text-2xl font-semibold text-foreground">Simulador: gente parada para projeto que pede gente</h2>
        <p className="text-sm text-muted-foreground">
          Pessoas com utilização abaixo de 20% nas últimas 12 semanas (até 16/10/2026) · gold.utilizacao_pessoa_semana
        </p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Quem e para onde</CardTitle>
        </CardHeader>
        <CardContent className="grid grid-cols-1 gap-4 md:grid-cols-3">
          <div className="space-y-2">
            <Label htmlFor="pessoa">Pessoa ociosa</Label>
            <Select value={pessoa.colaborador_id} onValueChange={setPessoaId}>
              <SelectTrigger id="pessoa">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {listaPessoas.map((p) => (
                  <SelectItem key={p.colaborador_id} value={p.colaborador_id}>
                    {p.nome} · {p.papel} {p.senioridade} · {percentual(p.utilizacao)}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <p className="text-xs text-muted-foreground">
              {pessoa.colaborador_id} · hoje em {pessoa.projetos} · {reais(pessoa.custo_hora)}/h
            </p>
          </div>

          <div className="space-y-2">
            <Label htmlFor="projeto">Projeto destino (atenção ou crítico)</Label>
            <Select value={projeto?.projeto_id ?? ''} onValueChange={setProjetoId} disabled={destinos.length === 0}>
              <SelectTrigger id="projeto">
                <SelectValue placeholder="Nenhum projeto em risco" />
              </SelectTrigger>
              <SelectContent>
                {destinos.map((p) => (
                  <SelectItem key={p.projeto_id} value={p.projeto_id}>
                    {p.projeto_id} · {p.situacao}
                    {ehSre ? ` · falta de SRE: ${dias(p.dias_falta_sre)}` : ''}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            {projeto && (
              <p className="text-xs text-muted-foreground">
                {projeto.projeto} · SPI {indice(projeto.spi)} · CPI {indice(projeto.cpi)} · causa principal:{' '}
                {causa(projeto.causa_principal)}
              </p>
            )}
          </div>

          <div className="space-y-2">
            <Label htmlFor="onboarding">Horas de onboarding</Label>
            <Input
              id="onboarding"
              type="number"
              min={0}
              step={1}
              value={horasOnboarding}
              onChange={(e) => setHorasOnboarding(e.target.value)}
            />
            <p className="text-xs text-muted-foreground">Tempo para a pessoa render no projeto novo.</p>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>O mês da mudança</CardTitle>
          <CardDescription>
            Valores de um mês (4 semanas), a partir das médias semanais das últimas 12 semanas.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <Linha rotulo="Horas no mês que deixam de ficar paradas" valor={horas(horasNoMes)} />
          <Linha rotulo="Ociosidade que deixa de ser paga" valor={reais(ociosidadeEvitada)} />
          <Linha
            rotulo={`Dias de cronograma recuperados (${causa(causaResolvida)})`}
            valor={dias(diasRecuperados)}
          />
          <Linha rotulo="Mobilização (onboarding × custo/hora)" valor={`− ${reais(mobilizacao)}`} />
          <Linha
            rotulo="Saldo do mês"
            valor={reais(saldo)}
            destaque={saldo >= 0 ? 'text-success' : 'text-destructive'}
          />

          <details className="mt-4 rounded-md bg-muted p-4 text-sm">
            <summary className="cursor-pointer font-medium">Como a conta é feita</summary>
            <ul className="mt-3 list-disc space-y-2 pl-5 text-muted-foreground">
              <li>
                <strong>Horas no mês</strong> = horas paradas por semana ({horas(pessoa.horas_ociosas_semana)}) × 4
                semanas = {horas(horasNoMes)}.
              </li>
              <li>
                <strong>Ociosidade que deixa de ser paga</strong> = custo ocioso por semana (
                {reais(pessoa.custo_ocioso_semana)}) × 4 = {reais(ociosidadeEvitada)}. A Vértice já paga essa
                pessoa: no projeto novo, essas horas viram entrega.
              </li>
              <li>
                <strong>Dias recuperados</strong> = dias de impacto que o status semanal atribuiu a{' '}
                {causa(causaResolvida)} nos últimos 90 dias ({dias(diasDaCausa)}) ÷ 90 × 30 ={' '}
                {dias(diasRecuperados)}. É o atraso que essa causa gera num mês típico; um SRE resolve falta de SRE, as
                demais funções cobrem a rotatividade. Zero quando o projeto não relatou essa causa.
              </li>
              <li>
                <strong>Mobilização</strong> = {horasMobilizacao} horas de onboarding × {reais(custoHora)}/h ={' '}
                {reais(mobilizacao)}.
              </li>
              <li>
                <strong>Saldo</strong> = ociosidade que deixa de ser paga − mobilização = {reais(saldo)}.
              </li>
            </ul>
          </details>
        </CardContent>
      </Card>
    </div>
  );
}

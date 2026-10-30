// Formatação em português. O warehouse devolve DECIMAL e alguns DOUBLE como
// texto: tudo passa por Number() antes de formatar.

const moeda = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL', maximumFractionDigits: 0 });
const decimal2 = new Intl.NumberFormat('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const decimal1 = new Intl.NumberFormat('pt-BR', { minimumFractionDigits: 1, maximumFractionDigits: 1 });
const inteiro = new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 0 });

export const SEM_VALOR = '—';

export function numero(valor: unknown): number | null {
  if (valor === null || valor === undefined || valor === '') return null;
  const n = Number(valor);
  return Number.isFinite(n) ? n : null;
}

/** R$ 1.234.567 */
export function reais(valor: unknown): string {
  const n = numero(valor);
  return n === null ? SEM_VALOR : moeda.format(n);
}

/** R$ 6,47 mi · R$ 305,2 mi · R$ 12.345 (para os KPIs) */
export function reaisCompacto(valor: unknown): string {
  const n = numero(valor);
  if (n === null) return SEM_VALOR;
  if (Math.abs(n) >= 1e8) return `R$ ${decimal1.format(n / 1e6)} mi`;
  if (Math.abs(n) >= 1e6) return `R$ ${decimal2.format(n / 1e6)} mi`;
  return moeda.format(n);
}

/** SPI e CPI: 0,63 */
export function indice(valor: unknown): string {
  const n = numero(valor);
  return n === null ? SEM_VALOR : decimal2.format(n);
}

/** 0,0552 → 5,5% */
export function percentual(valor: unknown): string {
  const n = numero(valor);
  return n === null ? SEM_VALOR : `${decimal1.format(n * 100)}%`;
}

export function horas(valor: unknown): string {
  const n = numero(valor);
  return n === null ? SEM_VALOR : `${decimal1.format(n)} h`;
}

export function dias(valor: unknown): string {
  const n = numero(valor);
  return n === null ? SEM_VALOR : `${decimal1.format(n)} dias`;
}

export function inteiroPt(valor: unknown): string {
  const n = numero(valor);
  return n === null ? SEM_VALOR : inteiro.format(n);
}

/** falta_sre → falta de SRE */
const NOMES_CAUSA: Record<string, string> = {
  change_freeze: 'change freeze',
  falta_sre: 'falta de SRE',
  dependencia_fornecedor: 'dependência de fornecedor',
  rotatividade: 'rotatividade',
  mudanca_escopo: 'mudança de escopo',
  bug_retrabalho: 'bug / retrabalho',
  aprovacao_cliente: 'aprovação do cliente',
};

export function causa(valor: string | null | undefined): string {
  if (!valor) return SEM_VALOR;
  return NOMES_CAUSA[valor] ?? valor;
}

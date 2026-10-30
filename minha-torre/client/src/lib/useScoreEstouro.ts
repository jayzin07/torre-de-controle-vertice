import { useEffect, useState } from 'react';

// Lê o score do modelo da noite 4 pela rota GET /api/score-estouro.
// Se a tabela gold.score_estouro_30d ainda não existe, disponivel = false
// e a tela mostra "—" em vez de quebrar.

export type LinhaScore = {
  projeto_id: string;
  probabilidade: number | null;
  faixa_risco: string | null;
};

type RespostaScore = {
  disponivel: boolean;
  linhas: LinhaScore[];
};

type EstadoScore = RespostaScore & { carregando: boolean };

function ehRespostaScore(valor: unknown): valor is RespostaScore {
  if (typeof valor !== 'object' || valor === null) return false;
  const v = valor as Partial<RespostaScore>;
  return typeof v.disponivel === 'boolean' && Array.isArray(v.linhas);
}

export function useScoreEstouro(): EstadoScore & { porProjeto: Map<string, LinhaScore> } {
  const [estado, setEstado] = useState<EstadoScore>({ carregando: true, disponivel: false, linhas: [] });

  useEffect(() => {
    let ativo = true;
    fetch('/api/score-estouro')
      .then((r) => r.json())
      .then((corpo: unknown) => {
        if (!ativo) return;
        setEstado(
          ehRespostaScore(corpo)
            ? { carregando: false, ...corpo }
            : { carregando: false, disponivel: false, linhas: [] },
        );
      })
      .catch(() => {
        if (ativo) setEstado({ carregando: false, disponivel: false, linhas: [] });
      });
    return () => {
      ativo = false;
    };
  }, []);

  const porProjeto = new Map(estado.linhas.map((l) => [l.projeto_id, l]));
  return { ...estado, porProjeto };
}

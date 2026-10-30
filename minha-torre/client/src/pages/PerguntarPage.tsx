import { Badge, Card, CardContent, CardDescription, CardHeader, CardTitle, GenieChat } from '@databricks/appkit-ui/react';
import { useEffect, useState } from 'react';

// Perguntar: o Genie "Farol · Diretoria" dentro do app. O GenieChat mostra o
// andamento da resposta e, em cada resposta, o SQL que o Genie gerou.

type Eu = { email: string | null };

export function PerguntarPage() {
  const [eu, setEu] = useState<Eu | null>(null);

  useEffect(() => {
    fetch('/api/whoami')
      .then((r) => (r.ok ? (r.json() as Promise<Eu>) : null))
      .then(setEu)
      .catch(() => setEu(null));
  }, []);

  return (
    <div className="mx-auto flex w-full max-w-5xl flex-col gap-4">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div>
          <h2 className="text-2xl font-semibold text-foreground">Perguntar</h2>
          <p className="text-sm text-muted-foreground">
            Pergunte em português sobre os projetos da Vértice. Dados de 16/10/2026.
          </p>
        </div>
        <Badge variant="secondary">{eu?.email ?? 'usuário conectado'}</Badge>
      </div>

      <Card className="flex min-h-0 flex-col">
        <CardHeader>
          <CardTitle>Farol · Diretoria</CardTitle>
          <CardDescription>
            Experimente: “Quais projetos estão atrasados, e de quais clientes?” · “Quanto esse atraso vai me custar?” ·
            “Tenho gente parada enquanto outro projeto pede gente?” · “O que vai dar errado no próximo mês?”
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="h-[600px]">
            <GenieChat alias="default" />
          </div>
        </CardContent>
      </Card>

      <p className="text-xs text-muted-foreground">
        Respostas geradas por IA (Genie) a partir da gold: confira o SQL de cada resposta antes de decidir. As consultas
        rodam com as suas permissões no Databricks, não com as do app.
      </p>
    </div>
  );
}

import {
  Alert,
  AlertDescription,
  AlertTitle,
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyTitle,
  Skeleton,
} from '@databricks/appkit-ui/react';
import type { ReactNode } from 'react';

// Peças comuns às telas: KPI, carregando, vazio e erro.

export function Kpi({
  titulo,
  valor,
  detalhe,
  fonte,
  carregando,
}: {
  titulo: string;
  valor: ReactNode;
  detalhe?: ReactNode;
  fonte: string;
  carregando?: boolean;
}) {
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardDescription>{titulo}</CardDescription>
        <CardTitle className="text-3xl tabular-nums">
          {carregando ? <Skeleton className="h-9 w-32" /> : valor}
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-1">
        {detalhe && <div className="text-sm text-muted-foreground">{detalhe}</div>}
        <div className="text-xs text-muted-foreground">{fonte}</div>
      </CardContent>
    </Card>
  );
}

export function Carregando({ linhas = 6 }: { linhas?: number }) {
  return (
    <div className="space-y-2">
      {Array.from({ length: linhas }, (_, i) => (
        <Skeleton key={i} className="h-8 w-full" />
      ))}
    </div>
  );
}

export function Erro({ mensagem }: { mensagem: string }) {
  return (
    <Alert variant="destructive">
      <AlertTitle>Não foi possível ler a gold</AlertTitle>
      <AlertDescription>{mensagem}</AlertDescription>
    </Alert>
  );
}

export function Vazio({ titulo, descricao }: { titulo: string; descricao: string }) {
  return (
    <Empty>
      <EmptyHeader>
        <EmptyTitle>{titulo}</EmptyTitle>
        <EmptyDescription>{descricao}</EmptyDescription>
      </EmptyHeader>
    </Empty>
  );
}

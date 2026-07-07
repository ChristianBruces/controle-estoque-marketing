# Controle de Estoque — Marketing e Comercial

Protótipo funcional e responsivo da operação de estoque. Abra `index.html` em um navegador para usar a interface.

## O que está funcional

- Dashboard com indicadores, alertas e movimentações recentes.
- Cadastro e edição de materiais, com limites de alerta configuráveis.
- Entradas, saídas com bloqueio de saldo negativo, transferências de área e ajustes pendentes.
- Busca, filtros, histórico e exportação CSV compatível com Excel.
- Persistência do protótipo no navegador (`localStorage`).
- Modelo de importação disponível na tela de Materiais.

## Implantação em nuvem

O arquivo `schema.sql` contém a base PostgreSQL para autenticação, perfis, cadastros, itens e movimentações. Para produção, conecte uma camada Next.js/Supabase a esse esquema, ative políticas de acesso por função e armazene fotos no bucket privado de arquivos.

## Sincronização com Supabase

Esta versão já possui uma camada online segura para sincronizar notebook, celular e demais acessos.

Arquivos adicionados:

- `supabase_migration.sql`: cria tabelas, permissões, views e funções seguras no Supabase.
- `supabase-config.js`: guarda a URL pública e a chave pública/anônima do projeto.
- `supabase-client.js`: conecta o site ao Supabase.
- `app-cloud.js`: ativa login, leitura online, cadastro, movimentações e aprovação de ajustes.

### Como ativar

1. Acesse o painel do Supabase.
2. Vá em **SQL Editor**.
3. Abra o arquivo `supabase_migration.sql`, copie tudo e execute.
4. Vá em **Authentication > Users** e crie o primeiro usuário.
5. Depois execute este comando no **SQL Editor**, trocando o e-mail e o nome:

```sql
insert into public.profiles (id, full_name, role)
select id, 'Christian Souza', 'manager'
from auth.users
where email = 'SEU_EMAIL_AQUI';
```

6. Abra o sistema, clique em **Entrar para sincronizar** e faça login.

Depois disso, qualquer entrada, saída, cadastro ou aprovação feita em um dispositivo será salva no Supabase e aparecerá para os demais acessos.

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

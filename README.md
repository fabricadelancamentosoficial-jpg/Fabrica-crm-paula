# Fábrica CRM

CRM comercial da Fábrica: pipeline, leads, follow-ups e botão de WhatsApp, com login por usuário e dados compartilhados em tempo real pelo Supabase.

## Como funciona
- `index.html`: o CRM inteiro (HTML, CSS e JavaScript), publicado pelo GitHub Pages.
- `vendor/supabase.js`: biblioteca oficial do Supabase (v2.45.4).
- `supabase/schema.sql`: estrutura do banco. Cole no SQL Editor do Supabase e rode.

## Usuários
Os logins são criados no Supabase em Authentication → Users → Add user (marque "Auto Confirm User").
O cadastro público deve ficar desligado em Authentication → Sign In / Providers.

## Segurança
A chave no `index.html` é a chave pública (publishable) do Supabase. Os dados só são acessíveis por usuários logados, por causa das regras de RLS do `schema.sql`. Nunca coloque a chave secreta (service_role / sb_secret) neste repositório.

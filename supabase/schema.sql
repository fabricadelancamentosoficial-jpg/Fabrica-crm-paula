-- Fábrica CRM: estrutura do banco
-- Cole tudo no SQL Editor do Supabase e clique em Run. Pode rodar mais de uma vez sem problema.

-- 1) Perfis da equipe (um por usuário que faz login)
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null default '',
  created_at timestamptz not null default now()
);

-- Cria o perfil automaticamente quando um usuário é adicionado em Authentication
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, name)
  values (new.id, coalesce(nullif(new.raw_user_meta_data->>'name',''), split_part(new.email,'@',1)))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Perfis para usuários que já existiam antes deste script
insert into public.profiles (id, name)
select id, split_part(email,'@',1) from auth.users
on conflict (id) do nothing;

-- 2) Leads
create table if not exists public.leads (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text default '',
  email text default '',
  origin text default '',
  stage text not null default 'novo'
    check (stage in ('novo','contato','qualificado','reuniao','proposta','ganho','perdido')),
  value numeric(12,2) not null default 0,
  temp text not null default 'warm' check (temp in ('hot','warm','cold')),
  owner_id uuid references public.profiles(id) on delete set null,
  next_followup date,
  tags text[] not null default '{}',
  notes text default '',
  loss_reason text default '',
  created_by uuid references public.profiles(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists leads_stage_idx on public.leads(stage);
create index if not exists leads_next_idx on public.leads(next_followup);

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

drop trigger if exists leads_touch on public.leads;
create trigger leads_touch before update on public.leads
  for each row execute function public.touch_updated_at();

-- 3) Histórico de cada lead
create table if not exists public.lead_events (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid not null references public.leads(id) on delete cascade,
  text text not null,
  author_id uuid references public.profiles(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists lead_events_lead_idx on public.lead_events(lead_id, created_at);

-- 4) Configurações da empresa (uma linha só)
create table if not exists public.settings (
  id int primary key default 1 check (id = 1),
  company text not null default 'Minha empresa',
  wa_msg text not null default 'Olá, {nome}! Tudo bem? Aqui é da {empresa}. Vi seu interesse e queria te ajudar. Podemos conversar?',
  updated_at timestamptz not null default now()
);
insert into public.settings (id) values (1) on conflict (id) do nothing;

-- 5) Segurança: só quem fez login acessa. Toda a equipe vê e edita os mesmos leads.
alter table public.profiles    enable row level security;
alter table public.leads       enable row level security;
alter table public.lead_events enable row level security;
alter table public.settings    enable row level security;

drop policy if exists "equipe le perfis" on public.profiles;
create policy "equipe le perfis" on public.profiles for select to authenticated using (true);
drop policy if exists "cada um edita o proprio perfil" on public.profiles;
drop policy if exists "equipe edita perfis" on public.profiles;
create policy "equipe edita perfis" on public.profiles for update to authenticated using (true) with check (true);

drop policy if exists "equipe gerencia leads" on public.leads;
create policy "equipe gerencia leads" on public.leads for all to authenticated using (true) with check (true);

drop policy if exists "equipe le historico" on public.lead_events;
create policy "equipe le historico" on public.lead_events for select to authenticated using (true);
drop policy if exists "equipe registra historico" on public.lead_events;
create policy "equipe registra historico" on public.lead_events for insert to authenticated with check (true);

drop policy if exists "equipe le config" on public.settings;
create policy "equipe le config" on public.settings for select to authenticated using (true);
drop policy if exists "equipe edita config" on public.settings;
create policy "equipe edita config" on public.settings for update to authenticated using (true) with check (true);

-- 5b) Permissões das tabelas (projetos novos do Supabase não liberam sozinho)
grant usage on schema public to authenticated, anon;
grant select, update on public.profiles to authenticated;
grant select, insert, update, delete on public.leads to authenticated;
grant select, insert on public.lead_events to authenticated;
grant select, update on public.settings to authenticated;
revoke all on public.profiles, public.leads, public.lead_events, public.settings from anon;

-- 6) Atualização em tempo real (um atendente vê na hora o que o outro mudou)
do $$
begin
  begin alter publication supabase_realtime add table public.leads; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.lead_events; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.settings; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.profiles; exception when duplicate_object then null; end;
end $$;

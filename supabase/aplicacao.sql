-- Fábrica CRM: entrada de leads pela página de aplicação (Do Plantão ao Milhão)
-- Cole no SQL Editor do Supabase e clique em Run. Pode rodar mais de uma vez.
--
-- A página pública NÃO ganha acesso à tabela de leads. Ela só pode chamar estas
-- duas funções, que validam os dados e gravam o lead.

create or replace function public.submit_application(
  p_nome text,
  p_whatsapp text,
  p_email text,
  p_especialidade text,
  p_consultorio text,
  p_renda text,
  p_faturamento text,
  p_trava text,
  p_origem text default 'direto'
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_temp text;
  v_phone text := left(regexp_replace(coalesce(p_whatsapp,''), '\D', '', 'g'), 15);
  v_nome text := left(btrim(coalesce(p_nome,'')), 120);
begin
  if length(v_nome) < 2 or length(v_phone) < 10 then
    raise exception 'dados_invalidos';
  end if;

  v_temp := case
    when p_faturamento in ('Acima de R$60 mil', 'R$30 a 60 mil') then 'hot'
    when p_faturamento = 'R$15 a 30 mil' then 'warm'
    else 'cold'
  end;

  insert into public.leads (name, phone, email, origin, stage, temp, tags, notes, next_followup, created_by)
  values (
    v_nome,
    v_phone,
    left(btrim(coalesce(p_email,'')), 160),
    'Aplicação (formulário)',
    'novo',
    v_temp,
    array_remove(array['Aplicação', nullif(left(btrim(coalesce(p_especialidade,'')), 60), '')], null),
    left(
      'Especialidade: ' || coalesce(nullif(btrim(p_especialidade),''), '-') || E'\n' ||
      'Consultório próprio: ' || coalesce(p_consultorio, '-') || E'\n' ||
      'Renda de convênio e plantão: ' || coalesce(p_renda, '-') || E'\n' ||
      'Faturamento mensal: ' || coalesce(p_faturamento, '-') || E'\n' ||
      'O que mais impede: ' || coalesce(nullif(btrim(p_trava),''), '(não respondeu)') || E'\n' ||
      'Origem: ' || coalesce(nullif(btrim(p_origem),''), 'direto'),
      4000),
    current_date,
    null
  )
  returning id into v_id;

  insert into public.lead_events (lead_id, text, author_id)
  values (v_id, 'Aplicação recebida pela página', null);

  return v_id;
end $$;

-- Quando a pessoa agenda no Calendly, o lead vai sozinho para "Reunião agendada".
-- Só funciona nas primeiras 24 horas e só para leads que ainda estão em "Novo lead".
create or replace function public.application_scheduled(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.leads
     set stage = 'reuniao'
   where id = p_id
     and stage = 'novo'
     and created_at > now() - interval '24 hours';
  if found then
    insert into public.lead_events (lead_id, text, author_id)
    values (p_id, 'Agendou a conversa pelo Calendly', null);
  end if;
end $$;

revoke all on function public.submit_application(text,text,text,text,text,text,text,text,text) from public;
revoke all on function public.application_scheduled(uuid) from public;
grant execute on function public.submit_application(text,text,text,text,text,text,text,text,text) to anon, authenticated;
grant execute on function public.application_scheduled(uuid) to anon, authenticated;

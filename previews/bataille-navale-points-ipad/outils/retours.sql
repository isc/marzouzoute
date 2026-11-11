-- Les messages « Écris-nous » de l'accueil de Marzouzoute : la table, ses droits, et l'email qui
-- prévient Ivan.
--
-- Marzouzoute n'a pas de projet Supabase à lui : l'offre gratuite n'en permet que deux, pris par
-- Arabesque et Tablito. La table vit donc dans le projet d'Arabesque (mtihhulokbhhvkomlmmk), à côté
-- de la sienne (public.feedback), et reprend son montage (arabesque/supabase/feedback.sql) :
--   - la page envoie le message directement à PostgREST, avec la clé publique du projet ;
--   - le rôle anon ne peut qu'ajouter une ligne : ni lire, ni modifier, ni effacer ;
--   - un trigger envoie l'email par Resend, sans faire attendre l'ajout (pg_net), avec la clé
--     resend_api_key que le Vault du projet garde pour Arabesque, depuis le domaine arabesque.app.
-- Les messages se lisent et se rangent avec outils/retours.py.
--
-- Pas de système de migrations : ce fichier fait référence, et s'applique à la main autant de fois
-- qu'on veut (if not exists, create or replace, drop … if exists) :
--   python3 outils/retours.py appliquer
--
-- Un email qui ne part pas : pg_net garde les réponses de Resend.
--   select status_code, content from net._http_response order by created desc limit 5;

create table if not exists public.marzouzoute_feedback (
  id         uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  message    text not null,
  email      text,          -- pour répondre, si la personne en a laissé une
  context    jsonb,         -- page, standalone, user_agent, viewport, locale, recent_games
  status     text not null default 'new'   -- 'new' à traiter, 'done' traité
);

-- Jusqu'en novembre 2026, le formulaire demandait aussi un type de message et un jeu. Aucun message
-- n'était encore arrivé : les deux colonnes sont parties avec.
alter table public.marzouzoute_feedback drop column if exists category, drop column if exists game;

-- La page tient ces limites ; la base aussi, puisque n'importe qui peut écrire avec la clé publique.
alter table public.marzouzoute_feedback drop constraint if exists marzouzoute_feedback_bornes;
alter table public.marzouzoute_feedback add constraint marzouzoute_feedback_bornes check (
  char_length(message) between 1 and 5000
  and (email is null or char_length(email) <= 320)
  and (context is null or length(context::text) <= 8000)
  and status in ('new', 'done')
);

create index if not exists marzouzoute_feedback_a_traiter
  on public.marzouzoute_feedback (created_at desc)
  where status = 'new';

-- anon peut ajouter un message, et rien d'autre : ni le relire, ni le modifier. Les droits de la
-- table le disent aussi, au cas où RLS serait un jour coupée.
alter table public.marzouzoute_feedback enable row level security;
revoke all on table public.marzouzoute_feedback from anon, authenticated;
grant insert on table public.marzouzoute_feedback to anon;

drop policy if exists marzouzoute_feedback_ajout on public.marzouzoute_feedback;
create policy marzouzoute_feedback_ajout
  on public.marzouzoute_feedback
  for insert
  to anon
  -- Le statut a une valeur par défaut, que la page n'envoie pas : un ajout fait à la main ne
  -- peut pas arriver déjà traité.
  with check (status = 'new');

create or replace function public.notify_marzouzoute_feedback()
returns trigger
language plpgsql
security definer
set search_path = public, extensions, vault
as $$
declare
  api_key text;
  texte   text;
begin
  select decrypted_secret into api_key
    from vault.decrypted_secrets
   where name = 'resend_api_key';

  if api_key is null then
    raise warning 'notify_marzouzoute_feedback : pas de secret resend_api_key dans le Vault, email non envoyé';
    return new;
  end if;

  -- Le message vient de n'importe qui : échappé avant d'aller dans le HTML.
  texte := replace(replace(replace(new.message, '&', '&amp;'), '<', '&lt;'), '>', '&gt;');
  texte := replace(texte, E'\n', '<br>');

  perform net.http_post(
    url := 'https://api.resend.com/emails',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || api_key,
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object(
      'from', 'Marzouzoute <marzouzoute@arabesque.app>',
      'to', jsonb_build_array('ivan.schneider@hey.com'),
      'reply_to', coalesce(nullif(new.email, ''), 'ivan.schneider@hey.com'),
      'subject', 'Marzouzoute : un message',
      'html', format(
        '<blockquote style="border-left:3px solid #ddd;padding-left:12px;color:#333">%s</blockquote>'
        '<p style="color:#666">%s</p>'
        '<p style="color:#999;font-size:13px">%s<br><code>python3 outils/retours.py traite %s</code></p>',
        texte,
        coalesce(nullif(new.email, ''), 'sans adresse'),
        coalesce(new.context->>'page', ''),
        left(new.id::text, 8)
      )
    )
  );

  return new;
end;
$$;

drop trigger if exists marzouzoute_feedback_notify on public.marzouzoute_feedback;
create trigger marzouzoute_feedback_notify
  after insert on public.marzouzoute_feedback
  for each row execute function public.notify_marzouzoute_feedback();

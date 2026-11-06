begin;

-- Reaction values are rendered in the chat UI. Restrict them at the database
-- boundary as well as escaping them in the client to prevent stored HTML payloads.
alter table public.kd_message_reactions
  drop constraint if exists kd_message_reactions_allowed_values_check;

alter table public.kd_message_reactions
  add constraint kd_message_reactions_allowed_values_check
  check (reaction in ('❤️', '👍')) not valid;

alter table public.kd_message_reactions
  validate constraint kd_message_reactions_allowed_values_check;

commit;

-- Minimal authentication objects required to replay migrations in plain PostgreSQL.
-- The runner supplies identity claims directly. These fixtures do not test Supabase Auth.
create role anon nologin;
create role authenticated nologin;
create schema auth;
create table auth.users (
  id uuid primary key,
  email text,
  email_confirmed_at timestamptz
);

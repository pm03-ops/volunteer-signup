-- ============================================================
--  志工服務報名系統 — Supabase 資料表
--  用法：Supabase 後台左側 SQL Editor → New query →
--        整段貼上 → 按 Run。跑一次就好。
--  重跑也安全（已存在的東西會跳過）。
-- ============================================================

-- ---------- 設定資料（人員/課室/地點庫/活動）：永遠只有一列 ----------
create table if not exists volunteer_config (
  id          int primary key default 1 check (id = 1),
  data        jsonb not null default '{}'::jsonb,
  updated_at  timestamptz not null default now()
);
comment on table volunteer_config is '志工報名系統設定（人員/課室/地點庫/活動），單列 jsonb';

-- ---------- 報名紀錄：一筆一列，多人同時報名不互相覆蓋 ----------
create table if not exists volunteer_signups (
  id          text primary key,
  person_id   text not null,
  occ_id      text not null,          -- 場次：單次活動 id，或「系列id:日期」
  slot        text default '',
  attended    boolean not null default false,
  ts          bigint default 0,
  created_at  timestamptz not null default now()
);
comment on table volunteer_signups is '志工報名紀錄，一筆一列';

-- 同一人同一場只能有一筆（兩台裝置同時報名時，資料庫會擋掉第二筆）
create unique index if not exists volunteer_signups_person_occ
  on volunteer_signups (person_id, occ_id);
create index if not exists volunteer_signups_occ on volunteer_signups (occ_id);

-- ---------- updated_at 自動更新 ----------
create or replace function touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists volunteer_config_touch on volunteer_config;
create trigger volunteer_config_touch before update on volunteer_config
  for each row execute function touch_updated_at();

-- ============================================================
--  權限（RLS）— 機構內部共用、不做登入：
--  知道 anon key 的人都能讀寫（anon key 會出現在前端程式碼裡）。
--  ⚠ 因此：請勿在系統中輸入住民姓名、床號、病歷號。
--  之後若要加登入，把 true 改成 auth.uid() is not null 即可。
-- ============================================================
alter table volunteer_config  enable row level security;
alter table volunteer_signups enable row level security;

drop policy if exists vc_all on volunteer_config;
create policy vc_all on volunteer_config  for all using (true) with check (true);

drop policy if exists vs_all on volunteer_signups;
create policy vs_all on volunteer_signups for all using (true) with check (true);

-- ---------- 即時同步（Realtime）：其他裝置畫面自動更新 ----------
do $$
begin
  begin
    alter publication supabase_realtime add table volunteer_signups;
  exception when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table volunteer_config;
  exception when duplicate_object then null;
  end;
end $$;

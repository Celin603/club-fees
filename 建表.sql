-- 羽球社共用帳本：ledger 表與存取規則
-- 專案：club-ledger（yhrwfyxjxpvlboziuggv）
-- 已透過 Supabase MCP 執行（migration: create_ledger）

-- 一個日期一筆帳
create table public.ledger (
  id          bigint generated always as identity primary key,
  play_date   date not null unique,
  court       numeric(10,2) not null default 0  check (court >= 0 and court <= 1000000),     -- 場地費總額
  ball        numeric(10,2) not null default 0  check (ball >= 0 and ball <= 1000000),       -- 球費總額
  reg_count   int not null default 0            check (reg_count between 0 and 500),         -- 一般社員人數
  new_count   int not null default 0            check (new_count between 0 and 500),         -- 新人人數
  reg_names   text not null default ''          check (char_length(reg_names) <= 2000),      -- 一般社員名字
  new_names   text not null default ''          check (char_length(new_names) <= 2000),      -- 新人名字
  discount    numeric(10,2) not null default 50 check (discount >= 0 and discount <= 100000), -- 新人每次折抵
  round_up    boolean not null default true,                                                 -- 無條件進位到整數元
  created_by  uuid default auth.uid(),                                                       -- 誰新增的
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()                                             -- 版本戳記，防止互相覆蓋
);

-- 開啟列層級安全（RLS）：沒有符合規則就一筆都碰不到
alter table public.ledger enable row level security;

-- 只有登入的社員（authenticated）能看、記、改、刪；沒登入（anon）沒有任何規則，全部擋掉
create policy "members can read ledger"   on public.ledger for select to authenticated using (true);
create policy "members can add ledger"    on public.ledger for insert to authenticated with check (true);
create policy "members can edit ledger"   on public.ledger for update to authenticated using (true) with check (true);
create policy "members can delete ledger" on public.ledger for delete to authenticated using (true);

-- 權限：沒登入的人連表都碰不到
revoke all on public.ledger from anon, authenticated;
grant select, insert, update, delete on public.ledger to authenticated;

-- =====================================================================
-- 第二次修改：改成共用帳本（migration: ledger_entries_with_amounts）
-- 每按一次「計算」新增一筆；同一天可以有好幾筆；記下算出來的金額與記帳人
-- 執行前 ledger 是空的（0 筆），沒有刪到任何帳
-- =====================================================================
alter table public.ledger drop constraint ledger_play_date_key;   -- 同一天可以記好幾筆

alter table public.ledger
  add column total     numeric(12,2) not null default 0 check (total >= 0),      -- 總費用
  add column reg_pay   numeric(12,2) not null default 0 check (reg_pay >= 0),    -- 一般社員每人要付
  add column new_pay   numeric(12,2) not null default 0 check (new_pay >= 0),    -- 新人每人要付
  add column collected numeric(12,2) not null default 0 check (collected >= 0),  -- 實收合計
  add column created_by_email text default (auth.jwt() ->> 'email'),             -- 記帳人
  add column updated_by_email text;                                              -- 最後修改的人

create index ledger_play_date_idx on public.ledger (play_date desc, created_at desc);

-- 記帳人／修改人必須是登入的本人，不能冒名
drop policy "members can add ledger"  on public.ledger;
drop policy "members can edit ledger" on public.ledger;

create policy "members can add ledger" on public.ledger for insert to authenticated
  with check (created_by = (select auth.uid()) and created_by_email = (select auth.jwt() ->> 'email'));

create policy "members can edit ledger" on public.ledger for update to authenticated
  using (true)
  with check (updated_by_email = (select auth.jwt() ->> 'email'));

-- 修改時不能改記帳人、建立時間
revoke update on public.ledger from authenticated;
grant update (play_date, court, ball, reg_count, new_count, reg_names, new_names, discount, round_up,
              total, reg_pay, new_pay, collected, updated_at, updated_by_email)
  on public.ledger to authenticated;

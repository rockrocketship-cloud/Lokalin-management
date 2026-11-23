-- Porsi Normal dan Reguler dipisah per menu pada menu_availability.
-- Owner menjalankan skrip ini sendiri di Supabase SQL Editor; skrip ini belum dijalankan oleh siapa pun.
-- Skrip ini idempoten, jadi aman dijalankan ulang.
-- Skrip ini tidak menghapus baris apa pun, termasuk roti bakar, dan tidak menimpa kolom price (harga Normal).
-- Kolom is_ready dan stock_qty tetap menjadi status dan jumlah porsi Normal.
-- Prasyarat: sql/menu-stock-sync.sql sudah pernah dijalankan.

begin;

-- Kolom baru ditambahkan lebih dulu supaya fungsi sinkron di bawah bisa memakainya.
alter table public.menu_availability
  add column if not exists is_ready_reguler boolean,
  add column if not exists stock_qty_reguler integer;

-- Menu yang sudah ada mulai dengan nilai bersama saat ini; staf bisa memisahkannya setelahnya.
-- Hanya baris yang masih NULL yang diisi, jadi pilihan staf tidak tertimpa saat skrip diulang.
update public.menu_availability
set is_ready_reguler = is_ready
where is_ready_reguler is null;

update public.menu_availability
set stock_qty_reguler = stock_qty
where stock_qty_reguler is null;

alter table public.menu_availability
  alter column is_ready_reguler set default true,
  alter column stock_qty_reguler set default 0;

-- Fungsi sinkron stok disalin dari sql/menu-stock-sync.sql.
-- Satu-satunya tambahan: is_ready_reguler diisi sama seperti is_ready saat availability_mode = 'auto'.
create or replace function public.lokalin_apply_menu_stock_sync(p_menu_id uuid default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null and not public.lokalin_can_manage_menu_stock() then
    raise exception 'Tidak punya akses untuk menyinkronkan menu dan stok';
  end if;

  update public.menu_availability m
  set
    sync_level = case
      when agg.is_out then 'out'
      when agg.is_low then 'low'
      else 'ok'
    end,
    is_ready = case
      when m.availability_mode = 'auto' then not agg.is_out
      else m.is_ready
    end,
    is_ready_reguler = case
      when m.availability_mode = 'auto' then not agg.is_out
      else m.is_ready_reguler
    end
  from (
    select
      l.menu_id,
      bool_or(
        coalesce(i.quantity, 0) <= 0
        or (
          l.qty_per_serving is not null
          and l.qty_per_serving > 0
          and coalesce(i.quantity, 0) < l.qty_per_serving
        )
      ) as is_out,
      bool_or(
        coalesce(i.quantity, 0) > 0
        and (l.qty_per_serving is null or coalesce(i.quantity, 0) >= l.qty_per_serving)
        and coalesce(i.quantity, 0) <= coalesce(i.minimum_stock, 0)
      ) as is_low
    from public.menu_stock_links l
    join public.lokalin_stock_items i on i.id = l.stock_item_id
    where p_menu_id is null or l.menu_id = p_menu_id
    group by l.menu_id
  ) agg
  where m.id = agg.menu_id;

  update public.menu_availability m
  set sync_level = null
  where (p_menu_id is null or m.id = p_menu_id)
    and not exists (
      select 1 from public.menu_stock_links l where l.menu_id = m.id
    );
end;
$$;

revoke all on function public.lokalin_apply_menu_stock_sync(uuid) from public, anon;
grant execute on function public.lokalin_apply_menu_stock_sync(uuid) to authenticated;

commit;

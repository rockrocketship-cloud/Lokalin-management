import sys, json, threading, http.server, functools, urllib.parse
from playwright.sync_api import sync_playwright
ROOT=sys.argv[1]
srv=http.server.ThreadingHTTPServer(('127.0.0.1',8765),functools.partial(http.server.SimpleHTTPRequestHandler,directory=ROOT))
threading.Thread(target=srv.serve_forever,daemon=True).start()
fake=open(__import__('os').path.join(__import__('os').path.dirname(__file__),'fake-supabase.js')).read()
ok=0
def check(cond,msg):
    global ok
    if not cond: print('✗',msg); sys.exit(1)
    ok+=1; print('✓',msg)
with sync_playwright() as p:
    b=p.chromium.launch(executable_path='/usr/bin/google-chrome',args=['--no-sandbox'])
    ctx=b.new_context(); opened=[]
    ctx.route('https://esm.sh/**',lambda r:r.fulfill(status=200,content_type='application/javascript',body=fake))
    pg=ctx.new_page(); errs=[]
    pg.on('pageerror',lambda e:errs.append(str(e)))
    pg.on('popup',lambda pp:opened.append(pp.url))
    # data lama di browser -> harus dimigrasi
    pg.add_init_script("window.open=u=>{(window.__OPENED=window.__OPENED||[]).push(u)}")
    pg.add_init_script("localStorage.setItem('lokalin_payroll_adjustments_v1',JSON.stringify({'2026-11|id:e-lilis':{rate:57692,meal:10000,bonus:100000,deduct:50000}}))")
    pg.goto('http://127.0.0.1:8765/payroll.html')
    pg.wait_for_selector('#staffRows tr')
    pg.fill('#month','2026-11'); pg.dispatch_event('#month','change'); pg.wait_for_timeout(500)
    check(not errs, 'tanpa error JS '+str(errs))
    db=pg.evaluate('window.__DB')
    check(len(db['payroll_adjustments'])==1 and db['payroll_adjustments'][0]['bonus']==100000,'data lama browser dipindah ke Supabase sekali')
    row=pg.locator('#staffRows tr',has_text='Lilis')
    check('Rp1.674.608' in row.inner_text(),'total Lilis dari data Supabase = Rp1.674.608')
    check(row.locator('[data-send]').is_disabled(),'tombol Kirim WA nonaktif tanpa nomor')
    wa=row.locator('[data-wa]'); wa.fill('0812'); wa.dispatch_event('change'); pg.wait_for_timeout(200)
    check('bad' in wa.get_attribute('class') and row.locator('[data-send]').is_disabled(),'nomor pendek ditolak, tombol tetap nonaktif')
    wa.fill('0812-3456-7890'); wa.dispatch_event('change'); pg.wait_for_timeout(300)
    db=pg.evaluate('window.__DB')
    check(db['payroll_contacts']==[{'emp_id':'e-lilis','no_wa':'6281234567890','updated_at':db['payroll_contacts'][0]['updated_at']}],'nomor WA tersimpan dinormalisasi')
    bonus=row.locator('[data-field="bonus"]'); bonus.fill('150000'); bonus.dispatch_event('input'); pg.wait_for_timeout(900)
    db=pg.evaluate('window.__DB')
    check(db['payroll_adjustments'][0]['bonus']==150000,'ubah bonus tersimpan ke Supabase (debounce)')
    row.locator('[data-send]').click(); pg.wait_for_timeout(600); opened=pg.evaluate('window.__OPENED||[]')
    check(opened and opened[0].startswith('https://wa.me/6281234567890?text='),'Kirim WA membuka wa.me dengan nomor benar')
    text=urllib.parse.unquote(opened[0].split('?text=')[1])
    check('Bonus      : Rp150.000' in text and 'TOTAL      : Rp1.724.608' in text and 'Periode: 26 Okt – 25 Nov 2026' in text,'isi slip memakai angka terbaru')
    db=pg.evaluate('window.__DB')
    check(db['payroll_adjustments'][0].get('sent_at'),'sent_at tercatat')
    check('Terkirim ✓' in row.inner_text(),'label Terkirim tampil')
    # reload perangkat lain (tanpa localStorage): angka tetap sama, tidak dobel migrasi
    pg2=ctx.new_page(); pg2.goto('http://127.0.0.1:8765/payroll.html'); pg2.wait_for_selector('#staffRows tr')
    pg2.fill('#month','2026-11'); pg2.dispatch_event('#month','change'); pg2.wait_for_timeout(500)
    r2=pg2.locator('#staffRows tr',has_text='Lilis').inner_text()
    check('Rp1.724.608' in r2 and 'Terkirim ✓' in r2,'halaman baru membaca angka & status dari Supabase')
    check(len(pg2.evaluate('window.__DB')['payroll_adjustments'])==1,'tidak ada migrasi ganda')
    pg.screenshot(path='/tmp/payroll.png',full_page=True)
    b.close()
print(f'\n{ok} cek lulus')

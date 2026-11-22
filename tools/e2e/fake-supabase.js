// Supabase palsu di memori untuk tes browser payroll.html
const T = window.__DB = JSON.parse(localStorage.getItem('__fakedb')||'null') || {
  app_roles:[{user_id:'u1',role:'owner'}],
  employees:[{id:'e-lilis',name:'Lilis',position:'Barista'},{id:'e-ardi',name:'Ardi',position:'Chef'}],
  absensi_harian:[...Array(24)].map((_,i)=>({id:'a'+i,emp_id:'e-lilis',nama:'Lilis',jabatan:'Barista',tanggal:`2026-11-${String(i+1).padStart(2,'0')}`,shift:'pagi',jam_masuk:'08:00',jam_pulang:'16:00'})),
  daily_worker_absensi:[], payroll_adjustments:[], payroll_contacts:[],
};
window.__LOG=[];
class Q{constructor(t){this.t=t;this.f=[];this.op='select'}
 select(){return this} eq(k,v){this.f.push(r=>r[k]===v);return this} gte(k,v){this.f.push(r=>r[k]>=v);return this} lte(k,v){this.f.push(r=>r[k]<=v);return this}
 order(){return this} range(){return this} limit(){return this}
 insert(rows){this.op='insert';this.rows=[].concat(rows);return this}
 upsert(rows,o){this.op='upsert';this.rows=[].concat(rows);this.keys=o.onConflict.split(',');return this}
 then(res0,rej){const res=v=>{localStorage.setItem('__fakedb',JSON.stringify(T));res0(v)};try{const tb=T[this.t];if(!tb)return res({data:null,error:{message:'relation '+this.t+' does not exist'}});
  if(this.op==='insert'){window.__LOG.push(['insert',this.t,this.rows]);tb.push(...this.rows.map(r=>({...r})));return res({data:null,error:null})}
  if(this.op==='upsert'){window.__LOG.push(['upsert',this.t,this.rows]);for(const r of this.rows){const o=tb.find(x=>this.keys.every(k=>x[k]===r[k]));o?Object.assign(o,r):tb.push({...r})}return res({data:null,error:null})}
  res({data:tb.filter(r=>this.f.every(f=>f(r))).map(r=>({...r})),error:null})}catch(e){rej(e)}}}
export function createClient(){return {from:t=>new Q(t),auth:{getUser:async()=>({data:{user:{id:'u1',email:'owner@x'}}}),signInWithPassword:async()=>({})}}}
